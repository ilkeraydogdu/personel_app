import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../security/secure_storage.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../../features/waiter/presentation/table_details_screen.dart';

class AuthState {
  final bool isInitialized;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final String? businessId;
  final String? userId;
  final String? userName;
  final String? userRole;

  const AuthState({
    this.isInitialized = false,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.businessId,
    this.userId,
    this.userName,
    this.userRole,
  });

  AuthState copyWith({
    bool? isInitialized,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isAuthenticated,
    String? businessId,
    String? userId,
    String? userName,
    String? userRole,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userRole: userRole ?? this.userRole,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  ApiClient get _client => ref.read(apiClientProvider);
  final _storage = SecureStorage.instance;

  @override
  AuthState build() {
    _client.onSessionExpired = _onSessionExpired;
    Future.microtask(_restoreSession);
    return const AuthState();
  }

  Future<void> _restoreSession() async {
    try {
      await _client.restoreTokens();
      if (!_client.hasToken) {
        state = state.copyWith(isInitialized: true);
        return;
      }

      // Token geçerliliğini sunucuda doğrula
      try {
        final me = await _client.get('/staff/me');
        final data = me['data'] as Map<String, dynamic>? ?? me;
        await _applySession(data);
      } on ApiException catch (e) {
        if (e.isUnauthorized || e.isForbidden) {
          await _clearLocal();
        } else {
          // Ağ hatasında saklı oturum bilgileri ile devam edilir (offline tolerans)
          final savedBizId = await _storage.read(key: 'business_id');
          final savedUserId = await _storage.read(key: 'user_id');
          final savedUserName = await _storage.read(key: 'user_name');
          final savedUserRole = await _storage.read(key: 'user_role');
          if (savedUserRole != null && savedUserRole.isNotEmpty) {
            state = state.copyWith(
              isAuthenticated: true,
              businessId: savedBizId,
              userId: savedUserId,
              userName: savedUserName,
              userRole: savedUserRole,
              clearError: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Session restore failed: $e');
    } finally {
      state = state.copyWith(isInitialized: true);
    }
  }

  Future<void> _applySession(Map<String, dynamic> data) async {
    final user = data['user'] as Map<String, dynamic>? ?? {};
    final business = data['business'] as Map<String, dynamic>? ?? {};

    final rawRole = (user['role'] ?? user['role_code'] ?? '').toString().toUpperCase();
    final prepScreenId = user['preparation_screen_id']?.toString();
    final prepScreenSlug = user['preparation_screen_slug']?.toString();
    final userName = (user['name'] ?? '').toString().toUpperCase();

    final mappedRole = _mapRole(
      rawRole: rawRole,
      prepScreenId: prepScreenId,
      prepScreenSlug: prepScreenSlug,
      userName: userName,
    );

    final bizId = business['id']?.toString() ?? user['business_id']?.toString();
    final uId = user['id']?.toString();
    final uName = user['name']?.toString();

    if (bizId != null && bizId.isNotEmpty) {
      await _storage.write(key: 'business_id', value: bizId);
    }
    if (uId != null && uId.isNotEmpty) {
      await _storage.write(key: 'user_id', value: uId);
    }
    if (uName != null && uName.isNotEmpty) {
      await _storage.write(key: 'user_name', value: uName);
    }
    await _storage.write(key: 'user_role', value: mappedRole);

    state = state.copyWith(
      isAuthenticated: true,
      businessId: bizId,
      userId: uId,
      userName: uName,
      userRole: mappedRole,
      clearError: true,
    );
  }

  String _mapRole({
    required String rawRole,
    String? prepScreenId,
    String? prepScreenSlug,
    String? userName,
  }) {
    // 1. Personelin atanmış hazırlık ekranı varsa veya adı/rolü NARGİLE / HAZIRLIK / PREP / BAR içeriyorsa
    if ((prepScreenId != null && prepScreenId.isNotEmpty) ||
        (prepScreenSlug != null && prepScreenSlug.isNotEmpty) ||
        (userName != null &&
            (userName.contains('NARGİLE') ||
                userName.contains('NARGILE') ||
                userName.contains('HAZIRLIK') ||
                userName.contains('PREP') ||
                userName.contains('BARİSTA') ||
                userName.contains('BARISTA'))) ||
        rawRole.contains('NARGİLE') ||
        rawRole.contains('NARGILE') ||
        rawRole.contains('PREP') ||
        rawRole.contains('HAZIRLIK') ||
        rawRole == 'BAR' ||
        rawRole.contains('BARISTA') ||
        rawRole.contains('BARTENDER')) {
      return 'preparation';
    }
    if (rawRole.contains('GARSON') || rawRole.contains('WAITER')) return 'waiter';
    if (rawRole.contains('KASİYER') || rawRole.contains('KASIYER') || rawRole.contains('POS') || rawRole.contains('CASHIER')) return 'pos';
    if (rawRole.contains('MUTFAK') || rawRole.contains('KITCHEN') || rawRole.contains('CHEF') || rawRole.contains('AŞÇI')) return 'kitchen';
    return 'waiter';
  }

  Future<bool> loginWithPin({
    required String pin,
    required String subdomain,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await _client.post('/staff/login', body: {
        'pin': pin,
        'subdomain': subdomain,
      });

      final data = response['data'] as Map<String, dynamic>? ?? response;
      final token = data['token']?.toString() ?? '';
      final refreshToken = data['refresh_token']?.toString();

      if (token.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'Token alınamadı');
        return false;
      }

      TableDetailsScreen.clearMenuCache();
      await _client.persistTokens(access: token, refresh: refreshToken);
      await _applySession(data);
      state = state.copyWith(isLoading: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Giriş yapılamadı: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      PersonelNotificationService().stopWatchdog(force: true);
      TableDetailsScreen.clearMenuCache();
      await BiometricService.setExplicitLogout(true);
      await _client.post('/staff/logout', idempotent: false);
    } catch (e) {
      debugPrint('[AuthNotifier] Logout API call failed: $e');
    }
    await _clearLocal();
  }

  Future<void> _clearLocal() async {
    PersonelNotificationService().stopWatchdog(force: true);
    TableDetailsScreen.clearMenuCache();
    await _client.clearPersistedTokens();
    await _storage.delete(key: 'business_id');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'user_name');
    await _storage.delete(key: 'user_role');
    state = const AuthState(isInitialized: true);
  }

  void _onSessionExpired() {
    if (state.isAuthenticated) {
      _clearLocal().then((_) {
        state = state.copyWith(error: 'Oturum süresi doldu, lütfen yeniden giriş yapın');
      });
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);