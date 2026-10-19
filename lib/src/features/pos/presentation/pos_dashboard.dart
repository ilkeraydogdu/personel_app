import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/tables_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/websocket/websocket_service.dart';
import '../../../core/widgets/staff_menu_modal.dart';
import '../../waiter/application/waiter_provider.dart';
import '../application/pos_provider.dart';
import 'widgets/split_bill_dialog.dart';
import '../../../core/utils/safe_parsers.dart';

class PosDashboard extends ConsumerStatefulWidget {
  const PosDashboard({super.key});

  @override
  ConsumerState<PosDashboard> createState() => _PosDashboardState();
}

class _PosDashboardState extends ConsumerState<PosDashboard> {
  bool _isProcessing = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  // Filter mode: 0 = Ödeme Bekleyenler (Dolu), 1 = Tüm Masalar
  int _selectedFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authProvider);
      ref.read(webSocketServiceProvider).connect(
            businessId: auth.businessId,
            userId: auth.userId,
          );
      final api = ref.read(apiClientProvider);
      PersonelNotificationService().registerDeviceWithBackend(api);
      PersonelNotificationService().startWatchdog(api);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    PersonelNotificationService().stopWatchdog();
    super.dispose();
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('[_triggerHaptic] Haptic feedback error: $e');
    }
  }

  Future<void> _processPayment({
    required PosTableModel table,
    required String method,
    double? customAmount,
  }) async {
    final amount = customAmount ?? table.totalAmount;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isProcessing = true);
    final api = ref.read(apiClientProvider);

    try {
      final res = await api.post('/pos/process-payment', data: {
        'table_id': table.id,
        'payment_method': method.toUpperCase(),
        'amount': amount,
      });

      if (!mounted) return;
      if (res['success'] == true || (res['status_code'] ?? 200) == 200) {
        _triggerHaptic();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${table.name} hesabı kapatıldı (₺${amount.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        ref.invalidate(posTablesProvider);
        ref.invalidate(waiterZonesProvider);
        ref.invalidate(tablesProvider);
        ref.invalidate(dashboardProvider);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(res['error']?.toString() ?? res['message']?.toString() ?? 'Ödeme işlenemedi'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e is ApiException ? e.message : 'Ödeme hatası: $e';
      messenger.showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _printAdisyon(PosTableModel table) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      final res = await api.post('/pos/print-adisyon', body: {
        'table_id': table.id,
      });
      if (!mounted) return;
      final msg = res['message'] ??
          (res['data'] is Map ? res['data']['message'] : null) ??
          'Adisyon fişi başarıyla yazıcıya aktarıldı.';
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errMsg = e is ApiException ? e.message : '$e';
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Yazdırma hatası: $errMsg',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSplitPaymentDialog(PosTableModel table) {
    SplitBillDialog.show(
      context,
      tableId: table.id,
      tableName: table.name,
      totalAmount: table.totalAmount,
      onPaymentSuccess: () {
        ref.invalidate(posTablesProvider);
        ref.invalidate(waiterZonesProvider);
      },
    );
  }

  void _showAdisyonDetailSheet(PosTableModel table) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final detailsFuture = ref.read(apiClientProvider).get(
          '/waiter/table-details',
          queryParameters: {'table_id': table.id},
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: detailsFuture,
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            Map<String, dynamic>? data;
            if (snapshot.hasData && snapshot.data != null) {
              final res = snapshot.data!;
              if (res['data'] is Map) {
                data = Map<String, dynamic>.from(res['data'] as Map);
              } else {
                data = res;
              }
            }

            final orders = safeList(data?['active_orders'] ?? data?['orders']);
            final totalAmount = double.tryParse('${data?['total_amount'] ?? data?['bill_total'] ?? table.totalAmount}') ?? table.totalAmount;

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Sheet Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header: Table Info & Total
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.receipt_long, color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        table.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        table.zoneName.isNotEmpty ? '${table.zoneName} • Açık Adisyon' : 'Açık Adisyon Detayı',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Adisyon Yazdır',
                                icon: Icon(Icons.print_outlined, color: textSecColor),
                                onPressed: () => _printAdisyon(table),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: textSecColor),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Items List: Minimal Single Line per item with complete details
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488)))
                          : orders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.restaurant_outlined, size: 48, color: textSecColor.withValues(alpha: 0.5)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Bu masada henüz kayıtlı ürün kalemi yok.',
                                        style: TextStyle(color: textSecColor, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  children: [
                                    ...orders.expand((o) {
                                      final items = o is Map ? safeList(o['items']) : const [];
                                      return items.map((it) {
                                        if (it is! Map) return const SizedBox.shrink();
                                        final name = it['name'] ?? it['item_name'] ?? it['product_name'] ?? 'Ürün';
                                        final qty = it['quantity'] ?? it['item_quantity'] ?? 1;
                                        final price = double.tryParse('${it['price'] ?? it['item_price'] ?? it['unit_price'] ?? 0}') ?? 0.0;
                                        final itemTotal = price * qty;
                                        final rawImg = it['item_image']?.toString() ?? it['image']?.toString() ?? '';
                                        final imgUrl = AppConfig.assetUrl(rawImg) ?? '';
                                        final variant = (it['variant_name'] ?? it['variant'] ?? '').toString();
                                        final note = it['note']?.toString() ?? it['item_note']?.toString();

                                        // Parse excluded ingredients
                                        List<String> excludedList = [];
                                        final rawEx = it['excluded_ingredients'] ?? it['removed_ingredients'];
                                        if (rawEx is List) {
                                          excludedList = rawEx.map((e) => e.toString()).toList();
                                        } else if (rawEx is String && rawEx.isNotEmpty && rawEx != '[]') {
                                          excludedList = rawEx.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                                        }

                                        // Parse extras (support both Map and String items)
                                        List<Map<String, dynamic>> extrasList = [];
                                        final rawExtras = it['selected_extras'] ?? it['extras'];
                                        if (rawExtras is List) {
                                          for (final ex in rawExtras) {
                                            if (ex is Map<String, dynamic>) {
                                              extrasList.add(ex);
                                            } else if (ex is Map) {
                                              extrasList.add(Map<String, dynamic>.from(ex));
                                            } else if (ex != null && ex.toString().trim().isNotEmpty) {
                                              extrasList.add({'name': ex.toString().trim(), 'price': 0});
                                            }
                                          }
                                        }

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              // Product Thumbnail
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Container(
                                                  width: 44,
                                                  height: 44,
                                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                                  child: imgUrl.isNotEmpty
                                                      ? Image.network(
                                                          imgUrl,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => const Icon(Icons.fastfood_outlined, size: 20, color: Color(0xFF0D9488)),
                                                        )
                                                      : const Icon(Icons.fastfood_outlined, size: 20, color: Color(0xFF0D9488)),
                                                ),
                                              ),
                                              const SizedBox(width: 10),

                                              // Quantity Badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(7),
                                                  border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  '${qty}x',
                                                  style: const TextStyle(
                                                    color: Color(0xFF0D9488),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),

                                              // Product Name, Variants, Excluded, Extras (Single row / compact wrap)
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            name,
                                                            style: TextStyle(
                                                              color: textColor,
                                                              fontWeight: FontWeight.w700,
                                                              fontSize: 14,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (variant.isNotEmpty) ...[
                                                          const SizedBox(width: 6),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(5),
                                                            ),
                                                            child: Text(
                                                              variant,
                                                              style: const TextStyle(
                                                                color: Color(0xFF818CF8),
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),

                                                    // Excluded / Extras / Note Badges
                                                    if (excludedList.isNotEmpty || extrasList.isNotEmpty || (note != null && note.isNotEmpty)) ...[
                                                      const SizedBox(height: 3),
                                                      Wrap(
                                                        spacing: 4,
                                                        runSpacing: 2,
                                                        children: [
                                                          ...excludedList.map((ex) => Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                decoration: BoxDecoration(
                                                                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                                                  borderRadius: BorderRadius.circular(4),
                                                                ),
                                                                child: Text(
                                                                  '🚫 $ex',
                                                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                                                                ),
                                                              )),
                                                          ...extrasList.map((ex) {
                                                            final exName = ex['name'] ?? ex['extra_name'] ?? 'Ekstra';
                                                            final exP = double.tryParse('${ex['price'] ?? ex['extra_price'] ?? 0}') ?? 0.0;
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: Text(
                                                                '+ $exName (+₺${exP.toStringAsFixed(0)})',
                                                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                                              ),
                                                            );
                                                          }),
                                                          if (note != null && note.isNotEmpty)
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: Text(
                                                                '📌 $note',
                                                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontStyle: FontStyle.italic),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              // Item Total Price
                                              Text(
                                                '₺${itemTotal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: Color(0xFF10B981),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      });
                                    }),
                                  ],
                                ),
                    ),

                    // Bottom Total & Fast Payment Actions
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: Border(top: BorderSide(color: cardBorder)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Total Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Adisyon Toplamı:',
                                style: TextStyle(color: textSecColor, fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '₺${totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Direct Payment Buttons: Nakit / Kart
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.payments_outlined, size: 20),
                                  label: const Text(
                                    'Nakit Kapat',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          final currentTable = PosTableModel(
                                            id: table.id,
                                            name: table.name,
                                            totalAmount: totalAmount,
                                            status: table.status,
                                            zoneName: table.zoneName,
                                          );
                                          _processPayment(table: currentTable, method: 'cash', customAmount: totalAmount);
                                        },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.credit_card_outlined, size: 20),
                                  label: const Text(
                                    'Kartla Kapat',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          final currentTable = PosTableModel(
                                            id: table.id,
                                            name: table.name,
                                            totalAmount: totalAmount,
                                            status: table.status,
                                            zoneName: table.zoneName,
                                          );
                                          _processPayment(table: currentTable, method: 'credit_card', customAmount: totalAmount);
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Split Bill (Hesap Bölme) Action Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0D9488),
                                side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.splitscreen, size: 19),
                              label: const Text(
                                'Hesabı Böl (Kişiye / Parçalı Ödeme)',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      final currentTable = PosTableModel(
                                        id: table.id,
                                        name: table.name,
                                        totalAmount: totalAmount,
                                        status: table.status,
                                        zoneName: table.zoneName,
                                      );
                                      _showSplitPaymentDialog(currentTable);
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(posTablesProvider);

    ref.listen<AsyncValue<WebSocketEvent>>(wsEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (event.isTableEvent || event.isOrderEvent || event.isKitchenEvent || event.isBillRequest || event.isCustomerSeated) {
        _triggerHaptic();
        if (event.isCustomerSeated) {
          final msg = event.data?['message']?.toString() ?? 'Yeni misafir masaya oturdu.';
          PersonelNotificationService().showStaffAlert(
            title: '👋 Masaya Misafir Oturdu',
            body: msg,
            isUrgent: true,
          );
        }
        ref.invalidate(posTablesProvider);
      }
      if (event.type.toUpperCase() == 'NOTIFICATION') {
        final roles = event.data?['target_roles'];
        PersonelNotificationService().alertFromSocket(
          id: event.data?['notification_id']?.toString() ?? event.eventId ?? '',
          title: event.data?['title']?.toString() ?? '',
          body: event.data?['body']?.toString() ?? event.data?['message']?.toString() ?? '',
          roles: roles is List ? roles.map((item) => item.toString()).toList() : [event.data?['target_role']?.toString() ?? ''],
          screenRole: 'POS',
        );
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header: Figma 2026 & iOS Frosted Glass Kasa Ekranı Top Bar ───────────────
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: 0.88),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title & Role Badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Kasa Ekranı',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                                  ),
                                  child: const Text(
                                    'KASİYER / POS',
                                    style: TextStyle(
                                      color: Color(0xFF0D9488),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Hızlı Tahsilat • Canlı Adisyon Takibi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),

                      // Actions: Refresh + 3-Line Operational Menu Button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _triggerHaptic();
                              ref.invalidate(posTablesProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Text('Kasa ve adisyon verileri güncellendi.'),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.refresh_rounded,
                                color: textColor,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 3-Line Operational Hamburger Menu Button
                          GestureDetector(
                            onTap: () {
                              _triggerHaptic();
                              showStaffMenuModal(
                                context: context,
                                ref: ref,
                                currentScreen: 'pos',
                                onRefresh: () => ref.invalidate(posTablesProvider),
                                refreshLabel: 'Kasa Masalarını Yenile',
                                refreshSubtitle: 'Canlı hesap ve adisyon verilerini hemen senkronize et',
                              );
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.menu_rounded,
                                color: textColor,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Content Area
            Expanded(
              child: tablesAsync.when(
                data: (allTables) {
                  final pendingPaymentTables = allTables.where((t) => t.totalAmount > 0 || t.status.toLowerCase() == 'payment_pending').toList();
                  final vacantCount = allTables.length - pendingPaymentTables.length;
                  final totalPendingRevenue = pendingPaymentTables.fold<double>(0.0, (sum, t) => sum + t.totalAmount);

                  // Table filtering logic:
                  // Tab 0 = Ödeme Bekleyenler (Sadece açık hesap/ödeme bekleyen masalar)
                  // Tab 1 = Tüm Masalar
                  List<PosTableModel> tablesToDisplay = _selectedFilterIndex == 0 ? pendingPaymentTables : allTables;

                  // Search filter
                  if (_searchQuery.isNotEmpty) {
                    tablesToDisplay = tablesToDisplay.where((t) {
                      return t.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                          t.zoneName.toLowerCase().contains(_searchQuery.toLowerCase());
                    }).toList();
                  }

                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(posTablesProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      children: [
                        // ─── Top Minimal Stats Bar (Figma 2026) ────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF161F30) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Occupied and Empty Counter Badges
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${pendingPaymentTables.length} Dolu',
                                          style: const TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$vacantCount Boş',
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Total Pending Amount Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0D9488), Color(0xFF10B981)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'Toplam: ₺${totalPendingRevenue.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ─── Filter Tabs & Search ─────────────────────────────
                        Row(
                          children: [
                            // Tab 1: Ödeme Bekleyenler (Dolu)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedFilterIndex = 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: _selectedFilterIndex == 0
                                        ? const Color(0xFF0D9488)
                                        : (isDark ? const Color(0xFF161F30) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedFilterIndex == 0 ? const Color(0xFF0D9488) : cardBorder,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Ödeme Bekleyen (${pendingPaymentTables.length})',
                                      style: TextStyle(
                                        color: _selectedFilterIndex == 0 ? Colors.white : textColor,
                                        fontWeight: _selectedFilterIndex == 0 ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Tab 2: Tüm Masalar
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedFilterIndex = 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: _selectedFilterIndex == 1
                                        ? const Color(0xFF0D9488)
                                        : (isDark ? const Color(0xFF161F30) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedFilterIndex == 1 ? const Color(0xFF0D9488) : cardBorder,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Tüm Masalar (${allTables.length})',
                                      style: TextStyle(
                                        color: _selectedFilterIndex == 1 ? Colors.white : textColor,
                                        fontWeight: _selectedFilterIndex == 1 ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Search Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF161F30) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorder),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: textColor, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Masa veya alan ara (örn: Masa 4, Bahçe)...',
                              hintStyle: TextStyle(color: textSecColor, fontSize: 13),
                              prefixIcon: Icon(Icons.search, size: 18, color: textSecColor),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, size: 16, color: textSecColor),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _searchController.clear();
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ─── Tables Listing ──────────────────────────────────
                        if (tablesToDisplay.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check_circle_outline, size: 36, color: Color(0xFF10B981)),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    pendingPaymentTables.isEmpty ? 'Ödeme Bekleyen Masa Yok' : 'Aradığınız kriterde masa bulunamadı',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    pendingPaymentTables.isEmpty
                                        ? 'Şu anda açık adisyon veya ödeme bekleyen masa bulunmuyor.'
                                        : 'Filtrenizi temizleyerek tekrar deneyin.',
                                    style: TextStyle(fontSize: 13, color: textSecColor),
                                  ),
                                  if (_selectedFilterIndex == 0 && pendingPaymentTables.isEmpty) ...[
                                    const SizedBox(height: 18),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0D9488),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                      ),
                                      icon: const Icon(Icons.table_restaurant_outlined, size: 18),
                                      label: Text(
                                        'Tüm Masaları Gör (${allTables.length})',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      onPressed: () => setState(() => _selectedFilterIndex = 1),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else
                          ...tablesToDisplay.map((table) {
                            final isOccupied = table.status == 'occupied' || table.totalAmount > 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isOccupied
                                      ? const Color(0xFF0D9488).withValues(alpha: 0.5)
                                      : cardBorder,
                                  width: isOccupied ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isOccupied
                                        ? const Color(0xFF0D9488).withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    _triggerHaptic();
                                    if (table.totalAmount <= 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(Icons.info_outline, color: Colors.white, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  '${table.name} boş, henüz açık sipariş veya adisyon bulunmuyor.',
                                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: const Color(0xFF475569),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                      return;
                                    }
                                    _showAdisyonDetailSheet(table);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        // Row 1: Table Name, Status & Cute Price Badge
                                        Row(
                                          children: [
                                            // Table Icon
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: isOccupied
                                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                                    : const Color(0xFF10B981).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(13),
                                                border: Border.all(
                                                  color: isOccupied
                                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                                                      : const Color(0xFF10B981).withValues(alpha: 0.25),
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.table_restaurant,
                                                color: isOccupied ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Table Name & Zone
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        table.name,
                                                        style: TextStyle(
                                                          fontSize: 17,
                                                          fontWeight: FontWeight.w800,
                                                          color: textColor,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: (isOccupied ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                                                              .withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          isOccupied ? 'Açık Hesap' : 'Müsait',
                                                          style: TextStyle(
                                                            color: isOccupied ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    table.zoneName.isNotEmpty ? table.zoneName : 'Genel Alan',
                                                    style: TextStyle(color: textSecColor, fontSize: 12, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Tatlı Minimal Para Bilgisi (Cute minimal price badge)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isOccupied
                                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isOccupied
                                                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                                      : Colors.transparent,
                                                ),
                                              ),
                                              child: Text(
                                                '₺${table.totalAmount.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  color: isOccupied ? const Color(0xFF10B981) : textSecColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Row 2: Occupied Table Info & Tap to view adisyon
                                        if (isOccupied) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  const Color(0xFF0D9488).withValues(alpha: isDark ? 0.18 : 0.08),
                                                  const Color(0xFF14B8A6).withValues(alpha: isDark ? 0.08 : 0.04),
                                                ],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0D9488).withValues(alpha: 0.18),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.receipt_long_rounded,
                                                    size: 16,
                                                    color: Color(0xFF14B8A6),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'Adisyonu İncele & Tahsil Et',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w700,
                                                          color: Color(0xFF14B8A6),
                                                        ),
                                                      ),
                                                      Text(
                                                        'Ödeme almak için dokunun',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Color(0xFF94A3B8),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Hızlı Adisyon Yazdır',
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                  icon: const Icon(Icons.print_outlined, size: 18, color: Color(0xFF14B8A6)),
                                                  onPressed: _isProcessing ? null : () => _printAdisyon(table),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.arrow_forward_ios_rounded,
                                                  size: 14,
                                                  color: Color(0xFF14B8A6),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488))),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                      const SizedBox(height: 8),
                      Text('Kasa verileri yüklenemedi: $err', style: TextStyle(color: textColor)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.refresh(posTablesProvider),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
