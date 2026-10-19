import 'package:flutter_secure_storage/flutter_secure_storage.dart';

export 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Qordy Personel için merkezi ve güçlendirilmiş güvenli depolama (Secure Storage).
///
/// **iOS Güvenliği:**
/// - [KeychainAccessibility.first_unlock_this_device]: Token, PIN ve oturum anahtarları
///   yalnızca cihaz açılıp ilk kilit çözüldükten sonra erişilebilir. Cihaz dışına
///   çıkamaz (iCloud Keychain senkronizasyonu kapalıdır).
/// - [synchronizable: false]: Kurumsal restoran oturum ve personel verilerinin
///   kişisel Apple ID iCloud Keychain'ine sızmasını önler.
///
/// **Android Güvenliği:**
/// - Android KeyStore RSA-OAEP + AES-GCM donanımsal şifreleme ve resetOnError koruması.
class SecureStorage {
  static const IOSOptions iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const AndroidOptions androidOptions = AndroidOptions(
    resetOnError: true,
  );

  /// Uygulama genelinde kullanılacak tekil, güçlendirilmiş güvenli depolama örneği.
  static const FlutterSecureStorage instance = FlutterSecureStorage(
    iOptions: iosOptions,
    aOptions: androidOptions,
  );
}
