import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../network/api_client.dart';
import '../routing/app_router.dart';
import '../security/secure_storage.dart';

class PersonelNotificationService {
  static final PersonelNotificationService _instance = PersonelNotificationService._internal();
  factory PersonelNotificationService() => _instance;
  PersonelNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = SecureStorage.instance;

  bool _isInitialized = false;
  Timer? _watchdogTimer;
  final Set<String> _seenNotificationIds = {};
  final Map<String, DateTime> _recentlyFiredAlerts = {};
  ApiClient? _apiClient;

  static const String channelId = 'qordy_staff_urgent_channel';
  static const String channelName = 'Qordy Personel Acil Bildirimler';
  static const String channelDescription = 'Siparişler, mutfak hazırlıkları ve garson çağrıları';

  Future<void> initialize({ApiClient? apiClient}) async {
    if (_isInitialized) return;
    _apiClient = apiClient;

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      notificationCategories: [
        DarwinNotificationCategory(
          channelId,
          actions: [
            DarwinNotificationAction.plain(
              'view_order',
              'Siparişi Gör',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              'dismiss',
              'Kapat',
              options: {DarwinNotificationActionOption.destructive},
            ),
          ],
          options: {
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[PersonelNotificationService] Notification clicked: ${response.payload}');
        _handleNotificationClick(response.payload);
      },
    );

    // Create High-Priority Heads-Up Channel for restaurant staff (Android)
    final androidNotificationChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500, 250, 500, 250, 800]),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidNotificationChannel);

    final savedSound = await _storage.read(key: 'sound_alerts_enabled');
    if (savedSound != null) {
      _soundAlertsEnabled = savedSound != 'false';
    }

    _isInitialized = true;
    debugPrint('[PersonelNotificationService] Initialized for ${Platform.operatingSystem} with max priority');
  }

  bool _permissionsRequested = false;

  /// Request OS notification permissions when a staff member logs in or enables alerts
  Future<void> requestPermissionsIfNeeded() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: false,
          );
    } catch (e) {
      debugPrint('[PersonelNotificationService] Permission request error: $e');
    }
  }

  bool _soundAlertsEnabled = true;
  bool get soundAlertsEnabled => _soundAlertsEnabled;

  Future<void> setSoundAlertsEnabled(bool enabled) async {
    _soundAlertsEnabled = enabled;
    await _storage.write(key: 'sound_alerts_enabled', value: enabled.toString());
  }

  /// Register device token with backend
  Future<void> registerDeviceWithBackend(ApiClient api) async {
    _apiClient = api;
    await requestPermissionsIfNeeded();
    try {
      String? deviceId = await _storage.read(key: 'device_uuid');
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = 'personel_${const Uuid().v4()}';
        await _storage.write(key: 'device_uuid', value: deviceId);
      }

      final role = await _storage.read(key: 'user_role') ?? 'staff';
      final bizId = await _storage.read(key: 'business_id') ?? '';
      final isIOS = !kIsWeb && Platform.isIOS;

      await api.post('/notifications/register-token', data: {
        'token': '${isIOS ? "apns" : "fcm"}_personel_local_$deviceId',
        'platform': Platform.operatingSystem,
        'device_model': isIOS ? 'iOS Staff Terminal' : 'Android Staff Terminal',
        'app_version': '1.0.0',
        'device_id': deviceId,
        'user_role': role,
        'business_id': bizId,
      });

      debugPrint('[PersonelNotificationService] Device registered (${Platform.operatingSystem}): $deviceId');
    } catch (e) {
      debugPrint('[PersonelNotificationService] Failed to register device: $e');
    }
  }

  /// Start 4-second background watchdog to catch any notifications that arrive while the app was backgrounded
  void startWatchdog(ApiClient api) {
    _apiClient = api;
    unawaited(requestPermissionsIfNeeded());
    if (_watchdogTimer != null && _watchdogTimer!.isActive) return;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await pollUnreadNotifications();
    });
    debugPrint('[PersonelNotificationService] Watchdog started (4s polling interval)');
  }

  void stopWatchdog({bool force = false}) {
    if (!force) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    debugPrint('[PersonelNotificationService] Watchdog stopped');
  }

  /// Resolve human-readable title from type or raw key
  String _resolveTitle(String rawTitle, String type) {
    final t = rawTitle.trim();
    if (t.isNotEmpty && !t.contains('backend.notifications') && !t.contains('rolesPublic.')) {
      return t;
    }
    final upperType = type.toUpperCase();
    if (upperType.contains('NEW_ORDER')) return '🔔 Yeni Sipariş';
    if (upperType.contains('ORDER_SERVED')) return '🍽️ Masaya Servis Edildi';
    if (upperType.contains('ORDER_READY')) return '🍽️ Sipariş Hazır';
    if (upperType.contains('CALL_WAITER')) return '🛎️ Garson Çağrısı';
    if (upperType.contains('REQUEST_BILL') || upperType.contains('BILL')) return '💳 Hesap İstendi';
    if (upperType.contains('CANCEL')) return '❌ Sipariş İptal';
    if (upperType.contains('ISSUE')) return '⚠️ Mutfak Uyarısı';
    if (upperType.contains('PREPARING')) return '🔥 Hazırlanıyor';
    if (upperType.contains('PAYMENT')) return '✅ Ödeme Alındı';
    return '🔔 Qordy Bildirimi';
  }

  /// Resolve human-readable body
  String _resolveBody(String rawBody, String type, String tableName) {
    final b = rawBody.trim();
    if (b.isNotEmpty && !b.contains('backend.notifications') && !b.contains('rolesPublic.')) {
      return b;
    }
    final table = tableName.isNotEmpty ? tableName : 'Masa';
    final upperType = type.toUpperCase();
    if (upperType.contains('NEW_ORDER')) return '$table yeni bir sipariş verdi.';
    if (upperType.contains('ORDER_SERVED')) return '$table siparişi masaya servis edildi.';
    if (upperType.contains('ORDER_READY')) return '$table siparişi servise hazır.';
    if (upperType.contains('CALL_WAITER')) return '$table garson çağırıyor.';
    if (upperType.contains('REQUEST_BILL') || upperType.contains('BILL')) return '$table hesap istiyor.';
    if (upperType.contains('CANCEL')) return '$table sipariş iptal edildi.';
    if (upperType.contains('ISSUE')) return '$table için mutfakta bir uyarı var.';
    if (upperType.contains('PREPARING')) return '$table siparişi hazırlanıyor.';
    if (upperType.contains('PAYMENT')) return '$table masasının hesabı ödendi.';
    return '$table için yeni bildirim var.';
  }

  /// Fetch unread notifications from API and trigger instant alert for any new ones
  Future<void> pollUnreadNotifications() async {
    if (_apiClient == null) return;
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null || token.isEmpty) return;

      dynamic res;
      try {
        res = await _apiClient!.get('/notifications', queryParameters: {'unread_only': true});
      } catch (_) {
        res = await _apiClient!.get('/v1/notifications/unread');
      }
      if (res != null && (res['success'] == true || res['notifications'] != null)) {
        final dataMap = res['data'] is Map ? res['data'] as Map : res;
        final List items = (dataMap['notifications'] is List)
            ? dataMap['notifications'] as List
            : (res['notifications'] is List ? res['notifications'] as List : []);
        
        final role = (await _storage.read(key: 'user_role') ?? '').toUpperCase();
        for (var notif in items) {
          if (notif is! Map) continue;
          final id = notif['id']?.toString() ?? notif['notification_id']?.toString() ?? '';
          if (id.isNotEmpty && _seenNotificationIds.contains(id)) continue;

          final type = (notif['type'] ?? '').toString();
          final tableName = (notif['table_name'] ?? '').toString();
          final notifData = notif['data'] is Map ? notif['data'] as Map : notif;
          final rawTitle = (notifData['title'] ?? notif['title'] ?? type).toString();
          final rawBody = (notifData['body'] ?? notifData['message'] ?? notif['body'] ?? notif['message'] ?? '').toString();

          final resolvedTitle = _resolveTitle(rawTitle, type);
          final resolvedBody = _resolveBody(rawBody, type, tableName);

          await alertFromSocket(
            id: id,
            title: resolvedTitle,
            body: resolvedBody,
            roles: _roleList(notif),
            screenRole: role,
            urgent: type.contains('CALL') || type.contains('NEW_ORDER'),
          );
        }
      }
    } catch (_) {
      // Background poll silently fails on network drop
    }
  }

  List<String> _roleList(dynamic notif) {
    final data = notif is Map ? notif : <String, dynamic>{};
    final raw = data['target_roles'] ?? data['data']?['target_roles'];
    if (raw is List) {
      return raw.map((item) => item.toString().toUpperCase()).toList();
    }
    final one = (data['target_role'] ?? data['data']?['target_role'] ?? '').toString();
    return one.isEmpty ? <String>[] : [one.toUpperCase()];
  }

  /// One alert per id, only for the screen role, and only with a readable title.
  Future<void> alertFromSocket({
    required String id,
    required String title,
    required String body,
    required List<String> roles,
    required String screenRole,
    bool urgent = false,
  }) async {
    if (id.isNotEmpty && _seenNotificationIds.contains(id)) return;
    final mine = screenRole.toUpperCase();
    final wanted = roles.map((role) => role.toUpperCase()).where((role) => role.isNotEmpty).toList();
    // Allow notifications if roles match, OR if it's a general staff notification,
    // OR if user is on any staff terminal and the notification is NEW_ORDER, KITCHEN, CALL_WAITER, REQUEST_BILL, ORDER_READY, ORDER_SERVED
    final isStaffTerminalAlert = wanted.isEmpty ||
        wanted.contains(mine) ||
        wanted.contains('STAFF') ||
        wanted.contains('ALL') ||
        wanted.contains('BUSINESS_OWNER') ||
        (wanted.contains('KITCHEN') && (mine == 'KITCHEN' || mine == 'PREPARATION' || mine == 'WAITER' || mine == 'POS' || mine == 'STAFF' || mine.isEmpty)) ||
        (wanted.contains('WAITER') && (mine == 'WAITER' || mine == 'STAFF' || mine == 'POS' || mine == 'STAFF' || mine.isEmpty));
    if (!isStaffTerminalAlert) return;

    final cleanTitle = _resolveTitle(title, '');
    final cleanBody = _resolveBody(body, '', '');

    if (id.isNotEmpty) _seenNotificationIds.add(id);
    await showStaffAlert(
      title: cleanTitle,
      body: cleanBody,
      payload: id,
      isUrgent: urgent,
    );
  }

  /// Triggers a loud, heads-up restaurant alarm on iOS & Android
  Future<void> showStaffAlert({
    required String title,
    required String body,
    String? payload,
    bool isUrgent = false,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty) return;

    // Deduplication check: drop duplicate alert within 8 seconds
    final dedupeKey = '$cleanTitle|$cleanBody';
    final now = DateTime.now();
    if (_recentlyFiredAlerts.containsKey(dedupeKey)) {
      final lastFired = _recentlyFiredAlerts[dedupeKey]!;
      if (now.difference(lastFired).inSeconds < 8) {
        debugPrint('[PersonelNotificationService] Dropped duplicate alert within 8s: $dedupeKey');
        return;
      }
    }
    _recentlyFiredAlerts[dedupeKey] = now;
    _recentlyFiredAlerts.removeWhere((_, time) => now.difference(time).inSeconds > 30);

    // Deterministic ID ensures duplicate events update/replace rather than stack
    final id = (cleanTitle.hashCode ^ cleanBody.hashCode).abs() % 100000;
    final playSound = _soundAlertsEnabled || isUrgent;

    // Trigger native Taptic Engine feedback on iOS for immediate pocket awareness
    if (!kIsWeb && Platform.isIOS) {
      if (isUrgent) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 180), () => HapticFeedback.vibrate());
      } else {
        HapticFeedback.mediumImpact();
      }
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: playSound,
      ticker: 'Qordy Bildirim',
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      color: isUrgent ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
      colorized: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: isUrgent ? '🚨 ACİL ÇAĞRI' : 'Qordy Personel',
      ),
      vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 600, 200, 1000]),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      presentBanner: true,
      presentList: true,
      sound: playSound ? 'default' : null,
      subtitle: isUrgent ? '🚨 ACİL ÇAĞRI' : 'Qordy Personel',
      threadIdentifier: channelId,
      categoryIdentifier: channelId,
      interruptionLevel: isUrgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );

    debugPrint('[PersonelNotificationService] Showed alert: "$title" - "$body"');
  }

  /// Handles user tapping an iOS or Android notification
  void _handleNotificationClick(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        debugPrint('[PersonelNotificationService] Navigator context not ready for payload: $payload');
        return;
      }

      // If direct route string
      if (payload.startsWith('/')) {
        GoRouter.of(context).go(payload);
        return;
      }

      // If JSON payload
      if (payload.startsWith('{')) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final route = data['route']?.toString();
        final tableId = data['table_id']?.toString();
        final tableName = data['table_name']?.toString();

        if (tableId != null && tableId.isNotEmpty) {
          GoRouter.of(context).go('/waiter/table/$tableId', extra: tableName);
        } else if (route != null && route.isNotEmpty) {
          GoRouter.of(context).go(route);
        }
      }
    } catch (e) {
      debugPrint('[PersonelNotificationService] Tap routing error: $e');
    }
  }

  /// iOS uygulama rozet sayısını (badge count) sıfırlar
  Future<void> clearBadge() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        // Clear iOS badge
        await _localNotifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(badge: true);
      }
    } catch (e) {
      debugPrint('[PersonelNotificationService] clearBadge hatası: $e');
    }
  }

  /// Uygulama arka plandan öne geldiğinde veya ağ tekrar bağlandığında
  /// 15 saniyelik periyodu beklemeden derhal bildirimleri sorgular.
  Future<void> triggerImmediateSync() async {
    debugPrint('[PersonelNotificationService] Derhal bildirim senkronizasyonu tetiklendi');
    await pollUnreadNotifications();
  }

  /// Test loud restaurant alert for iOS & Android testing
  Future<void> triggerTestAlert({String? targetRole}) async {
    await showStaffAlert(
      title: '🛎️ Masa 22 Siparişi Hazır!',
      body: 'Americano (1 adet) hazırlandı, masaya servis bekleniyor.',
      payload: '/waiter/table/22',
      isUrgent: true,
    );
  }
}
