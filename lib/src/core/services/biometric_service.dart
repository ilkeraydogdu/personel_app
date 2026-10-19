import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import '../security/secure_storage.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const _storage = SecureStorage.instance;

  static const _kBiometricEnabledKey = 'biometric_login_enabled';
  static const _kSavedSubdomainKey = 'saved_login_subdomain';
  static const _kSavedPinKey = 'saved_login_pin';

  /// Check if hardware supports biometrics and device has enrolled biometrics
  static Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get list of enrolled biometric types (e.g. fingerprint, face)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Returns platform-appropriate biometric label (e.g. 'Face ID' on iOS)
  static String get platformBiometricLabel {
    if (!kIsWeb && Platform.isIOS) {
      return 'Face ID / Touch ID';
    }
    return 'Parmak İzi / Kilit';
  }

  /// Prompt biometric authentication dialog (Face ID / Touch ID on iOS, BiometricPrompt on Android)
  static Future<bool> authenticate({String? reason}) async {
    try {
      final isIOS = !kIsWeb && Platform.isIOS;
      return await _auth.authenticate(
        localizedReason: reason ??
            (isIOS
                ? 'Qordy Personel terminaline giriş yapmak için Face ID veya cihaz parolanızı doğrulayın'
                : 'Giriş yapmak için parmak izinizi veya telefon kilidinizi doğrulayın'),
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Cihaz Kilidi ile Doğrulama',
            biometricHint: 'Parmak izinizi okutun veya ekran şifrenizi girin',
            biometricNotRecognized: 'Kimlik tanınamadı. Lütfen tekrar deneyin.',
            biometricSuccess: 'Kimlik başarıyla doğrulandı.',
            cancelButton: 'Vazgeç',
            deviceCredentialsRequiredTitle: 'Cihaz Kilidi',
            deviceCredentialsSetupDescription: 'Lütfen telefonunuzun ekran kilit şifresini veya desenini girin.',
            goToSettingsButton: 'Ayarlar',
            goToSettingsDescription: 'Cihazınızda biyometrik kilit ayarlanmamış. Lütfen cihaz ayarlarından açın.',
          ),
          IOSAuthMessages(
            localizedFallbackTitle: 'Parola Kullan',
            cancelButton: 'Vazgeç',
            goToSettingsButton: 'Ayarlar',
            goToSettingsDescription: 'Face ID / Touch ID etkin değil. Lütfen iOS Ayarlar > Face ID ve Parola menüsünden etkinleştirin.',
            lockOut: 'Çok fazla başarısız deneme yapıldı. Lütfen cihaz parolanızla kilidi açın.',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Check if user has enabled biometric login
  static Future<bool> isBiometricLoginEnabled() async {
    final enabled = await _storage.read(key: _kBiometricEnabledKey);
    final pin = await _storage.read(key: _kSavedPinKey);
    return enabled == 'true' && pin != null && pin.isNotEmpty;
  }

  /// Save credentials for quick biometric login
  static Future<void> saveCredentialsForBiometric({
    required String subdomain,
    required String pin,
  }) async {
    await _storage.write(key: _kBiometricEnabledKey, value: 'true');
    await _storage.write(key: _kSavedSubdomainKey, value: subdomain);
    await _storage.write(key: _kSavedPinKey, value: pin);
  }

  /// Retrieve saved credentials
  static Future<Map<String, String>?> getSavedCredentials() async {
    final isEnabled = await isBiometricLoginEnabled();
    if (!isEnabled) return null;

    final subdomain = await _storage.read(key: _kSavedSubdomainKey);
    final pin = await _storage.read(key: _kSavedPinKey);

    if (pin != null && pin.isNotEmpty) {
      return {
        'subdomain': subdomain ?? '',
        'pin': pin,
      };
    }
    return null;
  }

  /// Mark if the user explicitly clicked "Log Out" (so we never auto-prompt biometrics)
  static const _kExplicitLogoutKey = 'did_explicitly_logout';

  static Future<void> setExplicitLogout(bool value) async {
    if (value) {
      await _storage.write(key: _kExplicitLogoutKey, value: 'true');
    } else {
      await _storage.delete(key: _kExplicitLogoutKey);
    }
  }

  /// Check if last action was an intentional logout
  static Future<bool> didExplicitLogout() async {
    final val = await _storage.read(key: _kExplicitLogoutKey);
    return val == 'true';
  }

  /// Clear saved credentials
  static Future<void> clearBiometricCredentials() async {
    await _storage.delete(key: _kBiometricEnabledKey);
    await _storage.delete(key: _kSavedSubdomainKey);
    await _storage.delete(key: _kSavedPinKey);
    await _storage.delete(key: _kExplicitLogoutKey);
  }
}
