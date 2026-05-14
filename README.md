<p align="center">
  <img src="https://rov3r.github.io/depictions/assets/images/scmusicplus-icon.png" width="150" title="SCMusicPlusRevanced">
</p>

# SCMusicPlusRevanced
Enhance your SoundCloud experience with the following features:
- Remove Ads (network-level URL blocking + audio ad controller disabled)
- Remove Upsell & Go Lite Prompts
- Unlock Full Track Playback (removes snipped/blocked restrictions)
- Enable HQ Audio
- Geo Monetization Bypass

Note: To ensure all ads are blocked, use a DNS filter like NextDNS to block the domain `ads.soundcloud.com`

# Building
You can build the project any time using GitHub Actions. Just run `build.yml` and you will get both rootful and rootless debs in a zip file.

Alternatively, build locally on Linux/WSL:
```bash
export THEOS=~/theos
cd SCMusicPlusRevanced_project
make package
```

# Known Issues
- Sideloading without TrollStore breaks sign-in, even with unmodified ipa
- Sideloading without TrollStore, on (at least) 7.55.0 or higher, app will crash on launch, even with unmodified ipa

# Installation
**Jailbroken:** Add the repo: `https://rov3r.github.io/`

**Sideloaded (TrollStore):**
- Download the REGULAR SoundCloud app from the App Store (IMPORTANT)
- Sign in to the app
- Delete the app while still signed in
- Download the `.ipa` from a source of your choosing
- Use Sideloadly to merge the deb (in Releases) with the ipa
- Once installed, you should already be logged in

**Sideloaded (Developer Account):**
- Link a Google or Facebook account to your SoundCloud account first (do this on the SoundCloud website)
- Download the `.ipa` from a source of your choosing
- Use Sideloadly to merge the deb (in Releases) with the ipa
- Install using your preferred sideloading method (AltStore, Sideloadly, appdb, etc.)
- Once installed, sign in via Google or Facebook only — regular email sign-in does not work for sideloaded installs

For troubleshooting assistance, please see the Issues section of this repository.

# Changelog

### 26.1.0-1
- Updated `initWithUrn:` signature for latest SoundCloud binary (`isPrivate:` param added between `shareable:` and `blocked:`)
- Added `isMonetizableAdGeo` hook (new geo-based monetization check)
- Added `shouldUpsellGoLite` hook (new Go Lite upsell variant)
- Merged ADsBlocker URL filtering into single tweak — one dylib, one install
- Forked as SCMusicPlusRevanced

### 24.9.1-3 (moe's build)
- Updated `initWithUrn:` to v24.x signature with `artworkUrn`, `itemType`, `secretToken`, `playlistStationUrn`, `permalinkURL` params
- Patched `blocked` and `snipped` flags alongside `monetizable`

### Original (Rov3r)
- Initial release
