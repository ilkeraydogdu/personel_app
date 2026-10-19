/// Uygulama genel yapılandırması.
class AppConfig {
  AppConfig._();

  static const String apiBase = String.fromEnvironment(
    'QORDY_API_BASE',
    defaultValue: 'https://qordy.com',
  );

  /// Mobil API kök yolu (örn. https://qordy.com/api/mobile)
  static String get mobileApiBase => '$apiBase/api/mobile';

  /// WebSocket adresi (wss://qordy.com/ws)
  static String get wsUrl {
    final scheme = apiBase.startsWith('https') ? 'wss' : 'ws';
    final host = apiBase.replaceFirst(RegExp(r'^https?://'), '');
    return '$scheme://$host/ws';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  static const String appName = 'Qordy Personel';
  static const String appVersion = '1.1.0';

  /// Göreli asset yolunu (örn. /assets/images/...) mutlak URL'ye çevirir.
  static String? assetUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$apiBase/${path.startsWith('/') ? path.substring(1) : path}';
  }
}
