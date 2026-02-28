# SlideCrop App Store Submission Checklist

Last verified: February 27, 2026

## Completed in Project

- [x] App icon set present in `/Users/sira27/Desktop/SlideCrop/SlideCrop/Resources/Assets.xcassets/AppIcon.appiconset`, including `ios-marketing.png` (1024x1024).
- [x] Marketing icon confirmed non-alpha (`hasAlpha: no`).
- [x] Launch screen configured and referenced via `UILaunchStoryboardName = LaunchScreen`.
- [x] Privacy usage descriptions present in `Info.plist`:
  - `NSPhotoLibraryUsageDescription`
  - `NSPhotoLibraryAddUsageDescription`
- [x] `ITSAppUsesNonExemptEncryption = false` in `Info.plist`.
- [x] Privacy manifest present: `/Users/sira27/Desktop/SlideCrop/SlideCrop/Resources/PrivacyInfo.xcprivacy`.
- [x] In-app Settings contains Privacy Policy + Contact Support.
- [x] Simulator build passes.
- [x] Static analysis (`xcodebuild analyze`) passes.
- [x] Release device build passes (`generic/platform=iOS`).
- [x] Signed archive created:
  - `/Users/sira27/Desktop/SlideCrop/build/SlideCrop.xcarchive`

## Current Blocking Item

- [ ] App Store export/upload profile not available for bundle ID `com.local.SlideCrop`.
  - Current export error: `No profiles for 'com.local.SlideCrop' were found`.

## Must Be Done in Apple Developer / App Store Connect

- [ ] Use a production bundle ID (recommended) instead of `com.local.SlideCrop`.
- [ ] Create/confirm matching App ID in Apple Developer.
- [ ] Create app record in App Store Connect with the exact same bundle ID.
- [ ] Ensure your selected team is a paid Apple Developer Program team with App Store distribution enabled.
- [ ] In Xcode Signing, keep Automatic signing enabled for Release and confirm team/profile resolution.
- [ ] Archive from Organizer and upload to App Store Connect.
- [ ] Complete App Store Connect metadata:
  - Name, subtitle, description, keywords, category
  - Privacy Policy URL
  - Support URL
  - Screenshots
  - App Privacy questionnaire
  - Export compliance answers
  - Review notes and test instructions

## Final Device QA Before Submit

- [ ] Test on a real iPhone with iCloud Photos enabled:
  - Full Photos access flow
  - Limited library flow
  - Save as new images
  - Replace originals (revertible edits)
- [ ] Validate manual crop flow for low-confidence/failed detections.
- [ ] Confirm no visual clipping/layout issues on small and large devices.
- [ ] Set final version/build:
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`
