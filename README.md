# 📱 Qordy Personel (Garson, Mutfak KDS, POS & WMS)

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://flutter.dev)
[![State Management](https://img.shields.io/badge/State-Riverpod%202.x-5E50F9?style=for-the-badge)](https://riverpod.dev)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20Architecture-blueviolet?style=for-the-badge)](https://flutter.dev)

**Qordy Personel**, restoran, kafe, bar ve perakende işletmeleri için tasarlanmış yüksek performanslı, rol tabanlı operasyonel mobil terminal uygulamasıdır. Garson el terminali, mutfak ekranı (KDS), kasa/POS noktası ve depo stok yönetimini tek bir modern Flutter çatısı altında birleştirir.

---

## 🚀 Öne Çıkan Modüller ve Özellikler

### 1. 🛎️ Garson (Waiter) Terminali
* **Canlı Masa Haritası & Durumları**: Dolu, boş, rezerve, hesap istendi ve geciken masaların anlık renk kodlu takibi.
* **Hızlı Sipariş Girişi & Masa Detayı**: Kategorize menü, varyasyonlar, porsiyon/özellik seçimi ve sipariş notları.
* **🎙️ AI Destekli Sesli Sipariş (`ai_voice_order_sheet`)**: Speech-to-Text ile personelin sesli olarak masaya sipariş eklemesi.
* **🤖 AI Masa Rezervasyon Asistanı (`ai_reservation_sheet`)**: Hızlı ve akıllı rezervasyon kayıt sihirbazı.

### 2. 🍳 Mutfak KDS (Kitchen Display System)
* **Gerçek Zamanlı Sipariş Akışı**: WebSocket üzerinden anında mutfak ekranına düşen sipariş fişleri.
* **Hazırlık Aşamaları**: Beklemede, Hazırlanıyor, Hazır, Teslim Edildi durum geçişleri ve süre takibi.
* **Görsel & Sesli İkazlar**: Geciken siparişler için otomatik uyarılar ve etkileşimli tava animasyonu (`sizzling_pan_animation`).

### 3. 💳 POS & Kasa Terminali
* **Tahsilat & Ödeme**: Nakit, Kredi Kartı ve Cari ödeme seçenekleri.
* **Parçalı Hesap (Split Bill)**: Kişi başı veya tutar bazlı parçalı hesap bölme (`split_bill_dialog`).
* **Adisyon & İkram/İptal Yönetimi**: Yetkili onaylı ikram, indirim ve masa transferi.

### 4. 📦 Perakende & Depo Yönetimi (Retail WMS)
* **Kör Stok Sayımı (`blind_stocktake_screen`)**: Sistem stoğunu personele göstermeden tarafsız ve güvenli sayım.
* **Karanlık Depo Toplayıcı (`dark_store_picker_screen`)**: E-ticaret ve hızlı teslimat siparişlerini optimize rota ile raftan toplama.
* **Endüstriyel PDA & Barkod Desteği (`pda_barcode_scanner`)**: Donanımsal tarayıcılar ve kamera ile seri okutma.
* **Mobil Etiket Yazıcı Servisi (`mobile_label_printer_service`)**: Bluetooth/Ağ etiket ve fiş yazıcı entegrasyonu.

### 5. ⚡ Gerçek Zamanlı Altyapı & Senkronizasyon
* **Canlı WebSocket Akışı**: Sipariş, masa durumu ve çağrı bildirimlerinin tüm terminallerle anlık senkronizasyonu.
* **Otomatik Reconnect**: Bağlantı koptuğunda arka planda otomatik yeniden bağlanma ve veri eşitleme.

### 6. 🔒 Güvenlik, Biyometri & Native Entegrasyonlar
* **Biyometrik Kimlik Doğrulama**: FaceID / TouchID / Parmak İzi ile şifresiz anında giriş (`BiometricService`).
* **Uygulama İçi Kilit Ekranı**: Güvenlik zaman aşımı veya arka plana geçişte otomatik kilit (`AppLockOverlayWrapper`).
* **Korumalı Hafıza**: JWT token ve hassas işletme anahtarlarının şifreli saklanması (`flutter_secure_storage`).
* **📱 Native HomeWidget**: Android ve iOS ana ekranında canlı ciro, açık masa ve bekleyen sipariş widget senkronizasyonu (`PersonelWidgetSyncService`).
* **🌐 Çoklu Dil & Tema**: Türkçe ve İngilizce tam dil desteği, modern Light/Dark tema ve adaptif scroll davranışı.

---

## 🏛️ Mimari ve Proje Yapısı

Proje, **Feature-First Clean Architecture** prensipleriyle tasarlanmıştır:

```text
lib/
├── main.dart                          # Uygulama başlangıcı, global provider'lar ve tema
└── src/
    ├── core/                          # Çekirdek servisler ve altyapı
    │   ├── common_widgets/            # Yeniden kullanılabilir UI bileşenleri (Button, Card, Search vb.)
    │   ├── config/                    # API Base URL ve global ortam değişkenleri (AppConfig)
    │   ├── data/                      # Global modeller ve JSON dönüştürücüler
    │   ├── localization/              # TR/EN çoklu dil yönetimi (AppLocalizations)
    │   ├── network/                   # Dio tabanlı ApiClient ve WebSocket altyapısı
    │   ├── providers/                 # Auth, Dashboard, Vardiya ve Masa Riverpod sağlayıcıları
    │   ├── routing/                   # GoRouter deklaratif yönlendirme ve rota koruyucuları
    │   ├── security/                  # Şifreli depolama ve kimlik yönetimi
    │   ├── services/                  # Bildirim, HomeWidget, Biyometri ve Yaşam Döngüsü servisleri
    │   ├── theme/                     # Qordy UI Tasarım Sistemi (Renkler, Tipografi, Temalar)
    │   └── utils/                     # Güvenli parse işlemleri, para birimi ve snackbar yardımcıları
    └── features/                      # İş mantığı ve ekranlar
        ├── auth/                      # Giriş, 4 adımlı kayıt, OTP ve şifre sıfırlama
        ├── business/                  # İşletme metrikleri, masa ve sipariş modelleri
        ├── kitchen/                   # Mutfak KDS ekranı ve animasyonları
        ├── pos/                       # Kasa terminali ve parçalı ödeme ekranları
        ├── preparation/               # Bar / Hazırlık istasyon dashboard'u
        ├── retail_wms/                # Depo sayım, toplama ve barkod çözümleri
        └── waiter/                    # Garson masa planı, masa detayları ve AI sipariş fişleri
```

---

## 🛠️ Kurulum ve Geliştirme

### Gereksinimler
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.12.2` veya güncel stable)
* [Dart SDK](https://dart.dev)
* Android Studio / Xcode (macOS için)
* CocoaPods (iOS derlemeleri için: `brew install cocoapods`)

### 1. Depoyu Klonlayın
```bash
git clone https://github.com/ilkeraydogdu/personel_app.git
cd personel_app
```

### 2. Bağımlılıkları Yükleyin
```bash
flutter pub get
```

### 3. Kod Üretimini Çalıştırın (Freezed / Riverpod / JSON)
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Uygulamayı Başlatın
```bash
# Standart çalıştırma (Varsayılan: https://qordy.com)
flutter run

# Farklı bir API sunucusu tanımlayarak çalıştırma:
flutter run --dart-define=QORDY_API_BASE=https://staging.qordy.com
```

---

## 📦 Derleme ve Canlıya Alma (Build & Deploy)

Proje kök dizininde hazır optimize derleme betikleri bulunmaktadır:

### Android Release APK
Optimize edilmiş, kod karmaşıklaştırması (obfuscation) yapılmış ve sembol tablosu ayrıştırılmış APK üretir:
```bash
chmod +x build_apk.sh
./build_apk.sh
```
*Çıktı konumu: `build/app/outputs/flutter-apk/app-release.apk`*

### iOS IPA & Simulator Derlemesi
```bash
chmod +x build_ios.sh

# Geliştirme / Simülatör için:
./build_ios.sh --simulator

# App Store / TestFlight için IPA paketi:
./build_ios.sh --ipa

# İmzalamasız yerel test paketi:
./build_ios.sh
```

---

## 🔄 Git & Güncelleme İş Akışı

Projeye yeni bir özellik eklerken veya güncelleme yaparken aşağıdaki adımları izleyebilirsiniz:

```bash
# 1. En son değişiklikleri çekin
git pull origin main

# 2. Değişiklikleri yapın ve kontrol edin
flutter analyze
git status

# 3. Değişiklikleri sahneye ekleyin
git add .

# 4. Anlamlı bir commit mesajı ile kaydedin
git commit -m "feat(waiter): AI sesli sipariş filtresi optimize edildi"

# 5. GitHub'a gönderin
git push origin main
```

---

## 🤖 GitHub Actions CI/CD

Depoda entegre çalışan CI boru hatları mevcuttur:
* **`Qordy Personel CI`**: Her `push` ve `pull_request` işleminde otomatik `flutter analyze` ve `flutter test` kontrollerini çalıştırır.
* **`Build Android APK`**: GitHub Actions sekmesinden manuel tek tıkla (`workflow_dispatch`) Release veya Debug APK derleyip indirilebilir artifact olarak sunar.

---

## 📄 Lisans & Telif Hakkı
Bu yazılımın tüm hakları **Qordy** ve **İlker Aydoğdu**'ya aittir. İzinsiz kopyalanamaz, çoğaltılamaz veya dağıtılamaz.
