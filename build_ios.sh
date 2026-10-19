#!/bin/bash
set -e

echo "====================================================="
echo "  Qordy Personel (Garson / KDS / POS) — iOS Build    "
echo "====================================================="

# macOS Desktop / iCloud Drive xattr (com.apple.FinderInfo / provenance) codesign hatasını önle
CACHE_BUILD_DIR="$HOME/Library/Caches/qordy_personel_build"
mkdir -p "$CACHE_BUILD_DIR"
if [ ! -L "build" ]; then
  rm -rf build
  ln -s "$CACHE_BUILD_DIR" build
fi

echo "[1/4] Bağımlılıklar güncelleniyor (flutter pub get)..."
flutter pub get

echo "[2/4] Kod analizi çalıştırılıyor (flutter analyze)..."
flutter analyze

echo "[3/4] CocoaPods bağımlılıkları kuruluyor (pod install)..."
cd ios
pod install
cd ..

if [ "$1" == "--simulator" ]; then
  echo "[4/4] iOS Simulator sürümü derleniyor..."
  flutter build ios --simulator
  echo "✅ iOS Simulator derlemesi tamamlandı: build/ios/iphonesimulator/Runner.app"
elif [ "$1" == "--ipa" ]; then
  echo "[4/4] App Store / TestFlight IPA paketi oluşturuluyor..."
  flutter build ipa --release
  echo "✅ IPA paketi hazır: build/ios/ipa/"
else
  echo "[4/4] iOS Release (No-Codesign) derlemesi başlatılıyor..."
  flutter build ios --release --no-codesign
  echo "✅ iOS Release derlemesi tamamlandı: build/ios/iphoneos/Runner.app"
  echo "💡 İpucu: Simulator için './build_ios.sh --simulator', IPA için './build_ios.sh --ipa' kullanabilirsiniz."
fi
