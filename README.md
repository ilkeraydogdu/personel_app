# Qordy Staff (Personel App)

> **Enterprise Operations Terminal for Hospitality & Retail Ecosystem**  
> Powered by [Qordy.com](https://qordy.com)

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://qordy.com)
[![State Management](https://img.shields.io/badge/State-Riverpod%202.x-5E50F9?style=for-the-badge)](https://riverpod.dev)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20Architecture-blueviolet?style=for-the-badge)](https://flutter.dev)
[![Website](https://img.shields.io/badge/Official%20Website-qordy.com-00B4D8?style=for-the-badge)](https://qordy.com)

---

## 📌 Overview

**Qordy Staff** (`personel_app`) is the mission-critical operational terminal built for restaurants, cafes, bars, and retail enterprises operating on the [Qordy Platform](https://qordy.com). 

Designed for high-speed shifts, it unifies Waiter El-Terminals, Kitchen Display Systems (KDS), POS/Cashier Desks, and Warehouse Inventory Pickers into a single responsive, multi-role mobile application.

---

## ⚡ Core Modules

### 🛎️ 1. Waiter Terminal
* **Dynamic Table Matrix**: Live status indicators for occupied, vacant, reserved, pending bill, and overdue tables.
* **Rapid Order Entry**: Instant menu navigation, portion modifiers, item notes, and ticket routing.
* **AI Voice Orders**: Real-time voice-to-order parsing powered by Speech-to-Text (`ai_voice_order_sheet`).
* **AI Reservation Assistant**: Fast booking wizard with guest party and timing validation (`ai_reservation_sheet`).

### 🍳 2. Kitchen Display System (KDS)
* **Real-Time Ticket Stream**: Zero-latency kitchen display fed directly via WebSocket pipelines.
* **Lifecycle Tracking**: Multi-state order stages (*Queued ➔ Preparing ➔ Ready ➔ Delivered*).
* **Audio-Visual Urgency**: Visual timers, color thresholds, and interactive animations (`sizzling_pan_animation`).

### 💳 3. POS & Cashier Station
* **Multi-Channel Settlement**: Seamless cash, credit card, and corporate account checkouts.
* **Split Billing**: Flexible bill division by person, custom percentage, or itemized splits (`split_bill_dialog`).
* **Table Closure**: Manager-approved discounts, cancellations, and table transfers.

### 📦 4. Retail & Warehouse Management (WMS)
* **Blind Stocktaking (`blind_stocktake_screen`)**: Impartial inventory audit without bias from theoretical counts.
* **Dark Store Picker (`dark_store_picker_screen`)**: Optimized path routing for high-volume quick-commerce orders.
* **Industrial PDA Scanning (`pda_barcode_scanner`)**: Hardware-accelerated barcode and QR scanning.
* **Mobile Label & Receipt Service (`mobile_label_printer_service`)**: Wireless Bluetooth and network thermal printing.

### 🔒 5. Enterprise Security & Native Experience
* **Biometric Authentication**: Instant touchless sign-in via Face ID / Touch ID / Fingerprint (`BiometricService`).
* **Auto-Lock Overlay**: Screen shielding during background transitions or session timeouts (`AppLockOverlayWrapper`).
* **Native Home Widgets**: Real-time shift stats, open tables, and kitchen counters right on the device home screen (`home_widget`).
* **Encrypted Storage**: Secure AES hardware-backed credential storage (`flutter_secure_storage`).

---

## 🏛️ Architecture & Directory Layout

Built on **Feature-First Clean Architecture** principles:

```text
lib/
├── main.dart                          # Application entry point, global observers & theme bootstrap
└── src/
    ├── core/                          # Cross-cutting foundational services
    │   ├── common_widgets/            # Reusable UI library (Buttons, Cards, Search, OTP)
    │   ├── config/                    # Global environment configurations & Base URLs (AppConfig)
    │   ├── data/                      # Global models, serializable entities, JSON utilities
    │   ├── localization/              # Internationalization (EN / TR)
    │   ├── network/                   # Dio HTTP client with JWT interceptors & WebSocket client
    │   ├── providers/                 # Core Riverpod providers (Auth, Dashboard, Shift, Tables)
    │   ├── routing/                   # GoRouter navigation & role-based route guards
    │   ├── security/                  # Hardware-backed keystore & secure token storage
    │   ├── services/                  # Notification, HomeWidget, Biometric & Lifecycle services
    │   ├── theme/                     # Corporate design system (Dark & Light themes, typography)
    │   └── utils/                     # Formatters, currency helpers, and defensive parsers
    └── features/                      # Domain features
        ├── auth/                      # Multi-step authentication, onboarding & recovery
        ├── business/                  # Business metrics, table matrices & order models
        ├── kitchen/                   # KDS dashboard & live kitchen animations
        ├── pos/                       # Cashier terminal, split billing & payments
        ├── preparation/               # Bar & beverage preparation dashboard
        ├── retail_wms/                # Warehouse stocktaking, picking & barcode integrations
        └── waiter/                    # Floor plan, table details & AI order assistants
```

---

## 🛠️ Getting Started

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.12.2` or latest stable)
* [Dart SDK](https://dart.dev)
* Android Studio / Xcode
* CocoaPods (`brew install cocoapods` on macOS)

### 1. Clone the Repository
```bash
git clone git@github.com:ilkeraydogdu/personel_app.git
cd personel_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Generate Code Assets (Riverpod / Freezed / JSON)
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run the Application
```bash
# Default production configuration (https://qordy.com)
flutter run

# Custom API endpoint
flutter run --dart-define=QORDY_API_BASE=https://staging.qordy.com
```

---

## 📦 Build & Release

Pre-configured, production-optimized deployment scripts:

```bash
# Android Release APK (Code obfuscated, stripped symbols):
./build_apk.sh

# iOS Simulator Build:
./build_ios.sh --simulator

# iOS App Store / TestFlight IPA:
./build_ios.sh --ipa
```

---

## 🤖 CI/CD Pipelines

Automated via **GitHub Actions**:
* **`Qordy Personel CI`**: Runs `flutter analyze` and `flutter test` automatically on every push and pull request.
* **`Build Android APK`**: Manual on-demand release build trigger (`workflow_dispatch`) delivering downloadable APK artifacts.

---

## 🌐 Enterprise & Support

For enterprise deployments, custom white-label solutions, or technical support, visit our corporate portal:

* **Official Website**: [https://qordy.com](https://qordy.com)
* **Company**: Qordy Hospitality & Retail Technologies
* **Copyright**: © 2026 Qordy. All rights reserved.
