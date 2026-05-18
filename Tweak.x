#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// SCMusicPlusRevanced — SoundCloud v8.60.0
// Sideload fixes handled by sideloadKeychainfix.dylib

static NSArray *blockerList = nil;

static BOOL isBlockedURL(NSString *urlString) {
    if (!urlString) return NO;
    for (NSString *pattern in blockerList) {
        if ([urlString containsString:pattern]) return YES;
    }
    return NO;
}

// try dotted name first, fall back to mangled
static Class SCResolveClass(const char *dottedName, const char *mangledName) {
    Class cls = objc_getClass(dottedName);
    if (!cls && mangledName) cls = objc_getClass(mangledName);
    return cls;
}

// --- ad url blocking (NSURLProtocol) ---

@interface SCAdBlockerProtocol : NSURLProtocol
@end

@implementation SCAdBlockerProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"SCAdBlockerHandled" inRequest:request])
        return NO;
    return isBlockedURL(request.URL.absoluteString);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    [self.client URLProtocol:self didFailWithError:
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}

- (void)stopLoading { }

@end

// inject our protocol into every url session
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

// --- objc ad stuff ---

%hook AdPlayQueueManager

- (bool)isItemMonetizable:(id)arg1 {
    return NO;
}

%end

%hook PlayQueueTrack

- (bool)isMonetizable {
    return NO;
}

// legacy init — force monetizable/blocked/snipped off
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
                 arg11, arg12, NO, arg14, NO, NO,
                 arg17, arg18, arg19, arg20, arg21, arg22, arg23, arg24);
}

%end

// --- swift ad controllers (neuter init, upstream hooks prevent them from firing) ---

%hook SCSoundCloudAudioAdPlayerEventController
- (id)init { return %orig; }
%end

%hook SCSoundCloudVideoAdPlayerEventController
- (id)init { return %orig; }
%end

// --- PlayQueueItemTrackEntity (swift, v8.60.0 signature) ---

%hook SCSoundCloudPlayQueueItemTrackEntity

- (bool)isMonetizable    { return NO; }
- (bool)isMonetizableAdGeo { return NO; }

// v8.60.0 init — force monetizable/blocked/snipped off
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
                 arg10, arg11, NO, arg13, arg14, NO, NO,
                 arg17, arg18, arg19, arg20, arg21, arg22, arg23, arg24,
                 arg25, arg26, arg27, arg28, arg29);
}

%end

// --- kill upsells ---

%hook SCSoundCloudUpsellManager

- (bool)shouldUpsell                        { return NO; }
- (bool)shouldUpsellCreator                 { return NO; }
- (bool)shouldUpsellForTrack:(id)arg1       { return NO; }
- (bool)shouldShowTabBarUpsell              { return NO; }
- (bool)canNotUpsell                        { return YES; }
- (bool)shouldUpsellForPlaylist:(id)arg1    { return NO; }
- (bool)shouldUpsellGoLite                  { return NO; }

%end

// --- premium feature flags ---

%hook SCSoundCloudUserFeaturesService

- (bool)isNoAudioAdsEnabled     { return YES; }
- (bool)isHQAudioFeatureEnabled { return YES; }

%end

// --- block ad requests at source ---

%hook SCSoundCloudAdsRequestPermitter
- (bool)shouldRequestAds { return NO; }
%end

// --- suppress golite upsell ---

%hook SCSoundCloudGoLitePlanManager
- (bool)isGoLiteAvailable { return NO; }
%end

// --- init ---

%ctor {
    blockerList = @[
        @"ad.getAd", @"adsbygoogle", @"/ads.", @"ads-",
        @"/ad/", @"/ad.", @"/adS", @"adlib.",
        @"/ads/", @"/ads?", @"adstm.",
        @"adorika.net", @"google-analytics", @"quantserve.com",
        @"bkrtx.com", @"zdtag.com", @"addthis.com",
        @"googletagservices.com", @"coinurl.com",
        @"banners.itunes.apple.com", @"techstats.net",
        @"doubleclick.net", @"mydas.mobi", @"googlesyndication.com",
    ];

    [NSURLProtocol registerClass:[SCAdBlockerProtocol class]];

    Class PlayQueueItemTrackEntity    = SCResolveClass("SoundCloud.PlayQueueItemTrackEntity",    "_TtC10SoundCloud24PlayQueueItemTrackEntity");
    Class UserFeaturesService          = SCResolveClass("SoundCloud.UserFeaturesService",          "_TtC10SoundCloud19UserFeaturesService");
    Class UpsellManager                = SCResolveClass("SoundCloud.UpsellManager",                "_TtC10SoundCloud13UpsellManager");
    Class AudioAdPlayerEventController = SCResolveClass("SoundCloud.AudioAdPlayerEventController", "_TtC10SoundCloud28AudioAdPlayerEventController");
    Class VideoAdPlayerEventController = SCResolveClass("SoundCloud.VideoAdPlayerEventController", "_TtC10SoundCloud28VideoAdPlayerEventController");
    Class AdsRequestPermitter          = SCResolveClass("SoundCloud.AdsRequestPermitter",          "_TtC10SoundCloud19AdsRequestPermitter");
    Class GoLitePlanManager            = SCResolveClass("SoundCloud.GoLitePlanManager",            "_TtC10SoundCloud17GoLitePlanManager");

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
