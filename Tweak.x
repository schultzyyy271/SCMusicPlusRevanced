#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// ============================================================================
// SCMusicPlusRevanced — SoundCloud v8.60.0
// ============================================================================

// MARK: - Helpers

static NSArray *blockerList = nil;
static NSString *sideloadedTeamPrefix = nil;

static BOOL isBlockedURL(NSString *urlString) {
    if (!urlString) return NO;
    for (NSString *pattern in blockerList) {
        if ([urlString containsString:pattern]) return YES;
    }
    return NO;
}

static Class SCResolveClass(const char *dottedName, const char *mangledName) {
    Class cls = objc_getClass(dottedName);
    if (!cls && mangledName) cls = objc_getClass(mangledName);
    return cls;
}

// ============================================================================
// MARK: - Sideload Fix: Bundle Seed ID Detection
// ============================================================================
// When sideloaded with a different signing identity, the team prefix changes.
// We detect the real prefix by adding a temporary keychain item and reading
// back the access group the system assigns.
// ============================================================================

static NSString *detectBundleSeedID(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:             (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount:       @"SCMusicPlusRevanced.seedID.probe",
        (__bridge id)kSecAttrService:       @"SCMusicPlusRevanced",
        (__bridge id)kSecReturnAttributes:  @YES,
    };

    // Try to find an existing probe item first
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecItemNotFound) {
        // Add a temporary item
        NSDictionary *add = @{
            (__bridge id)kSecClass:         (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount:   @"SCMusicPlusRevanced.seedID.probe",
            (__bridge id)kSecAttrService:   @"SCMusicPlusRevanced",
            (__bridge id)kSecValueData:     [@"probe" dataUsingEncoding:NSUTF8StringEncoding],
        };
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);

        if (status == errSecSuccess || status == errSecDuplicateItem) {
            status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        }
    }

    NSString *seedID = nil;
    if (status == errSecSuccess && result) {
        NSDictionary *attrs = (__bridge_transfer NSDictionary *)result;
        NSString *accessGroup = attrs[(__bridge id)kSecAttrAccessGroup];
        // Access group format: "XXXXXXXXXX.com.soundcloud.TouchApp"
        // We want the "XXXXXXXXXX" prefix
        if (accessGroup) {
            NSRange dot = [accessGroup rangeOfString:@"."];
            if (dot.location != NSNotFound && dot.location > 0) {
                seedID = [accessGroup substringToIndex:dot.location];
            }
        }
    }

    // Clean up probe item
    NSDictionary *del = @{
        (__bridge id)kSecClass:         (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount:   @"SCMusicPlusRevanced.seedID.probe",
        (__bridge id)kSecAttrService:   @"SCMusicPlusRevanced",
    };
    SecItemDelete((__bridge CFDictionaryRef)del);

    return seedID;
}

// ============================================================================
// MARK: - Sideload Fix: App Group Container
// ============================================================================

%hook NSFileManager

- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSURL *orig = %orig;
    if (orig) return orig;

    NSString *appLibrary = [NSSearchPathForDirectoriesInDomains(
        NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    if (!appLibrary) return nil;

    NSString *groupPath = [appLibrary stringByAppendingPathComponent:
        [NSString stringWithFormat:@"SharedGroup/%@", groupIdentifier]];

    [[NSFileManager defaultManager] createDirectoryAtPath:groupPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [NSURL fileURLWithPath:groupPath];
}

%end

// ============================================================================
// MARK: - Sideload Fix: Keychain Access Group Rewriting
// ============================================================================
// Rewrite the team prefix in kSecAttrAccessGroup to match the sideloaded
// app's actual signing identity. This ensures keychain items written by
// the app can be read back, and vice versa.
// ============================================================================

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);

static CFMutableDictionaryRef rewriteAccessGroup(CFDictionaryRef query) {
    CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(NULL, 0, query);

    if (!sideloadedTeamPrefix) {
        // No prefix detected — just strip the access group as fallback
        CFDictionaryRemoveValue(mutable, kSecAttrAccessGroup);
        return mutable;
    }

    CFStringRef accessGroup = CFDictionaryGetValue(query, kSecAttrAccessGroup);
    if (accessGroup && CFGetTypeID(accessGroup) == CFStringGetTypeID()) {
        NSString *group = (__bridge NSString *)accessGroup;
        NSRange dot = [group rangeOfString:@"."];
        if (dot.location != NSNotFound) {
            // Replace the original team prefix with our sideloaded one
            NSString *suffix = [group substringFromIndex:dot.location];
            NSString *rewritten = [sideloadedTeamPrefix stringByAppendingString:suffix];
            CFDictionarySetValue(mutable, kSecAttrAccessGroup,
                                 (__bridge CFStringRef)rewritten);
        }
    }

    return mutable;
}

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    OSStatus status = orig_SecItemAdd(attributes, result);
    if (status == errSecMissingEntitlement || status == -34018) {
        CFMutableDictionaryRef fixed = rewriteAccessGroup(attributes);
        status = orig_SecItemAdd(fixed, result);
        CFRelease(fixed);
    }
    return status;
}

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus status = orig_SecItemCopyMatching(query, result);
    if (status == errSecMissingEntitlement || status == -34018 || status == errSecItemNotFound) {
        CFMutableDictionaryRef fixed = rewriteAccessGroup(query);
        status = orig_SecItemCopyMatching(fixed, result);
        CFRelease(fixed);
    }
    return status;
}

static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    OSStatus status = orig_SecItemUpdate(query, attributesToUpdate);
    if (status == errSecMissingEntitlement || status == -34018) {
        CFMutableDictionaryRef fixed = rewriteAccessGroup(query);
        status = orig_SecItemUpdate(fixed, attributesToUpdate);
        CFRelease(fixed);
    }
    return status;
}

// ============================================================================
// MARK: - Ad URL Blocking via NSURLProtocol
// ============================================================================

@interface SCAdBlockerProtocol : NSURLProtocol
@end

@implementation SCAdBlockerProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"SCAdBlockerHandled" inRequest:request]) {
        return NO;
    }
    return isBlockedURL(request.URL.absoluteString);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorCancelled
                                     userInfo:nil];
    [self.client URLProtocol:self didFailWithError:error];
}

- (void)stopLoading { }

@end

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSArray *orig = %orig;
    if (![orig containsObject:[SCAdBlockerProtocol class]]) {
        NSMutableArray *modified = [NSMutableArray arrayWithObject:[SCAdBlockerProtocol class]];
        if (orig) [modified addObjectsFromArray:orig];
        return modified;
    }
    return orig;
}

%end

// ============================================================================
// MARK: - ObjC Ad Infrastructure
// ============================================================================

%hook AdPlayQueueManager

- (bool)isItemMonetizable:(id)arg1 {
    return NO;
}

%end

%hook PlayQueueTrack

- (bool)isMonetizable {
    return NO;
}

- (id)initWithUrn:(id)arg1
     transcodings:(id)arg2
        streamURL:(id)arg3
     permalinkURL:(id)arg4
      waveformURL:(id)arg5
        artistUrn:(id)arg6
       stationUrn:(id)arg7
       artistName:(id)arg8
            title:(id)arg9
   playQueueTitle:(id)arg10
 playableDuration:(double)arg11
     fullDuration:(double)arg12
      monetizable:(bool)arg13
        shareable:(bool)arg14
          blocked:(bool)arg15
          snipped:(bool)arg16
         syncable:(bool)arg17
       subMidTier:(bool)arg18
      subHighTier:(bool)arg19
           policy:(id)arg20
monetizationModel:(id)arg21
     analyticsBag:(id)arg22
 imageUrlTemplate:(id)arg23
            genre:(id)arg24 {
    return %orig(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10,
                 arg11, arg12,
                 NO,     // monetizable
                 arg14,
                 NO,     // blocked
                 NO,     // snipped
                 arg17, arg18, arg19,
                 arg20, arg21, arg22, arg23, arg24);
}

%end

// ============================================================================
// MARK: - Swift: Ad Player Controllers
// ============================================================================

%hook SCSoundCloudAudioAdPlayerEventController
- (id)init { return %orig; }
%end

%hook SCSoundCloudVideoAdPlayerEventController
- (id)init { return %orig; }
%end

// ============================================================================
// MARK: - Swift: PlayQueueItemTrackEntity
// ============================================================================

%hook SCSoundCloudPlayQueueItemTrackEntity

- (bool)isMonetizable {
    return NO;
}

- (bool)isMonetizableAdGeo {
    return NO;
}

- (id)initWithUrn:(id)arg1
     transcodings:(id)arg2
        streamURL:(id)arg3
      waveformURL:(id)arg4
        artistUrn:(id)arg5
       stationUrn:(id)arg6
       artistName:(id)arg7
            title:(id)arg8
   playQueueTitle:(id)arg9
playableDurationInMs:(unsigned long long)arg10
 fullDurationInMs:(unsigned long long)arg11
      monetizable:(bool)arg12
        shareable:(bool)arg13
        isPrivate:(bool)arg14
          blocked:(bool)arg15
          snipped:(bool)arg16
         syncable:(bool)arg17
       subMidTier:(bool)arg18
      subHighTier:(bool)arg19
monetizationModel:(id)arg20
           policy:(id)arg21
     analyticsBag:(id)arg22
       artworkUrn:(id)arg23
         itemType:(long long)arg24
 imageUrlTemplate:(id)arg25
      secretToken:(id)arg26
playlistStationUrn:(id)arg27
     permalinkURL:(id)arg28
            genre:(id)arg29 {
    return %orig(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9,
                 arg10, arg11,
                 NO,     // monetizable
                 arg13, arg14,
                 NO,     // blocked
                 NO,     // snipped
                 arg17, arg18, arg19,
                 arg20, arg21, arg22, arg23, arg24, arg25, arg26, arg27, arg28, arg29);
}

%end

// ============================================================================
// MARK: - Upsell Suppression
// ============================================================================

%hook SCSoundCloudUpsellManager

- (bool)shouldUpsell                        { return NO; }
- (bool)shouldUpsellCreator                 { return NO; }
- (bool)shouldUpsellForTrack:(id)arg1       { return NO; }
- (bool)shouldShowTabBarUpsell              { return NO; }
- (bool)canNotUpsell                        { return YES; }
- (bool)shouldUpsellForPlaylist:(id)arg1    { return NO; }
- (bool)shouldUpsellGoLite                  { return NO; }

%end

// ============================================================================
// MARK: - Premium Feature Flags
// ============================================================================

%hook SCSoundCloudUserFeaturesService

- (bool)isNoAudioAdsEnabled         { return YES; }
- (bool)isHQAudioFeatureEnabled     { return YES; }
- (bool)isOfflineSyncFeatureEnabled { return YES; }

%end

// ============================================================================
// MARK: - Ad Request Gating
// ============================================================================

%hook SCSoundCloudAdsRequestPermitter

- (bool)shouldRequestAds { return NO; }

%end

// ============================================================================
// MARK: - GoLite Upsell
// ============================================================================

%hook SCSoundCloudGoLitePlanManager

- (bool)isGoLiteAvailable { return NO; }

%end

// ============================================================================
// MARK: - Constructor
// ============================================================================

%ctor {
    blockerList = @[
        @"ad.getAd",
        @"adsbygoogle",
        @"/ads.",
        @"ads-",
        @"/ad/",
        @"/ad.",
        @"/adS",
        @"adlib.",
        @"/ads/",
        @"/ads?",
        @"adstm.",
        @"adorika.net",
        @"google-analytics",
        @"quantserve.com",
        @"bkrtx.com",
        @"zdtag.com",
        @"addthis.com",
        @"googletagservices.com",
        @"coinurl.com",
        @"banners.itunes.apple.com",
        @"techstats.net",
        @"doubleclick.net",
        @"mydas.mobi",
        @"googlesyndication.com",
    ];

    // Detect the sideloaded app's team prefix for keychain rewriting
    sideloadedTeamPrefix = detectBundleSeedID();

    // Register ad-blocking protocol
    [NSURLProtocol registerClass:[SCAdBlockerProtocol class]];

    // Swizzle Security framework C functions for keychain fix
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW);
    if (security) {
        void *addFunc = dlsym(security, "SecItemAdd");
        void *copyFunc = dlsym(security, "SecItemCopyMatching");
        void *updateFunc = dlsym(security, "SecItemUpdate");

        if (addFunc)    MSHookFunction(addFunc, (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd);
        if (copyFunc)   MSHookFunction(copyFunc, (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
        if (updateFunc) MSHookFunction(updateFunc, (void *)hook_SecItemUpdate, (void **)&orig_SecItemUpdate);
    }

    // Resolve Swift classes
    Class PlayQueueItemTrackEntity = SCResolveClass(
        "SoundCloud.PlayQueueItemTrackEntity",
        "_TtC10SoundCloud24PlayQueueItemTrackEntity");

    Class UserFeaturesService = SCResolveClass(
        "SoundCloud.UserFeaturesService",
        "_TtC10SoundCloud19UserFeaturesService");

    Class UpsellManager = SCResolveClass(
        "SoundCloud.UpsellManager",
        "_TtC10SoundCloud13UpsellManager");

    Class AudioAdPlayerEventController = SCResolveClass(
        "SoundCloud.AudioAdPlayerEventController",
        "_TtC10SoundCloud28AudioAdPlayerEventController");

    Class VideoAdPlayerEventController = SCResolveClass(
        "SoundCloud.VideoAdPlayerEventController",
        "_TtC10SoundCloud28VideoAdPlayerEventController");

    Class AdsRequestPermitter = SCResolveClass(
        "SoundCloud.AdsRequestPermitter",
        "_TtC10SoundCloud19AdsRequestPermitter");

    Class GoLitePlanManager = SCResolveClass(
        "SoundCloud.GoLitePlanManager",
        "_TtC10SoundCloud17GoLitePlanManager");

    %init(
        SCSoundCloudPlayQueueItemTrackEntity    = PlayQueueItemTrackEntity    ?: NSObject.class,
        SCSoundCloudUserFeaturesService          = UserFeaturesService          ?: NSObject.class,
        SCSoundCloudUpsellManager                = UpsellManager                ?: NSObject.class,
        SCSoundCloudAudioAdPlayerEventController = AudioAdPlayerEventController ?: NSObject.class,
        SCSoundCloudVideoAdPlayerEventController = VideoAdPlayerEventController ?: NSObject.class,
        SCSoundCloudAdsRequestPermitter          = AdsRequestPermitter          ?: NSObject.class,
        SCSoundCloudGoLitePlanManager            = GoLitePlanManager            ?: NSObject.class
    );
}
