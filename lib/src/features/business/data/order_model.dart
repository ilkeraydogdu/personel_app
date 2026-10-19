import '../../../core/utils/currency_helper.dart';

class OrderModel {
  final String orderId;
  final String tableId;
  final String tableName;
  final String status;
  final double totalAmount;
  final String currency;
  final double? currencyRate;
  final double? originalAmount;
  final List<OrderItem> items;
  final String createdAt;
  final String? updatedAt;

  OrderModel({
    required this.orderId,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.totalAmount,
    this.currency = 'TRY',
    this.currencyRate,
    this.originalAmount,
    required this.items,
    required this.createdAt,
    this.updatedAt,
  });

  String get timeText {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return createdAt.length >= 16 ? createdAt.substring(11, 16) : createdAt;
    }
  }

  String get formattedTotalAmount => CurrencyHelper.format(totalAmount, currency: currency);

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      orderId: json['order_id']?.toString() ?? '',
      tableId: json['table_id']?.toString() ?? '',
      tableName: json['table_name'] ?? json['name'] ?? '',
      status: json['status']?.toString().toLowerCase() ?? 'pending',
      totalAmount: double.tryParse('${json['total_amount'] ?? 0}') ?? 0.0,
      currency: json['currency']?.toString().toUpperCase() ?? 'TRY',
      currencyRate: json['currency_rate'] != null ? double.tryParse('${json['currency_rate']}') : null,
      originalAmount: json['original_amount'] != null ? double.tryParse('${json['original_amount']}') : null,
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => OrderItem.fromJson(e))
          .toList() ?? [],
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'table_id': tableId,
    'table_name': tableName,
    'status': status.toUpperCase(),
    'total_amount': totalAmount,
    'currency': currency,
    if (currencyRate != null) 'currency_rate': currencyRate,
    if (originalAmount != null) 'original_amount': originalAmount,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class OrderItem {
  final String name;
  final int quantity;
  final double price;
  final String? currency;
  final String? note;

  OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.currency,
    this.note,
  });

  String formattedPrice({String fallbackCurrency = 'TRY'}) =>
      CurrencyHelper.format(price, currency: currency ?? fallbackCurrency);

  String formattedTotal({String fallbackCurrency = 'TRY'}) =>
      CurrencyHelper.format(price * quantity, currency: currency ?? fallbackCurrency);

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['product_name'] ?? json['name'] ?? '',
      quantity: json['quantity'] is int ? json['quantity'] : int.tryParse('${json['quantity'] ?? 1}') ?? 1,
      price: double.tryParse('${json['unit_price'] ?? json['price'] ?? 0}') ?? 0.0,
      currency: json['currency']?.toString().toUpperCase(),
      note: json['note'] ?? json['customization_note'],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'price': price,
    if (currency != null) 'currency': currency,
    'note': note,
  };
}
