// 🔥 ERROR FIREWALL - Converts technical errors to user-friendly messages
// Central handler for ALL app errors

import 'package:flutter/foundation.dart';

import 'contract.dart';
import 'result.dart';

/// ErrorFirewall - Converts raw errors to safe UX messages
class ErrorFirewall {
  /// Convert any error to user-friendly message
  static String toUserMessage(dynamic error) {
    if (error is String) {
      return _mapErrorCode(error);
    }
    
    // Check for Firebase error patterns
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('permission-denied')) {
      return UiMessages.permissionDenied;
    }
    if (errorString.contains('not-found')) {
      return UiMessages.notFound;
    }
    if (errorString.contains('unauthenticated')) {
      return UiMessages.notAuthenticated;
    }
    if (errorString.contains('network') || 
        errorString.contains('socket') ||
        errorString.contains('connection')) {
      return UiMessages.networkError;
    }
    if (errorString.contains('timeout')) {
      return UiMessages.timeout;
    }
    
    return UiMessages.unknown;
  }

  /// Map error code to user message
  static String _mapErrorCode(String code) {
    switch (code) {
      case ErrorCodes.permissionDenied:
        return UiMessages.permissionDenied;
      case ErrorCodes.notFound:
        return UiMessages.notFound;
      case ErrorCodes.unauthenticated:
      case ErrorCodes.userNotFound:
        return UiMessages.notAuthenticated;
      case ErrorCodes.networkError:
      case ErrorCodes.unavailable:
        return UiMessages.networkError;
      case ErrorCodes.timeout:
      case ErrorCodes.deadlineExceeded:
        return UiMessages.timeout;
      default:
        return UiMessages.unknown;
    }
  }

  /// Process `Result<T>` and return safe display data.
  static Map<String, dynamic> processResult<T>(Result<T> result) {
    return {
      'success': result.success,
      'data': result.data,
      'showError': !result.success,
      'errorTitle': result.success ? null : 'Error',
      'errorMessage': result.success ? null : toUserMessage(result.errorCode),
      'canRetry': result.errorCode == ErrorCodes.networkError ||
                  result.errorCode == ErrorCodes.timeout ||
                  result.errorCode == ErrorCodes.unavailable,
    };
  }

  /// Show snackbar with safe message (no technical details)
  static void showError(dynamic error) {
    final message = toUserMessage(error);
    // This would integrate with your SnackbarService
    // For now, just print (replace with actual UI call)
    debugPrint('🔥 ERROR: $message');
  }

  /// Log error for debugging (keeps technical details)
  static void logError(dynamic error, {String? context}) {
    final prefix = context != null ? '[$context] ' : '';
    debugPrint('🔥 $prefix Technical Error: $error');
  }
}
