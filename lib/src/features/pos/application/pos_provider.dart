import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class PosTableModel {
  final String id;
  final String name;
  final double totalAmount;
  final String status;
  final String zoneName;

  PosTableModel({
    required this.id,
    required this.name,
    required this.totalAmount,
    required this.status,
    this.zoneName = '',
  });
  
  factory PosTableModel.fromJson(Map<String, dynamic> json, {String zoneName = ''}) {
    final rawZone = zoneName.isNotEmpty
        ? zoneName
        : (json['zone_name']?.toString() ?? json['zone']?.toString() ?? json['area']?.toString() ?? '');
    return PosTableModel(
      id: json['table_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['table_name']?.toString() ?? json['name']?.toString() ?? '',
      totalAmount: double.tryParse('${json['total_amount'] ?? json['bill_total'] ?? 0}') ?? 0.0,
      status: json['status']?.toString().toLowerCase() ?? 'available',
      zoneName: rawZone,
    );
  }
}

final posTablesProvider = FutureProvider<List<PosTableModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/tables');
    final data = response['data'] is Map ? response['data'] : response;
    final List<PosTableModel> result = [];
    if (data != null && data['zones'] is List) {
      for (final zone in data['zones']) {
        if (zone is Map && zone['tables'] is List) {
          final zName = (zone['zone_name'] ?? zone['name'] ?? zone['title'])?.toString() ?? '';
          for (final t in zone['tables']) {
            if (t is Map<String, dynamic>) {
              result.add(PosTableModel.fromJson(t, zoneName: zName));
            } else if (t is Map) {
              result.add(PosTableModel.fromJson(Map<String, dynamic>.from(t), zoneName: zName));
            }
          }
        }
      }
      return result;
    } else if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => PosTableModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  } catch (e) {
    rethrow;
  }
});
