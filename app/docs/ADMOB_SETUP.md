# AdMob Setup for LovelyPDF

The ad flow is now wired into the app in test mode:

- Home screen: small banner ad
- After successful PDF creation: interstitial ad with cooldown and frequency control

## Current behavior

For safety, the app is using Google test ads right now.

Before publishing live ads, update:

- [ad_service.dart](C:/Users/Adi/Documents/docpdf/app/lib/services/ad_service.dart)
- [AndroidManifest.xml](C:/Users/Adi/Documents/docpdf/app/android/app/src/main/AndroidManifest.xml)
- [Info.plist](C:/Users/Adi/Documents/docpdf/app/ios/Runner/Info.plist)

## Replace these values

In `lib/services/ad_service.dart`:

- Set `AdService.useTestAds` to `false`
- Replace:
  - `_androidBannerProdId`
  - `_androidInterstitialProdId`
  - `_iosBannerProdId`
  - `_iosInterstitialProdId`

In Android manifest:

- Replace the sample app ID in `com.google.android.gms.ads.APPLICATION_ID`

In iOS `Info.plist`:

- Replace `GADApplicationIdentifier`

## Play Console updates

Before release, update Play Console to match ad usage:

- `Contains ads` -> `Yes`
- Review `Data safety`
- Use the updated privacy policy that mentions ads

## Notes

- The interstitial is intentionally not shown after every single scan.
- Current policy-friendly rule:
  - after every 2 successful scans
  - at least 90 seconds between interstitials
