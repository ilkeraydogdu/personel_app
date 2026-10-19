import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pda_barcode_scanner.dart';

/// Item in a Q-Commerce picking batch
class PickTaskItem {
  final String orderItemId;
  final String productName;
  final String barcode;
  final String aisle;
  final String shelf;
  final String tier;
  final int requiredQty;
  int collectedQty;
  bool isSubstituted;
  String? substituteProductName;

  PickTaskItem({
    required this.orderItemId,
    required this.productName,
    required this.barcode,
    required this.aisle,
    required this.shelf,
    required this.tier,
    required this.requiredQty,
    this.collectedQty = 0,
    this.isSubstituted = false,
    this.substituteProductName,
  });

  bool get isFulfilled => collectedQty >= requiredQty;
  String get locationTag => '$aisle-$shelf-$tier';
}

/// Dark Store / Q-Commerce Picker Screen for high-speed warehouse fulfillment
class DarkStorePickerScreen extends StatefulWidget {
  final String orderId;
  final String platform; // 'getir', 'trendyol', 'yemeksepeti'
  final int slaTotalSeconds;

  const DarkStorePickerScreen({
    super.key,
    required this.orderId,
    this.platform = 'getir',
    this.slaTotalSeconds = 600, // 10 minutes default SLA
  });

  @override
  State<DarkStorePickerScreen> createState() => _DarkStorePickerScreenState();
}

class _DarkStorePickerScreenState extends State<DarkStorePickerScreen> {
  final PdaBarcodeScanner _scanner = PdaBarcodeScanner();
  StreamSubscription<BarcodeScanEvent>? _scannerSub;

  late int _remainingSeconds;
  Timer? _slaTimer;

  final List<PickTaskItem> _items = [];
  int _currentIndex = 0;
  bool _isFinished = false;
  String? _lastErrorBanner;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.slaTotalSeconds;
    _initPickerData();
    _startSlaCountdown();
    _initScanner();
  }

  void _initPickerData() {
    // Standard dark store route-optimized picking tasks sorted by aisle, shelf, tier
    _items.addAll([
      PickTaskItem(
        orderItemId: 'ITEM-101',
        productName: 'Sütaş Tam Yağlı Süt 1L',
        barcode: '8690555010012',
        aisle: 'K-01',
        shelf: 'R-03',
        tier: 'T-1',
        requiredQty: 2,
      ),
      PickTaskItem(
        orderItemId: 'ITEM-102',
        productName: 'Eti Burçak Bisküvi 131g',
        barcode: '8690526010025',
        aisle: 'K-02',
        shelf: 'R-01',
        tier: 'T-2',
        requiredQty: 3,
      ),
      PickTaskItem(
        orderItemId: 'ITEM-103',
        productName: 'Coca Cola Zero Sugar 1L',
        barcode: '5449000000996',
        aisle: 'K-03',
        shelf: 'R-02',
        tier: 'T-3',
        requiredQty: 1,
      ),
      PickTaskItem(
        orderItemId: 'ITEM-104',
        productName: 'Lipton Doğu Karadeniz Demlik 100lü',
        barcode: '8690637841108',
        aisle: 'K-04',
        shelf: 'R-05',
        tier: 'T-2',
        requiredQty: 1,
      ),
    ]);

    // Sort by warehouse aisle location to minimize picker steps
    _items.sort((a, b) => a.locationTag.compareTo(b.locationTag));
  }

  void _startSlaCountdown() {
    _slaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initScanner() async {
    await _scanner.initialize();
    _scannerSub = _scanner.scanStream.listen((event) {
      _processScannedBarcode(event.barcode);
    });
  }

  @override
  void dispose() {
    _slaTimer?.cancel();
    _scannerSub?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  void _processScannedBarcode(String barcode) {
    if (_isFinished) return;

    final targetItem = _items[_currentIndex];

    if (barcode.trim() == targetItem.barcode.trim()) {
      // MATCH! Correct item scanned
      HapticFeedback.lightImpact();

      setState(() {
        _lastErrorBanner = null;
        targetItem.collectedQty += 1;

        if (targetItem.isFulfilled) {
          if (_currentIndex < _items.length - 1) {
            _currentIndex++;
          } else {
            _checkAllFulfilled();
          }
        }
      });
    } else {
      // MISMATCH! Haptic heavy error feedback and alert banner
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);

      setState(() {
        _lastErrorBanner =
            'HATALI ÜRÜN OKUTULDU! (Okunan: $barcode)\nBeklenen: ${targetItem.productName} [${targetItem.barcode}]';
      });
    }
  }

  void _checkAllFulfilled() {
    final allDone = _items.every((it) => it.isFulfilled);
    if (allDone) {
      setState(() => _isFinished = true);
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _openSubstitutionDialog() async {
    final item = _items[_currentIndex];
    final subNameController = TextEditingController();

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.swap_horiz, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Alternatif Ürün Öner', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rafta Bulunamayan: ${item.productName}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subNameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Müşteriye Önerilecek Alternatif',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  hintText: 'Örn: Sütaş Yarım Yağlı 1L',
                  hintStyle: TextStyle(color: Colors.white24),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (subNameController.text.isNotEmpty) {
                  setState(() {
                    item.isSubstituted = true;
                    item.substituteProductName = subNameController.text;
                    item.collectedQty = item.requiredQty;
                    if (_currentIndex < _items.length - 1) {
                      _currentIndex++;
                    } else {
                      _checkAllFulfilled();
                    }
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Müşteriye Bildir'),
            ),
          ],
        ),
      );
    } finally {
      subNameController.dispose();
    }
  }

  String _formatSlaTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentTarget = _items[_currentIndex];
    final totalRequired = _items.fold(0, (sum, i) => sum + i.requiredQty);
    final totalCollected = _items.fold(0, (sum, i) => sum + i.collectedQty);
    final progress = totalRequired > 0 ? (totalCollected / totalRequired) : 0.0;

    final isUrgent = _remainingSeconds < 180; // less than 3 mins

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.platform == 'getir'
                    ? const Color(0xFF5D3EBC)
                    : const Color(0xFFF97316),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.platform.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Toplama #${widget.orderId}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF065F46),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  _formatSlaTime(_remainingSeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Linear Progress Bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF334155),
            color: const Color(0xFF10B981),
            minHeight: 6,
          ),

          // Error Banner if wrong barcode was scanned
          if (_lastErrorBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFDC2626),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _lastErrorBanner!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main Target Item Card
          if (!_isFinished) ...[
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6366F1), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '📍 HEDEF KONUM: ${currentTarget.locationTag}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Text(
                        '${_currentIndex + 1} / ${_items.length}',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentTarget.productName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Barkod: ${currentTarget.barcode}',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Toplanan: ${currentTarget.collectedQty} / ${currentTarget.requiredQty} Adet',
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: const Color(0xFFFBBF24),
                        ),
                        onPressed: _openSubstitutionDialog,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Ürün Yok'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Picking Completed Screen
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 64, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Sipariş Toplama Tamamlandı!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kurye poşet barkodu oluşturuldu: BAG-${widget.orderId}',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.print, color: Colors.white),
                      label: const Text(
                        'Kurye Etiketini Bas ve Çık',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Remaining Tasks List
          if (!_isFinished) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Sıradaki Ürünler (Rota Sıralı):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '$totalCollected / $totalRequired Adet',
                    style: const TextStyle(
                      color: Color(0xFF34D399),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, idx) {
                  final it = _items[idx];
                  final isCurrent = idx == _currentIndex;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFF6366F1)
                            : (it.isFulfilled
                                ? const Color(0xFF10B981)
                                : Colors.white.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          it.locationTag,
                          style: TextStyle(
                            color: isCurrent ? const Color(0xFF38BDF8) : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            it.productName,
                            style: TextStyle(
                              color: it.isFulfilled ? Colors.white38 : Colors.white,
                              decoration: it.isFulfilled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (it.isFulfilled)
                          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18)
                        else
                          Text(
                            '${it.collectedQty}/${it.requiredQty}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
