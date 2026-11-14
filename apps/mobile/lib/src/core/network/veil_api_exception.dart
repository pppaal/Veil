class VeilApiException implements Exception {
  VeilApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

String? extractVeilApiErrorCode(Object error) {
  if (error is VeilApiException) {
    return error.code;
  }
  return null;
}
