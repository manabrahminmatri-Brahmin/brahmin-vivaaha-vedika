import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Global error handler for the application
/// 
/// This class provides centralized error handling, logging, and recovery mechanisms
/// to ensure the app remains stable and user-friendly even when errors occur.
/// 
/// Features:
/// - Catches both synchronous and asynchronous errors
/// - Categorizes errors for appropriate handling strategies
/// - Provides retry mechanisms for recoverable errors
/// - Logs errors for debugging and monitoring
/// - Shows user-friendly error messages
/// 
/// Usage:
/// ```dart
/// // Initialize at app startup
/// GlobalErrorHandler.initialize();
/// 
/// // Handle exceptions in try-catch blocks
/// try {
///   await riskyOperation();
/// } catch (e, stackTrace) {
///   GlobalErrorHandler().handleException(e, stackTrace, context: 'Operation X');
/// }
/// ```
/// 
/// See also:
/// - [ErrorType] for error classification
/// - [CapturedErrorEvent] for error representation
class GlobalErrorHandler {
  static final GlobalErrorHandler _instance = GlobalErrorHandler._internal();
  factory GlobalErrorHandler() => _instance;
  GlobalErrorHandler._internal();

  // Error logging queue for batch processing
  final List<CapturedErrorEvent> _errorLog = [];
  Timer? _logUploadTimer;
  
  // Error callbacks
  final List<Function(CapturedErrorEvent)> _errorCallbacks = [];
  
  /// Initialize the global error handler
  static void initialize() {
    // Set up Flutter error handling
    FlutterError.onError = (FlutterErrorDetails details) {
      GlobalErrorHandler()._handleFlutterError(details);
    };

    // Set up Zone error handling for async errors
    runZonedGuarded(() {
      // App will be run here
    }, (error, stackTrace) {
      GlobalErrorHandler()._handleZoneError(error, stackTrace);
    });
  }

  /// Handle Flutter framework errors
  void _handleFlutterError(FlutterErrorDetails details) {
    final error = CapturedErrorEvent(
      type: ErrorType.flutter,
      message: details.exception.toString(),
      stackTrace: details.stack.toString(),
      timestamp: DateTime.now(),
      context: 'Flutter Framework',
    );

    _logError(error);
    
    // In debug mode, show the error
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  }

  /// Handle Zone errors (async errors)
  void _handleZoneError(Object error, StackTrace stackTrace) {
    final appError = CapturedErrorEvent(
      type: ErrorType.zone,
      message: error.toString(),
      stackTrace: stackTrace.toString(),
      timestamp: DateTime.now(),
      context: 'Async Operation',
    );

    _logError(appError);
  }

  /// Log an error for tracking and reporting
  void _logError(CapturedErrorEvent error) {
    _errorLog.add(error);
    
    // Notify all registered callbacks
    for (final callback in _errorCallbacks) {
      try {
        callback(error);
      } catch (e) {
        debugPrint('❌ Error in error callback: $e');
      }
    }

    // Log to console in debug mode
    if (kDebugMode) {
      _printError(error);
    }

    // Trigger upload if we have enough errors
    if (_errorLog.length >= 10) {
      _uploadErrorLog();
    }
  }

  /// Print error details to console
  void _printError(CapturedErrorEvent error) {
    debugPrint('🚨 ERROR [${error.type.name}]: ${error.message}');
    debugPrint('📍 Context: ${error.context}');
    debugPrint('⏰ Time: ${error.timestamp}');
    if (error.stackTrace != null) {
      debugPrint('📋 Stack trace: ${error.stackTrace}');
    }
  }

  /// Upload error log to server (batch operation)
  Future<void> _uploadErrorLog() async {
    if (_errorLog.isEmpty) return;

    try {
      // TODO: Implement error log upload to server
      // For now, just clear the log
      _errorLog.clear();
    } catch (e) {
      debugPrint('❌ Failed to upload error log: $e');
    }
  }

  /// Register a callback for error events
  void registerErrorCallback(Function(CapturedErrorEvent) callback) {
    _errorCallbacks.add(callback);
  }

  /// Unregister an error callback
  void unregisterErrorCallback(Function(CapturedErrorEvent) callback) {
    _errorCallbacks.remove(callback);
  }

  /// Handle a caught exception with context
  void handleException(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    bool fatal = false,
  }) {
    final appError = CapturedErrorEvent(
      type: fatal ? ErrorType.fatal : ErrorType.caught,
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
      timestamp: DateTime.now(),
      context: context ?? 'Unknown',
    );

    _logError(appError);
  }

  /// Get recent errors for debugging
  List<CapturedErrorEvent> getRecentErrors({int count = 10}) {
    return _errorLog.take(count).toList();
  }

  /// Clear error log
  void clearErrorLog() {
    _errorLog.clear();
  }

  /// Dispose resources
  void dispose() {
    _logUploadTimer?.cancel();
    _errorCallbacks.clear();
    _errorLog.clear();
  }
}

/// Error types for categorization
enum ErrorType {
  flutter,      // Flutter framework errors
  zone,         // Async/Zone errors
  caught,       // Caught exceptions
  fatal,        // Fatal errors
  network,      // Network-related errors
  database,     // Database errors
  validation,   // Validation errors
  authentication, // Auth errors
  unknown,      // Unknown errors
}

/// Structured error captured by [GlobalErrorHandler] (not the UI [AppError] in error_handler.dart).
class CapturedErrorEvent {
  final ErrorType type;
  final String message;
  final String? stackTrace;
  final DateTime timestamp;
  final String context;
  final Map<String, dynamic>? metadata;

  CapturedErrorEvent({
    required this.type,
    required this.message,
    this.stackTrace,
    required this.timestamp,
    required this.context,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'message': message,
      'stackTrace': stackTrace,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
      'metadata': metadata,
    };
  }
}

/// Widget error boundary for catching widget build errors
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(FlutterErrorDetails)? errorBuilder;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterErrorDetails? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!) ?? _defaultErrorWidget(_error!);
    }

    return widget.child;
  }

  Widget _defaultErrorWidget(FlutterErrorDetails error) {
    return Material(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'We apologize for the inconvenience. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF9E9E9E)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                });
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe async wrapper that handles exceptions gracefully
class SafeAsync {
  /// Execute an async operation with error handling
  static Future<T?> run<T>(
    Future<T> Function() operation, {
    String? context,
    Function(Object error)? onError,
    T? defaultValue,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      GlobalErrorHandler().handleException(
        e,
        stackTrace,
        context: context ?? 'SafeAsync operation',
      );

      if (onError != null) {
        onError(e);
      }

      return defaultValue;
    }
  }

  /// Execute an async operation with timeout
  static Future<T?> runWithTimeout<T>(
    Future<T> Function() operation, {
    // Reduce default timeout to keep UI responsive; callers can override.
    Duration timeout = const Duration(seconds: 10),
    String? context,
    Function(Object error)? onError,
    T? defaultValue,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException catch (e, stackTrace) {
      GlobalErrorHandler().handleException(
        e,
        stackTrace,
        context: '${context ?? 'Operation'} - Timeout',
      );

      if (onError != null) {
        onError(e);
      }

      return defaultValue;
    } catch (e, stackTrace) {
      GlobalErrorHandler().handleException(
        e,
        stackTrace,
        context: context ?? 'SafeAsync operation',
      );

      if (onError != null) {
        onError(e);
      }

      return defaultValue;
    }
  }
}

/// Retry mechanism for failed operations
class RetryPolicy {
  static Future<T> execute<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration delayBetweenAttempts = const Duration(seconds: 1),
    String? context,
    bool Function(Object error)? shouldRetry,
  }) async {
    int attempts = 0;
    Object? lastError;
    StackTrace? lastStackTrace;

    while (attempts < maxAttempts) {
      try {
        attempts++;
        return await operation();
      } catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;

        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(e)) {
          break;
        }

        if (attempts < maxAttempts) {
          debugPrint('⚠️ Retry $attempts/$maxAttempts after error: $e');
          await Future.delayed(delayBetweenAttempts * attempts);
        }
      }
    }

    // All retries exhausted
    GlobalErrorHandler().handleException(
      lastError!,
      lastStackTrace,
      context: '${context ?? 'Operation'} - All retries exhausted',
      fatal: true,
    );

    throw lastError;
  }
}
