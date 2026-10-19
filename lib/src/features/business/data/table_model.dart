class TableModel {
 final String tableId;
 final String tableName;
 final String status;
 final String? zoneId;
 final String? zoneName;
 final int activeOrders;

 TableModel({
 required this.tableId,
 required this.tableName,
 required this.status,
 this.zoneId,
 this.zoneName,
 this.activeOrders = 0,
 });

 factory TableModel.fromJson(Map<String, dynamic> json) {
 return TableModel(
 tableId: json['table_id']?.toString() ?? json['id']?.toString() ?? '',
 tableName: json['table_name'] ?? json['name'] ?? '',
 status: _normalize(json['status']?.toString() ?? 'available'),
 zoneId: json['zone_id']?.toString(),
 zoneName: json['zone_name']?.toString(),
 activeOrders: json['active_orders'] is int
 ? json['active_orders']
 : int.tryParse('${json['active_orders'] ?? 0}') ?? 0,
 );
 }

 static String _normalize(String s) {
 final lower = s.toLowerCase();
 if (lower == 'occupied' || lower == 'dolu') return 'occupied';
 if (lower == 'reserved' || lower == 'rezerve') return 'reserved';
 if (lower == 'payment_pending') return 'payment_pending';
 return 'available';
 }

 bool get isOccupied => status == 'occupied';
 bool get isAvailable => status == 'available';
 bool get isReserved => status == 'reserved';
 bool get isPaymentPending => status == 'payment_pending';
}

class ZoneModel {
 final String zoneId;
 final String zoneName;
 final String? description;
 final List<TableModel> tables;

 ZoneModel({
 required this.zoneId,
 required this.zoneName,
 this.description,
 required this.tables,
 });

 factory ZoneModel.fromJson(Map<String, dynamic> json) {
 return ZoneModel(
 zoneId: json['zone_id']?.toString() ?? json['id']?.toString() ?? '',
 zoneName: json['zone_name'] ?? json['name'] ?? '',
 description: json['description']?.toString(),
 tables: (json['tables'] as List<dynamic>?)
 ?.map((e) => TableModel.fromJson(e))
 .toList() ?? [],
 );
 }
}
