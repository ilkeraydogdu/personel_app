import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/safe_parsers.dart';

class KitchenOrderItemModel {
  final String orderItemId;
  final String name;
  final int quantity;
  final String? variant;
  final List<String> removedIngredients;
  final List<String> extras;
  final String? note;
  final double unitPrice;

  KitchenOrderItemModel({
    this.orderItemId = '',
    required this.name,
    this.quantity = 1,
    this.variant,
    this.removedIngredients = const [],
    this.extras = const [],
    this.note,
    this.unitPrice = 0.0,
  });

  factory KitchenOrderItemModel.fromDynamic(dynamic item) {
    if (item is Map) {
      final orderItemId = item['order_item_id']?.toString() ?? '';
      final name = item['name']?.toString() ?? item['product_name']?.toString() ?? item['item_name']?.toString() ?? 'Ürün';
      final qty = int.tryParse('${item['quantity'] ?? 1}') ?? 1;
      final variant = item['variant']?.toString() ?? item['variant_name']?.toString();
      final note = item['note']?.toString() ?? item['notes']?.toString();
      final price = double.tryParse('${item['unit_price'] ?? item['price'] ?? 0}') ?? 0.0;

      // Parse removed ingredients (e.g. "Soğansız", "Domates yok")
      final List<String> removed = [];
      if (item['removed_ingredients'] is List) {
        for (final r in item['removed_ingredients']) {
          if (r != null && r.toString().isNotEmpty) removed.add(r.toString());
        }
      } else if (item['excluded_ingredients'] is List) {
        for (final r in item['excluded_ingredients']) {
          if (r != null && r.toString().isNotEmpty) removed.add(r.toString());
        }
      }

      // Check if notes contains "Çıkar: ..."
      if (note != null && note.contains('Çıkar:')) {
        final parts = note.split('|');
        for (final p in parts) {
          final trimmed = p.trim();
          if (trimmed.startsWith('Çıkar:')) {
            final listStr = trimmed.replaceFirst('Çıkar:', '').trim();
            for (final sub in listStr.split(',')) {
              final s = sub.trim();
              if (s.isNotEmpty && !removed.contains(s)) removed.add(s);
            }
          }
        }
      }

      // Parse extras
      final List<String> ext = [];
      if (item['extras'] is List) {
        for (final e in item['extras']) {
          if (e is Map) {
            ext.add(e['name']?.toString() ?? '');
          } else if (e != null && e.toString().isNotEmpty) {
            ext.add(e.toString());
          }
        }
      } else if (item['selected_extras'] is List) {
        for (final e in item['selected_extras']) {
          if (e is Map) {
            ext.add(e['name']?.toString() ?? '');
          } else if (e != null && e.toString().isNotEmpty) {
            ext.add(e.toString());
          }
        }
      }

      // Cleaned note (omit Çıkar or Ekstra lines from general note display if already parsed)
      String? cleanNote = note;
      if (cleanNote != null && (cleanNote.contains('Çıkar:') || cleanNote.contains('Ekstra:'))) {
        final parts = cleanNote.split('|').map((p) => p.trim()).where((p) => !p.startsWith('Çıkar:') && !p.startsWith('Ekstra:')).toList();
        cleanNote = parts.isEmpty ? null : parts.join(' | ');
      }

      return KitchenOrderItemModel(
        orderItemId: orderItemId,
        name: name,
        quantity: qty,
        variant: variant,
        removedIngredients: removed,
        extras: ext,
        note: cleanNote,
        unitPrice: price,
      );
    }

    final str = item.toString();
    return KitchenOrderItemModel(name: str);
  }
}

class KitchenOrderModel {
  final String id;
  final String tableId;
  final String tableName;
  final String zoneName;
  final String waiterName;
  final String status;
  final String createdAt;
  final String notes;
  final double totalAmount;
  final List<KitchenOrderItemModel> items;

  KitchenOrderModel({
    required this.id,
    this.tableId = '',
    required this.tableName,
    this.zoneName = '',
    this.waiterName = '',
    required this.status,
    required this.createdAt,
    this.notes = '',
    this.totalAmount = 0.0,
    required this.items,
  });

  int get diffMinutes {
    if (createdAt.isEmpty) return 0;
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(dt).inMinutes;
      return diff < 0 ? 0 : diff;
    } catch (_) {
      return 0;
    }
  }

  String get elapsedTime {
    final diff = diffMinutes;
    if (diff < 1) return 'Yeni';
    return formatDurationMinutes(diff);
  }

  /// Flagged as delayed if waiting over 15 minutes and not ready yet
  bool get isDelayed => diffMinutes >= 15 && !isReady;

  bool get isPreparing => status.toLowerCase() == 'preparing';
  bool get isReady => status.toLowerCase() == 'ready';
  bool get isPending {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'new' || s == 'confirmed' || s == 'open' || s == 'created';
  }

  factory KitchenOrderModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final List<KitchenOrderItemModel> parsedItems = [];
    if (rawItems is List) {
      for (final it in rawItems) {
        parsedItems.add(KitchenOrderItemModel.fromDynamic(it));
      }
    } else if (json['product_name'] != null || json['item_name'] != null || json['name'] != null) {
      parsedItems.add(KitchenOrderItemModel.fromDynamic(json));
    }

    return KitchenOrderModel(
      id: json['order_id']?.toString() ?? json['id']?.toString() ?? '',
      tableId: json['table_id']?.toString() ?? '',
      tableName: json['table_name'] ?? json['tableName'] ?? 'Masa',
      zoneName: json['zone_name']?.toString() ?? '',
      waiterName: json['waiter_name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString() ?? '',
      notes: json['notes']?.toString() ?? json['customer_note']?.toString() ?? '',
      totalAmount: double.tryParse('${json['total_amount'] ?? 0}') ?? 0.0,
      items: parsedItems,
    );
  }
}

final kitchenOrdersProvider = FutureProvider.autoDispose<List<KitchenOrderModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/kitchen/orders');
    List rawList = [];
    final data = response['data'] ?? response;
    if (data is Map && data['orders'] is List) {
      rawList = data['orders'];
    } else if (data is List) {
      rawList = data;
    } else if (response['orders'] is List) {
      rawList = response['orders'];
    }

    return rawList
        .whereType<Map>()
        .map((e) => KitchenOrderModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (e) {
    debugPrint('[kitchenOrdersProvider] Failed to fetch kitchen orders: $e');
    rethrow;
  }
});

/// Plays haptic feedback when a new kitchen event arrives
void triggerKitchenHaptic() {
  try {
    HapticFeedback.heavyImpact();
  } catch (e) {
    debugPrint('[triggerKitchenHaptic] Haptic error: $e');
  }
}
