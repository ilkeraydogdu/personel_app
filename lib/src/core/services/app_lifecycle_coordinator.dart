import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'notification_service.dart';
import 'websocket/websocket_service.dart';

/// Ağ bağlantı değişimleri (Wi-Fi/Hücresel geçişleri) ve uygulama yaşam döngüsünü
/// (Foreground/Background) koordine eden merkezi servis.
///
/// Restoran personelinin cihazı arka plandan açtığı veya Wi-Fi kapsama alanına
/// geri girdiği anda WebSocket bağlantısını ve okunmamış bildirimleri derhal
/// senkronize eder.
class AppLifecycleCoordinator with WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;

  AppLifecycleCoordinator(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (isOnline) {
        if (_wasOffline) {
          debugPrint('[AppLifecycleCoordinator] Ağ bağlantısı geri geldi. Veri akışı yenileniyor...');
          _syncRealtimeData();
        }
        _wasOffline = false;
      } else {
        debugPrint('[AppLifecycleCoordinator] Cihaz çevrimdışı konuma geçti');
        _wasOffline = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AppLifecycleCoordinator] Uygulama ön plana geldi (resumed).');
      _syncRealtimeData();
      PersonelNotificationService().clearBadge();
    }
  }

  void _syncRealtimeData() {
    final isAuth = _ref.read(authProvider).isAuthenticated;
    if (!isAuth) return;

    try {
      // 1. WebSocket bağlantısını anında tazele
      final wsService = _ref.read(webSocketServiceProvider);
      wsService.reconnectNow();

      // 2. Bekleyen acil personel çağrılarını ve sipariş bildirimlerini anında sorgula
      PersonelNotificationService().triggerImmediateSync();
    } catch (e) {
      debugPrint('[AppLifecycleCoordinator] Senkronizasyon hatası: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
  }
}

final appLifecycleCoordinatorProvider = Provider<AppLifecycleCoordinator>((ref) {
  final coordinator = AppLifecycleCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
