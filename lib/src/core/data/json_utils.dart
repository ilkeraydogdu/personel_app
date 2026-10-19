import 'dart:convert';

/// JSON alanlarını güvenle dönüştüren yardımcılar.
/// Sunucu sayısal alanları bazen string ("270.00"), bazen sayı döner.
int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.round() ?? fallback;
}

double asDouble(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  if (s == '1' || s == 'true' || s == 'yes') return true;
  if (s == '0' || s == 'false' || s == 'no' || s == '') return false;
  return fallback;
}

String asString(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List<String> asStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String && v.isNotEmpty) {
    // JSON string veya CSV
    if (v.startsWith('[')) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

DateTime? asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}
