/// Authentication result wrapper for API responses
class AuthResult {
  final bool success;
  final String message;
  final dynamic data;
  final String? errorCode;

  AuthResult._(this.success, this.message, {this.data, this.errorCode});

  factory AuthResult.success(String message, {dynamic data}) {
    return AuthResult._(true, message, data: data);
  }

  factory AuthResult.failure(String message, {String? errorCode}) {
    return AuthResult._(false, message, errorCode: errorCode);
  }

  @override
  String toString() {
    return 'AuthResult(success: $success, message: $message, errorCode: $errorCode)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthResult &&
        other.success == success &&
        other.message == message &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode {
    return success.hashCode ^ message.hashCode ^ errorCode.hashCode;
  }
}
