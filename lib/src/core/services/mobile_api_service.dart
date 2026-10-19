import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_model.dart';
import '../network/api_client.dart';
import '../../features/business/data/order_model.dart';
import '../../features/business/data/table_model.dart';
import 'api_service.dart';

class MobileApiService {
  final ApiService api;

  MobileApiService(this.api);

  String _normalizePath(String path) {
    if (path.startsWith('/api/mobile/')) {
      return path.substring('/api/mobile'.length);
    }
    return path;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    return ApiClient.instance.post(_normalizePath(path), data: data);
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    return ApiClient.instance.get(_normalizePath(path), query: query);
  }

 // Auth

 Future<Map<String, dynamic>> staffLogin({
 required String email,
 required String password,
 String? subdomain,
 }) async {
 return post('/api/mobile/staff/login', {
 'email': email,
 'password': password,
 if (subdomain != null) 'subdomain': subdomain,
 });
 }

 Future<Map<String, dynamic>> refreshToken() async {
 return post('/api/mobile/refresh-token', {});
 }

 Future<Map<String, dynamic>> wsToken() async {
 return post('/api/mobile/ws-token', {});
 }

 // Dashboard

 Future<DashboardData> getStaffDashboard({String period = 'today'}) async {
 final response = await get('/api/mobile/staff/dashboard', query: {'period': period});
 if (response['success'] == true && response['data'] != null) {
 return DashboardModel.fromJson(response).data;
 }
 throw Exception(response['error'] ?? 'Dashboard yüklenemedi');
 }

 // Orders

 Future<List<OrderModel>> getOrders({String? period, String? status}) async {
 final query = <String, dynamic>{};
 if (period != null) query['period'] = period;
 if (status != null) query['status'] = status;

 final response = await get('/api/mobile/orders', query: query.isNotEmpty ? query : null);
 if (response['success'] == true && response['data'] != null) {
 final orders = (response['data']['orders'] as List<dynamic>? ?? []);
 return orders.map((e) => OrderModel.fromJson(e)).toList();
 }
 throw Exception(response['error'] ?? 'Siparişler yüklenemedi');
 }

 Future<bool> updateOrderStatus({required String orderId, required String status}) async {
 final response = await post('/api/mobile/orders/status', {
 'order_id': orderId,
 'status': status,
 });
 return response['success'] == true;
 }

 // Tables

 Future<List<ZoneModel>> getTables() async {
 final response = await get('/api/mobile/tables');
 if (response['success'] == true && response['data'] != null) {
 final zones = (response['data']['zones'] as List<dynamic>? ?? []);
 return zones.map((e) => ZoneModel.fromJson(e)).toList();
 }
 throw Exception(response['error'] ?? 'Masalar yüklenemedi');
 }

 // Menu

 Future<List<Map<String, dynamic>>> getMenu() async {
 final response = await get('/api/mobile/menu');
 if (response['success'] == true && response['data'] != null) {
 final categories = response['data']['categories'] as List<dynamic>? ?? [];
 final items = response['data']['items'] as List<dynamic>? ?? [];
 return [
 ...categories.map((e) => Map<String, dynamic>.from(e)),
 ...items.map((e) => Map<String, dynamic>.from(e)),
 ];
 }
 throw Exception(response['error'] ?? 'Menü yüklenemedi');
 }

 Future<List<Map<String, dynamic>>> getMenuItemIngredients(String itemId) async {
 final response = await get('/api/mobile/menu/item-ingredients', query: {'item_id': itemId});
 if (response['success'] == true && response['data'] != null) {
 return List<Map<String, dynamic>>.from(response['data']);
 }
 return [];
 }

 // Analytics

 Future<Map<String, dynamic>> getAnalytics({String period = 'today'}) async {
 final response = await get('/api/mobile/manager/analytics', query: {'period': period});
 if (response['success'] == true && response['data'] != null) {
 return response['data'] as Map<String, dynamic>;
 }
 throw Exception(response['error'] ?? 'Analiz yüklenemedi');
 }

 Future<List<Map<String, dynamic>>> getStaffList() async {
 final response = await get('/api/mobile/manager/staff');
 if (response['success'] == true && response['data'] != null) {
 final staff = response['data']['staff'] as List<dynamic>? ?? [];
 return staff.map((e) => Map<String, dynamic>.from(e)).toList();
 }
 return [];
 }

 Future<List<Map<String, dynamic>>> getStockList() async {
 final response = await get('/api/mobile/stock-list');
 if (response['success'] == true && response['data'] != null) {
 final items = response['data'] as List<dynamic>? ?? [];
 return items.map((e) => Map<String, dynamic>.from(e)).toList();
 }
 return [];
 }

 Future<Map<String, dynamic>> processPayment({
 String? tableId,
 String? orderId,
 required String paymentMethod,
 required double amount,
 double? cardAmount,
 double? cashAmount,
 }) async {
 return post('/api/mobile/pos/process-payment', {
 if (tableId != null) 'table_id': tableId,
 if (orderId != null) 'order_id': orderId,
 'payment_method': paymentMethod,
 'amount': amount,
 if (cardAmount != null) 'card_amount': cardAmount,
 if (cashAmount != null) 'cash_amount': cashAmount,
 });
 }

 // Receipts & Print

 Future<Map<String, dynamic>> printAdisyon({
 String? tableId,
 String? orderId,
 }) async {
 final body = <String, dynamic>{};
 if (tableId != null && tableId.isNotEmpty) body['table_id'] = tableId;
 if (orderId != null && orderId.isNotEmpty) body['order_id'] = orderId;
 return post('/api/mobile/pos/print-adisyon', body);
 }

 Future<List<Map<String, dynamic>>> getReceipts({String? period}) async {
 final query = <String, dynamic>{};
 if (period != null) query['period'] = period;
 final response = await get('/api/mobile/receipts', query: query.isNotEmpty ? query : null);
 if (response['success'] == true && response['data'] != null) {
 final list = response['data']['receipts'] as List<dynamic>? ?? response['data'] as List<dynamic>? ?? [];
 return list.map((e) => Map<String, dynamic>.from(e)).toList();
 }
 throw Exception(response['error'] ?? 'Fişler yüklenemedi');
 }

 Future<Map<String, dynamic>> getReceiptDetail(String receiptId) async {
 final response = await get('/api/mobile/receipts/$receiptId');
 if (response['success'] == true && response['data'] != null) {
 return response['data'] as Map<String, dynamic>;
 }
 throw Exception(response['error'] ?? 'Fiş detayı yüklenemedi');
 }
}

final mobileApiProvider = Provider<MobileApiService>((ref) {
 return MobileApiService(ApiService());
});
