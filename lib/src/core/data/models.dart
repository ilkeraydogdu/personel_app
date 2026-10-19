/// Mobil API sözleşmesine (contract_version 2) karşılık gelen alan modelleri.
/// Tüm `fromJson` fabrikaları sunucunun string/sayı karışık tiplerine
/// toleranslıdır (bkz. json_utils.dart).
library;

import 'dart:convert';
import '../config/app_config.dart';
import '../utils/currency_helper.dart';
import 'json_utils.dart';

// ─── Kimlik ────────────────────────────────────────────────

class AppUser {
  final String id;
  final String name;
  final String? email;
  /// OWNER | MANAGER | ADMIN | WAITER | KITCHEN | PREPARATION | CASHIER
  final String role;
  final String? roleId;
  final String? preparationScreenId;
  final String? avatar;
  final bool isManager;

  const AppUser({
    required this.id,
    required this.name,
    this.email,
    required this.role,
    this.roleId,
    this.preparationScreenId,
    this.avatar,
    required this.isManager,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = asString(json['role_code'] ?? json['role'], 'STAFF').toUpperCase();
    return AppUser(
      id: asString(json['id'] ?? json['user_id']),
      name: asString(json['name'], ''),
      email: asStringOrNull(json['email']),
      role: role,
      roleId: asStringOrNull(json['role_id']),
      preparationScreenId: asStringOrNull(json['preparation_screen_id']),
      avatar: AppConfig.assetUrl(asStringOrNull(json['avatar'])),
      isManager: json['is_manager'] != null
          ? asBool(json['is_manager'])
          : const {'OWNER', 'MANAGER', 'ADMIN', 'BUSINESS_MANAGER', 'ADMINISTRATOR', 'SUPER_ADMIN'}.contains(role),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'role_id': roleId,
        'preparation_screen_id': preparationScreenId,
        'avatar': avatar,
        'is_manager': isManager,
      };

  String get roleLabel => switch (role) {
        'OWNER' => 'İşletme Sahibi',
        'MANAGER' || 'BUSINESS_MANAGER' => 'Yönetici',
        'ADMIN' || 'ADMINISTRATOR' => 'Admin',
        'WAITER' => 'Garson',
        'KITCHEN' => 'Mutfak',
        'PREPARATION' => 'Hazırlık',
        'CASHIER' => 'Kasiyer',
        'COURIER' => 'Kurye',
        _ => role,
      };
}

class BusinessInfo {
  final String id;
  final String name;
  final String subdomain;
  final String? businessNumber;
  final String? logo;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? district;
  final String? country;
  final double? latitude;
  final double? longitude;
  final int? radius;

  const BusinessInfo({
    required this.id,
    required this.name,
    required this.subdomain,
    this.businessNumber,
    this.logo,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.district,
    this.country,
    this.latitude,
    this.longitude,
    this.radius,
  });

  factory BusinessInfo.fromJson(Map<String, dynamic> json) => BusinessInfo(
        id: asString(json['id'] ?? json['business_id'] ?? json['customer_id']),
        name: asString(json['name'] ?? json['company_name'], 'İşletme'),
        subdomain: asString(json['subdomain']),
        businessNumber: asStringOrNull(json['business_number']),
        logo: AppConfig.assetUrl(asStringOrNull(json['logo'] ?? json['logo_path'])),
        phone: asStringOrNull(json['phone']),
        email: asStringOrNull(json['email']),
        address: asStringOrNull(json['address']),
        city: asStringOrNull(json['city']),
        district: asStringOrNull(json['district']),
        country: asStringOrNull(json['country']),
        latitude: json['latitude'] != null ? asDouble(json['latitude']) : null,
        longitude: json['longitude'] != null ? asDouble(json['longitude']) : null,
        radius: json['radius'] != null || json['location_radius'] != null
            ? asInt(json['radius'] ?? json['location_radius'])
            : null,
      );

  BusinessInfo copyWith({
    String? id,
    String? name,
    String? subdomain,
    String? businessNumber,
    String? logo,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? district,
    String? country,
    double? latitude,
    double? longitude,
    int? radius,
  }) =>
      BusinessInfo(
        id: id ?? this.id,
        name: name ?? this.name,
        subdomain: subdomain ?? this.subdomain,
        businessNumber: businessNumber ?? this.businessNumber,
        logo: logo ?? this.logo,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        city: city ?? this.city,
        district: district ?? this.district,
        country: country ?? this.country,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radius: radius ?? this.radius,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subdomain': subdomain,
        'business_number': businessNumber,
        'logo': logo,
        'phone': phone,
        'email': email,
        'address': address,
        'city': city,
        'district': district,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      };
}

// ─── Menü ──────────────────────────────────────────────────

class MenuCategory {
  final String categoryId;
  final String name;
  final String? description;
  final int displayOrder;
  final int itemCount;

  const MenuCategory({
    required this.categoryId,
    required this.name,
    this.description,
    this.displayOrder = 0,
    this.itemCount = 0,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        categoryId: asString(json['category_id'] ?? json['id']),
        name: asString(json['name'] ?? json['category_name'], 'Kategori'),
        description: asStringOrNull(json['description']),
        displayOrder: asInt(json['display_order']),
        itemCount: json['items'] is List ? (json['items'] as List).length : asInt(json['item_count']),
      );
}

class MenuItemModel {
  final String menuItemId;
  final String name;
  final String? description;
  final double price;
  final Map<String, double>? prices;
  final String categoryId;
  final String? categoryName;
  final String? imageUrl;
  final bool isAvailable;
  final bool hasVariants;
  final List<Map<String, dynamic>> variants;
  final List<String> ingredients;
  final List<Map<String, dynamic>> extras;
  final int stock;
  final bool trackStock;

  const MenuItemModel({
    required this.menuItemId,
    required this.name,
    this.description,
    required this.price,
    this.prices,
    required this.categoryId,
    this.categoryName,
    this.imageUrl,
    this.isAvailable = true,
    this.hasVariants = false,
    this.variants = const [],
    this.ingredients = const [],
    this.extras = const [],
    this.stock = 0,
    this.trackStock = false,
  });

  String formatPrice({String currency = 'TRY'}) {
    final cur = currency.split(' ').first.toUpperCase();
    if (prices != null && prices!.containsKey(cur)) {
      return CurrencyHelper.format(prices![cur]!, currency: cur);
    }
    return CurrencyHelper.format(price, currency: cur);
  }

  factory MenuItemModel.fromJson(Map<String, dynamic> json, {String? categoryName}) {
    List<String> ingredientNames(dynamic v) {
      if (v is List) {
        return v.map((e) => e is Map ? asString(e['name']) : e.toString()).where((e) => e.isNotEmpty).toList();
      }
      return asStringList(v);
    }

    Map<String, double>? parsePrices(dynamic v) {
      if (v == null) return null;
      if (v is String && v.isNotEmpty) {
        try {
          final decoded = jsonDecode(v);
          return parsePrices(decoded);
        } catch (_) {}
      }
      if (v is Map) {
        final Map<String, double> res = {};
        final p = v['prices'] is Map ? v['prices'] as Map : v;
        p.forEach((k, val) {
          final d = double.tryParse('$val');
          if (d != null) res[k.toString().toUpperCase()] = d;
        });
        return res.isNotEmpty ? res : null;
      }
      return null;
    }

    return MenuItemModel(
      menuItemId: asString(json['menu_item_id'] ?? json['id']),
      name: asString(json['name'], 'Ürün'),
      description: asStringOrNull(json['description']),
      price: asDouble(json['price']),
      prices: parsePrices(json['prices_json'] ?? json['prices']),
      categoryId: asString(json['category_id']),
      categoryName: categoryName ?? asStringOrNull(json['category_name']),
      imageUrl: AppConfig.assetUrl(asStringOrNull(json['image_url'] ?? json['image'])),
      isAvailable: asBool(json['is_available'], true),
      hasVariants: asBool(json['has_variants']),
      variants: asMapList(json['variants']),
      ingredients: ingredientNames(json['ingredients']),
      extras: asMapList(json['available_extras'] ?? json['extras']),
      stock: asInt(json['stock']),
      trackStock: asBool(json['track_stock']),
    );
  }

  MenuItemModel copyWith({
    bool? isAvailable,
    double? price,
    Map<String, double>? prices,
    String? name,
    String? description,
  }) => MenuItemModel(
        menuItemId: menuItemId,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        prices: prices ?? this.prices,
        categoryId: categoryId,
        categoryName: categoryName,
        imageUrl: imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        hasVariants: hasVariants,
        variants: variants,
        ingredients: ingredients,
        extras: extras,
        stock: stock,
        trackStock: trackStock,
      );
}

// ─── Personel ──────────────────────────────────────────────

class StaffMember {
  final String userId;
  final String name;
  final String role;
  final String? roleId;
  final String? email;
  final String? phone;
  final String? avatar;
  final bool isActive;
  final String? preparationScreenId;
  final String? createdAt;

  const StaffMember({
    required this.userId,
    required this.name,
    required this.role,
    this.roleId,
    this.email,
    this.phone,
    this.avatar,
    this.isActive = true,
    this.preparationScreenId,
    this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        userId: asString(json['user_id'] ?? json['id']),
        name: asString(json['name'], 'Personel'),
        role: asString(json['role'], 'WAITER').toUpperCase(),
        roleId: asStringOrNull(json['role_id']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        avatar: AppConfig.assetUrl(asStringOrNull(json['avatar'])),
        isActive: asBool(json['is_active'], true),
        preparationScreenId: asStringOrNull(json['preparation_screen_id']),
        createdAt: asStringOrNull(json['created_at']),
      );

  String get roleLabel => switch (role) {
        'WAITER' => 'Garson',
        'KITCHEN' => 'Mutfak',
        'CASHIER' => 'Kasiyer',
        'PREPARATION' => 'Hazırlık',
        'BUSINESS_MANAGER' || 'MANAGER' => 'Yönetici',
        'ADMIN' || 'ADMINISTRATOR' => 'Admin',
        'COURIER' => 'Kurye',
        'CAYCI' => 'Çaycı',
        _ => role,
      };
}

class RoleOption {
  final String roleId;
  final String roleName;
  final String roleCode;

  const RoleOption({required this.roleId, required this.roleName, required this.roleCode});

  factory RoleOption.fromJson(Map<String, dynamic> json) => RoleOption(
        roleId: asString(json['role_id']),
        roleName: asString(json['role_name'] ?? json['name']),
        roleCode: asString(json['role_code'] ?? json['code']).toUpperCase(),
      );
}

// ─── Rezervasyon ───────────────────────────────────────────

class ReservationModel {
  final String reservationId;
  final String? tableId;
  final String? tableName;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final int partySize;
  final String status;
  final String? notes;
  final String? specialRequests;

  const ReservationModel({
    required this.reservationId,
    this.tableId,
    this.tableName,
    required this.customerName,
    required this.customerPhone,
    this.customerEmail,
    required this.date,
    required this.time,
    required this.partySize,
    this.status = 'confirmed',
    this.notes,
    this.specialRequests,
  });

  factory ReservationModel.fromJson(Map<String, dynamic> json) => ReservationModel(
        reservationId: asString(json['reservation_id'] ?? json['id']),
        tableId: asStringOrNull(json['table_id']),
        tableName: asStringOrNull(json['table_name']),
        customerName: asString(json['customer_name'], 'Misafir'),
        customerPhone: asString(json['customer_phone'] ?? json['contact']),
        customerEmail: asStringOrNull(json['customer_email']),
        date: asString(json['date']).length >= 10 ? asString(json['date']).substring(0, 10) : asString(json['date']),
        time: asString(json['time']).length >= 5 ? asString(json['time']).substring(0, 5) : asString(json['time']),
        partySize: asInt(json['party_size'] ?? json['guests'], 2),
        status: asString(json['status'], 'confirmed').toLowerCase(),
        notes: asStringOrNull(json['notes']),
        specialRequests: asStringOrNull(json['special_requests']),
      );

  DateTime? get dateTime => DateTime.tryParse('${date}T${time.length == 5 ? '$time:00' : time}');
}

// ─── Kampanya ──────────────────────────────────────────────

class CampaignModel {
  final String campaignId;
  final String title;
  final String? description;
  final String discountType; // percentage | fixed | bogo | other
  final double discountValue;
  final String? startsAt;
  final String? endsAt;
  final List<String> validDays;
  final String? validFromTime;
  final String? validUntilTime;
  final String appliesTo;
  final List<String> targetIds;
  final bool isActive;
  final String status; // active | scheduled | expired | inactive
  final int usageCount;

  const CampaignModel({
    required this.campaignId,
    required this.title,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.startsAt,
    this.endsAt,
    this.validDays = const [],
    this.validFromTime,
    this.validUntilTime,
    this.appliesTo = 'all',
    this.targetIds = const [],
    this.isActive = true,
    this.status = 'active',
    this.usageCount = 0,
  });

  factory CampaignModel.fromJson(Map<String, dynamic> json) => CampaignModel(
        campaignId: asString(json['campaign_id'] ?? json['id']),
        title: asString(json['title'], 'Kampanya'),
        description: asStringOrNull(json['description']),
        discountType: asString(json['discount_type'], 'percentage'),
        discountValue: asDouble(json['discount_value']),
        startsAt: asStringOrNull(json['starts_at']),
        endsAt: asStringOrNull(json['ends_at']),
        validDays: asStringList(json['valid_days']),
        validFromTime: asStringOrNull(json['valid_from_time']),
        validUntilTime: asStringOrNull(json['valid_until_time']),
        appliesTo: asString(json['applies_to'], 'all'),
        targetIds: asStringList(json['target_ids']),
        isActive: asBool(json['is_active'], true),
        status: asString(json['status'], 'active'),
        usageCount: asInt(json['usage_count']),
      );

  String get discountLabel => switch (discountType) {
        'percentage' => '%${discountValue.toStringAsFixed(discountValue.truncateToDouble() == discountValue ? 0 : 1)}',
        'fixed' => '₺${discountValue.toStringAsFixed(0)}',
        'bogo' => '1 Alana 1',
        _ => 'Özel',
      };
}

// ─── Ayarlar ───────────────────────────────────────────────

class WorkingHour {
  final String day; // mon..sun
  final String open; // HH:MM
  final String close; // HH:MM
  final bool closed;

  const WorkingHour({required this.day, required this.open, required this.close, this.closed = false});

  factory WorkingHour.fromJson(Map<String, dynamic> json) => WorkingHour(
        day: asString(json['day']).toLowerCase(),
        open: asString(json['open'] ?? json['start'], '09:00'),
        close: asString(json['close'] ?? json['end'], '23:00'),
        closed: asBool(json['closed'] ?? json['is_closed']),
      );

  Map<String, dynamic> toJson() => {'day': day, 'open': open, 'close': close, 'closed': closed};
}

class BusinessSettings {
  final String currency;
  final double serviceChargeRate;
  final double coverCharge;
  final String? wifiName;
  final String? wifiPassword;
  final bool wifiPasswordMasked;
  final bool showWifiToCustomer;
  final List<WorkingHour> workingHours;
  final String? workingHoursStart;
  final String? workingHoursEnd;
  final bool approvalRequired;
  final String? approvalRole;
  final int version;

  const BusinessSettings({
    this.currency = 'TRY',
    this.serviceChargeRate = 0,
    this.coverCharge = 0,
    this.wifiName,
    this.wifiPassword,
    this.wifiPasswordMasked = false,
    this.showWifiToCustomer = false,
    this.workingHours = const [],
    this.workingHoursStart,
    this.workingHoursEnd,
    this.approvalRequired = false,
    this.approvalRole,
    this.version = 1,
  });

  factory BusinessSettings.fromJson(Map<String, dynamic> settings, {int version = 1}) => BusinessSettings(
        currency: asString(settings['currency'], 'TRY'),
        serviceChargeRate: asDouble(settings['service_charge_rate']),
        coverCharge: asDouble(settings['cover_charge']),
        wifiName: asStringOrNull(settings['wifi_name']),
        wifiPassword: asStringOrNull(settings['wifi_password']),
        wifiPasswordMasked: asBool(settings['wifi_password_masked']),
        showWifiToCustomer: asBool(settings['show_wifi_to_customer']),
        workingHours: asMapList(settings['working_hours']).map(WorkingHour.fromJson).toList(),
        workingHoursStart: asStringOrNull(settings['working_hours_start']),
        workingHoursEnd: asStringOrNull(settings['working_hours_end']),
        approvalRequired: asBool(settings['approval_required']),
        approvalRole: asStringOrNull(settings['approval_role']),
        version: version,
      );
}

class BusinessProfile {
  final String id;
  final String name;
  final String subdomain;
  final String address;
  final String phone;
  final String email;
  final String taxNumber;
  final String taxOffice;
  final double? latitude;
  final double? longitude;
  final int radius;

  const BusinessProfile({
    this.id = '',
    this.name = '',
    this.subdomain = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.taxNumber = '',
    this.taxOffice = '',
    this.latitude,
    this.longitude,
    this.radius = 200,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) => BusinessProfile(
        id: asString(json['id']),
        name: asString(json['name']),
        subdomain: asString(json['subdomain']),
        address: asString(json['address']),
        phone: asString(json['phone']),
        email: asString(json['email']),
        taxNumber: asString(json['tax_number']),
        taxOffice: asString(json['tax_office']),
        latitude: json['latitude'] != null ? asDouble(json['latitude']) : null,
        longitude: json['longitude'] != null ? asDouble(json['longitude']) : null,
        radius: asInt(json['radius'] ?? json['location_radius'], 200),
      );
}

// ─── Bildirim ──────────────────────────────────────────────

class NotificationModel {
  final String notificationId;
  final String type;
  final String? tableId;
  final String? tableName;
  final bool isRead;
  final Map<String, dynamic> data;
  final String createdAt;

  const NotificationModel({
    required this.notificationId,
    required this.type,
    this.tableId,
    this.tableName,
    this.isRead = false,
    this.data = const {},
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        notificationId: asString(json['notification_id'] ?? json['id']),
        type: asString(json['type'], 'INFO').toUpperCase(),
        tableId: asStringOrNull(json['table_id']),
        tableName: asStringOrNull(json['table_name']),
        isRead: asBool(json['is_read']),
        data: asMap(json['data']),
        createdAt: asString(json['created_at'] ?? json['timestamp']),
      );

  String get title => switch (type) {
        'CALL_WAITER' => 'Garson Çağrısı',
        'REQUEST_BILL' => 'Hesap İsteği',
        'NEW_ORDER' => 'Yeni Sipariş',
        'ORDER_READY' => 'Sipariş Hazır',
        'KITCHEN_ISSUE' => 'Mutfak Sorunu',
        'NEW_DELIVERY' => 'Yeni Paket Sipariş',
        'EDIT_APPROVAL' => 'Onay Bekliyor',
        _ => asString(data['title'], 'Bildirim'),
      };

  String get body {
    final msg = asStringOrNull(data['message'] ?? data['body']);
    if (msg != null) return msg;
    final table = tableName != null ? '$tableName · ' : '';
    return switch (type) {
      'CALL_WAITER' => '${table}Müşteri garson çağırıyor',
      'REQUEST_BILL' => '${table}Müşteri hesap istiyor',
      'NEW_ORDER' => '${table}Yeni sipariş alındı',
      'ORDER_READY' => '${table}Sipariş servise hazır',
      'KITCHEN_ISSUE' => '${table}Mutfak bir sorun bildirdi',
      'EDIT_APPROVAL' => '${table}Sipariş değişikliği onay bekliyor',
      _ => tableName ?? '',
    };
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        notificationId: notificationId,
        type: type,
        tableId: tableId,
        tableName: tableName,
        isRead: isRead ?? this.isRead,
        data: data,
        createdAt: createdAt,
      );
}

// ─── Finans ────────────────────────────────────────────────

class ExpenseModel {
  final String expenseId;
  final String title;
  final double amount;
  final String? category;
  final String date;
  final String? sourceType;

  const ExpenseModel({
    required this.expenseId,
    required this.title,
    required this.amount,
    this.category,
    required this.date,
    this.sourceType,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) => ExpenseModel(
        expenseId: asString(json['expense_id'] ?? json['id']),
        title: asString(json['title'] ?? json['description'], 'Gider'),
        amount: json['amount_minor'] != null ? asInt(json['amount_minor']) / 100 : asDouble(json['amount']),
        category: asStringOrNull(json['category']),
        date: asString(json['date']),
        sourceType: asStringOrNull(json['source_type']),
      );
}

class InvoiceModel {
  final String invoiceId;
  final String? supplierId;
  final double amount;
  final String date;
  final String? dueDate;
  final bool isPaid;
  final List<Map<String, dynamic>> items;

  const InvoiceModel({
    required this.invoiceId,
    this.supplierId,
    required this.amount,
    required this.date,
    this.dueDate,
    this.isPaid = false,
    this.items = const [],
  });

  factory InvoiceModel.fromJson(Map<String, dynamic> json) => InvoiceModel(
        invoiceId: asString(json['invoice_id'] ?? json['id']),
        supplierId: asStringOrNull(json['supplier_id']),
        amount: json['amount_minor'] != null ? asInt(json['amount_minor']) / 100 : asDouble(json['amount']),
        date: asString(json['date']),
        dueDate: asStringOrNull(json['due_date']),
        isPaid: asBool(json['is_paid']),
        items: asMapList(json['items']),
      );
}

class SupplierModel {
  final String supplierId;
  final String name;
  final String? phone;
  final String? email;
  final String? category;

  const SupplierModel({required this.supplierId, required this.name, this.phone, this.email, this.category});

  factory SupplierModel.fromJson(Map<String, dynamic> json) => SupplierModel(
        supplierId: asString(json['supplier_id'] ?? json['id']),
        name: asString(json['name'] ?? json['supplier_name'], 'Tedarikçi'),
        phone: asStringOrNull(json['phone']),
        email: asStringOrNull(json['email']),
        category: asStringOrNull(json['category']),
      );
}

class ReceiptModel {
  final String receiptId;
  final String receiptNumber;
  final String? orderId;
  final String? tableId;
  final String? tableName;
  final double totalAmount;
  final double taxAmount;
  final double serviceCharge;
  final double discountAmount;
  final String paymentMethod;
  final String receiptType;
  final String status;
  final String createdAt;
  final List<Map<String, dynamic>> items;

  const ReceiptModel({
    required this.receiptId,
    required this.receiptNumber,
    this.orderId,
    this.tableId,
    this.tableName,
    required this.totalAmount,
    this.taxAmount = 0,
    this.serviceCharge = 0,
    this.discountAmount = 0,
    this.paymentMethod = 'CASH',
    this.receiptType = 'FULL',
    this.status = 'ACTIVE',
    required this.createdAt,
    this.items = const [],
  });

  factory ReceiptModel.fromJson(Map<String, dynamic> json) => ReceiptModel(
        receiptId: asString(json['receipt_id'] ?? json['id']),
        receiptNumber: asString(json['receipt_number'] ?? json['receipt_id']),
        orderId: asStringOrNull(json['order_id']),
        tableId: asStringOrNull(json['table_id']),
        tableName: asStringOrNull(json['table_name']),
        totalAmount: asDouble(json['total_amount'] ?? json['total']),
        taxAmount: asDouble(json['tax_amount']),
        serviceCharge: asDouble(json['service_charge']),
        discountAmount: asDouble(json['discount_amount']),
        paymentMethod: asString(json['payment_method'], 'CASH').toUpperCase(),
        receiptType: asString(json['receipt_type'], 'FULL'),
        status: asString(json['status'], 'ACTIVE'),
        createdAt: asString(json['created_at'] ?? json['payment_time']),
        items: asMapList(json['items']),
      );

  String get paymentLabel => switch (paymentMethod) {
        'CASH' => 'Nakit',
        'CARD' || 'CREDIT_CARD' => 'Kredi Kartı',
        'QR' => 'QR Ödeme',
        'MIXED' => 'Karışık',
        'PENDING' => 'Bekliyor',
        _ => paymentMethod,
      };
}

// ─── Stok ──────────────────────────────────────────────────

class StockItemModel {
  final String itemId;
  final String itemType;
  final String name;
  final String unit;
  final double currentStock;
  final double? minThreshold;
  final String status; // OK | LOW_STOCK | OUT_OF_STOCK
  final String statusLabel;
  final String? category;

  const StockItemModel({
    required this.itemId,
    required this.itemType,
    required this.name,
    required this.unit,
    required this.currentStock,
    this.minThreshold,
    this.status = 'OK',
    this.statusLabel = '',
    this.category,
  });

  factory StockItemModel.fromJson(Map<String, dynamic> json) => StockItemModel(
        itemId: asString(json['item_id'] ?? json['id']),
        itemType: asString(json['item_type'], 'MENU_ITEM'),
        name: asString(json['name'], 'Ürün'),
        unit: asString(json['unit'], 'ADET'),
        currentStock: asDouble(json['current_stock'] ?? json['quantity']),
        minThreshold: json['min_threshold'] != null ? asDouble(json['min_threshold']) : null,
        status: asString(json['status'], 'OK').toUpperCase(),
        statusLabel: asString(json['status_label']),
        category: asStringOrNull(json['category']),
      );

  double get percentage {
    final threshold = minThreshold ?? 0;
    if (threshold <= 0) return currentStock > 0 ? 1.0 : 0.0;
    return (currentStock / (threshold * 2)).clamp(0.0, 1.0);
  }

  bool get isLow => status == 'LOW_STOCK' || status == 'OUT_OF_STOCK';
}

// ─── Abonelik ──────────────────────────────────────────────

class SubscriptionStatus {
  final bool hasSubscription;
  final String phase;
  final int daysLeft;
  final bool readOnly;
  final String status;
  final bool isTrial;
  final String packageName;
  final String? currentPeriodEnd;
  final String? currentPeriodStart;
  final String? billingCycle;
  final double amount;
  final String currency;
  final String? subscriptionId;
  final String? packageId;
  final List<String> features;

  const SubscriptionStatus({
    this.hasSubscription = false,
    this.phase = 'unknown',
    this.daysLeft = 0,
    this.readOnly = false,
    this.status = '',
    this.isTrial = false,
    this.packageName = '',
    this.currentPeriodEnd,
    this.currentPeriodStart,
    this.billingCycle,
    this.amount = 0,
    this.currency = 'TRY',
    this.subscriptionId,
    this.packageId,
    this.features = const [],
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final sub = asMap(json['subscription']);
    final rawFeatures = json['features'] as List? ?? sub['features'] as List?;
    return SubscriptionStatus(
      hasSubscription: asBool(json['has_subscription']),
      phase: asString(json['phase'], 'unknown'),
      daysLeft: asInt(json['daysLeft'] ?? json['days_left']),
      readOnly: asBool(json['readOnly'] ?? json['read_only']),
      status: asString(json['status']),
      isTrial: asBool(json['isTrial'] ?? json['is_trial']),
      packageName: asString(json['packageName'] ?? sub['package_name'], 'Paket'),
      currentPeriodEnd: asStringOrNull(json['currentPeriodEnd'] ?? sub['current_period_end']),
      currentPeriodStart: asStringOrNull(sub['current_period_start']),
      billingCycle: asStringOrNull(sub['billing_cycle']),
      amount: asDouble(sub['amount']),
      currency: asString(sub['currency'], 'TRY'),
      subscriptionId: asStringOrNull(sub['subscription_id']),
      packageId: asStringOrNull(sub['package_id']),
      features: rawFeatures?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  String get phaseLabel => switch (phase) {
        'active' => 'Aktif',
        'trial' => 'Deneme',
        'grace_period' || 'grace' => 'Ödeme Bekleniyor',
        'expired' => 'Süresi Doldu',
        'suspended' => 'Askıda',
        'cancelled' => 'İptal Edildi',
        _ => phase,
      };
}

class PackageModel {
  final String packageId;
  final String name;
  final String? description;
  final double priceMonthly;
  final double priceYearly;
  final double discountedMonthly;
  final double discountedYearly;
  final String currency;
  final int maxUsers;
  final int maxTables;
  final int maxMenuItems;
  final List<String> features;
  final bool isFeatured;

  const PackageModel({
    required this.packageId,
    required this.name,
    this.description,
    required this.priceMonthly,
    required this.priceYearly,
    required this.discountedMonthly,
    required this.discountedYearly,
    this.currency = 'TRY',
    this.maxUsers = 0,
    this.maxTables = 0,
    this.maxMenuItems = 0,
    this.features = const [],
    this.isFeatured = false,
  });

  factory PackageModel.fromJson(Map<String, dynamic> json) => PackageModel(
        packageId: asString(json['package_id'] ?? json['id']),
        name: asString(json['name'] ?? json['package_name'], 'Paket'),
        description: asStringOrNull(json['description']),
        priceMonthly: asDouble(json['price_monthly']),
        priceYearly: asDouble(json['price_yearly']),
        discountedMonthly: asDouble(json['discounted_price_monthly'] ?? json['price_monthly']),
        discountedYearly: asDouble(json['discounted_price_yearly'] ?? json['price_yearly']),
        currency: asString(json['currency'], 'TRY'),
        maxUsers: asInt(json['max_users']),
        maxTables: asInt(json['max_tables']),
        maxMenuItems: asInt(json['max_menu_items']),
        features: asStringList(json['features']),
        isFeatured: asBool(json['is_featured']),
      );
}

// ─── Analitik ──────────────────────────────────────────────

class AnalyticsData {
  final int totalOrders;
  final double totalRevenue;
  final int paidOrders;
  final int cancelledOrders;
  final int pendingOrders;
  final int readyOrders;
  final int occupiedTables;
  final int totalTables;
  final int staffCount;
  final double avgOrderValue;
  final double completionRate;
  final double occupancyRate;
  final double totalTips;
  final List<Map<String, dynamic>> topItems;
  final List<Map<String, dynamic>> hourlyDistribution;
  final List<Map<String, dynamic>> paymentBreakdown;
  final List<Map<String, dynamic>> recentOrders;
  final List<Map<String, dynamic>> dailyTrend;
  final String period;
  final String startDate;
  final String endDate;

  const AnalyticsData({
    this.totalOrders = 0,
    this.totalRevenue = 0,
    this.paidOrders = 0,
    this.cancelledOrders = 0,
    this.pendingOrders = 0,
    this.readyOrders = 0,
    this.occupiedTables = 0,
    this.totalTables = 0,
    this.staffCount = 0,
    this.avgOrderValue = 0,
    this.completionRate = 0,
    this.occupancyRate = 0,
    this.totalTips = 0,
    this.topItems = const [],
    this.hourlyDistribution = const [],
    this.paymentBreakdown = const [],
    this.recentOrders = const [],
    this.dailyTrend = const [],
    this.period = 'today',
    this.startDate = '',
    this.endDate = '',
  });

  factory AnalyticsData.fromJson(Map<String, dynamic> json) => AnalyticsData(
        totalOrders: asInt(json['total_orders'] ?? json['order_count']),
        totalRevenue: asDouble(json['total_revenue'] ?? json['revenue']),
        paidOrders: asInt(json['paid_orders']),
        cancelledOrders: asInt(json['cancelled_orders']),
        pendingOrders: asInt(json['pending_orders']),
        readyOrders: asInt(json['ready_orders']),
        occupiedTables: asInt(json['occupied_tables'] ?? json['active_tables']),
        totalTables: asInt(json['total_tables']),
        staffCount: asInt(json['staff_count']),
        avgOrderValue: asDouble(json['avg_order_value']),
        completionRate: asDouble(json['completion_rate']),
        occupancyRate: asDouble(json['occupancy_rate']),
        totalTips: asDouble(json['total_tips']),
        topItems: asMapList(json['top_items']),
        hourlyDistribution: asMapList(json['hourly_distribution']),
        paymentBreakdown: asMapList(json['payment_breakdown']),
        recentOrders: asMapList(json['recent_orders']),
        dailyTrend: asMapList(json['daily_trend']),
        period: asString(json['period'], 'today'),
        startDate: asString(json['start_date']),
        endDate: asString(json['end_date']),
      );
}

class ZReport {
  final String date;
  final int totalOrders;
  final int paidOrders;
  final int cancelledOrders;
  final double totalRevenue;
  final double avgOrderValue;
  final List<Map<String, dynamic>> paymentBreakdown;

  const ZReport({
    required this.date,
    this.totalOrders = 0,
    this.paidOrders = 0,
    this.cancelledOrders = 0,
    this.totalRevenue = 0,
    this.avgOrderValue = 0,
    this.paymentBreakdown = const [],
  });

  factory ZReport.fromJson(Map<String, dynamic> json) => ZReport(
        date: asString(json['date']),
        totalOrders: asInt(json['total_orders']),
        paidOrders: asInt(json['paid_orders']),
        cancelledOrders: asInt(json['cancelled_orders']),
        totalRevenue: asDouble(json['total_revenue']),
        avgOrderValue: asDouble(json['avg_order_value']),
        paymentBreakdown: asMapList(json['payment_breakdown']),
      );
}

class ProductSales {
  final List<Map<String, dynamic>> productTotals;
  final List<Map<String, dynamic>> categoryTotals;
  final List<Map<String, dynamic>> top10;
  final int totalQuantity;
  final double totalRevenue;
  final int totalProducts;

  const ProductSales({
    this.productTotals = const [],
    this.categoryTotals = const [],
    this.top10 = const [],
    this.totalQuantity = 0,
    this.totalRevenue = 0,
    this.totalProducts = 0,
  });

  factory ProductSales.fromJson(Map<String, dynamic> json) {
    final summary = asMap(json['summary']);
    return ProductSales(
      productTotals: asMapList(json['product_totals']),
      categoryTotals: asMapList(json['category_totals']),
      top10: asMapList(json['top_10_products']),
      totalQuantity: asInt(summary['total_quantity']),
      totalRevenue: asDouble(summary['total_revenue']),
      totalProducts: asInt(summary['total_products']),
    );
  }
}
