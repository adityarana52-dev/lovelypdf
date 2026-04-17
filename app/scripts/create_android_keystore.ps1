param(
    [string]$KeystoreFile = "docpdf-release.jks",
    [string]$Alias = "docpdf",
    [string]$StorePassword = "ChangeThisStorePassword123!",
    [string]$Dname = "CN=DocPDF, OU=Mobile, O=DocPDF, L=Delhi, S=Delhi, C=IN",
    [int]$ValidityDays = 10000
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $projectRoot "android"
$keystorePath = Join-Path $projectRoot $KeystoreFile
$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"

if (-not (Test-Path $keytool)) {
    throw "keytool not found at $keytool"
}

if (Test-Path $keystorePath) {
    throw "Keystore already exists: $keystorePath"
}

& $keytool -genkeypair `
    -v `
    -keystore $keystorePath `
    -storepass $StorePassword `
    -alias $Alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -dname $Dname

$keyPropertiesPath = Join-Path $androidDir "key.properties"
@"
storePassword=$StorePassword
keyPassword=$StorePassword
keyAlias=$Alias
storeFile=../../$KeystoreFile
"@ | Set-Content -Path $keyPropertiesPath -Encoding Ascii

Write-Host "Keystore created at: $keystorePath"
Write-Host "Key properties created at: $keyPropertiesPath"
