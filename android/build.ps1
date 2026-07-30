# Build the CamCoreEQ APK. No Gradle: raw aapt2 / javac / d8 / jar / zipalign / apksigner.
#
# Prereqs (all user-scope, no admin):
#   - Android SDK with build-tools;35.0.0 and platforms;android-35
#   - A JDK on PATH (javac / keytool / jar). Temurin 25 works.
# Override the SDK location with -Sdk if yours differs.
#
# The signing keystore lives OUTSIDE the repository and is created on first run.
# KEEP IT: Android will refuse to update an installed app signed with a different key,
# so losing it means every user has to uninstall and reinstall.
#
# When the WEB app changes: nothing here needs touching -- installed apps pick it up
# over the air. Only bump versionCode/versionName and NATIVE_VERSION when this SHELL
# changes, and bump build.json's nativeVersion in the same commit.

param(
  [string]$Sdk  = "$env:USERPROFILE\android-sdk",
  [string]$Keys = "$env:USERPROFILE\OneDrive\Desktop\camcoreeq-android-keys"
)

$ErrorActionPreference = 'Stop'

$android = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo    = Split-Path -Parent $android
$bt      = Join-Path $Sdk 'build-tools\35.0.0'
$jar     = Join-Path $Sdk 'platforms\android-35\android.jar'
$build   = Join-Path $android 'build'

if (-not (Test-Path $jar))            { throw "Android SDK platform not found at $jar" }
if (-not (Test-Path "$bt\aapt2.exe")) { throw "build-tools 35.0.0 not found at $bt" }

# ---- clean staging ----
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force "$build\assets\www","$build\res","$build\classes","$build\dex" | Out-Null

# ---- stage the web app ----
# build.json ships too: WebStore reads it to learn which build the bundled copy is, and
# the OTA updater compares that against what GitHub Pages publishes. Without it the app
# cannot tell whether a download is newer.
Copy-Item "$repo\index.html","$repo\build.json" "$build\assets\www\"

# ---- stage resources ----
Copy-Item -Recurse -Force "$android\res\*" "$build\res\"
if (-not (Test-Path "$build\res\mipmap-xxxhdpi\ic_launcher.png")) {
  throw "launcher icon missing - run: node android\make-icon.mjs android\res\mipmap-xxxhdpi\ic_launcher.png 192"
}

# ---- compile + link resources ----
& "$bt\aapt2.exe" compile --dir "$build\res" -o "$build\res.zip"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }
& "$bt\aapt2.exe" link -o "$build\unsigned.apk" -I $jar --manifest "$android\AndroidManifest.xml" --auto-add-overlay "$build\res.zip"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

# ---- compile java + dex ----
$javaSrc = Get-ChildItem -Recurse "$android\src" -Filter *.java | ForEach-Object { $_.FullName }
& javac --release 11 -Xlint:-options -classpath $jar -d "$build\classes" @javaSrc
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
$classes = Get-ChildItem -Recurse "$build\classes" -Filter *.class | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --release --lib $jar --min-api 24 --output "$build\dex" @classes
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }

# ---- add classes.dex + assets ----
# Assets are added with `jar`, NOT aapt2 -A: on Windows aapt2 writes zip entries with
# backslashes (assets/www\index.html) and Android's AssetManager cannot resolve those.
# jar always normalises to forward slashes.
Push-Location "$build\dex"; & jar -uf "$build\unsigned.apk" classes.dex; Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'jar dex update failed' }
Push-Location $build; & jar -uf "$build\unsigned.apk" assets; Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'jar assets update failed' }

# ---- align ----
& "$bt\zipalign.exe" -f 4 "$build\unsigned.apk" "$build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

# ---- keystore (created once, then reused forever) ----
New-Item -ItemType Directory -Force $Keys | Out-Null
$ksFile = Join-Path $Keys 'camcoreeq.keystore'
$pwFile = Join-Path $Keys 'keystore-password.txt'
if (-not (Test-Path $ksFile)) {
    $pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 24 | ForEach-Object {[char]$_})
    Set-Content -Path $pwFile -Value $pw -Encoding ascii -NoNewline
    & keytool -genkeypair -keystore $ksFile -alias camcoreeq -keyalg RSA -keysize 2048 -validity 10000 `
        -storepass $pw -keypass $pw -dname 'CN=CamCoreEQ'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
    Write-Host "NOTE: created a new keystore at $ksFile - back this up and keep it."
}
$pw = Get-Content $pwFile -Raw

# ---- sign + verify ----
& "$bt\apksigner.bat" sign --ks $ksFile --ks-key-alias camcoreeq --ks-pass "pass:$pw" --key-pass "pass:$pw" --out "$build\CamCoreEQ.apk" "$build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }
& "$bt\apksigner.bat" verify "$build\CamCoreEQ.apk"
if ($LASTEXITCODE -ne 0) { throw 'apksigner verify failed' }

Write-Host "OK -> $build\CamCoreEQ.apk"
