import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/websocket/websocket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/safe_parsers.dart';
import '../../pos/application/pos_provider.dart';
import '../application/waiter_provider.dart';
import 'widgets/ai_voice_order_sheet.dart';

class TableDetailsScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String? tableName;
  const TableDetailsScreen({super.key, required this.tableId, this.tableName});

  static void clearMenuCache() {
    _TableDetailsScreenState.clearCache();
  }

  @override
  ConsumerState<TableDetailsScreen> createState() => _TableDetailsScreenState();
}

class _TableDetailsScreenState extends ConsumerState<TableDetailsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _tableData;
  List<dynamic> _menuItems = [];
  List<String> _categories = [];

  static List<dynamic>? _cachedMenuItems;
  static List<String>? _cachedCategories;

  static void clearCache() {
    _cachedMenuItems = null;
    _cachedCategories = null;
  }

  IconData _getCategoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('kahve') || c.contains('sıcak') || c.contains('çay') || c.contains('coffee')) {
      return Icons.coffee_rounded;
    }
    if (c.contains('soğuk') || c.contains('içecek') || c.contains('drink') || c.contains('kokteyl') || c.contains('bar')) {
      return Icons.local_bar_rounded;
    }
    if (c.contains('burger') || c.contains('fast') || c.contains('atıştırmalık') || c.contains('snack')) {
      return Icons.lunch_dining_rounded;
    }
    if (c.contains('pizza')) {
      return Icons.local_pizza_rounded;
    }
    if (c.contains('tatlı') || c.contains('pasta') || c.contains('dondurma') || c.contains('dessert')) {
      return Icons.cake_rounded;
    }
    if (c.contains('kahvaltı') || c.contains('breakfast')) {
      return Icons.bakery_dining_rounded;
    }
    if (c.contains('ana') || c.contains('yemek') || c.contains('ızgara') || c.contains('et') || c.contains('kebap')) {
      return Icons.restaurant_rounded;
    }
    if (c.contains('salata') || c.contains('vejetaryen')) {
      return Icons.eco_rounded;
    }
    if (c.contains('nargile') || c.contains('shisha')) {
      return Icons.cloud_outlined;
    }
    return Icons.restaurant_menu_rounded;
  }

  String? _resolveItemImageUrl(Map it) {
    final direct = it['image_url'] ?? it['item_image'] ?? it['image'] ?? it['photo'] ?? it['image_path'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      final s = direct.toString().trim();
      if (s.startsWith('http')) return s;
      return 'https://qordy.com/${s.replaceFirst(RegExp(r'^/+'), '')}';
    }
    // Lookup in _menuItems by menu_item_id or name
    final mId = it['menu_item_id'] ?? it['product_id'] ?? it['id'];
    final name = (it['name'] ?? it['product_name'] ?? '').toString().trim().toLowerCase();
    for (final m in _menuItems) {
      if (m is! Map) continue;
      final idMatch = mId != null && (m['menu_item_id']?.toString() == mId.toString() || m['id']?.toString() == mId.toString());
      final nameMatch = name.isNotEmpty && (m['name']?.toString().trim().toLowerCase() == name);
      if (idMatch || nameMatch) {
        final img = m['image_url'] ?? m['image'] ?? m['item_image'] ?? m['photo'] ?? m['image_path'];
        if (img != null && img.toString().trim().isNotEmpty) {
          final s = img.toString().trim();
          if (s.startsWith('http')) return s;
          return 'https://qordy.com/${s.replaceFirst(RegExp(r'^/+'), '')}';
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_cachedMenuItems != null && _cachedMenuItems!.isNotEmpty) {
      _menuItems = _cachedMenuItems!;
      _categories = _cachedCategories ?? [];
    }
    _loadAll();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAll() async {
    // Only show full loading spinner if we don't have table data yet
    if (_tableData == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final api = ref.read(apiClientProvider);

    try {
      final resDetails = await api.get('/waiter/table-details', queryParameters: {'table_id': widget.tableId});
      final detailsSuccess = resDetails['success'] == true;
      final rawDetailsData = resDetails['data'];

      if (detailsSuccess && rawDetailsData != null) {
        _tableData = rawDetailsData is Map
            ? Map<String, dynamic>.from(rawDetailsData)
            : resDetails;
      } else if (rawDetailsData is Map) {
        _tableData = Map<String, dynamic>.from(rawDetailsData);
      }

      // Fetch menu if not cached
      if (_cachedMenuItems == null || _cachedMenuItems!.isEmpty) {
        final resMenu = await api.get('/menu');
        final menuData = resMenu['data'] ?? resMenu;
        List<dynamic> itemsList = [];
        if (menuData is Map && menuData['items'] is List) {
          itemsList = menuData['items'];
        } else if (menuData is List) {
          itemsList = menuData;
        }

        _menuItems = itemsList;
        _cachedMenuItems = itemsList;

        // Extract unique categories (no 'Tümü')
        final catSet = <String>{};
        if (menuData is Map && menuData['categories'] is List) {
          for (final c in menuData['categories']) {
            if (c is Map && c['name'] != null && c['name'].toString().trim().isNotEmpty) {
              final cName = c['name'].toString().trim();
              if (cName.toLowerCase() != 'tümü') catSet.add(cName);
            } else if (c is String && c.trim().isNotEmpty && c.trim().toLowerCase() != 'tümü') {
              catSet.add(c.trim());
            }
          }
        }
        for (final it in _menuItems) {
          if (it is Map) {
            final cat = it['category_name']?.toString() ?? it['category']?.toString();
            if (cat != null && cat.trim().isNotEmpty && cat.trim().toLowerCase() != 'tümü') {
              catSet.add(cat.trim());
            }
          }
        }
        _categories = catSet.toList()..sort();
        _cachedCategories = _categories;
      }
    } catch (e) {
      if (_tableData == null) {
        _errorMessage = 'Masa detayları yüklenemedi: $e';
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearTable() async {
    HapticFeedback.mediumImpact();
    final isIOS = !kIsWeb && Platform.isIOS;
    final bool? confirm;
    if (isIOS) {
      confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Masayı Kapat / Temizle'),
          content: const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Bu masadaki açık adisyonu kapatıp masayı boşaltmak istediğinize emin misiniz?'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Kapat'),
            ),
          ],
        ),
      );
    } else {
      confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Masayı Kapat / Temizle'),
          content: const Text('Bu masadaki açık adisyonu kapatıp masayı boşaltmak istediğinize emin misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Kapat', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (confirm != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.post('/pos/clear-table', data: {'table_id': widget.tableId});
      ref.invalidate(waiterZonesProvider);
      ref.invalidate(posTablesProvider);
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Masa boşaltıldı.'), backgroundColor: Color(0xFF00C896)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _showMoveTableDialog() async {
    final api = ref.read(apiClientProvider);
    List<Map<String, dynamic>> availableTables = [];
    try {
      final res = await api.get('/tables');
      final data = res['data'] is Map ? res['data'] : res;
      if (data != null && data['zones'] is List) {
          for (final z in data['zones']) {
            final zoneName = z['name']?.toString() ?? 'Genel';
            if (z['tables'] is List) {
              for (final t in z['tables']) {
                if (t['id']?.toString() != widget.tableId && t['table_id']?.toString() != widget.tableId) {
                  final tMap = Map<String, dynamic>.from(t);
                  tMap['zone_name'] = zoneName;
                  availableTables.add(tMap);
                }
              }
            }
          }
        }
    } catch (e) {
      debugPrint('[TableDetailsScreen] Failed to load available target tables: $e');
    }

    if (!mounted) return;

    final tableName = _tableData?['table_name'] ?? _tableData?['name'] ?? 'Masa';
    final totalAmount = double.tryParse('${_tableData?['total_amount'] ?? 0}') ?? 0.0;

    String? selectedTargetTableId;
    String? selectedTargetTableName;
    bool selectedTargetIsOccupied = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
          final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
          final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: cardBorder),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Handle
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

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.swap_horiz, color: Color(0xFF6366F1), size: 24),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Masa Taşıma',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sipariş ve adisyonu başka masaya aktar',
                                  style: TextStyle(color: textSecColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: textSecColor),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Current Table Info Banner
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.table_restaurant, color: Color(0xFFF59E0B), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Taşınacak: $tableName',
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₺${totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Target Table Grid Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'HEDEF MASA SEÇİN',
                          style: TextStyle(
                            color: textSecColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Target Tables Visual Grid
                  Expanded(
                    child: availableTables.isEmpty
                        ? Center(
                            child: Text(
                              'Taşınabilecek boş masa bulunamadı.',
                              style: TextStyle(color: textSecColor, fontSize: 14),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.1,
                            ),
                            itemCount: availableTables.length,
                            itemBuilder: (context, i) {
                              final t = availableTables[i];
                              final id = t['id']?.toString() ?? t['table_id']?.toString() ?? '';
                              final name = t['name'] ?? t['table_name'] ?? 'Masa $id';
                              final isOccupied = t['status'] == 'occupied';
                              final isSelected = selectedTargetTableId == id;

                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    selectedTargetTableId = id;
                                    selectedTargetTableName = name;
                                    selectedTargetIsOccupied = isOccupied;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF10B981)
                                          : (isOccupied
                                              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isSelected ? Icons.check_circle : Icons.table_restaurant,
                                        color: isSelected
                                            ? const Color(0xFF10B981)
                                            : (isOccupied ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)),
                                        size: 24,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isOccupied ? 'Dolu' : 'Boş',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isOccupied ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Bottom Action Button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedTargetTableId == null ? Colors.grey : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.swap_horiz, size: 20),
                        label: Text(
                          selectedTargetTableName != null
                              ? (selectedTargetIsOccupied
                                  ? 'Masayı $selectedTargetTableName ile Birleştir'
                                  : 'Masayı $selectedTargetTableName\'ye Taşı')
                              : 'Hedef Masa Seçin',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        onPressed: selectedTargetTableId == null
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                if (selectedTargetIsOccupied) {
                                  final confirmMerge = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('Dolu Masaya Aktarım'),
                                      content: Text(
                                        '$selectedTargetTableName şu an dolu görünüyor. Mevcut adisyonu bu masayla birleştirmek istediğinize emin misiniz?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dCtx, false),
                                          child: const Text('İptal'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                                          onPressed: () => Navigator.pop(dCtx, true),
                                          child: const Text('Birleştir', style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmMerge != true) return;
                                }
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                try {
                                  await api.post('/waiter/move-table', data: {
                                    'from_table_id': widget.tableId,
                                    'new_table_id': selectedTargetTableId,
                                  });
                                  ref.invalidate(waiterZonesProvider);
                                  ref.invalidate(posTablesProvider);
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('$tableName başarıyla $selectedTargetTableName\'ye taşındı.'),
                                      backgroundColor: const Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  context.pop();
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Taşıma başarısız: $e'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCustomizationSheet(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

    final name = item['name']?.toString() ?? 'Ürün';
    final basePrice = double.tryParse('${item['price'] ?? 0}') ?? 0.0;
    final rawVariants = safeList(item['variants']);
    final rawIngredients = safeList(item['ingredients'] ?? item['removable_ingredients']);
    final rawExtras = safeList(item['extras']);

    int quantity = 1;
    Map<String, dynamic>? selectedVariant = rawVariants.isNotEmpty ? rawVariants.first as Map<String, dynamic> : null;
    final Set<String> excludedIngredients = {};
    final Set<Map<String, dynamic>> selectedExtras = {};
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final varPrice = double.tryParse('${selectedVariant?['price'] ?? selectedVariant?['price_modifier'] ?? 0}') ?? 0.0;
          final extraSum = selectedExtras.fold<double>(0.0, (s, e) => s + (double.tryParse('${e['price'] ?? 0}') ?? 0.0));
          final unitPrice = (basePrice + varPrice + extraSum);
          final totalPrice = unitPrice * quantity;

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: cardBorder),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: (item['image_url'] ?? item['image']) != null &&
                                    (item['image_url'] ?? item['image']).toString().isNotEmpty
                                ? Image.network(
                                    (item['image_url'] ?? item['image']).toString(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
                                  )
                                : const Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '₺${unitPrice.toStringAsFixed(2)}',
                                style: const TextStyle(color: Color(0xFF00C896), fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        // Quantity controls
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 16),
                                onPressed: quantity > 1 ? () => setModalState(() => quantity--) : null,
                              ),
                              Text('$quantity', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16),
                                onPressed: () => setModalState(() => quantity++),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        // 1. Varyantlar (Boyut / Porsiyon)
                        if (rawVariants.isNotEmpty) ...[
                          Text('Porsiyon / Boyut Seçimi', style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: rawVariants.map((v) {
                              final vMap = v as Map<String, dynamic>;
                              final isSel = selectedVariant?['id'] == vMap['id'] || selectedVariant?['name'] == vMap['name'];
                              return ChoiceChip(
                                label: Text(vMap['name']?.toString() ?? ''),
                                selected: isSel,
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(color: isSel ? Colors.white : textColor, fontWeight: isSel ? FontWeight.bold : FontWeight.normal),
                                onSelected: (sel) {
                                  if (sel) setModalState(() => selectedVariant = vMap);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 2. Çıkarılabilir Malzemeler ("Soğansız", "Domatessiz" vb.)
                        if (rawIngredients.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.no_food_outlined, size: 16, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text('Çıkarılabilir Malzemeler (Dokunarak Çıkarın)', style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: rawIngredients.map((ing) {
                              final ingName = ing is Map ? (ing['name']?.toString() ?? '') : ing.toString();
                              final isExcluded = excludedIngredients.contains(ingName);
                              return FilterChip(
                                avatar: isExcluded ? const Icon(Icons.close, size: 14, color: Colors.redAccent) : null,
                                label: Text(
                                  isExcluded ? '$ingName (Çıkarıldı)' : ingName,
                                  style: TextStyle(
                                    color: isExcluded ? Colors.redAccent : textColor,
                                    decoration: isExcluded ? TextDecoration.lineThrough : null,
                                    fontWeight: isExcluded ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: isExcluded,
                                selectedColor: Colors.redAccent.withValues(alpha: 0.15),
                                checkmarkColor: Colors.redAccent,
                                onSelected: (val) {
                                  setModalState(() {
                                    if (val) {
                                      excludedIngredients.add(ingName);
                                    } else {
                                      excludedIngredients.remove(ingName);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 3. Ekstralar
                        if (rawExtras.isNotEmpty) ...[
                          Text('Ekstralar', style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: rawExtras.map((ex) {
                              final exMap = ex as Map<String, dynamic>;
                              final exName = exMap['name']?.toString() ?? '';
                              final exPrice = double.tryParse('${exMap['price'] ?? 0}') ?? 0.0;
                              final isSel = selectedExtras.contains(exMap);
                              return FilterChip(
                                label: Text('+$exName (₺${exPrice.toStringAsFixed(0)})'),
                                selected: isSel,
                                selectedColor: const Color(0xFF00C896).withValues(alpha: 0.2),
                                labelStyle: TextStyle(color: isSel ? const Color(0xFF00C896) : textColor, fontWeight: isSel ? FontWeight.bold : FontWeight.normal),
                                onSelected: (val) {
                                  setModalState(() {
                                    if (val) {
                                      selectedExtras.add(exMap);
                                    } else {
                                      selectedExtras.remove(exMap);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 4. Sipariş Notu
                        Text('Sipariş Notu', style: TextStyle(color: textSecColor, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: noteCtrl,
                          style: TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Örn: Az pişmiş, acısız, sosu ayrı vb.',
                            hintStyle: TextStyle(color: textSecColor, fontSize: 13),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // Bottom Add Button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.add_shopping_cart, size: 20),
                        label: Text(
                          isSubmitting ? 'Ekleniyor...' : 'Masaya Ekle • ₺${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                final api = ref.read(apiClientProvider);
                                final itemId = (item['id'] ?? item['menu_item_id'])?.toString() ?? '';
                                final variantId = (selectedVariant?['variant_id'] ?? selectedVariant?['id'])?.toString();

                                final orderItemPayload = <String, dynamic>{
                                  'menu_item_id': itemId,
                                  'quantity': quantity,
                                  if (variantId != null && variantId.isNotEmpty) 'variant_id': variantId,
                                  if (excludedIngredients.isNotEmpty) 'excluded_ingredients': excludedIngredients.toList(),
                                  if (selectedExtras.isNotEmpty)
                                    'selected_extras': selectedExtras
                                        .map((e) => {
                                              if (e['id'] != null) 'id': e['id'],
                                              'name': e['name']?.toString() ?? '',
                                              'price': double.tryParse('${e['price'] ?? 0}') ?? 0.0,
                                            })
                                        .toList(),
                                  if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
                                };

                                try {
                                  await api.post('/orders', data: {
                                    'table_id': widget.tableId,
                                    'order_type': 'DINE_IN',
                                    'items': [orderItemPayload],
                                  });
                                  ref.invalidate(waiterZonesProvider);
                                  ref.invalidate(posTablesProvider);

                                  if (!mounted) return;
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$name ($quantity adet) masaya eklendi'),
                                      backgroundColor: const Color(0xFF00C896),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  _loadAll();
                                } catch (e) {
                                  if (!mounted) return;
                                  setModalState(() => isSubmitting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ürün eklenemedi: $e'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => noteCtrl.dispose());
  }

  void _openProductCatalogSheet() {
    String? selectedCat;
    String searchQ = '';
    final searchCtrl = TextEditingController();
    final Map<String, Map<String, dynamic>> draftCart = {};
    bool isSendingBatch = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
          final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
          final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          final filtered = _menuItems.where((it) {
            if (it is! Map) return false;
            final name = (it['name']?.toString() ?? '').toLowerCase();
            final cat = (it['category_name'] ?? it['category'])?.toString() ?? '';
            final matchesSearch = searchQ.isEmpty || name.contains(searchQ.toLowerCase());
            final matchesCat = selectedCat == null || cat.trim().toLowerCase() == selectedCat!.trim().toLowerCase();
            return matchesSearch && matchesCat;
          }).toList();

          final isCategoryView = selectedCat == null && searchQ.isEmpty;

          final totalDraftCount = draftCart.values.fold<int>(0, (sum, v) => sum + ((v['quantity'] as int?) ?? 1));
          final totalDraftSum = draftCart.values.fold<double>(0.0, (sum, v) {
            final p = double.tryParse('${v['item']['price'] ?? 0}') ?? 0.0;
            final q = (v['quantity'] as int?) ?? 1;
            return sum + (p * q);
          });

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: cardBorder),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Handle
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

                  // Header with AI Voice Order shortcut
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
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
                              child: const Icon(Icons.restaurant_menu, color: Color(0xFF6366F1), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCategoryView ? 'Kategoriler' : (selectedCat ?? 'Ürün Ekle'),
                                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  isCategoryView
                                      ? 'Sipariş eklemek için bir kategori seçin'
                                      : 'Masaya tek dokunuşla ekleyin',
                                  style: TextStyle(color: textSecColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // Quick AI Mic Voice Order button inside Catalog
                            IconButton(
                              tooltip: 'Sesli Hızlı Sipariş',
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 16),
                              ),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (ctx) => AiVoiceOrderSheet(
                                    initialTableId: widget.tableId,
                                    initialTableName: widget.tableName,
                                    onOrderPlaced: _loadAll,
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: textSecColor),
                              onPressed: () => Navigator.pop(sheetCtx),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: TextField(
                        controller: searchCtrl,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Menüde ürün ara...',
                          hintStyle: TextStyle(color: textSecColor, fontSize: 13),
                          prefixIcon: Icon(Icons.search, size: 20, color: textSecColor),
                          suffixIcon: searchQ.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear, size: 18, color: textSecColor),
                                  onPressed: () {
                                    setSheetState(() {
                                      searchQ = '';
                                      searchCtrl.clear();
                                    });
                                  },
                                )
                              : null,
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) => setSheetState(() => searchQ = val),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // View Switcher: Category-First 2-Column Grid or Products List
                  Expanded(
                    child: isCategoryView
                        ? (_categories.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.category_outlined, size: 48, color: textSecColor.withValues(alpha: 0.5)),
                                    const SizedBox(height: 8),
                                    Text('Kategori bulunamadı', style: TextStyle(color: textSecColor, fontSize: 14)),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 1.15,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: _categories.length,
                                itemBuilder: (context, index) {
                                  final cat = _categories[index];
                                  final catCount = _menuItems.where((it) {
                                    if (it is! Map) return false;
                                    final c = (it['category_name'] ?? it['category'])?.toString() ?? '';
                                    return c.trim().toLowerCase() == cat.trim().toLowerCase();
                                  }).length;
                                  final catIcon = _getCategoryIcon(cat);

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setSheetState(() => selectedCat = cat),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: cardBorder),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Icon(catIcon, color: const Color(0xFF6366F1), size: 24),
                                                ),
                                                Icon(Icons.arrow_forward_ios_rounded, color: textSecColor, size: 14),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cat,
                                                  style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '$catCount Ürün',
                                                    style: TextStyle(
                                                      color: textSecColor,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ))
                        : Column(
                            children: [
                              // Category Navigation Bar with Back Button
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Row(
                                  children: [
                                    if (selectedCat != null)
                                      InkWell(
                                        onTap: () => setSheetState(() => selectedCat = null),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.arrow_back_ios_new, size: 12, color: Color(0xFF6366F1)),
                                              SizedBox(width: 4),
                                              Text(
                                                'Kategoriler',
                                                style: TextStyle(
                                                  color: Color(0xFF6366F1),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        selectedCat ?? 'Arama: "$searchQ"',
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${filtered.length} Ürün',
                                        style: TextStyle(
                                          color: textSecColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Products List
                              Expanded(
                                child: filtered.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.search_off_rounded, size: 48, color: textSecColor),
                                            const SizedBox(height: 8),
                                            Text('Ürün bulunamadı', style: TextStyle(color: textSecColor, fontSize: 14)),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        itemCount: filtered.length,
                                        itemBuilder: (context, index) {
                                          final item = Map<String, dynamic>.from(filtered[index] as Map);
                                          final name = item['name']?.toString() ?? '';
                                          final price = double.tryParse('${item['price'] ?? 0}') ?? 0.0;
                                          final imgUrl = item['image_url']?.toString() ?? item['image']?.toString();
                                          final hasOptions = safeList(item['variants']).isNotEmpty ||
                                              safeList(item['ingredients']).isNotEmpty ||
                                              safeList(item['extras']).isNotEmpty;
                                          final itemId = (item['id'] ?? item['menu_item_id'])?.toString() ?? '';
                                          final inCartCount = (draftCart[itemId]?['quantity'] as int?) ?? 0;

                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: inCartCount > 0 ? const Color(0xFF6366F1) : cardBorder,
                                                width: inCartCount > 0 ? 1.5 : 1.0,
                                              ),
                                            ),
                                            child: ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              leading: Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: imgUrl != null && imgUrl.isNotEmpty
                                                      ? Image.network(
                                                          imgUrl,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => const Icon(
                                                            Icons.fastfood_rounded,
                                                            color: Color(0xFF6366F1),
                                                            size: 24,
                                                          ),
                                                        )
                                                      : const Icon(
                                                          Icons.fastfood_rounded,
                                                          color: Color(0xFF6366F1),
                                                          size: 24,
                                                        ),
                                                ),
                                              ),
                                              title: Text(
                                                name,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                              ),
                                              subtitle: Row(
                                                children: [
                                                  Text(
                                                    '₺${price.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 13,
                                                      color: Color(0xFF10B981),
                                                    ),
                                                  ),
                                                  if (hasOptions) ...[
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () => _showCustomizationSheet(item),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.tune_rounded, size: 10, color: Color(0xFF6366F1)),
                                                            SizedBox(width: 3),
                                                            Text(
                                                              'Özelleştir',
                                                              style: TextStyle(
                                                                color: Color(0xFF6366F1),
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              trailing: inCartCount > 0
                                                  ? Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        InkWell(
                                                          onTap: () {
                                                            setSheetState(() {
                                                              if (inCartCount <= 1) {
                                                                draftCart.remove(itemId);
                                                              } else {
                                                                final newQ = inCartCount - 1;
                                                                draftCart[itemId]!['quantity'] = newQ;
                                                                draftCart[itemId]!['payload']['quantity'] = newQ;
                                                              }
                                                            });
                                                          },
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: Container(
                                                            padding: const EdgeInsets.all(6),
                                                            decoration: BoxDecoration(
                                                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: Icon(Icons.remove, size: 16, color: textColor),
                                                          ),
                                                        ),
                                                        Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                                          child: Text(
                                                            '$inCartCount',
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.w800,
                                                              fontSize: 15,
                                                              color: textColor,
                                                            ),
                                                          ),
                                                        ),
                                                        InkWell(
                                                          onTap: () {
                                                            setSheetState(() {
                                                              final newQ = inCartCount + 1;
                                                              draftCart[itemId]!['quantity'] = newQ;
                                                              draftCart[itemId]!['payload']['quantity'] = newQ;
                                                            });
                                                          },
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: Container(
                                                            padding: const EdgeInsets.all(6),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF6366F1),
                                                        foregroundColor: Colors.white,
                                                        elevation: 0,
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                      ),
                                                      icon: const Icon(Icons.add, size: 16),
                                                      label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                      onPressed: () {
                                                        if (hasOptions) {
                                                          _showCustomizationSheet(item);
                                                        } else {
                                                          setSheetState(() {
                                                            draftCart[itemId] = {
                                                              'item': item,
                                                              'quantity': 1,
                                                              'payload': {
                                                                'menu_item_id': itemId,
                                                                'quantity': 1,
                                                              },
                                                            };
                                                          });
                                                        }
                                                      },
                                                    ),
                                              onTap: () {
                                                if (hasOptions) {
                                                  _showCustomizationSheet(item);
                                                } else {
                                                  setSheetState(() {
                                                    final newQ = inCartCount + 1;
                                                    draftCart[itemId] = {
                                                      'item': item,
                                                      'quantity': newQ,
                                                      'payload': {
                                                        'menu_item_id': itemId,
                                                        'quantity': newQ,
                                                      },
                                                    };
                                                  });
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                  ),

                  // Sticky Draft Cart Bottom Bar (Fast One-Tap Dispatch)
                  if (draftCart.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        border: Border(top: BorderSide(color: cardBorder)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: isSendingBatch
                            ? null
                            : () async {
                                setSheetState(() => isSendingBatch = true);
                                final api = ref.read(apiClientProvider);
                                final itemsPayload = draftCart.values.map((v) => v['payload']).toList();

                                try {
                                  await api.post('/orders', data: {
                                    'table_id': widget.tableId,
                                    'order_type': 'DINE_IN',
                                    'items': itemsPayload,
                                  });
                                  ref.invalidate(waiterZonesProvider);
                                  ref.invalidate(posTablesProvider);

                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('$totalDraftCount adet ürün masaya eklendi ve mutfağa iletildi!'),
                                        backgroundColor: const Color(0xFF10B981),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                    _loadAll();
                                  }
                                } catch (e) {
                                  setSheetState(() => isSendingBatch = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Sipariş iletilemedi: $e'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        icon: isSendingBatch
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isSendingBatch
                              ? 'Mutfağa İletiliyor...'
                              : 'Masaya Gönder • $totalDraftCount Ürün (₺${totalDraftSum.toStringAsFixed(2)})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => searchCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rawName = _tableData?['table_name'] ?? _tableData?['name'] ?? widget.tableName;
    final tableName = (rawName != null && rawName.toString().isNotEmpty)
        ? rawName.toString()
        : (widget.tableId.startsWith('table_') ? 'Masa' : 'Masa ${widget.tableId}');
    final orders = safeList(_tableData?['orders'] ?? _tableData?['active_orders']);
    final totalAmount = double.tryParse('${_tableData?['total_amount'] ?? 0}') ?? 0.0;

    // Listen to real-time table/order/kitchen updates
    ref.listen<AsyncValue<WebSocketEvent>>(wsEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event != null && (event.isTableEvent || event.isOrderEvent || event.isKitchenEvent)) {
        _loadAll();
      }
    });

    final cardBg = AppColors.getCardBg(context);
    final cardBorder = AppColors.getCardBorder(context);
    final textColor = AppColors.getTextPrimary(context);
    final textSecColor = AppColors.getTextSecondary(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.getScaffoldBg(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(tableName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          // "Masayı Taşı" is ONLY displayed if the table is NOT empty!
          if (orders.isNotEmpty || totalAmount > 0)
            IconButton(
              tooltip: 'Masayı Taşı',
              icon: const Icon(Icons.swap_horiz),
              onPressed: _showMoveTableDialog,
            ),
          IconButton(
            tooltip: 'Sesli AI Sipariş',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 18),
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => AiVoiceOrderSheet(
                  initialTableId: widget.tableId,
                  initialTableName: tableName,
                  onOrderPlaced: _loadAll,
                ),
              );
            },
          ),
          if (orders.isNotEmpty || totalAmount > 0)
            IconButton(
              tooltip: 'Masayı Kapat',
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              onPressed: _clearTable,
            ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                      const SizedBox(height: 8),
                      Text(_errorMessage!),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadAll, child: const Text('Tekrar Dene')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Total Bill Card (No Kasaya Aktar, has + Ürün Ekle button)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      l10n.t('total_bill'),
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        orders.isEmpty ? 'BOŞ MASA' : 'DOLU',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '₺${totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text(
                                'Ürün Ekle',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              onPressed: _openProductCatalogSheet,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── AI Voice Order Luxury Pill/Card ───
                      InkWell(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => AiVoiceOrderSheet(
                              initialTableId: widget.tableId,
                              initialTableName: tableName,
                              onOrderPlaced: _loadAll,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [
                                      const Color(0xFF1E1B4B).withValues(alpha: 0.6),
                                      const Color(0xFF0F172A).withValues(alpha: 0.8),
                                    ]
                                  : [
                                      const Color(0xFFEEF2FF),
                                      const Color(0xFFF8FAFC),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.25),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.15 : 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.mic_none_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Yapay Zekâ Sesli Sipariş',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: textColor,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: const Text(
                                            'AI',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF6366F1),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Masaya konuşarak saniyeler içinde ürün ekleyin',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: textSecColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Başlat',
                                      style: TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF6366F1)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Current Orders (Adisyon Kalemleri)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Açık Adisyon Kalemleri',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${orders.fold<int>(0, (s, o) => s + (o is Map ? safeList(o['items']).length : 0))} Kalem',
                              style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (orders.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.receipt_long_outlined, size: 32, color: textSecColor),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Bu masada henüz sipariş yok',
                                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Masa şu an boş durumda. Hemen sipariş ekleyebilirsiniz.',
                                  style: TextStyle(color: textSecColor, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: 200,
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Sipariş Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: _openProductCatalogSheet,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        ...orders.map((o) {
                          final items = o is Map ? safeList(o['items']) : const [];
                          return Column(
                            children: items.map((it) {
                              if (it is! Map) return const SizedBox.shrink();
                              final name = it['name'] ?? it['product_name'] ?? 'Ürün';
                              final qty = it['quantity'] ?? 1;
                              final price = double.tryParse('${it['unit_price'] ?? it['price'] ?? 0}') ?? 0.0;
                              final itemTotal = price * qty;
                              final status = it['status']?.toString().toLowerCase() ?? 'pending';
                              final note = it['note']?.toString() ?? it['notes']?.toString();
                              final excluded = safeList(it['excluded_ingredients'] ?? it['removed_ingredients']);
                              final variant = it['variant']?.toString() ?? it['variant_name']?.toString();
                              final extras = safeList(it['extras'] ?? it['selected_extras']);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Ürün Görseli (Food Thumbnail)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: cardBorder),
                                            ),
                                            child: Builder(builder: (ctx) {
                                              final itemImg = _resolveItemImageUrl(it);
                                              if (itemImg != null && itemImg.isNotEmpty) {
                                                return Image.network(
                                                  itemImg,
                                                  width: 50,
                                                  height: 50,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => Center(
                                                    child: Icon(_getCategoryIcon(it['category_name']?.toString() ?? ''), size: 24, color: textSecColor),
                                                  ),
                                                );
                                              }
                                              return Center(
                                                child: Icon(_getCategoryIcon(it['category_name']?.toString() ?? ''), size: 24, color: textSecColor),
                                              );
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${qty}x',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                              ),
                                              if (variant != null && variant.isNotEmpty)
                                                Text(variant, style: TextStyle(color: textSecColor, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₺${itemTotal.toStringAsFixed(2)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF00C896)),
                                        ),
                                      ],
                                    ),
                                    if (excluded.isNotEmpty || extras.isNotEmpty || (note != null && note.isNotEmpty)) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          ...excluded.map((ex) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  '🚫 $ex Çıkarıldı',
                                                  style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              )),
                                          ...extras.map((ex) {
                                            final exName = ex is Map ? (ex['name'] ?? ex['extra_name'] ?? 'Ekstra') : ex.toString();
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                '+ $exName',
                                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            );
                                          }),
                                          if (note != null && note.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                '📝 $note',
                                                style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: ((status == 'served' || status == 'ready') ? const Color(0xFF00C896) : Colors.orange).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          (status == 'served' || status == 'ready') ? '✓ Masaya Servis Edildi' : '⏱ Hazırlanıyor',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: (status == 'served' || status == 'ready') ? const Color(0xFF00C896) : Colors.orange,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        }),
                        const SizedBox(height: 16),
                        // Prominent "+ Yeni Ürün Ekle" button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.add_shopping_cart, size: 20),
                            label: const Text(
                              '+ Yeni Ürün / İçecek Ekle',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _openProductCatalogSheet,
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }
}
