import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pda_barcode_scanner.dart';

/// Item counted during a blind stocktaking session.
/// Note: Expected/System stock is intentionally omitted to uphold the blind count principle.
class BlindStocktakeItem {
  final String barcode;
  final String? productName;
  final String? sku;
  int countedQty;
  final DateTime firstScannedAt;
  DateTime lastScannedAt;

  BlindStocktakeItem({
    required this.barcode,
    this.productName,
    this.sku,
    this.countedQty = 1,
    required this.firstScannedAt,
    required this.lastScannedAt,
  });
}

/// Blind Stocktaking Screen for PDA Terminals
class BlindStocktakeScreen extends StatefulWidget {
  final String? sessionId;
  final String? branchId;
  final String? defaultShelfCode;

  const BlindStocktakeScreen({
    super.key,
    this.sessionId,
    this.branchId,
    this.defaultShelfCode,
  });

  @override
  State<BlindStocktakeScreen> createState() => _BlindStocktakeScreenState();
}

class _BlindStocktakeScreenState extends State<BlindStocktakeScreen> {
  final PdaBarcodeScanner _scanner = PdaBarcodeScanner();
  StreamSubscription<BarcodeScanEvent>? _scannerSub;

  final TextEditingController _manualInputController = TextEditingController();
  final TextEditingController _shelfController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<BlindStocktakeItem> _countedItems = [];
  bool _isContinuousMode = true;
  bool _isSubmitting = false;
  String _activeShelf = 'A1-R1-S1';
  int _totalPcsCounted = 0;

  @override
  void initState() {
    super.initState();
    _activeShelf = widget.defaultShelfCode ?? 'A1-R1-S1';
    _shelfController.text = _activeShelf;
    _initScanner();
  }

  Future<void> _initScanner() async {
    await _scanner.initialize();
    _scanner.setContinuousMode(_isContinuousMode);
    _scannerSub = _scanner.scanStream.listen((event) {
      _handleBarcodeScanned(event.barcode);
    });
  }

  @override
  void dispose() {
    _scannerSub?.cancel();
    _scanner.dispose();
    _manualInputController.dispose();
    _shelfController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleBarcodeScanned(String rawBarcode) {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    HapticFeedback.lightImpact();

    setState(() {
      final existingIndex =
          _countedItems.indexWhere((item) => item.barcode == barcode);

      if (existingIndex != -1) {
        _countedItems[existingIndex].countedQty += 1;
        _countedItems[existingIndex].lastScannedAt = DateTime.now();

        // Move to top of the list for visual confirmation
        final item = _countedItems.removeAt(existingIndex);
        _countedItems.insert(0, item);
      } else {
        _countedItems.insert(
          0,
          BlindStocktakeItem(
            barcode: barcode,
            productName: 'Barkod: $barcode',
            countedQty: 1,
            firstScannedAt: DateTime.now(),
            lastScannedAt: DateTime.now(),
          ),
        );
      }

      _recalculateTotal();
    });

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _recalculateTotal() {
    _totalPcsCounted = _countedItems.fold(0, (sum, i) => sum + i.countedQty);
  }

  Future<void> _editQuantity(int index) async {
    final item = _countedItems[index];
    final qtyController = TextEditingController(text: item.countedQty.toString());

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E222D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Adet Düzeltme (${item.barcode})',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Sayılan Adet',
              labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              suffixText: 'Adet',
              suffixStyle: TextStyle(color: Colors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final newQty = int.tryParse(qtyController.text) ?? item.countedQty;
                if (newQty > 0) {
                  setState(() {
                    item.countedQty = newQty;
                    _recalculateTotal();
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
    } finally {
      qtyController.dispose();
    }
  }

  void _removeItem(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _countedItems.removeAt(index);
      _recalculateTotal();
    });
  }

  Future<void> _submitCountSession() async {
    if (_countedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sayım listesi boş. Lütfen ürün okutunuz.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Simulate network save to BlindStocktakingService API
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;

      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_totalPcsCounted adet ürün kör sayım olarak başarıyla kaydedildi!',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      setState(() {
        _countedItems.clear();
        _recalculateTotal();
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kör Sayım Terminali (WMS)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Raf: $_activeShelf • Toplam: $_totalPcsCounted Adet',
              style: const TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Hızlı/Sürekli Okuma Modu',
            icon: Icon(
              _isContinuousMode ? Icons.flash_on : Icons.flash_off,
              color: _isContinuousMode ? const Color(0xFFFBBF24) : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _isContinuousMode = !_isContinuousMode;
                _scanner.setContinuousMode(_isContinuousMode);
              });
            },
          ),
          IconButton(
            tooltip: 'Lazer Tetikle',
            icon: const Icon(Icons.barcode_reader, color: Colors.white),
            onPressed: () => _scanner.triggerLaser(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Shelf & Quick Input Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _manualInputController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Barkod gir / okut...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.qr_code_scanner, color: Color(0xFF6366F1)),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) {
                      _handleBarcodeScanned(val);
                      _manualInputController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    _handleBarcodeScanned(_manualInputController.text);
                    _manualInputController.clear();
                  },
                  child: const Text('Ekle', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),

          // Information Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
            child: const Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 16, color: Color(0xFF38BDF8)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kör Sayım: Sistem stok miktarı personel tarafsızlığı için gizlenmiştir.',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Counted Items List
          Expanded(
            child: _countedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 72,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Henüz ürün okutulmadı',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'PDA lazeri veya el ile barkod girerek sayıma başlayın.',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _countedItems.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemBuilder: (context, index) {
                      final item = _countedItems[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index == 0
                                ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                            child: const Icon(Icons.inventory_2, color: Color(0xFF818CF8)),
                          ),
                          title: Text(
                            item.barcode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            'Son Okutma: ${item.lastScannedAt.hour.toString().padLeft(2, '0')}:${item.lastScannedAt.minute.toString().padLeft(2, '0')}:${item.lastScannedAt.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _editQuantity(index),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF10B981)),
                                  ),
                                  child: Text(
                                    '${item.countedQty} Adet',
                                    style: const TextStyle(
                                      color: Color(0xFF34D399),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                                onPressed: () => _removeItem(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_countedItems.length} Çeşit Ürün',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          '$_totalPcsCounted Toplam Adet',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSubmitting ? null : _submitCountSession,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Kaydediliyor...' : 'Sayımı Onayla',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
