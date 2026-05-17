#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ============================================================================
// SCMusicPlusRevanced — SoundCloud v8.60.0
// ============================================================================

// MARK: - Helpers

static NSArray *blockerList = nil;

static BOOL isBlockedURL(NSString *urlString) {
    if (!urlString) return NO;
    for (NSString *pattern in blockerList) {
        if ([urlString containsString:pattern]) return YES;
    }
    return NO;
}

/// Resolve a Swift class by dotted name, falling back to the mangled name.
static Class SCResolveClass(const char *dottedName, const char *mangledName) {
    Class cls = objc_getClass(dottedName);
    if (!cls && mangledName) cls = objc_getClass(mangledName);
    return cls;
}

// ============================================================================
// MARK: - Ad URL Blocking via NSURLProtocol
// ============================================================================
// NSURLProtocol is the correct interception point — it works for every
// networking API (NSURLSession, NSURLConnection, etc.) and delivers a
// clean error to the caller without nil-pointer or double-callback issues.
// ============================================================================

@interface SCAdBlockerProtocol : NSURLProtocol
@end

@implementation SCAdBlockerProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // Already handled — avoid infinite loops
    if ([NSURLProtocol propertyForKey:@"SCAdBlockerHandled" inRequest:request]) {
        return NO;
    }
    return isBlockedURL(request.URL.absoluteString);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    // Immediately fail the request with a cancellation error
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorCancelled
                                     userInfo:nil];
    [self.client URLProtocol:self didFailWithError:error];
}

- (void)stopLoading { }

@end

// Hook NSURLSessionConfiguration so our protocol is injected into every
// session, including those created with custom configurations.

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

// Legacy init — present in v8.60.0 (ObjC class)
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
// MARK: - Swift: AudioAdPlayerEventController
// ============================================================================
// We only hook -init here. The event methods (startAdSession:, adDidStart:,
// etc.) are Swift-only and not visible to the ObjC runtime, so Logos can't
// hook them. With shouldRequestAds → NO and isNoAudioAdsEnabled → YES,
// the ad controllers are never triggered in practice.
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

// v8.60.0 signature (with isPrivate)
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
    // -- Ad blocklist (patterns from moe's ADsBlocker + additions) --
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

    // -- Register ad-blocking NSURLProtocol globally --
    [NSURLProtocol registerClass:[SCAdBlockerProtocol class]];

    // -- Resolve Swift classes (dotted → mangled fallback) --
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

    // -- Init only classes that were found --
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
