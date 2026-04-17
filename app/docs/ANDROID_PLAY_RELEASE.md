# Android Play Release Guide

This project is prepared for Android release signing and Play Store submission.

## 1. Create a release keystore

Run from the project root:

```powershell
cd C:\Users\Adi\Documents\docpdf\app
.\scripts\create_android_keystore.ps1
```

This creates:

- `docpdf-release.jks`
- `android\key.properties`

Important:

- Keep the `.jks` file safe
- Keep the passwords safe
- Do not lose the keystore
- Do not commit `android\key.properties` or the `.jks` file

If you want custom passwords:

```powershell
.\scripts\create_android_keystore.ps1 `
  -StorePassword "YourStorePassword123!" `
  -Alias "docpdf"
```

## 2. Build Play Store bundle

```powershell
cd C:\Users\Adi\Documents\docpdf\app
$env:ANDROID_SDK_ROOT="C:\Users\Adi\AppData\Local\Android\Sdk"
C:\Users\Adi\Documents\docpdf\.flutter-sdk\bin\flutter.bat build appbundle --release
```

Output:

- `build\app\outputs\bundle\release\app-release.aab`

## 3. Build release APK for testing

```powershell
cd C:\Users\Adi\Documents\docpdf\app
$env:ANDROID_SDK_ROOT="C:\Users\Adi\AppData\Local\Android\Sdk"
C:\Users\Adi\Documents\docpdf\.flutter-sdk\bin\flutter.bat build apk --release
```

## 4. Play Console checklist

- Final app icon
- Final screenshots
- Short description
- Full description
- App category
- Privacy policy URL
- Data safety form
- App content declarations
- Test release on Internal testing track

## 5. Current app notes

- App label is `DocPDF`
- Android package id is `com.docpdf.scanner`
- Temporary file retention is currently `1 hour`
- Release signing uses `android\key.properties` when available

## 6. Before production publish

- Replace placeholder icon with final brand icon
- Review texts and language
- Test scanning on at least 2 Android phones
- Verify share flow with WhatsApp and email
- Verify auto cleanup after 1 hour
- Increment app version before each Play upload
