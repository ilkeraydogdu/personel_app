#!/bin/bash
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
DOWNLOAD_DIR="/var/www/vhosts/qordy.com/httpdocs/public/downloads"

export ANDROID_HOME="/opt/android-sdk"
export ANDROID_SDK_ROOT="/opt/android-sdk"
export PATH="$PATH:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin"

mkdir -p "$DOWNLOAD_DIR"

echo "=== Removing old Personnel APKs ==="
rm -f "$DOWNLOAD_DIR/qordy-personel.apk" "$DOWNLOAD_DIR/personel-app.apk" "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

cd "$APP_DIR"

echo "=== Cleaning previous build artifacts ==="
/opt/flutter/bin/flutter clean
/opt/flutter/bin/flutter pub get

echo "=== Building Qordy Personel Release APK (Optimized & Stripped) ==="
/opt/flutter/bin/flutter build apk --release --obfuscate --split-debug-info="$APP_DIR/build/app/outputs/symbols"

APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

if [ -f "$APK_SRC" ]; then
    echo "=== Copying new APK to downloads directory ==="
    mkdir -p "$DOWNLOAD_DIR"
    cp -f "$APK_SRC" "$DOWNLOAD_DIR/qordy-personel.apk"
    ln -f "$DOWNLOAD_DIR/qordy-personel.apk" "$DOWNLOAD_DIR/personel-app.apk"
    chmod 644 "$DOWNLOAD_DIR"/qordy-personel.apk "$DOWNLOAD_DIR"/personel-app.apk
    chown qordy.com_jckqwoy6r4j:psacln "$DOWNLOAD_DIR"/qordy-personel.apk "$DOWNLOAD_DIR"/personel-app.apk 2>/dev/null || true
    echo "=== Cleaning up build artifacts to save disk space ==="
    rm -rf "$APP_DIR/build" "$APP_DIR/.dart_tool" "$APP_DIR/.sdk_platforms" "$APP_DIR/android/.gradle"
    echo "=== Personel APK Build & Deploy Completed Successfully! ==="
    ls -lh "$DOWNLOAD_DIR/qordy-personel.apk" "$DOWNLOAD_DIR/personel-app.apk"
else
    echo "ERROR: Release APK not found at $APK_SRC"
    exit 1
fi
