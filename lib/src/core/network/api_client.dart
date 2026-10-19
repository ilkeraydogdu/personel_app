import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../security/secure_storage.dart';
import 'api_exception.dart';

export 'api_exception.dart';

/// Qordy Personel API istemcisi.
///
/// * Singleton: tüm uygulama boyunca tek Dio instance.
/// * Token yönetimi: SecureStorage üzerinde access + refresh token.
/// * 401 durumunda tek seferlik refresh + retry; başarısızsa [onSessionExpired].
/// * Mutasyonlara otomatik Idempotency-Key ekler.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.mobileApiBase,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.connectTimeout,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'QordyPersonel',
          'X-App-Version': AppConfig.appVersion,
        },
        validateStatus: (_) => true,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest),
    );
  }

  static final ApiClient instance = ApiClient._();
  static String get baseUrl => AppConfig.mobileApiBase;

  late final Dio _dio;
  Dio get dio => _dio;
  final _uuid = const Uuid();
  final _storage = SecureStorage.instance;

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshing;

  /// Oturum düşünce (refresh de başarısızsa) çağrılır.
  void Function()? onSessionExpired;

  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;
  String? get accessToken => _accessToken;

  // ─── Token Yönetimi ──────────────────────────────────────

  void setTokens({required String? access, String? refresh}) {
    _accessToken = access;
    if (refresh != null) _refreshToken = refresh;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  Future<void> restoreTokens() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<void> persistTokens({required String access, String? refresh}) async {
    _accessToken = access;
    await _storage.write(key: 'access_token', value: access);
    if (refresh != null) {
      _refreshToken = refresh;
      await _storage.write(key: 'refresh_token', value: refresh);
    }
  }

  Future<void> clearPersistedTokens() async {
    clearTokens();
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // ─── Interceptor ─────────────────────────────────────────

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_accessToken != null &&
        _accessToken!.isNotEmpty &&
        options.headers['Authorization'] == null) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    final method = options.method.toUpperCase();
    if ((method == 'POST' || method == 'PUT' || method == 'PATCH' || method == 'DELETE') &&
        options.headers['Idempotency-Key'] == null &&
        options.extra['idempotent'] != false) {
      options.headers['Idempotency-Key'] = 'personel-${_uuid.v4()}';
    }
    handler.next(options);
  }

  // ─── Public API ──────────────────────────────────────────

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? queryParameters,
  }) =>
      _request('GET', path, query: queryParameters ?? query);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Object? data,
    bool idempotent = true,
  }) =>
      _request('POST', path, body: data ?? body ?? const {}, idempotent: idempotent);

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    Object? data,
  }) =>
      _request('PUT', path, body: data ?? body ?? const {});

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Object? data,
  }) =>
      _request('PATCH', path, body: data ?? body ?? const {});

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    Object? data,
  }) =>
      _request('DELETE', path, body: data ?? body);

  Future<Map<String, dynamic>> upload(String path, FormData form) =>
      _request('POST', path, body: form);

  // ─── Core ────────────────────────────────────────────────

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool idempotent = true,
    bool retried = false,
  }) async {
    Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, extra: {'idempotent': idempotent}),
      );
    } on DioException catch (e) {
      throw _networkError(e);
    }

    final status = response.statusCode ?? 0;
    final data = _asMap(response.data);

    // Token süresi dolmuş → refresh + retry (tek sefer)
    if (status == 401 &&
        !retried &&
        _refreshToken != null &&
        !path.contains('/auth/refresh') &&
        !path.contains('/refresh-token') &&
        !path.contains('/login') &&
        !path.contains('/staff/login')) {
      final ok = await _refreshTokens();
      if (ok) {
        return _request(method, path, query: query, body: body, idempotent: idempotent, retried: true);
      }
      onSessionExpired?.call();
    }

    final success = data['success'];
    if (status >= 200 && status < 300 && success != false) {
      data['status_code'] = status;
      return data;
    }

    final message = _extractError(data, status);
    final code = data['code']?.toString();
    if (status == 401 && retried) {
      onSessionExpired?.call();
    }
    throw ApiException(message, code: code, statusCode: status, payload: data);
  }

  Future<bool> _refreshTokens() {
    _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
    return _refreshing!;
  }

  Future<bool> _doRefresh() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
        options: Options(
          headers: {'Authorization': 'Bearer $refresh'},
          extra: {'idempotent': false},
        ),
      );
      final data = _asMap(response.data);
      if ((response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300 &&
          data['success'] != false) {
        final payload = _asMap(data['data'] ?? data);
        final newAccess = payload['token']?.toString() ?? payload['access_token']?.toString();
        final newRefresh = payload['refresh_token']?.toString();
        if (newAccess != null && newAccess.isNotEmpty) {
          await persistTokens(access: newAccess, refresh: newRefresh);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Token refresh failed: $e');
    }
    return false;
  }

  // ─── Helpers ─────────────────────────────────────────────

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List) return {'success': true, 'data': raw};
    if (raw is String && raw.isNotEmpty) return {'success': false, 'error': raw};
    return <String, dynamic>{};
  }

  String _extractError(Map<String, dynamic> data, int status) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;
    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
    if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
      return (data['errors'] as Map).values.first.toString();
    }
    return switch (status) {
      401 => 'Oturum süresi doldu, lütfen yeniden giriş yapın',
      403 => 'Bu işlem için yetkiniz yok',
      404 => 'Kayıt bulunamadı',
      409 => 'Bu işlem daha önce yapılmış',
      422 => 'Girilen bilgiler geçersiz',
      429 => 'Çok fazla istek, lütfen biraz bekleyin',
      >= 500 => 'Sunucu hatası, lütfen tekrar deneyin',
      _ => 'İşlem başarısız ($status)',
    };
  }

  ApiException _networkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          'Sunucuya ulaşılamadı (zaman aşımı). İnternet bağlantınızı kontrol edin.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          'İnternet bağlantısı yok veya sunucuya erişilemiyor.',
          code: 'NO_CONNECTION',
        );
      case DioExceptionType.badCertificate:
        return const ApiException('Güvenli bağlantı kurulamadı.', code: 'BAD_CERT');
      case DioExceptionType.cancel:
        return const ApiException('İstek iptal edildi.', code: 'CANCELLED');
      default:
        return ApiException(e.message ?? 'Ağ hatası', code: 'NETWORK');
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

/// Dio Response uyumluluğu için Map uzantısı (.data ve .statusCode erişimi)
extension ApiResponseMapExtension on Map {
  dynamic get data => this;
  int get statusCode =>
      (this['status_code'] as int?) ??
      (this['statusCode'] as int?) ??
      (this['success'] == false ? 400 : 200);
}