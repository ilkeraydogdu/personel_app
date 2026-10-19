import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/widget_sync_service.dart';
import '../../../core/services/websocket/websocket_service.dart';
import '../../../core/utils/safe_parsers.dart';
import '../../../core/widgets/staff_menu_modal.dart';
import '../application/waiter_provider.dart';

class WaiterDashboard extends ConsumerStatefulWidget {
  const WaiterDashboard({super.key});

  @override
  ConsumerState<WaiterDashboard> createState() => _WaiterDashboardState();
}

class _WaiterDashboardState extends ConsumerState<WaiterDashboard> {
  // Filter mode: 0 = Tümü, 1 = Sadece Dolular, 2 = Sadece Boşlar
  int _filterIndex = 0;
  String _selectedZoneId = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  int _activeAlertCount = 0;
  String? _lastAlertMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  @override
  Widget build(BuildContext context) {
    final zonesAsync = ref.watch(waiterZonesProvider);

    // Listen to real-time table events via WebSocket and trigger loud heads-up alerts
    ref.listen<AsyncValue<WebSocketEvent>>(wsEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (event.type.toUpperCase() == 'NOTIFICATION') {
        final roles = event.data?['target_roles'];
        final title = event.data?['title']?.toString() ?? '';
        PersonelNotificationService().alertFromSocket(
          id: event.data?['notification_id']?.toString() ?? event.eventId ?? '',
          title: title,
          body: event.data?['body']?.toString() ?? event.data?['message']?.toString() ?? '',
          roles: roles is List ? roles.map((item) => item.toString()).toList() : [event.data?['target_role']?.toString() ?? ''],
          screenRole: 'WAITER',
          urgent: true,
        ).then((_) {
          if (!mounted || title.isEmpty) return;
          setState(() {
            _activeAlertCount++;
            _lastAlertMessage = title;
          });
        });
      }
      if (event.name == 'ORDER_READY' || event.name == 'order.ready') {
        final tName = event.data?['table_name']?.toString() ?? 'Masa';
        PersonelNotificationService().showStaffAlert(
          title: '🍽️ Sipariş Hazır!',
          body: '$tName siparişi servise hazır.',
          isUrgent: true,
        );
      }
      if (event.isTableEvent || event.isOrderEvent || event.isKitchenEvent || event.type.toUpperCase() == 'NOTIFICATION') {
        _triggerHaptic();
        ref.invalidate(waiterZonesProvider);
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
            // ─── Header: Figma 2026 & iOS Frosted Glass Garson Ekranı Top Bar ─────────────
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
                      // Staff Profile & Role (Flexible to prevent any overflow)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final auth = ref.watch(authProvider);
                            final staffName = (auth.userName != null && auth.userName!.isNotEmpty) ? auth.userName! : 'Personel';
                            final rawRole = auth.userRole ?? 'Garson';
                            final staffRole = rawRole.toUpperCase() == 'WAITER' || rawRole.toUpperCase() == 'STAFF'
                                ? 'Garson'
                                : rawRole;

                            return Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      staffName.isNotEmpty ? staffName[0].toUpperCase() : 'P',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        staffName,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 5,
                                                  height: 5,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF10B981),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  staffRole.toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Color(0xFF10B981),
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Canlı Vardiya',
                                              style: TextStyle(color: textSecColor, fontSize: 11, fontWeight: FontWeight.w500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Actions: Refresh + 3-Line Operational Menu Button
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              _triggerHaptic();
                              ref.invalidate(waiterZonesProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Text('Masa ve adisyonlar güncellendi.'),
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

                          // 3-Line Operational Menu Button
                          GestureDetector(
                            onTap: () {
                              _triggerHaptic();
                              showStaffMenuModal(
                                context: context,
                                ref: ref,
                                currentScreen: 'waiter',
                                onRefresh: () => ref.invalidate(waiterZonesProvider),
                                refreshLabel: 'Masaları & Siparişleri Yenile',
                                refreshSubtitle: 'Canlı masa durumlarını sunucuyla senkronize et',
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
              child: zonesAsync.when(
                data: (zones) {
                  final allTables = <TableModel>[];
                  for (final z in zones) {
                    allTables.addAll(z.tables);
                  }

                  final allOccupiedCount = allTables.where((t) => t.status == 'occupied').length;

                  // Sync to native Android HomeWidget
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    PersonelWidgetSyncService.updateWaiterWidget(
                      pendingCalls: _activeAlertCount,
                      activeTables: allOccupiedCount,
                      lastEvent: _lastAlertMessage,
                    );
                  });

                  // Filter by zone
                  List<TableModel> zoneFilteredTables;
                  if (_selectedZoneId == 'all') {
                    zoneFilteredTables = allTables;
                  } else {
                    final targetZone = zones.firstWhere(
                      (z) => z.id == _selectedZoneId,
                      orElse: () => ZoneModel(id: '', name: '', tables: []),
                    );
                    zoneFilteredTables = targetZone.tables;
                  }

                  final occupiedCount = zoneFilteredTables.where((t) => t.status == 'occupied').length;
                  final vacantCount = zoneFilteredTables.length - occupiedCount;

                  // Filter by search query
                  var displayedTables = zoneFilteredTables.where((t) {
                    if (_searchQuery.isEmpty) return true;
                    return t.name.toLowerCase().contains(_searchQuery.toLowerCase());
                  }).toList();

                  // Apply status filter: 0 = Tümü (Dolular üstte), 1 = Sadece Dolular, 2 = Sadece Boşlar
                  if (_filterIndex == 1) {
                    displayedTables = displayedTables.where((t) => t.status == 'occupied').toList();
                  } else if (_filterIndex == 2) {
                    displayedTables = displayedTables.where((t) => t.status != 'occupied').toList();
                  } else {
                    displayedTables.sort((a, b) {
                      final aOcc = a.status == 'occupied' ? 1 : 0;
                      final bOcc = b.status == 'occupied' ? 1 : 0;
                      return bOcc.compareTo(aOcc);
                    });
                  }

                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(waiterZonesProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      children: [
                        // ─── Minimal Segmented Filtre Bar (Tümü / Dolu / Boş) ───
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            children: [
                              // Tümü
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    _triggerHaptic();
                                    setState(() => _filterIndex = 0);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _filterIndex == 0 ? const Color(0xFF6366F1) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Tümü (${zoneFilteredTables.length})',
                                        style: TextStyle(
                                          color: _filterIndex == 0 ? Colors.white : textColor,
                                          fontWeight: _filterIndex == 0 ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Sadece Dolular
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    _triggerHaptic();
                                    setState(() => _filterIndex = 1);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _filterIndex == 1 ? const Color(0xFFF59E0B) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: _filterIndex == 1 ? Colors.white : const Color(0xFFF59E0B),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Dolu ($occupiedCount)',
                                          style: TextStyle(
                                            color: _filterIndex == 1 ? Colors.white : textColor,
                                            fontWeight: _filterIndex == 1 ? FontWeight.w800 : FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Sadece Boşlar
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    _triggerHaptic();
                                    setState(() => _filterIndex = 2);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _filterIndex == 2 ? const Color(0xFF10B981) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: _filterIndex == 2 ? Colors.white : const Color(0xFF10B981),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Boş ($vacantCount)',
                                          style: TextStyle(
                                            color: _filterIndex == 2 ? Colors.white : textColor,
                                            fontWeight: _filterIndex == 2 ? FontWeight.w800 : FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Zones Horizontal Bar (Ferah ve Geniş Tasarım)
                        if (zones.isNotEmpty) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _buildZoneChip(
                                  id: 'all',
                                  title: 'Tüm Alanlar (${allTables.length})',
                                  isSelected: _selectedZoneId == 'all',
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  textColor: textColor,
                                ),
                                const SizedBox(width: 8),
                                ...zones.map((zone) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildZoneChip(
                                      id: zone.id,
                                      title: '${zone.name} (${zone.tables.length})',
                                      isSelected: _selectedZoneId == zone.id,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textColor: textColor,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Search Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorder),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: textColor, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Masa ara (örn: Masa 4, Bahçe)...',
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

                        // Tables Grid
                        if (displayedTables.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48.0),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.table_restaurant_outlined, size: 48, color: textSecColor),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Gösterilecek masa bulunamadı.',
                                    style: TextStyle(color: textSecColor, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.88,
                            ),
                            itemCount: displayedTables.length,
                            itemBuilder: (context, index) {
                              final table = displayedTables[index];
                              return _buildTableCard(context, table, isDark, cardBg, cardBorder, textColor, textSecColor);
                            },
                          ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                      const SizedBox(height: 8),
                      Text('Masalar yüklenemedi: $err', style: TextStyle(color: textColor)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.refresh(waiterZonesProvider),
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

  Widget _buildZoneChip({
    required String id,
    required String title,
    required bool isSelected,
    required Color cardBg,
    required Color cardBorder,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: () {
        _triggerHaptic();
        setState(() => _selectedZoneId = id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              id == 'all' ? Icons.grid_view_rounded : Icons.location_on_outlined,
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF818CF8),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : textColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    TableModel table,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textColor,
    Color textSecColor,
  ) {
    final isOccupied = table.status == 'occupied';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        _triggerHaptic();
        context.push('/waiter/table/${table.id}', extra: table.name);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isOccupied
                ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                : cardBorder,
            width: isOccupied ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isOccupied
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Row 1: Name and dynamic stage badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    table.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isOccupied)
                  _buildTableStageBadge(table)
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text(
                      'Müsait',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
              ],
            ),

            // Row 2: Operational Info (Products chips, item count, wait time)
            if (isOccupied) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mini product avatars / chips
                  if (table.itemsPreview.isNotEmpty) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: table.itemsPreview.take(3).map((item) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image.network(
                                    item.imageUrl!,
                                    width: 13,
                                    height: 13,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, size: 11, color: Color(0xFF10B981)),
                                  ),
                                ),
                                const SizedBox(width: 3),
                              ] else ...[
                                const Icon(Icons.restaurant_menu, size: 11, color: Color(0xFF6366F1)),
                                const SizedBox(width: 3),
                              ],
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 60),
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: textSecColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.quantity > 1) ...[
                                const SizedBox(width: 2),
                                Text(
                                  'x${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 5),
                  ],

                  // Elapsed wait time & Total item count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 13,
                              color: table.waitMinutes >= 15 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              formatDurationMinutes(table.waitMinutes),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: table.waitMinutes >= 15 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  table.itemsCount > 0
                                      ? '${table.itemsCount} Kalem'
                                      : '${table.activeOrders} Sipariş',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: textSecColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 12, color: textSecColor),
                    ],
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sipariş Al',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline,
                    size: 22,
                    color: Color(0xFF10B981),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableStageBadge(TableModel table) {
    if (table.stage == 'READY') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 10, color: Color(0xFF10B981)),
            SizedBox(width: 3),
            Text(
              'Hazır',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    } else if (table.stage == 'PREPARING') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.soup_kitchen_rounded, size: 10, color: Color(0xFFF59E0B)),
            SizedBox(width: 3),
            Text(
              'Pişiyor',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 9, color: Color(0xFF6366F1)),
            SizedBox(width: 3),
            Text(
              'Bekliyor',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6366F1),
              ),
            ),
          ],
        ),
      );
    }
  }

}
