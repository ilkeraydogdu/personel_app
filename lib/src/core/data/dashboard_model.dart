class DashboardModel {
  final bool success;
  final DashboardData data;

  DashboardModel({required this.success, required this.data});

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      success: json['success'] ?? false,
      data: DashboardData.fromJson(json['data'] ?? {}),
    );
  }
}

class DashboardData {
  final int totalOrders;
  final double totalRevenue;
  final int activeTables;
  final int totalTables;
  final int pendingOrders;
  final int unreadNotifications;
  final List<RecentOrder> recentOrders;
  final String businessDate;
  final double occupancyRate;
  final double completionRate;
  final int totalTips;
  final int cancelledOrders;
  final int paidOrders;
  final double avgOrderValue;
  final Map<String, dynamic> previousPeriod;

  DashboardData({
    required this.totalOrders,
    required this.totalRevenue,
    required this.activeTables,
    required this.totalTables,
    required this.pendingOrders,
    required this.unreadNotifications,
    required this.recentOrders,
    required this.businessDate,
    required this.occupancyRate,
    required this.completionRate,
    required this.totalTips,
    required this.cancelledOrders,
    required this.paidOrders,
    required this.avgOrderValue,
    required this.previousPeriod,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      totalOrders: (json['total_orders'] ?? 0) is int ? json['total_orders'] : int.tryParse('${json['total_orders'] ?? 0}') ?? 0,
      totalRevenue: double.tryParse('${json['total_revenue'] ?? 0}') ?? 0.0,
      activeTables: (json['active_tables'] ?? 0) is int ? json['active_tables'] : int.tryParse('${json['active_tables'] ?? 0}') ?? 0,
      totalTables: (json['total_tables'] ?? 0) is int ? json['total_tables'] : int.tryParse('${json['total_tables'] ?? 0}') ?? 0,
      pendingOrders: (json['pending_orders'] ?? 0) is int ? json['pending_orders'] : int.tryParse('${json['pending_orders'] ?? 0}') ?? 0,
      unreadNotifications: (json['unread_notifications'] ?? 0) is int ? json['unread_notifications'] : int.tryParse('${json['unread_notifications'] ?? 0}') ?? 0,
      recentOrders: (json['recent_orders'] as List<dynamic>?)
          ?.map((e) => RecentOrder.fromJson(e))
          .toList() ?? [],
      businessDate: json['business_date'] ?? '',
      occupancyRate: double.tryParse('${json['occupancy_rate'] ?? 0}') ?? 0.0,
      completionRate: double.tryParse('${json['completion_rate'] ?? 0}') ?? 0.0,
      totalTips: (json['total_tips'] ?? 0) is int ? json['total_tips'] : int.tryParse('${json['total_tips'] ?? 0}') ?? 0,
      cancelledOrders: (json['cancelled_orders'] ?? 0) is int ? json['cancelled_orders'] : int.tryParse('${json['cancelled_orders'] ?? 0}') ?? 0,
      paidOrders: (json['paid_orders'] ?? 0) is int ? json['paid_orders'] : int.tryParse('${json['paid_orders'] ?? 0}') ?? 0,
      avgOrderValue: double.tryParse('${json['avg_order_value'] ?? 0}') ?? 0.0,
      previousPeriod: json['previous_period'] ?? {},
    );
  }
}

class RecentOrder {
  final String? orderId;
  final String? tableName;
  final String? status;
  final double? totalAmount;
  final String? createdAt;

  RecentOrder({
    this.orderId,
    this.tableName,
    this.status,
    this.totalAmount,
    this.createdAt,
  });

  factory RecentOrder.fromJson(Map<String, dynamic> json) {
    return RecentOrder(
      orderId: json['order_id']?.toString(),
      tableName: json['table_name'] ?? json['name'],
      status: json['status']?.toString(),
      totalAmount: double.tryParse('${json['total_amount'] ?? 0}'),
      createdAt: json['created_at']?.toString(),
    );
  }
}