// 🔥 RESULT WRAPPER - Never throw raw errors to UI
// Every service/repository operation returns Result<T>

class Result<T> {
  final bool success;
  final T? data;
  final String errorCode;
  final String message;
  final dynamic rawError;

  Result._({
    required this.success,
    this.data,
    this.errorCode = '',
    this.message = '',
    this.rawError,
  });

  // Success factory
  factory Result.success(T data, {String message = 'Success'}) {
    return Result._(
      success: true,
      data: data,
      message: message,
    );
  }

  // Error factory
  factory Result.error(String errorCode, String message, {dynamic rawError}) {
    return Result._(
      success: false,
      errorCode: errorCode,
      message: message,
      rawError: rawError,
    );
  }

  // Convenience getters
  bool get isSuccess => success;
  bool get isError => !success;
  T get requireData => data!;

  // Map success value
  Result<R> map<R>(R Function(T) transform) {
    if (success && data != null) {
      return Result.success(transform(data as T));
    }
    return Result<R>._(
      success: false,
      errorCode: errorCode,
      message: message,
      rawError: rawError,
    );
  }

  // FlatMap for chaining
  Result<R> flatMap<R>(Result<R> Function(T) transform) {
    if (success && data != null) {
      return transform(data as T);
    }
    return Result<R>._(
      success: false,
      errorCode: errorCode,
      message: message,
      rawError: rawError,
    );
  }

  @override
  String toString() {
    return 'Result{success: $success, errorCode: $errorCode, message: $message}';
  }
}

/// Void result for operations with no return value
typedef VoidResult = Result<void>;

/// Extension for easier error handling
extension ResultExtensions<T> on Result<T> {
  void when({
    required void Function(T data) success,
    required void Function(String errorCode, String message) error,
  }) {
    if (this.success && data != null) {
      success(data as T);
    } else {
      error(errorCode, message);
    }
  }

  T? getOrNull() => success ? data : null;

  T getOrElse(T defaultValue) => success && data != null ? data as T : defaultValue;
}
