<p align="center">
  <a href="https://qordy.com">
    <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0A0E1A,50:0F172A,100:1E293B&height=200&section=header&text=Qordy%20Staff&fontSize=42&fontColor=ffffff&fontAlignY=38&desc=Enterprise%20Operations%20Terminal%20for%20Hospitality%20%26%20Retail&descAlignY=60&descSize=16" width="100%"/>
  </a>
</p>

<p align="center">
  <a href="https://qordy.com">
    <img src="https://readme-typing-svg.demolab.com?font=Inter&weight=500&size=16&duration=3000&pause=1000&color=38BDF8&center=true&vCenter=true&width=620&lines=High-Performance+Flutter+3.x+Operations+Suite;Real-Time+WebSocket+Floor+Synchronization;Waiter+Console+%7C+Kitchen+KDS+%7C+POS+Desk+%7C+WMS+Picker;Official+Client+for+Qordy+Hospitality+Cloud" alt="Qordy Typing SVG" />
  </a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart" /></a>
  <a href="https://riverpod.dev"><img src="https://img.shields.io/badge/State-Riverpod%202.x-5E50F9?style=flat-square" alt="Riverpod" /></a>
  <a href="https://qordy.com"><img src="https://img.shields.io/badge/Platforms-Android%20%7C%20iOS-10B981?style=flat-square&logo=apple&logoColor=white" alt="Platforms" /></a>
  <a href="https://qordy.com"><img src="https://img.shields.io/badge/Architecture-Clean%20Architecture-6366F1?style=flat-square" alt="Clean Architecture" /></a>
  <a href="https://qordy.com"><img src="https://img.shields.io/badge/Official%20Platform-qordy.com-00B4D8?style=flat-square&logo=googlechrome&logoColor=white" alt="Qordy.com" /></a>
</p>

---

## Overview

**Qordy Staff** (`personel_app`) is an enterprise-grade operational workforce terminal built for dining, beverage, and retail businesses powered by the [Qordy Platform](https://qordy.com). 

Engineered for intense service shifts, it unifies Waiter El-Terminals, Kitchen Display Systems (KDS), Cashier & POS Stations, and Warehouse Picking operations into a single platform-adaptive Flutter codebase.

---

## System Architecture & Modules

| Module ID | Component | Operational Scope | Key Integrations |
| :--- | :--- | :--- | :--- |
| `MOD-01` | **Waiter Console** | Dynamic floor layout, table lifecycle states, ticket modifications, AI voice orders | `Speech-to-Text`, `Riverpod 2.x` |
| `MOD-02` | **Kitchen Display (KDS)** | Multi-channel kitchen routing, prep stage timers, visual and acoustic threshold alerts | `WebSocket`, `CustomPainter` |
| `MOD-03` | **POS & Cashier Station** | Check settlement, multi-tender payments, percentage/itemized split billing, table closure | `GoRouter`, `Dio` |
| `MOD-04` | **Retail WMS & Picking** | Blind stocktaking audits, dark store route picker, hardware barcode & PDA scanning | `MobileScanner`, `ESC/POS` |
| `MOD-05` | **Security & Biometrics** | Hardware keystore access, biometric TouchID / FaceID sign-in, background auto-shield | `LocalAuth`, `SecureStorage` |

---

### Module 01: Waiter Operations Console
* **Interactive Floor Matrix**: Real-time table status monitoring (Vacant, Seated, Bill Requested, Delayed).
* **High-Speed Ordering**: Categorized menu hierarchy, portion modifiers, ingredient exclusions, and prep notes.
* **AI Voice Order Pipeline**: Speech-to-Text natural language input parsing (`ai_voice_order_sheet`).
* **AI Reservation Manager**: Rapid party seating and reservation allocation wizard (`ai_reservation_sheet`).

### Module 02: Kitchen Display System (KDS)
* **Real-Time Ticket Stream**: Zero-latency order dispatch delivered via continuous bidirectional WebSocket pipelines.
* **State Progression**: Multi-stage transitions (*Queued ➔ In Preparation ➔ Expedited ➔ Delivered*).
* **Urgency Telemetry**: Visual countdown timers and dynamic cookware state animations (`sizzling_pan_animation`).

### Module 03: POS & Cashier Station
* **Multi-Tender Settlement**: Seamless Cash, Credit/Debit Card, and Corporate Account processing.
* **Granular Split Billing**: Flexible bill division by party count, custom percentage, or itemized allocations (`split_bill_dialog`).
* **Audited Management Overrides**: Supervisor-authorized discounts, comps, cancellations, and table transfers.

### Module 04: Retail WMS & Picking Engine
* **Blind Stocktaking (`blind_stocktake_screen`)**: Impartial inventory cycle counts without theoretical count bias.
* **Dark Store Picker (`dark_store_picker_screen`)**: Algorithmic picking path optimization for rapid fulfilment.
* **Industrial PDA Scanning (`pda_barcode_scanner`)**: Hardware-accelerated 1D/2D barcode and QR capture.
* **Mobile Thermal Printing (`mobile_label_printer_service`)**: Wireless Bluetooth and network thermal printer drivers.

### Module 05: Enterprise Security & Native Services
* **Biometric Authentication**: Instant touchless sign-in via Face ID / Touch ID / Fingerprint (`BiometricService`).
* **Auto-Lock Shield**: Real-time privacy blur during OS background transitions and session inactivity (`AppLockOverlayWrapper`).
* **Native Home Widgets**: Real-time shift counters, open tables, and kitchen metrics on device home screens (`home_widget`).
* **Hardware-Backed Keystore**: AES-256 encrypted local token management via `flutter_secure_storage`.

---

## Directory Structure

```text
lib/
├── main.dart                          # Application entry point, global observers & theme bootstrap
└── src/
    ├── core/                          # Foundational infrastructure & cross-cutting concerns
    │   ├── common_widgets/            # Reusable UI component library (Buttons, Cards, Search, Inputs)
    │   ├── config/                    # Global runtime environments & API base endpoints (AppConfig)
    │   ├── data/                      # Data models, serialization entities & JSON parsers
    │   ├── localization/              # Internationalization infrastructure (EN / TR)
    │   ├── network/                   # Dio HTTP client with JWT interceptors & WebSocket service
    │   ├── providers/                 # Core Riverpod providers (Auth, Dashboard, Shift, Tables)
    │   ├── routing/                   # GoRouter navigation & role-based route guards
    │   ├── security/                  # Hardware-backed keystore & secure token storage
    │   ├── services/                  # Notification, HomeWidget, Biometric & Lifecycle drivers
    │   ├── theme/                     # Corporate design system (Dark & Light themes, typography)
    │   └── utils/                     # Currency formatters, platform parsers & UI helpers
    └── features/                      # Domain features
        ├── auth/                      # Multi-step authentication, onboarding & account recovery
        ├── business/                  # Business metrics, floor matrices & order entities
        ├── kitchen/                   # KDS dashboard & live kitchen state animations
        ├── pos/                       # Cashier terminal, split billing & payments
        ├── preparation/               # Bar & beverage preparation dashboard
        ├── retail_wms/                # Warehouse stocktaking, picking & barcode integrations
        └── waiter/                    # Floor plan, table details & AI order assistants
```

---

## Development & Deployment

### Prerequisites
* Flutter SDK `^3.12.2` (or current stable release)
* Dart SDK `^3.x`
* Xcode (macOS) / Android Studio
* CocoaPods (`brew install cocoapods` on macOS)

### Installation
```bash
# Clone the repository
git clone git@github.com:ilkeraydogdu/personel_app.git
cd personel_app

# Fetch dependencies
flutter pub get

# Execute code generation
dart run build_runner build --delete-conflicting-outputs

# Launch in development
flutter run --dart-define=QORDY_API_BASE=https://qordy.com
```

### Build Pipelines
```bash
# Compile Android Release APK (obfuscated, stripped symbols):
./build_apk.sh

# Compile iOS Simulator package:
./build_ios.sh --simulator

# Compile iOS App Store / TestFlight IPA:
./build_ios.sh --ipa
```

---

## Continuous Integration

* **`Qordy Personel CI`**: Automatically executes static code analysis (`flutter analyze`) and unit test suites on pull requests and pushes to `main`.
* **`Build Android APK`**: Manual workflow dispatch (`workflow_dispatch`) that builds and packages production APK artifacts directly on GitHub Actions.

---

## Corporate Inquiries

* **Platform Website**: [https://qordy.com](https://qordy.com)
* **Company**: Qordy Hospitality & Retail Technologies
* **Copyright**: © 2026 Qordy. All rights reserved.
