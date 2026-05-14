#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// MARK: - Ad URL Blocklist

static NSArray *blockerList = nil;

%hook NSURL

+ (id)URLWithString:(NSString *)string {
    if (!string) return %orig;
    for (NSString *domain in blockerList) {
        if ([string containsString:domain]) return nil;
    }
    return %orig;
}

%end

%hook NSURLRequest

+ (id)requestWithURL:(NSURL *)url {
    NSString *urlString = url.absoluteString;
    for (NSString *domain in blockerList) {
        if ([urlString containsString:domain]) return nil;
    }
    return %orig;
}

+ (id)requestWithURL:(NSURL *)url cachePolicy:(NSUInteger)cachePolicy timeoutInterval:(double)timeout {
    NSString *urlString = url.absoluteString;
    for (NSString *domain in blockerList) {
        if ([urlString containsString:domain]) return nil;
    }
    return %orig;
}

%end

// MARK: - SoundCloud Premium Hooks

%hook AdPlayQueueManager
- (bool)isItemMonetizable:(id)arg1 {
    return NO;
}
%end

%hook PlayQueueTrack
- (bool)isMonetizable {
    return NO;
}

// Legacy signature (pre-v24)
- (id)initWithUrn:(id)arg1 transcodings:(id)arg2 streamURL:(id)arg3 permalinkURL:(id)arg4 waveformURL:(id)arg5 artistUrn:(id)arg6 stationUrn:(id)arg7 artistName:(id)arg8 title:(id)arg9 playQueueTitle:(id)arg10 playableDuration:(double)arg11 fullDuration:(double)arg12 monetizable:(bool)arg13 shareable:(bool)arg14 blocked:(bool)arg15 snipped:(bool)arg16 syncable:(bool)arg17 subMidTier:(bool)arg18 subHighTier:(bool)arg19 policy:(id)arg20 monetizationModel:(id)arg21 analyticsBag:(id)arg22 imageUrlTemplate:(id)arg23 genre:(id)arg24 {
    arg13 = NO;
    arg15 = NO;
    arg16 = NO;
    return %orig;
}
%end

%hook SoundCloudPatchedSwiftClassNameAudioAdPlayerEventController
- (id)init {
    return NULL;
}
%end

%hook SoundCloudPatchedSwiftClassNamePlayQueueItemTrackEntity
- (bool)isMonetizable {
    return NO;
}

// isMonetizableAdGeo: new geo-based monetization check added in latest binary
- (bool)isMonetizableAdGeo {
    return NO;
}

// moe's v24.x signature
- (id)initWithUrn:(id)arg1 transcodings:(id)arg2 streamURL:(id)arg3 waveformURL:(id)arg4 artistUrn:(id)arg5 stationUrn:(id)arg6 artistName:(id)arg7 title:(id)arg8 playQueueTitle:(id)arg9 playableDurationInMs:(unsigned long long)arg10 fullDurationInMs:(unsigned long long)arg11 monetizable:(bool)arg12 shareable:(bool)arg13 blocked:(bool)arg14 snipped:(bool)arg15 syncable:(bool)arg16 subMidTier:(bool)arg17 subHighTier:(bool)arg18 monetizationModel:(id)arg19 policy:(id)arg20 analyticsBag:(id)arg21 artworkUrn:(id)arg22 itemType:(long long)arg23 imageUrlTemplate:(id)arg24 secretToken:(id)arg25 playlistStationUrn:(id)arg26 permalinkURL:(id)arg27 genre:(id)arg28 {
    arg12 = NO;
    arg14 = NO;
    arg15 = NO;
    return %orig;
}

// Latest binary: isPrivate inserted between shareable and blocked — args shift by 1
- (id)initWithUrn:(id)arg1 transcodings:(id)arg2 streamURL:(id)arg3 waveformURL:(id)arg4 artistUrn:(id)arg5 stationUrn:(id)arg6 artistName:(id)arg7 title:(id)arg8 playQueueTitle:(id)arg9 playableDurationInMs:(unsigned long long)arg10 fullDurationInMs:(unsigned long long)arg11 monetizable:(bool)arg12 shareable:(bool)arg13 isPrivate:(bool)arg14 blocked:(bool)arg15 snipped:(bool)arg16 syncable:(bool)arg17 subMidTier:(bool)arg18 subHighTier:(bool)arg19 monetizationModel:(id)arg20 policy:(id)arg21 analyticsBag:(id)arg22 artworkUrn:(id)arg23 itemType:(long long)arg24 imageUrlTemplate:(id)arg25 secretToken:(id)arg26 playlistStationUrn:(id)arg27 permalinkURL:(id)arg28 genre:(id)arg29 {
    arg12 = NO;
    arg15 = NO;
    arg16 = NO;
    return %orig;
}
%end

%hook SoundCloudPatchedSwiftClassNameUpsellManager
- (bool)shouldUpsell {
    return NO;
}

- (bool)shouldUpsellCreator {
    return NO;
}

- (bool)shouldUpsellForTrack:(id)arg1 {
    return NO;
}

- (bool)shouldShowTabBarUpsell {
    return NO;
}

- (bool)canNotUpsell {
    return YES;
}

- (bool)shouldUpsellForPlaylist:(id)arg1 {
    return NO;
}

// New in latest binary
- (bool)shouldUpsellGoLite {
    return NO;
}
%end

%hook SoundCloudPatchedSwiftClassNameUserFeaturesService
- (bool)isNoAudioAdsEnabled {
    return YES;
}

- (bool)isHQAudioFeatureEnabled {
    return YES;
}
%end

// MARK: - Constructor

%ctor {
    // Ad blocklist init
    blockerList = @[
        @"ad.getAd",
        @"adsbygoogle",
        @"/offer/",
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
    ];

    // Swift class resolution for SoundCloud hooks
    %init(
        SoundCloudPatchedSwiftClassNamePlayQueueItemTrackEntity = objc_getClass("SoundCloud.PlayQueueItemTrackEntity"),
        SoundCloudPatchedSwiftClassNameUserFeaturesService = objc_getClass("SoundCloud.UserFeaturesService"),
        SoundCloudPatchedSwiftClassNameUpsellManager = objc_getClass("SoundCloud.UpsellManager"),
        SoundCloudPatchedSwiftClassNameAudioAdPlayerEventController = objc_getClass("SoundCloud.AudioAdPlayerEventController")
    );
}
