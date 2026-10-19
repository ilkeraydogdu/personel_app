import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/websocket/websocket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/staff_menu_modal.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../kitchen/application/kitchen_provider.dart';
import '../application/prep_provider.dart';

class PrepDashboard extends ConsumerStatefulWidget {
  const PrepDashboard({super.key});

  @override
  ConsumerState<PrepDashboard> createState() => _PrepDashboardState();
}

class _PrepDashboardState extends ConsumerState<PrepDashboard> {
  // Tabs: 0 = Aktif Hazırlıklar, 1 = Tamamlananlar
  int _selectedTabIndex = 0;
  final List<KitchenOrderModel> _completedOrders = [];

  // Urgency & Status filter: 0 = Tümü, 1 = Geciken (>=10 dk), 2 = Yeni (<10 dk), 3 = Hazırlanıyor
  int _selectedUrgencyFilter = 0;
  // Compact high-density mobile view
  bool _isCompactView = false;
  bool _soundAlertsEnabled = PersonelNotificationService().soundAlertsEnabled;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _soundAlertsEnabled = PersonelNotificationService().soundAlertsEnabled;

    // Auto-refresh elapsed time counters every 30 seconds
    _tickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

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
    _tickerTimer?.cancel();
    PersonelNotificationService().stopWatchdog();
    super.dispose();
  }

  bool _isNargile(String name) {
    final l = name.toLowerCase();
    return l.contains('nargile') ||
        l.contains('shisha') ||
        l.contains('hookah') ||
        l.contains('tütün') ||
        l.contains('tutun') ||
        l.contains('köz') ||
        l.contains('koz') ||
        l.contains('lüle') ||
        l.contains('lule');
  }

  bool _matchesUrgency(KitchenOrderModel order, int filter) {
    if (filter == 0) return true;
    if (filter == 1) return order.diffMinutes >= 10;
    if (filter == 2) return order.status.toUpperCase() != 'PREPARING' && order.diffMinutes < 10;
    if (filter == 3) return order.status.toUpperCase() == 'PREPARING';
    return true;
  }

  Future<void> _updateOrderStatus(KitchenOrderModel order, String newStatus) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/preparation/update-status', data: {
        'order_id': order.id,
        'status': newStatus.toUpperCase(),
      });
      if (newStatus.toUpperCase() == 'READY' || newStatus.toUpperCase() == 'SERVED') {
        setState(() {
          _completedOrders.removeWhere((o) => o.id == order.id);
          _completedOrders.insert(0, order);
          if (_completedOrders.length > 50) _completedOrders.removeLast();
        });
      } else if (newStatus.toUpperCase() == 'PREPARING') {
        setState(() {
          _completedOrders.removeWhere((o) => o.id == order.id);
        });
      }
      ref.invalidate(prepOrdersProvider);
      if (mounted) {
        HapticFeedback.mediumImpact();
        final isReady = newStatus.toUpperCase() == 'READY' || newStatus.toUpperCase() == 'SERVED';
        final hasNargile = order.items.any((it) => _isNargile(it.name));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isReady ? Icons.check_circle_outline : (hasNargile ? Icons.cloud_outlined : Icons.local_bar),
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isReady
                        ? '${order.tableName} hazırlığı tamamlandı ve servise bildirildi.'
                        : '${order.tableName} ${hasNargile ? "közleniyor" : "hazırlanıyor"} aşamasına alındı.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: isReady ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PrepDashboard] Error updating prep: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Durum güncellenirken hata oluştu.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(prepOrdersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = !kIsWeb && Platform.isIOS;

    ref.listen<AsyncValue<WebSocketEvent>>(wsEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (event.isOrderEvent || event.isKitchenEvent || event.name.contains('prep') || event.name.contains('bar')) {
        ref.invalidate(prepOrdersProvider);
      }
      if (event.type.toUpperCase() != 'NOTIFICATION') return;
      final roles = event.data?['target_roles'];
      PersonelNotificationService().alertFromSocket(
        id: event.data?['notification_id']?.toString() ?? event.eventId ?? '',
        title: event.data?['title']?.toString() ?? '',
        body: event.data?['body']?.toString() ?? event.data?['message']?.toString() ?? '',
        roles: roles is List ? roles.map((item) => item.toString()).toList() : [event.data?['target_role']?.toString() ?? ''],
        screenRole: 'PREPARATION',
      );
    });

    final bgColor = isDark ? const Color(0xFF0A0F1D) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final auth = ref.watch(authProvider);
    final stationName = (auth.userName != null && auth.userName!.isNotEmpty)
        ? auth.userName!.toUpperCase()
        : 'HAZIRLIK';
    final stationTitle = '$stationName (Hazırlık)';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header: Figma 2026 & iOS Frosted Glass Preparation App Bar ─────────────
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    stationTitle,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'CANLI',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'İstasyon Görünümü • Canlı Hazırlık Akışı',
                              style: TextStyle(
                                color: textSecColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Actions: Notification Bell + Refresh + 3-Dots Quick Settings Menu
                      Row(
                        children: [
                          // Notification Bell
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              final orders = ordersAsync.asData?.value ?? <KitchenOrderModel>[];
                              _showPrepNotificationCenter(orders, cardBg, textColor, textSecColor, isDark);
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    isIOS ? CupertinoIcons.bell : Icons.notifications_outlined,
                                    color: textColor,
                                    size: 20,
                                  ),
                                ),
                                if ((ordersAsync.asData?.value.where((o) => !o.isReady).length ?? 0) > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEF4444),
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                      child: Center(
                                        child: Text(
                                          '${ordersAsync.asData!.value.where((o) => !o.isReady).length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Refresh Button
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref.invalidate(prepOrdersProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Text('Hazırlık siparişleri güncellendi.'),
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
                              HapticFeedback.selectionClick();
                              showStaffMenuModal(
                                context: context,
                                ref: ref,
                                currentScreen: 'prep',
                                onRefresh: () => ref.invalidate(prepOrdersProvider),
                                refreshLabel: 'Hazırlık Siparişlerini Yenile',
                                refreshSubtitle: 'Canlı bar ve istasyon siparişlerini hemen senkronize et',
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

            // ─── Segmented Tabs: [Aktif Hazırlıklar (X)] / [Tamamlananlar (Y)] ───
            ordersAsync.maybeWhen(
              data: (orders) {
                final activeOrders = orders.where((o) => !o.isReady).toList();
                final backendReadyOrders = orders.where((o) => o.isReady).toList();
                final allCompletedCount = backendReadyOrders.length +
                    _completedOrders.where((c) => !backendReadyOrders.any((b) => b.id == c.id)).length;
                final activeCount = activeOrders.length;
                final completedCount = allCompletedCount;
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      // Tab 0: Aktif Hazırlıklar
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTabIndex = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTabIndex == 0
                                  ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTabIndex == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Aktif Hazırlıklar ($activeCount)',
                                style: TextStyle(
                                  color: _selectedTabIndex == 0 ? textColor : textSecColor,
                                  fontWeight: _selectedTabIndex == 0 ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Tab 1: Tamamlananlar
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTabIndex = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTabIndex == 1
                                  ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTabIndex == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Tamamlananlar ($completedCount)',
                                style: TextStyle(
                                  color: _selectedTabIndex == 1 ? textColor : textSecColor,
                                  fontWeight: _selectedTabIndex == 1 ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

            // ─── Main Content ────────────────────────────────────────
            Expanded(
              child: _selectedTabIndex == 1
                  ? ordersAsync.maybeWhen(
                      data: (orders) {
                        final backendReadyOrders = orders.where((o) => o.isReady).toList();
                        final combinedCompleted = [
                          ..._completedOrders,
                          ...backendReadyOrders.where((b) => !_completedOrders.any((c) => c.id == b.id)),
                        ];
                        return _buildCompletedOrdersList(combinedCompleted, cardBg, textColor, textSecColor, isDark);
                      },
                      orElse: () => _buildCompletedOrdersList(_completedOrders, cardBg, textColor, textSecColor, isDark),
                    )
                  : ordersAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      error: (err, _) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text('Hazırlık siparişleri yüklenemedi', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => ref.refresh(prepOrdersProvider),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      ),
                      data: (orders) {
                        final activeOrders = orders.where((o) => !o.isReady).toList();
                        if (activeOrders.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.coffee_outlined, size: 48, color: Colors.purpleAccent),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Bekleyen Hazırlık Fişi Yok',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tüm içecek ve hazırlık siparişleri tamamlandı.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textSecColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Count stats
                        final totalCount = activeOrders.length;
                        final delayedCount = activeOrders.where((o) => o.diffMinutes >= 10).length;
                        final newCount = activeOrders.where((o) => o.diffMinutes < 10 && o.status.toUpperCase() != 'PREPARING').length;
                        final preparingCount = activeOrders.where((o) => o.status.toUpperCase() == 'PREPARING').length;

                        // Filter orders by operational urgency & status
                        final filteredOrders = activeOrders
                            .where((o) => _matchesUrgency(o, _selectedUrgencyFilter))
                            .toList();

                        return Column(
                          children: [
                            // ─── Urgency & Status Operational Filter Pills + Compact Density Toggle ───
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      child: Row(
                                        children: [
                                          _buildUrgencyChip(
                                            index: 0,
                                            label: 'Tümü',
                                            count: totalCount,
                                            color: const Color(0xFF0D9488),
                                            isDark: isDark,
                                            textColor: textColor,
                                            textSecColor: textSecColor,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildUrgencyChip(
                                            index: 3,
                                            label: '🔥 Hazırlanıyor',
                                            count: preparingCount,
                                            color: const Color(0xFFF59E0B),
                                            isDark: isDark,
                                            textColor: textColor,
                                            textSecColor: textSecColor,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildUrgencyChip(
                                            index: 2,
                                            label: '🆕 Yeni',
                                            count: newCount,
                                            color: const Color(0xFF06B6D4),
                                            isDark: isDark,
                                            textColor: textColor,
                                            textSecColor: textSecColor,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildUrgencyChip(
                                            index: 1,
                                            label: '🔴 Geciken',
                                            count: delayedCount,
                                            color: const Color(0xFFEF4444),
                                            isDark: isDark,
                                            textColor: textColor,
                                            textSecColor: textSecColor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Compact Mode Toggle
                                  InkWell(
                                    onTap: () => setState(() => _isCompactView = !_isCompactView),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _isCompactView
                                            ? const Color(0xFF0D9488).withValues(alpha: 0.2)
                                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _isCompactView ? const Color(0xFF0D9488) : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isCompactView ? Icons.view_headline_rounded : Icons.view_agenda_rounded,
                                            size: 16,
                                            color: _isCompactView ? const Color(0xFF0D9488) : textSecColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isCompactView ? 'Kompakt' : 'Geniş',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: _isCompactView ? const Color(0xFF0D9488) : textSecColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ─── Tickets List ───
                            Expanded(
                              child: filteredOrders.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.filter_list_off_rounded, size: 48, color: textSecColor.withValues(alpha: 0.5)),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Bu filtrede hazırlık fişi yok',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () => setState(() {
                                              _selectedUrgencyFilter = 0;
                                            }),
                                            child: const Text('Tüm Fişleri Göster'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: () async => ref.refresh(prepOrdersProvider.future),
                                      child: ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                        itemCount: filteredOrders.length,
                                        itemBuilder: (context, index) {
                                          final order = filteredOrders[index];
                                          return _isCompactView
                                              ? _buildCompactPrepTicket(order, cardBg, cardBorder, textColor, textSecColor, isDark)
                                              : _buildPrepTicket(order, cardBg, cardBorder, textColor, textSecColor, isDark);
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgencyChip({
    required int index,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    required Color textColor,
    required Color textSecColor,
  }) {
    final isSelected = _selectedUrgencyFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedUrgencyFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.15)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? (isDark ? Colors.white : color) : textSecColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : textColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// High-density compact prep card for mobile screens
  Widget _buildCompactPrepTicket(
    KitchenOrderModel order,
    Color cardBg,
    Color cardBorder,
    Color textColor,
    Color textSecColor,
    bool isDark,
  ) {
    final isDelayed = order.diffMinutes >= 10;
    final hasNargile = order.items.any((it) => _isNargile(it.name));

    final Color accentColor = isDelayed
        ? const Color(0xFFEF4444)
        : (hasNargile ? const Color(0xFF06B6D4) : const Color(0xFF0D9488));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: isDelayed ? 0.8 : 0.4),
          width: isDelayed ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDelayed ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showPrepDetailsSheet(order, cardBg, cardBorder, textColor, textSecColor, isDark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Table name, Station tag, Timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            order.tableName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasNargile)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                            ),
                            child: const Text('💨 Nargile', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.4)),
                            ),
                            child: const Text('⚡ Hazırlık', style: TextStyle(color: Color(0xFF0D9488), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    // Elapsed time
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDelayed
                            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDelayed ? const Color(0xFFEF4444) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDelayed ? Icons.warning_amber_rounded : Icons.access_time_rounded,
                            size: 12,
                            color: isDelayed ? const Color(0xFFEF4444) : textSecColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDelayed ? '${order.elapsedTime} ⚠️' : order.elapsedTime,
                            style: TextStyle(
                              color: isDelayed ? const Color(0xFFEF4444) : textSecColor,
                              fontSize: 11,
                              fontWeight: isDelayed ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Items summary + Quick action button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...order.items.take(3).map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '${item.quantity}x ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: accentColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Expanded(
                                    child: RichText(
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: TextStyle(color: textColor, fontSize: 13),
                                        children: [
                                          TextSpan(
                                            text: item.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          if (item.removedIngredients.isNotEmpty)
                                            TextSpan(
                                              text: ' (🚫 ${item.removedIngredients.join(', ')})',
                                              style: const TextStyle(
                                                color: Color(0xFFEF4444),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          if (item.extras.isNotEmpty)
                                            TextSpan(
                                              text: ' (+ ${item.extras.join(', ')})',
                                              style: const TextStyle(
                                                color: Color(0xFF00C896),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (order.items.length > 3)
                            Text(
                              '+${order.items.length - 3} kalem ürün daha...',
                              style: TextStyle(color: textSecColor, fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Quick Action Buttons
                    if (order.status.toUpperCase() == 'PREPARING')
                      SizedBox(
                        height: 38,
                        child: ElevatedButton.icon(
                          onPressed: () => _updateOrderStatus(order, 'SERVED'),
                          icon: const Icon(Icons.check, size: 16, color: Colors.white),
                          label: const Text('Masaya Servis Et', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      )
                    else
                       Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              onPressed: () => _updateOrderStatus(order, 'PREPARING'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                hasNargile ? '🔥 Közle' : '🔥 Başla',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 36,
                            child: OutlinedButton(
                              onPressed: () => _updateOrderStatus(order, 'SERVED'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF10B981),
                                side: const BorderSide(color: Color(0xFF10B981)),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Masaya Servis Et', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Full preparation ticket matching Figma standards
  Widget _buildPrepTicket(
    KitchenOrderModel order,
    Color cardBg,
    Color cardBorder,
    Color textColor,
    Color textSecColor,
    bool isDark,
  ) {
    final isDelayed = order.diffMinutes >= 10;
    final hasNargile = order.items.any((it) => _isNargile(it.name));
    final accentColor = isDelayed
        ? const Color(0xFFEF4444)
        : (hasNargile ? const Color(0xFF06B6D4) : const Color(0xFF0D9488));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withValues(alpha: isDelayed ? 0.8 : 0.35),
          width: isDelayed ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDelayed ? 0.2 : (isDark ? 0.25 : 0.03)),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${order.id}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    order.tableName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: textColor),
                  ),
                  const SizedBox(width: 8),
                  if (hasNargile)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                      ),
                      child: const Text('💨 Nargile', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDelayed ? Icons.warning_amber_rounded : Icons.access_time,
                      size: 13,
                      color: accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDelayed ? '${order.elapsedTime} ⚠️' : order.elapsedTime,
                      style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Items
          ...order.items.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.quantity}x',
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                            ),
                            if (item.variant != null && item.variant!.isNotEmpty)
                              Text('Seçenek: ${item.variant}', style: TextStyle(fontSize: 12, color: textSecColor)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Removed Ingredients
                  if (item.removedIngredients.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.removedIngredients.map((rem) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            '🚫 $rem Yok',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Extras
                  if (item.extras.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.extras.map((ex) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C896).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+ $ex',
                            style: const TextStyle(color: Color(0xFF00C896), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Note
                  if (item.note != null && item.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Text(
                        '📝 ${item.note}',
                        style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 14),

          // Action Buttons
          if (order.status.toUpperCase() == 'PREPARING') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasNargile ? '🔥 Közleniyor / Hazırlanıyor...' : '🍹 Hazırlanıyor...',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.check_circle, size: 20),
                label: const Text(
                  '✅ Hazır (Servise Bildir)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () => _updateOrderStatus(order, 'READY'),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(hasNargile ? Icons.local_fire_department : Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      hasNargile ? '🔥 Közleniyor' : '🔥 Hazırlanıyor',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () => _updateOrderStatus(order, 'PREPARING'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'Direkt Hazır',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () => _updateOrderStatus(order, 'READY'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showPrepDetailsSheet(
    KitchenOrderModel order,
    Color cardBg,
    Color cardBorder,
    Color textColor,
    Color textSecColor,
    bool isDark,
  ) {
    final isPreparing = order.status.toUpperCase() == 'PREPARING';
    final hasNargile = order.items.any((it) => _isNargile(it.name));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C896).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            order.tableName,
                            style: const TextStyle(
                              color: Color(0xFF00C896),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasNargile)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                            ),
                            child: const Text('💨 Nargile', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                            ),
                            child: const Text('🍹 Bar', style: TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: order.diffMinutes >= 10
                                ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            order.elapsedTime,
                            style: TextStyle(
                              color: order.diffMinutes >= 10 ? const Color(0xFFEF4444) : textSecColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 18),

              // Items List
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: order.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final item = order.items[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${item.quantity}x',
                                  style: const TextStyle(
                                    color: Color(0xFF00C896),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.removedIngredients.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              children: item.removedIngredients.map((r) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('🚫 Çıkar: $r', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                              )).toList(),
                            ),
                          ],
                          if (item.extras.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              children: item.extras.map((e) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('+ $e', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                              )).toList(),
                            ),
                          ],
                          if (item.note != null && item.note!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Not: ${item.note}', style: TextStyle(color: textSecColor, fontSize: 11, fontStyle: FontStyle.italic)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      if (!isPreparing) ...[
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateOrderStatus(order, 'PREPARING');
                              },
                              icon: Icon(hasNargile ? Icons.local_fire_department : Icons.play_arrow_rounded, size: 20, color: Colors.white),
                              label: Text(hasNargile ? 'Közlemeye Başla' : 'Hazırlığa Başla', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateOrderStatus(order, 'READY');
                              },
                              icon: const Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                              label: const Text('Direkt Hazır', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateOrderStatus(order, 'READY');
                              },
                              icon: const Icon(Icons.check_circle_rounded, size: 22, color: Colors.white),
                              label: const Text(
                                'Hazırlığı Tamamla & Servis',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.3),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                elevation: 2,
                                shadowColor: const Color(0xFF00C896).withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds list of completed orders for the secondary tab matching Kitchen KDS
  Widget _buildCompletedOrdersList(
    List<KitchenOrderModel> completedOrders,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    if (completedOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 54, color: textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              'Henüz Tamamlanan Hazırlık Yok',
              style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Hazırlandı olarak işaretlenen siparişler burada listelenir.',
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: completedOrders.length,
      itemBuilder: (context, index) {
        final order = completedOrders[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.tableName,
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.items.length} Kalem Ürün',
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Hazırlandı • Servise Verildi',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows rich preparation notification and status center
  void _showPrepNotificationCenter(
    List<KitchenOrderModel> orders,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final activeOrders = orders.where((o) => !o.isReady).toList();
            final backendReadyOrders = orders.where((o) => o.isReady).toList();
            final allCompletedCount = backendReadyOrders.length +
                _completedOrders.where((c) => !backendReadyOrders.any((b) => b.id == c.id)).length;
            final delayedOrders = activeOrders.where((o) => o.diffMinutes >= 10).toList();
            final preparingOrders = activeOrders.where((o) => o.status.toUpperCase() == 'PREPARING').toList();
            final pendingOrders = activeOrders.where((o) => o.status.toUpperCase() != 'PREPARING').toList();

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF6366F1), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hazırlık Bildirim & Durum',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'WebSocket Canlı Bağlantı Aktif',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sound alert setting card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _soundAlertsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                  color: _soundAlertsEnabled ? const Color(0xFF10B981) : textSecondary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sesli Sipariş Alarmları',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Yeni sipariş düştüğünde ses ve titreşim',
                                        style: TextStyle(color: textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _soundAlertsEnabled,
                                  activeTrackColor: const Color(0xFF10B981),
                                  onChanged: (val) {
                                    setState(() => _soundAlertsEnabled = val);
                                    PersonelNotificationService().setSoundAlertsEnabled(val);
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Test Alert Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                PersonelNotificationService().alertFromSocket(
                                  id: 'test_${DateTime.now().millisecondsSinceEpoch}',
                                  title: '🔔 Test Hazırlık Uyarısı',
                                  body: 'Hazırlık bildirim ve ses sistemi kusursuz şekilde aktif.',
                                  roles: ['PREPARATION'],
                                  screenRole: 'PREPARATION',
                                  urgent: true,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Test bildirimi ve ses uyarısı tetiklendi.'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                              label: const Text('Zil ve Ses Uyarısını Test Et', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Live Summary Counters
                          Text(
                            'CANLI SİPARİŞ DURUMU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildMetricTile('Yeni', '${pendingOrders.length}', const Color(0xFF38BDF8), isDark),
                              const SizedBox(width: 8),
                              _buildMetricTile('Hazırlık', '${preparingOrders.length}', const Color(0xFFF59E0B), isDark),
                              const SizedBox(width: 8),
                              _buildMetricTile('Geciken', '${delayedOrders.length}', const Color(0xFFEF4444), isDark),
                              const SizedBox(width: 8),
                              _buildMetricTile('Tamam', '$allCompletedCount', const Color(0xFF10B981), isDark),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Delayed Warnings
                          if (delayedOrders.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'ACİL VE GECİKEN MASALAR (${delayedOrders.length})',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...delayedOrders.map((dOrder) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dOrder.tableName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      Text(
                                        '${dOrder.items.length} Kalem • ${dOrder.waiterName.isNotEmpty ? dOrder.waiterName : 'Garson atanmadı'}',
                                        style: TextStyle(color: textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      dOrder.elapsedTime,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                            const SizedBox(height: 14),
                          ],

                          // Manual Refresh Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ref.invalidate(prepOrdersProvider);
                                Navigator.of(ctx).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Fişleri Manuel Yenile', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
