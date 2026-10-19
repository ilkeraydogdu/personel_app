import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents a scanned barcode event with hardware metadata
class BarcodeScanEvent {
  final String barcode;
  final String symbology;
  final DateTime timestamp;
  final ScanSource source;

  const BarcodeScanEvent({
    required this.barcode,
    this.symbology = 'UNKNOWN',
    required this.timestamp,
    this.source = ScanSource.hardwarePda,
  });

  @override
  String toString() =>
      'BarcodeScanEvent(barcode: $barcode, symbology: $symbology, source: $source, at: $timestamp)';
}

enum ScanSource {
  hardwarePda,
  camera,
  manual,
}

/// Service to handle industrial PDA barcode scanners (Zebra, Honeywell, Newland, Datalogic)
/// via Android Broadcast Intents with a camera scanner fallback.
class PdaBarcodeScanner {
  static const MethodChannel _methodChannel =
      MethodChannel('com.qordy.personel/pda_scanner');
  static const EventChannel _eventChannel =
      EventChannel('com.qordy.personel/pda_scanner_events');

  // Standard Zebra DataWedge Actions & Extras
  static const String zebraDataWedgeAction =
      'com.symbol.datawedge.api.ACTION';
  static const String zebraDataStringExtra =
      'com.symbol.datawedge.data_string';
  static const String zebraLabelTypeExtra =
      'com.symbol.datawedge.label_type';

  // Standard Honeywell Scanning Actions & Extras
  static const String honeywellScanAction =
      'com.honeywell.decode.intent.action.SCAN_RESULT';
  static const String honeywellDataExtra = 'data';

  final StreamController<BarcodeScanEvent> _scanStreamController =
      StreamController<BarcodeScanEvent>.broadcast();

  StreamSubscription? _eventSubscription;
  bool _isInitialized = false;
  bool _continuousMode = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  /// Cooldown between scans in milliseconds to prevent accidental double-reading
  final int debounceMs;

  PdaBarcodeScanner({this.debounceMs = 300});

  /// Exposes the live broadcast stream of barcode reads
  Stream<BarcodeScanEvent> get scanStream => _scanStreamController.stream;

  bool get isInitialized => _isInitialized;
  bool get isContinuousMode => _continuousMode;

  /// Initialize hardware listener and register broadcast intent receivers
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Subscribe to platform event channel for broadcast intents
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleRawScanData,
        onError: (dynamic error) {
          debugPrint('[PdaBarcodeScanner] Hardware channel error: $error');
        },
      );

      // Notify native bridge to start listening to Zebra & Honeywell intents
      await _methodChannel.invokeMethod('startListening', {
        'zebraAction': 'com.symbol.datawedge.ACTION_BROADCAST',
        'honeywellAction': honeywellScanAction,
      });

      _isInitialized = true;
      debugPrint('[PdaBarcodeScanner] Industrial scanner initialized successfully.');
    } on MissingPluginException {
      // Graceful fallback for non-Android platforms / emulator development
      debugPrint(
          '[PdaBarcodeScanner] Native PDA plugin not available. Running in fallback mode.');
      _isInitialized = true;
    } catch (e) {
      debugPrint('[PdaBarcodeScanner] Initialization failed: $e');
      _isInitialized = true;
    }
  }

  /// Process raw data from native PDA intent
  void _handleRawScanData(dynamic event) {
    if (event == null) return;

    String barcode = '';
    String symbology = 'EAN13';

    if (event is String) {
      barcode = event.trim();
    } else if (event is Map) {
      barcode = (event['barcode'] ?? event['data'] ?? '').toString().trim();
      symbology = (event['symbology'] ?? event['type'] ?? 'UNKNOWN').toString();
    }

    if (barcode.isNotEmpty) {
      _emitScan(barcode, symbology: symbology, source: ScanSource.hardwarePda);
    }
  }

  /// Manual or camera-based fallback scan emission
  void emitCameraScan(String barcode, {String symbology = 'UNKNOWN'}) {
    _emitScan(barcode, symbology: symbology, source: ScanSource.camera);
  }

  /// Manual keyboard/dialog scan input
  void emitManualScan(String barcode) {
    _emitScan(barcode, symbology: 'MANUAL', source: ScanSource.manual);
  }

  /// Emit scan with debouncing check
  void _emitScan(
    String barcode, {
    String symbology = 'UNKNOWN',
    ScanSource source = ScanSource.hardwarePda,
  }) {
    final now = DateTime.now();

    // Debounce duplicate scans within debounceMs unless continuous mode is active
    if (!_continuousMode &&
        _lastScannedCode == barcode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < debounceMs) {
      return;
    }

    _lastScannedCode = barcode;
    _lastScanTime = now;

    final event = BarcodeScanEvent(
      barcode: barcode,
      symbology: symbology,
      timestamp: now,
      source: source,
    );

    _scanStreamController.add(event);
  }

  /// Toggle continuous rapid scanning (useful for inventory shelf audits)
  void setContinuousMode(bool enabled) {
    _continuousMode = enabled;
  }

  /// Software trigger to activate laser on supported Zebra/Honeywell terminals
  Future<void> triggerLaser() async {
    try {
      await _methodChannel.invokeMethod('softTrigger');
    } catch (_) {
      // Ignore if unsupported
    }
  }

  /// Dispose listeners and close broadcast stream
  void dispose() {
    _eventSubscription?.cancel();
    _scanStreamController.close();
    _isInitialized = false;
  }
}
