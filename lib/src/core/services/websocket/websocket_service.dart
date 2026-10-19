import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as channel_status;
import '../../network/api_client.dart';
import '../../security/secure_storage.dart';

enum WebSocketConnectionState {
  disconnected,
  connecting,
  authenticating,
  authenticated,
  subscribed,
  error,
}

class WebSocketEvent {
  final String type;
  final String? event;
  final Map<String, dynamic>? data;
  final String? tenantId;
  final String? eventId;
  final int? sequence;
  final int? eventVersion;
  final DateTime receivedAt;

  WebSocketEvent({
    required this.type,
    this.event,
    this.data,
    this.tenantId,
    this.eventId,
    this.sequence,
    this.eventVersion,
    required this.receivedAt,
  });

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: json['type']?.toString() ?? 'UNKNOWN',
      event: json['event']?.toString(),
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'])
          : null,
      tenantId: json['tenant_id']?.toString(),
      eventId: json['event_id']?.toString(),
      sequence: json['sequence'] is int
          ? json['sequence']
          : int.tryParse('${json['sequence'] ?? 0}'),
      eventVersion: json['event_version'] is int
          ? json['event_version']
          : int.tryParse('${json['event_version'] ?? 0}'),
      receivedAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'WebSocketEvent(type: $type, event: $event, tenantId: $tenantId)';

  /// order.created | order.updated | order.status_changed | table.updated | notification.created …
  String get name => event ?? type;
  bool get isOrderEvent => name.startsWith('order.') || name.contains('order');
  bool get isKitchenEvent =>
      name.startsWith('kitchen.') ||
      name.contains('kitchen') ||
      name.contains('kds') ||
      name.contains('prep');
  bool get isTableEvent => name.startsWith('table.') || name.contains('table');
  bool get isNotificationEvent => name.startsWith('notification.') || name.contains('notification');
  bool get isWaiterCall => name.contains('waiter') || name.contains('call');
  bool get isBillRequest => name.contains('bill') || name.contains('payment');
  bool get isCustomerSeated => name.contains('seated') || name.contains('customer.seated') || name.contains('table.seated');
}

class WebSocketService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = SecureStorage.instance;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  WebSocketConnectionState _state = WebSocketConnectionState.disconnected;
  final StreamController<WebSocketEvent> _eventController =
      StreamController<WebSocketEvent>.broadcast();
  final StreamController<WebSocketConnectionState> _stateController =
      StreamController<WebSocketConnectionState>.broadcast();

  String? _businessId;
  String? _userId;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 15;
  static const Duration _baseReconnectDelay = Duration(seconds: 1);
  static const Duration _heartbeatInterval = Duration(seconds: 25);

  bool get isConnected =>
      _state == WebSocketConnectionState.authenticated ||
      _state == WebSocketConnectionState.subscribed;

  WebSocketConnectionState get state => _state;

  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;

  WebSocketService(this._apiClient);

  String get _wsUrl {
    final base = ApiClient.baseUrl;
    // baseUrl looks like: https://qordy.com/api/mobile
    final wsScheme = base.startsWith('https') ? 'wss' : 'ws';
    // Strip scheme: https://qordy.com/api/mobile -> qordy.com/api/mobile
    final withoutScheme = base.replaceFirst(RegExp(r'^https?://'), '');
    // Strip path after host: qordy.com/api/mobile -> qordy.com
    final host = withoutScheme.split('/').first;
    return '$wsScheme://$host/ws';
  }

  bool _isConnecting = false;

  Future<void> connect({String? businessId, String? userId}) async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _stopHeartbeat();
      await _subscription?.cancel();
      _subscription = null;
      try {
        await _channel?.sink.close(channel_status.normalClosure);
      } catch (_) {}
      _channel = null;

      // Automatically resolve stored businessId / userId if not explicitly passed
      _businessId = businessId ?? await _storage.read(key: 'business_id');
      _userId = userId ?? await _storage.read(key: 'user_id');

      _updateState(WebSocketConnectionState.connecting);

      // Step 1: Fetch ws-token via HTTP
      _updateState(WebSocketConnectionState.authenticating);
      final response = await _apiClient.post('/ws-token');
      final resData = response;
      final token = (resData['data'] is Map ? resData['data']['token'] : null)?.toString() ??
          resData['token']?.toString();

      if (token == null || token.isEmpty) {
        throw Exception('WebSocket token alınamadı');
      }

      // Step 2: Establish WebSocket connection
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Step 3: Send AUTH message
      final authPayload = jsonEncode(<String, dynamic>{
        'type': 'AUTH',
        'token': token,
        if (_businessId != null && _businessId!.isNotEmpty) 'business_id': _businessId,
        if (_userId != null && _userId!.isNotEmpty) 'user_id': _userId,
        'locale': 'tr',
      });

      _channel!.sink.add(authPayload);
      _startHeartbeat();
    } on DioException catch (e) {
      debugPrint('WS connect: HTTP error getting ws-token: ${e.message}');
      _updateState(WebSocketConnectionState.error);
      _scheduleReconnect();
    } catch (e) {
      debugPrint('WS connect error: $e');
      _updateState(WebSocketConnectionState.error);
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final event = WebSocketEvent.fromJson(data);

      _eventController.add(event);

      if (event.type == 'AUTH_SUCCESS') {
        _updateState(WebSocketConnectionState.authenticated);
        _reconnectAttempts = 0;

        // Always subscribe to business orders & notifications channels on AUTH_SUCCESS
        _channel?.sink.add(jsonEncode({
          'type': 'SUBSCRIBE',
          'channel': 'orders',
          if (_businessId != null && _businessId!.isNotEmpty) 'business_id': _businessId,
        }));
        _updateState(WebSocketConnectionState.subscribed);
      } else if (event.type == 'ERROR') {
        final errorCode = event.data?['error']?.toString();
        if (errorCode == 'invalid_auth' ||
            errorCode == 'not_authenticated') {
          debugPrint('WS auth error: $errorCode');
          _updateState(WebSocketConnectionState.error);
          _scheduleReconnect();
        }
      } else if (event.type == 'PONG') {
        // Heartbeat acknowledged, nothing to do
      }
    } catch (e) {
      debugPrint('WS message parse error: $e');
    }
  }

  void _onError(error) {
    debugPrint('WS error: $error');
    _updateState(WebSocketConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WS connection closed');
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    // If we were connected, schedule reconnect. If intentionally closed,
    // the state is already disconnected so no reconnect happens.
    if (_state != WebSocketConnectionState.disconnected) {
      _updateState(WebSocketConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close(channel_status.normalClosure);
    } catch (_) {
      // ignore close errors
    }
    _channel = null;

    _updateState(WebSocketConnectionState.disconnected);
  }

  void _updateState(WebSocketConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_state == WebSocketConnectionState.authenticated ||
          _state == WebSocketConnectionState.subscribed) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'PING'}));
        } catch (e) {
          debugPrint('WS heartbeat send failed: $e');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Ağ bağlantısı yeniden sağlandığında veya uygulama arka plandan
  /// öne geldiğinde gecikmeksizin derhal yeniden bağlanır.
  void reconnectNow() {
    debugPrint('[WebSocketService] Derhal yeniden bağlanma tetiklendi (Lifecycle/Connectivity)');
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connect(businessId: _businessId, userId: _userId);
  }

  void _scheduleReconnect() {
    final Duration cappedDelay;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      // 15 denemeden sonra tamamen pes etmek yerine her 30 saniyede bir arka planda yoklamaya devam et
      cappedDelay = const Duration(seconds: 30);
      debugPrint('WS: Azami deneme sınırına ulaşıldı, 30s periyotla arka planda yoklanıyor');
    } else {
      _reconnectAttempts++;
      // Exponential backoff: 1s, 2s, 3s, 4s, 5s... (en fazla 10s)
      final exponent = _reconnectAttempts > 5 ? 5 : _reconnectAttempts;
      final delay = _baseReconnectDelay * exponent;
      cappedDelay = delay > const Duration(seconds: 10)
          ? const Duration(seconds: 10)
          : delay;
      debugPrint(
          'WS: scheduling reconnect attempt $_reconnectAttempts in ${cappedDelay.inSeconds}s');
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(cappedDelay, () {
      connect(businessId: _businessId, userId: _userId);
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (e) {
      debugPrint('[WebSocketService] Error closing sink on dispose: $e');
    }
    _eventController.close();
    _stateController.close();
  }
}

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final client = ref.watch(apiClientProvider);
  final service = WebSocketService(client);
  ref.onDispose(service.dispose);
  return service;
});

/// Canlı WebSocket olay akışı
final wsEventsProvider = StreamProvider<WebSocketEvent>((ref) {
  return ref.watch(webSocketServiceProvider).eventStream;
});

/// Canlı WebSocket bağlantı durum akışı
final wsStateProvider = StreamProvider<WebSocketConnectionState>((ref) {
  return ref.watch(webSocketServiceProvider).stateStream;
});
