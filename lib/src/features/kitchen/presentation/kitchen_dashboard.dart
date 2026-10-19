import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/services/websocket/websocket_service.dart';
import '../../../core/widgets/staff_menu_modal.dart';
import '../application/kitchen_provider.dart';
import 'widgets/sizzling_pan_animation.dart';

class KitchenDashboard extends ConsumerStatefulWidget {
  const KitchenDashboard({super.key});

  @override
  ConsumerState<KitchenDashboard> createState() => _KitchenDashboardState();
}

class _KitchenDashboardState extends ConsumerState<KitchenDashboard> {
  // Tab index: 0 = Aktif Siparişler, 1 = Tamamlananlar
  int _selectedTabIndex = 0;
  // Urgency filter: 0 = Tümü, 1 = Geciken/Acil, 2 = Yeni Gelen, 3 = Hazırlanıyor
  int _selectedUrgencyFilter = 0;
  // Compact high-density mobile view
  bool _isCompactView = false;
  // Sound alerts toggle
  bool _soundAlertsEnabled = PersonelNotificationService().soundAlertsEnabled;
  Timer? _tickerTimer;

  // Track completed orders locally for the "Tamamlananlar" tab
  final List<KitchenOrderModel> _completedOrders = [];

  @override
  void initState() {
    super.initState();
    _soundAlertsEnabled = PersonelNotificationService().soundAlertsEnabled;

    // Connect WebSocket and initialize push token & watchdog
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

    // Refresh elapsed time every 30 seconds
    _tickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    PersonelNotificationService().stopWatchdog();
    super.dispose();
  }

  Future<void> _updateOrderStatus(KitchenOrderModel order, String newStatus) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/kitchen/update-status', data: {
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

      ref.invalidate(kitchenOrdersProvider);
      triggerKitchenHaptic();

      if (mounted) {
        final isServed = newStatus.toUpperCase() == 'READY' || newStatus.toUpperCase() == 'SERVED';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isServed ? Icons.check_circle_outline : Icons.soup_kitchen,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isServed
                        ? '${order.tableName} hazırlandı ve masaya servis edildi.'
                        : '${order.tableName} hazırlanıyor durumuna alındı.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: isServed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
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
    final ordersAsync = ref.watch(kitchenOrdersProvider);

    // Listen to real-time events via WebSocket and trigger loud heads-up alerts
    ref.listen<AsyncValue<WebSocketEvent>>(wsEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (event.isOrderEvent || event.isKitchenEvent) {
        ref.invalidate(kitchenOrdersProvider);
        triggerKitchenHaptic();

        // Also trigger sound/heads-up notification on direct order creation
        if (event.name == 'ORDER_CREATED' || event.name == 'order.created' || event.name == 'ORDER_UPDATED') {
          final tName = event.data?['table_name']?.toString() ?? 'Masa';
          final orderId = event.data?['order_id']?.toString() ?? '';
          PersonelNotificationService().showStaffAlert(
            title: '🔔 Mutfak: Yeni Sipariş',
            body: '$tName için sipariş mutfağa iletildi.',
            payload: orderId,
            isUrgent: true,
          );
        }
      }
      if (event.type.toUpperCase() != 'NOTIFICATION') return;
      final roles = event.data?['target_roles'];
      PersonelNotificationService().alertFromSocket(
        id: event.data?['notification_id']?.toString() ?? event.eventId ?? '',
        title: event.data?['title']?.toString() ?? '',
        body: event.data?['body']?.toString() ?? event.data?['message']?.toString() ?? '',
        roles: roles is List ? roles.map((item) => item.toString()).toList() : [event.data?['target_role']?.toString() ?? ''],
        screenRole: 'KITCHEN',
        urgent: true,
      );
      triggerKitchenHaptic();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header: Figma 2026 & iOS Frosted Glass KDS App Bar ─────────────────────
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
                  // Title and Subtitle (Wrapped in Expanded to prevent overflow on mobile)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Mutfak (KDS)',
                                style: TextStyle(
                                  color: textPrimary,
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
                          'Şef Görünümü • Canlı Sipariş Akışı',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Actions: Notification Bell + Quick Settings Menu
                  Row(
                    children: [
                      // Notification Bell
                      GestureDetector(
                        onTap: () {
                          triggerKitchenHaptic();
                          final orders = ordersAsync.asData?.value ?? <KitchenOrderModel>[];
                          _showKitchenNotificationCenter(orders, cardBg, textPrimary, textSecondary, isDark);
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.notifications_outlined,
                                color: textPrimary,
                                size: 22,
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
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  child: Center(
                                    child: Text(
                                      '${ordersAsync.asData!.value.where((o) => !o.isReady).length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Modern Glassmorphic Kitchen Settings Drawer Button (Unified Menu)
                      GestureDetector(
                        onTap: () {
                          triggerKitchenHaptic();
                          showStaffMenuModal(
                            context: context,
                            ref: ref,
                            currentScreen: 'kitchen',
                            onRefresh: () => ref.invalidate(kitchenOrdersProvider),
                            refreshLabel: 'Mutfak Siparişlerini Yenile',
                            refreshSubtitle: 'Canlı sipariş ve pişme sürelerini anında senkronize et',
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
                          child: Icon(Icons.menu_rounded, color: textPrimary, size: 22),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
                ),
              ),
            ),

            // ─── Tabs: [Aktif Siparişler (X)] / [Tamamlananlar (Y)] ─────
            ordersAsync.maybeWhen(
              data: (orders) {
                final activeOrders = orders.where((o) => !o.isReady).toList();
                final backendReadyOrders = orders.where((o) => o.isReady).toList();
                final allCompletedCount = backendReadyOrders.length +
                    _completedOrders.where((c) => !backendReadyOrders.any((b) => b.id == c.id)).length;

                // Sync metrics to native Android KDS widget
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final prepCount = activeOrders.where((o) => o.isPreparing || o.isPending).length;
                  final urgentCount = activeOrders.where((o) => o.isDelayed).length;
                  PersonelWidgetSyncService.updateKdsWidget(
                    preparing: prepCount,
                    urgent: urgentCount,
                    ready: allCompletedCount,
                  );
                });

                final activeCount = activeOrders.length;
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      // Tab 1: Aktif Siparişler
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
                                'Aktif Siparişler ($activeCount)',
                                style: TextStyle(
                                  color: _selectedTabIndex == 0 ? textPrimary : textSecondary,
                                  fontWeight: _selectedTabIndex == 0 ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Tab 2: Tamamlananlar
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
                                'Tamamlananlar ($allCompletedCount)',
                                style: TextStyle(
                                  color: _selectedTabIndex == 1 ? textPrimary : textSecondary,
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

            // ─── Urgency Filters & Density Toggle (Active Tab Only) ───
            if (_selectedTabIndex == 0)
              ordersAsync.maybeWhen(
                data: (allOrders) {
                  final activeOrders = allOrders.where((o) => !o.isReady).toList();
                  final totalCount = activeOrders.length;
                  final delayedCount = activeOrders.where((o) => o.isDelayed).length;
                  final pendingCount = activeOrders.where((o) => o.isPending && !o.isDelayed).length;
                  final preparingCount = activeOrders.where((o) => o.isPreparing && !o.isDelayed).length;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
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
                                  color: const Color(0xFF6366F1),
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                                const SizedBox(width: 8),
                                _buildUrgencyChip(
                                  index: 1,
                                  label: '🔴 Geciken',
                                  count: delayedCount,
                                  color: const Color(0xFFEF4444),
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                                const SizedBox(width: 8),
                                _buildUrgencyChip(
                                  index: 2,
                                  label: '🆕 Yeni',
                                  count: pendingCount,
                                  color: const Color(0xFF38BDF8),
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                                const SizedBox(width: 8),
                                _buildUrgencyChip(
                                  index: 3,
                                  label: '🔥 Pişiyor',
                                  count: preparingCount,
                                  color: const Color(0xFFF59E0B),
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Compact density toggle
                        InkWell(
                          onTap: () => setState(() => _isCompactView = !_isCompactView),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: _isCompactView
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isCompactView ? const Color(0xFF6366F1) : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isCompactView ? Icons.view_headline_rounded : Icons.view_agenda_rounded,
                                  size: 16,
                                  color: _isCompactView ? const Color(0xFF818CF8) : textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isCompactView ? 'Kompakt' : 'Geniş',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isCompactView ? const Color(0xFF818CF8) : textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),

            // ─── Order Content / List ──────────────────────────────
            Expanded(
              child: _selectedTabIndex == 1
                  ? _buildCompletedOrdersList(
                      ordersAsync.asData?.value.where((o) => o.isReady).toList() ?? [],
                      cardBg,
                      textPrimary,
                      textSecondary,
                      isDark,
                    )
                  : ordersAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                      ),
                      error: (err, stack) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text('Siparişler yüklenemedi', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => ref.refresh(kitchenOrdersProvider),
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
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check_circle_outline, size: 52, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Bekleyen Mutfak Siparişi Yok',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tüm siparişler hazırlandı ve servise gönderildi.',
                                  style: TextStyle(fontSize: 14, color: textSecondary),
                                ),
                              ],
                            ),
                          );
                        }

                        // Filter by selected urgency
                        final filteredOrders = activeOrders.where((o) {
                          if (_selectedUrgencyFilter == 1) return o.isDelayed;
                          if (_selectedUrgencyFilter == 2) return o.isPending && !o.isDelayed;
                          if (_selectedUrgencyFilter == 3) return o.isPreparing && !o.isDelayed;
                          return true;
                        }).toList();

                        if (filteredOrders.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.filter_list_off_rounded, size: 48, color: textSecondary.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  'Bu filtrede sipariş bulunamadı',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => setState(() => _selectedUrgencyFilter = 0),
                                  child: const Text('Tüm Siparişleri Göster'),
                                ),
                              ],
                            ),
                          );
                        }

                        // Responsive grid: 2 columns on tablets/landscape, 1 column on phone
                        final isTablet = MediaQuery.of(context).size.width >= 700;

                        if (isTablet) {
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: _isCompactView ? 1.6 : 0.82,
                            ),
                            itemCount: filteredOrders.length,
                            itemBuilder: (context, index) {
                              return _isCompactView
                                  ? _buildCompactKitchenOrderCard(filteredOrders[index], cardBg, textPrimary, textSecondary, isDark)
                                  : _buildKitchenOrderCard(filteredOrders[index], cardBg, textPrimary, textSecondary, isDark);
                            },
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            return _isCompactView
                                ? _buildCompactKitchenOrderCard(filteredOrders[index], cardBg, textPrimary, textSecondary, isDark)
                                : _buildKitchenOrderCard(filteredOrders[index], cardBg, textPrimary, textSecondary, isDark);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single 2026 KDS order ticket card matching Figma 04_Mutfak_KDS.png
  Widget _buildKitchenOrderCard(
    KitchenOrderModel order,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final isDelayed = order.isDelayed;
    final isPreparing = order.isPreparing;

    // Border and Accent Colors
    Color borderColor;
    Color badgeColor;
    if (isDelayed) {
      borderColor = const Color(0xFFEF4444); // Neon Red alert
      badgeColor = const Color(0xFFEF4444);
    } else if (isPreparing) {
      borderColor = const Color(0xFFF59E0B); // Amber glow
      badgeColor = const Color(0xFFF59E0B);
    } else {
      borderColor = const Color(0xFF38BDF8); // Electric blue
      badgeColor = const Color(0xFF38BDF8);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor.withValues(alpha: isDelayed ? 0.9 : (isPreparing ? 0.7 : 0.4)),
          width: isDelayed ? 2.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: isDelayed ? 0.25 : (isPreparing ? 0.15 : 0.08)),
            blurRadius: isDelayed ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header: Table Badge + Status Alert + Timer + Sizzling Pan ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Table Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        order.tableName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Delayed Alert Badge
                    if (isDelayed) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Gecikmeli!',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (isPreparing) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          'Hazırlanıyor',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Right Side: Elapsed Time + Sizzling Pan Animation
                Row(
                  children: [
                    // Sizzling Pan Cooking Animation (when order is preparing)
                    if (isPreparing) ...[
                      const SizzlingPanAnimation(size: 40),
                      const SizedBox(width: 8),
                    ],

                    // Elapsed Timer Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, size: 14, color: borderColor),
                          const SizedBox(width: 5),
                          Text(
                            order.elapsedTime,
                            style: TextStyle(
                              color: borderColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Waiter & Zone Subtitle
            if (order.waiterName.isNotEmpty || order.zoneName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${order.zoneName.isNotEmpty ? '${order.zoneName} • ' : ''}Garson: ${order.waiterName.isNotEmpty ? order.waiterName : 'Personel'}',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 12),
            Divider(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 12),

            // ─── Items List with Variants, Excluded Ingredients, Extras, Notes ───
            ...order.items.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Item Name and Variant
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.variant != null && item.variant!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Varyant: ${item.variant}',
                                      style: const TextStyle(
                                        color: Color(0xFF818CF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Quantity Badge (e.g. x1, x2)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'x${item.quantity}',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Excluded Ingredients (Very prominent red badges: 🚫 Soğansız)
                    if (item.removedIngredients.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.removedIngredients.map((rem) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🚫', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  rem,
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Extras (+ Peynir)
                    if (item.extras.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.extras.map((ex) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+ $ex',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Chef / Customer Item Note (📌 Not: ...)
                    if (item.note != null && item.note!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Text('📌', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Not: ${item.note}',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

            // General Order Note
            if (order.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Masa Notu: ${order.notes}',
                  style: TextStyle(color: textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ─── Action Buttons: Progression (PENDING -> PREPARING -> READY) ───
            Row(
              children: [
                if (!isPreparing) ...[
                  // Primary Action: [🔥 Hazırlanıyor (Başla)]
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateOrderStatus(order, 'PREPARING'),
                        icon: const Icon(Icons.soup_kitchen, color: Colors.white, size: 20),
                        label: const Text(
                          'Hazırlanıyor (Başla)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B), // Amber
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Secondary Quick Action: [✅ Direkt Hazır]
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _updateOrderStatus(order, 'SERVED'),
                        icon: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 18),
                        label: const Text(
                          'Direkt Servis Et',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Order is currently PREPARING ("Pişiyor"):
                  // Status badge on the left, and PROMINENT [✅ Masaya Servis Et] button beside it
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.soup_kitchen, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Pişiyor...',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The Prominent [✅ Masaya Servis Et] Button:
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateOrderStatus(order, 'SERVED'),
                        icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'Masaya Servis Et',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981), // Vibrant Emerald Green
                          elevation: 2,
                          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds list of completed orders for the secondary tab
  Widget _buildCompletedOrdersList(
    List<KitchenOrderModel> backendReadyOrders,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    // Combine backend completed orders + locally completed orders without duplicates
    final Set<String> seenIds = {};
    final List<KitchenOrderModel> combinedCompleted = [];

    for (final o in _completedOrders) {
      if (seenIds.add(o.id)) combinedCompleted.add(o);
    }
    for (final o in backendReadyOrders) {
      if (seenIds.add(o.id)) combinedCompleted.add(o);
    }

    if (combinedCompleted.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 54, color: textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              'Henüz Tamamlanan Sipariş Yok',
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
      itemCount: combinedCompleted.length,
      itemBuilder: (context, index) {
        final order = combinedCompleted[index];
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

  Widget _buildUrgencyChip({
    required int index,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isSelected = _selectedUrgencyFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedUrgencyFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                color: isSelected ? (isDark ? Colors.white : color) : textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// High-density compact kitchen order card for mobile phones
  Widget _buildCompactKitchenOrderCard(
    KitchenOrderModel order,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final isDelayed = order.isDelayed;
    final isPreparing = order.isPreparing;
    final isReady = order.isReady;

    Color borderColor;
    Color badgeColor;
    if (isDelayed) {
      borderColor = const Color(0xFFEF4444);
      badgeColor = const Color(0xFFEF4444);
    } else if (isPreparing) {
      borderColor = const Color(0xFFF59E0B);
      badgeColor = const Color(0xFFF59E0B);
    } else if (isReady) {
      borderColor = const Color(0xFF10B981);
      badgeColor = const Color(0xFF10B981);
    } else {
      borderColor = const Color(0xFF38BDF8);
      badgeColor = const Color(0xFF38BDF8);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor.withValues(alpha: isDelayed ? 0.9 : 0.4),
          width: isDelayed ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: isDelayed ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showOrderDetailsBottomSheet(order, cardBg, textPrimary, textSecondary, isDark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Table name, timer, waiter & status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor,
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
                          if (order.waiterName.isNotEmpty)
                            Flexible(
                              child: Text(
                                order.waiterName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        // Elapsed time pill
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
                                color: isDelayed ? const Color(0xFFEF4444) : textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDelayed ? '${order.elapsedTime} ⚠️' : order.elapsedTime,
                                style: TextStyle(
                                  color: isDelayed ? const Color(0xFFEF4444) : textSecondary,
                                  fontSize: 11,
                                  fontWeight: isDelayed ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Item list summary
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
                                      color: badgeColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Expanded(
                                    child: RichText(
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: TextStyle(color: textPrimary, fontSize: 13),
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
                                                color: Color(0xFF10B981),
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
                              style: TextStyle(color: textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          if (order.notes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '📌 ${order.notes}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Quick action button
                    SizedBox(
                      height: 38,
                      child: isReady
                          ? ElevatedButton(
                              onPressed: () => _updateOrderStatus(order, 'SERVED'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Servis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            )
                          : isPreparing
                              ? ElevatedButton.icon(
                                  onPressed: () => _updateOrderStatus(order, 'READY'),
                                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                                  label: const Text('Hazır', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _updateOrderStatus(order, 'PREPARING'),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFFF59E0B)),
                                  label: const Text('Başla', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFF59E0B)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    );
  }

  /// Shows full bottom sheet details when tapping on a compact order card
  void _showOrderDetailsBottomSheet(
    KitchenOrderModel order,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final isPreparing = order.isPreparing;
    final isDelayed = order.isDelayed;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
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

              // Header: Table badge, timer, close
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              order.tableName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (order.waiterName.isNotEmpty)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline, size: 14, color: textSecondary),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      order.waiterName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDelayed
                                ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                : (isPreparing
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDelayed
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                  : (isPreparing ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : Colors.transparent),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDelayed ? Icons.warning_amber_rounded : Icons.access_time_rounded,
                                size: 14,
                                color: isDelayed
                                    ? const Color(0xFFEF4444)
                                    : (isPreparing ? const Color(0xFFF59E0B) : textSecondary),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                order.elapsedTime,
                                style: TextStyle(
                                  color: isDelayed
                                      ? const Color(0xFFEF4444)
                                      : (isPreparing ? const Color(0xFFF59E0B) : textSecondary),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
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

              const SizedBox(height: 10),

              // Items List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: order.items.length + (order.notes.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (order.notes.isNotEmpty && i == order.items.length) {
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.note_alt_rounded, color: Color(0xFFF59E0B), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Masa Notu: ${order.notes}',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final item = order.items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
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
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      color: Color(0xFF818CF8),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: textPrimary,
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
                            Text('Not: ${item.note}', style: TextStyle(color: textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
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
                              icon: const Icon(Icons.soup_kitchen, size: 20, color: Colors.white),
                              label: const Text('Pişirmeye Başla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
                                backgroundColor: const Color(0xFF10B981),
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
                                'Siparişi Tamamla & Hazır',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.3),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                elevation: 2,
                                shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
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

  /// Shows rich kitchen notification and status center
  void _showKitchenNotificationCenter(
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
            final delayedOrders = activeOrders.where((o) => o.isDelayed).toList();
            final preparingOrders = activeOrders.where((o) => o.isPreparing).toList();
            final pendingOrders = activeOrders.where((o) => o.isPending).toList();

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
                                  'Mutfak Bildirim & Durum',
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
                                triggerKitchenHaptic();
                                PersonelNotificationService().alertFromSocket(
                                  id: 'test_${DateTime.now().millisecondsSinceEpoch}',
                                  title: '🔔 Test Mutfak Uyarısı',
                                  body: 'Mutfak bildirim ve ses sistemi kusursuz şekilde aktif.',
                                  roles: ['KITCHEN'],
                                  screenRole: 'KITCHEN',
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
                              _buildMetricTile('Pişiyor', '${preparingOrders.length}', const Color(0xFFF59E0B), isDark),
                              const SizedBox(width: 8),
                              _buildMetricTile('Geciken', '${delayedOrders.length}', const Color(0xFFEF4444), isDark),
                              const SizedBox(width: 8),
                              _buildMetricTile('Hazır', '$allCompletedCount', const Color(0xFF10B981), isDark),
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
                                ref.invalidate(kitchenOrdersProvider);
                                Navigator.of(ctx).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Siparişleri Manuel Yenile', style: TextStyle(fontWeight: FontWeight.bold)),
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
              style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF334155), fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

}
