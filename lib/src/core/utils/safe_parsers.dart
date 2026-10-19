import 'dart:convert';

/// Safely extracts a List<dynamic> from any dynamic value (List, JSON String, comma-separated String, null, etc.)
List<dynamic> safeList(dynamic val) {
  if (val == null) return const [];
  if (val is List) return val;
  if (val is String) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) return decoded;
      } catch (_) {}
    } else if (trimmed.contains(',')) {
      return trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      return [trimmed];
    }
  }
  return const [];
}

/// Safely extracts a double from any dynamic value
double safeDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString().replaceAll(',', '.')) ?? fallback;
}

/// Safely extracts an int from any dynamic value
int safeInt(dynamic val, [int fallback = 0]) {
  if (val == null) return fallback;
  if (val is num) return val.toInt();
  return int.tryParse(val.toString()) ?? fallback;
}

/// Formats duration in minutes into a clean, human-readable format for restaurant operations:
/// - 0 or negative -> '<1 dk'
/// - 1..59 -> 'X dk'
/// - 60..719 -> 'H sa M dk' (or 'H sa' if M == 0)
/// - 720..1439 -> 'H sa'
/// - 1440+ -> '>24 sa' (stale session safeguard)
String formatDurationMinutes(int totalMinutes) {
  if (totalMinutes <= 0) return '<1 dk';
  if (totalMinutes < 60) return '$totalMinutes dk';
  final hours = totalMinutes ~/ 60;
  final mins = totalMinutes % 60;
  if (hours < 12) {
    return mins > 0 ? '$hours sa $mins dk' : '$hours sa';
  }
  if (hours < 24) {
    return '$hours sa';
  }
  return '>24 sa';
}
