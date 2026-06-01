import 'package:flutter/foundation.dart';

/// Centralized error handling utility for consistent error management
class AppErrorHandler {
  static void logError(String context, String error, {String? stackTrace}) {
    if (kDebugMode) {
      debugPrint('🚨 ERROR [$context]: $error');
      if (stackTrace != null) {
        debugPrint('📍 Stack trace: $stackTrace');
      }
    }
  }

  static void logWarning(String context, String warning) {
    if (kDebugMode) {
      debugPrint('⚠️ WARNING [$context]: $warning');
    }
  }

  static void logInfo(String context, String message) {
    if (kDebugMode) {
      debugPrint('ℹ️ INFO [$context]: $message');
    }
  }

  static void logSuccess(String context, String message) {
    if (kDebugMode) {
      debugPrint('✅ SUCCESS [$context]: $message');
    }
  }

  static String getErrorMessage(dynamic error) {
    if (error == null) return 'Unknown error occurred';
    
    if (error.toString().contains('permission-denied')) {
      return 'Permission denied. Please check your settings and try again.';
    }
    
    if (error.toString().contains('not-found')) {
      return 'Data not found. Please refresh and try again.';
    }
    
    if (error.toString().contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    }
    
    if (error.toString().contains('network')) {
      return 'Network error. Please check your internet connection.';
    }
    
    return error.toString();
  }

  static bool shouldRetry(dynamic error) {
    if (error == null) return false;
    
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
           errorStr.contains('network') ||
           errorStr.contains('connection');
  }
}
