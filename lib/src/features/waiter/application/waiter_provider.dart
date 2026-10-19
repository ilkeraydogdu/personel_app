import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class TableItemPreview {
  final String name;
  final String? imageUrl;
  final int quantity;

  TableItemPreview({
    required this.name,
    this.imageUrl,
    required this.quantity,
  });

  factory TableItemPreview.fromJson(Map<String, dynamic> json) {
    return TableItemPreview(
      name: json['name']?.toString() ?? '',
      imageUrl: json['image_url']?.toString(),
      quantity: int.tryParse('${json['quantity'] ?? 1}') ?? 1,
    );
  }
}

class TableModel {
  final String id;
  final String name;
  final String status;
  final int activeOrders;
  final double totalAmount;
  final int itemsCount;
  final int waitMinutes;
  final String stage;
  final List<TableItemPreview> itemsPreview;

  TableModel({
    required this.id,
    required this.name,
    required this.status,
    required this.activeOrders,
    this.totalAmount = 0.0,
    this.itemsCount = 0,
    this.waitMinutes = 0,
    this.stage = 'NONE',
    this.itemsPreview = const [],
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    final previewList = (json['items_preview'] as List?)
            ?.map((e) => TableItemPreview.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];

    return TableModel(
      id: json['table_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['table_name'] ?? json['name'] ?? '',
      status: json['status']?.toString().toLowerCase() ?? 'available',
      activeOrders: int.tryParse('${json['active_orders'] ?? json['order_count'] ?? 0}') ?? 0,
      totalAmount: double.tryParse('${json['total_amount'] ?? json['bill_total'] ?? 0}') ?? 0.0,
      itemsCount: int.tryParse('${json['items_count'] ?? 0}') ?? 0,
      waitMinutes: int.tryParse('${json['wait_minutes'] ?? 0}') ?? 0,
      stage: json['stage']?.toString().toUpperCase() ?? 'NONE',
      itemsPreview: previewList,
    );
  }
}

class ZoneModel {
  final String id;
  final String name;
  final List<TableModel> tables;

  ZoneModel({required this.id, required this.name, required this.tables});

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    return ZoneModel(
      id: json['zone_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['zone_name']?.toString() ?? json['name']?.toString() ?? '',
      tables: (json['tables'] as List?)
              ?.whereType<Map>()
              .map((e) => TableModel.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

final waiterZonesProvider = FutureProvider<List<ZoneModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/tables');
    final data = response['data'] is Map ? response['data'] : response;
    if (data != null && data['zones'] is List) {
      final List zonesList = data['zones'];
      return zonesList
          .whereType<Map>()
          .map((e) => ZoneModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  } catch (e) {
    debugPrint('[waiterZonesProvider] Failed to fetch waiter zones: $e');
    rethrow;
  }
});
