class ApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final Map<String, dynamic>? payload;

  const ApiException(
    this.message, {
    this.code,
    this.statusCode,
    this.payload,
  });

  bool get isUnauthorized => statusCode == 401 || code == 'TOKEN_EXPIRED' || code == 'TOKEN_INVALID';
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isReadOnly => code == 'READ_ONLY' || code == 'DEMO_READ_ONLY';
  bool get isNetwork => statusCode == null;
  bool get isNotImplemented => statusCode == 501;

  @override
  String toString() => message;
}
