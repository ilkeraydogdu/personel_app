import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../kitchen/application/kitchen_provider.dart';

final prepOrdersProvider = FutureProvider.autoDispose<List<KitchenOrderModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/preparation/orders');
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
    debugPrint('[prepOrdersProvider] Failed to fetch preparation orders: $e');
    rethrow;
  }
});

