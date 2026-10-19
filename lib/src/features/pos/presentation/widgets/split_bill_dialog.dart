import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/dashboard_provider.dart';
import '../../../../core/providers/tables_provider.dart';
import '../../../../core/utils/custom_snackbar.dart';
import '../../../waiter/application/waiter_provider.dart';
import '../../application/pos_provider.dart';

class SplitBillDialog extends ConsumerStatefulWidget {
  final String? tableId;
  final String? tableName;
  final String? orderId;
  final double totalAmount;
  final VoidCallback? onPaymentSuccess;

  const SplitBillDialog({
    super.key,
    required this.tableId,
    this.tableName,
    this.orderId,
    required this.totalAmount,
    this.onPaymentSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required String? tableId,
    String? tableName,
    String? orderId,
    required double totalAmount,
    VoidCallback? onPaymentSuccess,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SplitBillDialog(
        tableId: tableId,
        tableName: tableName,
        orderId: orderId,
        totalAmount: totalAmount,
        onPaymentSuccess: onPaymentSuccess,
      ),
    );
  }

  @override
  ConsumerState<SplitBillDialog> createState() => _SplitBillDialogState();
}

class _PersonShare {
  final int index;
  double amount;
  String? method; // 'CREDIT_CARD' or 'CASH'
  bool isPaid;

  _PersonShare({
    required this.index,
    required this.amount,
  }) : method = null, isPaid = false;
}

class _SplitBillDialogState extends ConsumerState<SplitBillDialog> {
  int _personCount = 1;
  bool _isProcessing = false;

  // 1 Kişi (Parçalı: Kart + Nakit) için Controller'lar
  late TextEditingController _cardAmountController;
  late TextEditingController _cashAmountController;

  // 2+ Kişi için durum listesi
  List<_PersonShare> _shares = [];

  @override
  void initState() {
    super.initState();
    _cardAmountController = TextEditingController(text: widget.totalAmount.toStringAsFixed(2));
    _cashAmountController = TextEditingController(text: '0.00');
    _recalculateShares(1);
  }

  @override
  void dispose() {
    _cardAmountController.dispose();
    _cashAmountController.dispose();
    super.dispose();
  }

  void _recalculateShares(int count) {
    HapticFeedback.selectionClick();
    _personCount = count;
    if (count <= 1) {
      _shares = [];
      _cardAmountController.text = widget.totalAmount.toStringAsFixed(2);
      _cashAmountController.text = '0.00';
      return;
    }

    final totalInCents = (widget.totalAmount * 100).round();
    final baseCents = totalInCents ~/ count;
    final remainderCents = totalInCents % count;

    _shares = List.generate(count, (i) {
      final cents = baseCents + (i < remainderCents ? 1 : 0);
      return _PersonShare(index: i + 1, amount: cents / 100.0);
    });
  }

  void _onCardChanged(String val) {
    final parsed = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    final clamped = parsed.clamp(0.0, widget.totalAmount);
    final remaining = (widget.totalAmount - clamped).clamp(0.0, widget.totalAmount);
    _cashAmountController.text = remaining.toStringAsFixed(2);
  }

  void _onCashChanged(String val) {
    final parsed = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    final clamped = parsed.clamp(0.0, widget.totalAmount);
    final remaining = (widget.totalAmount - clamped).clamp(0.0, widget.totalAmount);
    _cardAmountController.text = remaining.toStringAsFixed(2);
  }

  void _setSingleSplit(double card, double cash) {
    HapticFeedback.selectionClick();
    _cardAmountController.text = card.toStringAsFixed(2);
    _cashAmountController.text = cash.toStringAsFixed(2);
  }

  double get _singleCardAmount =>
      double.tryParse(_cardAmountController.text.replaceAll(',', '.')) ?? 0.0;
  double get _singleCashAmount =>
      double.tryParse(_cashAmountController.text.replaceAll(',', '.')) ?? 0.0;

  double get _multiPaidTotal =>
      _shares.where((s) => s.isPaid).fold(0.0, (sum, s) => sum + s.amount);
  double get _multiCardTotal => _shares
      .where((s) => s.isPaid && s.method == 'CREDIT_CARD')
      .fold(0.0, (sum, s) => sum + s.amount);
  double get _multiCashTotal => _shares
      .where((s) => s.isPaid && s.method == 'CASH')
      .fold(0.0, (sum, s) => sum + s.amount);

  bool get _canSubmit {
    if (_isProcessing) return false;
    if (_personCount == 1) {
      final sum = _singleCardAmount + _singleCashAmount;
      return (sum - widget.totalAmount).abs() <= 0.05 && sum > 0;
    } else {
      return _shares.isNotEmpty && _shares.every((s) => s.isPaid);
    }
  }

  Future<void> _submitPayment() async {
    if (!_canSubmit) return;
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    final double cardAmt;
    final double cashAmt;

    if (_personCount == 1) {
      cardAmt = _singleCardAmount;
      cashAmt = _singleCashAmount;
    } else {
      cardAmt = _multiCardTotal;
      cashAmt = _multiCashTotal;
    }

    final String paymentMethod;
    if (cardAmt > 0 && cashAmt > 0) {
      paymentMethod = 'MIXED';
    } else if (cardAmt > 0) {
      paymentMethod = 'CREDIT_CARD';
    } else {
      paymentMethod = 'CASH';
    }

    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '/pos/process-payment',
        data: {
          if (widget.tableId != null) 'table_id': widget.tableId,
          if (widget.orderId != null) 'order_id': widget.orderId,
          'payment_method': paymentMethod,
          'amount': widget.totalAmount,
          'card_amount': cardAmt,
          'cash_amount': cashAmt,
        },
      );

      ref.invalidate(posTablesProvider);
      ref.invalidate(waiterZonesProvider);
      ref.invalidate(tablesProvider);
      ref.invalidate(dashboardProvider);

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop();

      final summary = [
        if (cardAmt > 0) '₺${cardAmt.toStringAsFixed(2)} Kart',
        if (cashAmt > 0) '₺${cashAmt.toStringAsFixed(2)} Nakit',
      ].join(' + ');

      CustomSnackBar.show(
        context,
        'Hesap başarıyla kapatıldı! ($summary)',
      );

      widget.onPaymentSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Ödeme tamamlanamadı: $e';
      CustomSnackBar.show(context, msg, isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    const activeColor = Color(0xFF6B52FF);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sürükleme çizgisi
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: textSecColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.splitscreen, color: activeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesabı Böl',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.tableName ?? "Masa"} • Toplam: ₺${widget.totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(color: textSecColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textSecColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kişi Sayısı Seçimi
                    Text(
                      'KAÇ KİŞİ ÖDEYECEK?',
                      style: TextStyle(
                        color: textSecColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Kişi Sayacı & Hızlı Seçim
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _personCount == 1
                                    ? '1 Kişi (Parçalı Kart + Nakit)'
                                    : '$_personCount Kişi (Eşit Pay)',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  _buildCounterButton(
                                    icon: Icons.remove,
                                    onTap: _personCount > 1
                                        ? () => setState(() => _recalculateShares(_personCount - 1))
                                        : null,
                                    isDark: isDark,
                                  ),
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 40),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$_personCount',
                                      style: const TextStyle(
                                        color: activeColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  _buildCounterButton(
                                    icon: Icons.add,
                                    onTap: _personCount < 20
                                        ? () => setState(() => _recalculateShares(_personCount + 1))
                                        : null,
                                    isDark: isDark,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Hızlı seçim hapları
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [1, 2, 3, 4, 5, 6].map((n) {
                                final isSel = _personCount == n;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _recalculateShares(n)),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSel ? activeColor : (isDark ? const Color(0xFF161B22) : Colors.white),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSel ? activeColor : cardBorder,
                                        ),
                                      ),
                                      child: Text(
                                        n == 1 ? '1 Kişi' : '$n Kişi',
                                        style: TextStyle(
                                          color: isSel ? Colors.white : textColor,
                                          fontSize: 12,
                                          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 1 Kişi Modu: Parçalı Kart + Nakit
                    if (_personCount == 1) ...[
                      Text(
                        'ÖDEME DAĞILIMI',
                        style: TextStyle(
                          color: textSecColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Hızlı oran butonları
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickRatioButton(
                              'Tümü Kart',
                              () => setState(() => _setSingleSplit(widget.totalAmount, 0.0)),
                              cardBg,
                              cardBorder,
                              textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildQuickRatioButton(
                              'Tümü Nakit',
                              () => setState(() => _setSingleSplit(0.0, widget.totalAmount)),
                              cardBg,
                              cardBorder,
                              textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildQuickRatioButton(
                              '%50 / %50',
                              () => setState(() {
                                final half = widget.totalAmount / 2.0;
                                _setSingleSplit(half, widget.totalAmount - half);
                              }),
                              cardBg,
                              cardBorder,
                              textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Kart Tutarı Girişi
                      _buildAmountField(
                        icon: Icons.credit_card,
                        iconColor: const Color(0xFF4F75FF),
                        title: 'Kart ile Ödenecek',
                        controller: _cardAmountController,
                        onChanged: (val) => setState(() => _onCardChanged(val)),
                        cardBg: cardBg,
                        cardBorder: cardBorder,
                        textColor: textColor,
                        textSecColor: textSecColor,
                      ),
                      const SizedBox(height: 12),

                      // Nakit Tutarı Girişi
                      _buildAmountField(
                        icon: Icons.payments_outlined,
                        iconColor: const Color(0xFF00C896),
                        title: 'Nakit ile Ödenecek (Otomatik Kalan)',
                        controller: _cashAmountController,
                        onChanged: (val) => setState(() => _onCashChanged(val)),
                        cardBg: cardBg,
                        cardBorder: cardBorder,
                        textColor: textColor,
                        textSecColor: textSecColor,
                      ),
                      const SizedBox(height: 14),

                      // Eşleşme Durumu Kartı
                      _buildMatchSummary(
                        card: _singleCardAmount,
                        cash: _singleCashAmount,
                        total: widget.totalAmount,
                        isDark: isDark,
                        textColor: textColor,
                      ),
                    ] else ...[
                      // 2+ Kişi Modu: Sıralı Tahsilat
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'KİŞİ BAŞI: ₺${(widget.totalAmount / _personCount).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_shares.where((s) => s.isPaid).length} / $_personCount Ödendi',
                            style: TextStyle(
                              color: _shares.every((s) => s.isPaid)
                                  ? const Color(0xFF00C896)
                                  : activeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // İlerleme Çubuğu
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: widget.totalAmount > 0
                              ? (_multiPaidTotal / widget.totalAmount).clamp(0.0, 1.0)
                              : 0.0,
                          backgroundColor: cardBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _shares.every((s) => s.isPaid)
                                ? const Color(0xFF00C896)
                                : activeColor,
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tahsil: ₺${_multiPaidTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF00C896),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Kalan: ₺${(widget.totalAmount - _multiPaidTotal).clamp(0.0, widget.totalAmount).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: (widget.totalAmount - _multiPaidTotal) <= 0.05
                                  ? const Color(0xFF00C896)
                                  : Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Kişi Kartları Listesi
                      ..._shares.map((share) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: share.isPaid
                                ? (isDark
                                    ? const Color(0xFF00C896).withValues(alpha: 0.08)
                                    : const Color(0xFF00C896).withValues(alpha: 0.06))
                                : cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: share.isPaid
                                  ? const Color(0xFF00C896).withValues(alpha: 0.4)
                                  : cardBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Kişi İkon / Sıra
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: share.isPaid
                                      ? const Color(0xFF00C896).withValues(alpha: 0.2)
                                      : activeColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: share.isPaid
                                      ? const Icon(Icons.check, color: Color(0xFF00C896), size: 18)
                                      : Text(
                                          '${share.index}',
                                          style: const TextStyle(
                                            color: activeColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Kişi Bilgisi & Tutar
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${share.index}. Kişi Payı',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₺${share.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: share.isPaid
                                            ? const Color(0xFF00C896)
                                            : textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Tahsilat Butonları veya Ödendi Rozeti
                              if (!share.isPaid) ...[
                                _buildPayMethodButton(
                                  icon: Icons.credit_card,
                                  label: 'Kart',
                                  color: const Color(0xFF4F75FF),
                                  onTap: () {
                                    setState(() {
                                      share.method = 'CREDIT_CARD';
                                      share.isPaid = true;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildPayMethodButton(
                                  icon: Icons.payments_outlined,
                                  label: 'Nakit',
                                  color: const Color(0xFF00C896),
                                  onTap: () {
                                    setState(() {
                                      share.method = 'CASH';
                                      share.isPaid = true;
                                    });
                                  },
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00C896).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        share.method == 'CREDIT_CARD'
                                            ? Icons.credit_card
                                            : Icons.payments_outlined,
                                        color: const Color(0xFF00C896),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        share.method == 'CREDIT_CARD' ? 'Kart' : 'Nakit',
                                        style: const TextStyle(
                                          color: Color(0xFF00C896),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(Icons.undo, color: textSecColor, size: 18),
                                  tooltip: 'Geri Al',
                                  onPressed: () {
                                    setState(() {
                                      share.method = null;
                                      share.isPaid = false;
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            // Alt Buton Alanı
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(top: BorderSide(color: cardBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submitPayment : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
                    disabledBackgroundColor: activeColor.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _personCount == 1
                              ? 'Ödemeyi Tamamla (₺${_singleCardAmount.toStringAsFixed(2)} Kart + ₺${_singleCashAmount.toStringAsFixed(2)} Nakit)'
                              : (_shares.every((s) => s.isPaid)
                                  ? 'Masayı Kapat ve Tamamla (₺${widget.totalAmount.toStringAsFixed(2)})'
                                  : 'Tüm Kişilerin Ödemesini Seçin (${_shares.where((s) => s.isPaid).length}/$_personCount)'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: onTap != null
              ? (isDark ? const Color(0xFF161B22) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: onTap != null
                ? (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1))
                : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? (isDark ? Colors.white : const Color(0xFF0F172A))
              : (isDark ? Colors.white24 : Colors.black26),
        ),
      ),
    );
  }

  Widget _buildQuickRatioButton(
    String label,
    VoidCallback onTap,
    Color bg,
    Color border,
    Color text,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildAmountField({
    required IconData icon,
    required Color iconColor,
    required String title,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required Color cardBg,
    required Color cardBorder,
    required Color textColor,
    required Color textSecColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textSecColor, fontSize: 11)),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '₺',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchSummary({
    required double card,
    required double cash,
    required double total,
    required bool isDark,
    required Color textColor,
  }) {
    final diff = (card + cash - total).abs();
    final isMatched = diff <= 0.05;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMatched
            ? const Color(0xFF00C896).withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMatched
              ? const Color(0xFF00C896).withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMatched ? Icons.check_circle : Icons.info_outline,
            color: isMatched ? const Color(0xFF00C896) : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMatched
                  ? 'Toplam tam denk geldi: ₺${(card + cash).toStringAsFixed(2)} / ₺${total.toStringAsFixed(2)}'
                  : 'Fark var: ₺${(card + cash).toStringAsFixed(2)} (Kalan: ₺${(total - (card + cash)).toStringAsFixed(2)})',
              style: TextStyle(
                color: isMatched ? const Color(0xFF00C896) : Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayMethodButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
