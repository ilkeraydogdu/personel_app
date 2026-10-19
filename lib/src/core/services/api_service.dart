import 'package:dio/dio.dart';
import '../network/api_client.dart';

/// Legacy uyumluluk için ApiService köprüsü.
///
/// Uygulamada iki farklı Dio örneğinin ve mükerrer ağ katmanının
/// çalışmasını engeller; tüm istekleri ve token yönetimini
/// merkezi [ApiClient] üzerinden yürütür.
class ApiService {
  static ApiService? _instance;
  factory ApiService() => _instance ??= ApiService._();
  ApiService._();

  /// Merkezi ApiClient üzerinden yönetilen resmi Dio istemcisi
  Dio get dio => ApiClient.instance.dio;

  String get baseUrl => ApiClient.baseUrl;
  String? get accessToken => ApiClient.instance.accessToken;
  String? get businessId => null;

  void init({String? baseUrl}) {
    // Merkezi ApiClient zaten yapılandırılmıştır.
  }

  void setAuth({required String accessToken, String? businessId}) {
    ApiClient.instance.setTokens(access: accessToken);
  }

  void clearAuth() {
    ApiClient.instance.clearTokens();
  }
}
