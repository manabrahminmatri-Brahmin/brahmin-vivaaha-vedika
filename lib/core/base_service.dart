import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base service class with common functionality
/// Provides consistent error handling, retry logic, and logging
abstract class BaseService {
  final SharedPreferences _prefs;
  
  BaseService(this._prefs);
  
  /// Get SharedPreferences instance
  SharedPreferences get prefs => _prefs;
  
  /// Retry mechanism for network operations
  Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(dynamic error)? shouldRetry,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries) {
          rethrow;
        }
        
        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }
        
        debugPrint('⚠️ $runtimeType: Attempt $attempt failed, retrying in ${delay.inSeconds}s: $e');
        await Future.delayed(delay * attempt); // Exponential backoff
      }
    }
    throw Exception('Operation failed after $maxRetries attempts');
  }
  
  /// Check if error is network related
  bool isNetworkError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return error is SocketException ||
           errorString.contains('socketexception') ||
           errorString.contains('failed host lookup') ||
           errorString.contains('network is unreachable') ||
           errorString.contains('connection refused') ||
           errorString.contains('timeout') ||
           errorString.contains('connection timed out') ||
           errorString.contains('no internet');
  }
  
  /// Get user-friendly error message for Firebase operations
  String getUserFriendlyError(dynamic error) {
    if (isNetworkError(error)) {
      return 'Network error. Please check your internet connection and try again.';
    }
    
    final errorString = error.toString().toLowerCase();
    
    // Firebase Auth errors
    if (errorString.contains('permission-denied') || 
        errorString.contains('permission denied') ||
        errorString.contains('insufficient permissions')) {
      return 'Permission denied. Please sign in again or contact support.';
    }
    
    // Firestore errors
    if (errorString.contains('not-found') || 
        errorString.contains('document not found') ||
        errorString.contains('no document to update')) {
      return 'Data not found. Please refresh and try again.';
    }
    
    // Firebase Auth specific errors
    if (errorString.contains('user-not-found') || errorString.contains('user disabled')) {
      return 'Account not found or disabled. Please contact support.';
    }
    
    if (errorString.contains('wrong-password') || errorString.contains('invalid-credentials')) {
      return 'Invalid credentials. Please check and try again.';
    }
    
    if (errorString.contains('email-already-in-use') || errorString.contains('already exists')) {
      return 'This email/mobile is already registered. Please sign in instead.';
    }
    
    if (errorString.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    
    if (errorString.contains('invalid-email')) {
      return 'Invalid email address. Please check and try again.';
    }
    
    if (errorString.contains('weak-password')) {
      return 'Password is too weak. Please use a stronger password.';
    }
    
    // Firestore transaction errors
    if (errorString.contains('transaction') && errorString.contains('failed')) {
      return 'Database operation failed. Please try again.';
    }
    
    if (errorString.contains('already-exists')) {
      return 'This data already exists. Please check and try again.';
    }
    
    // Timeout errors
    if (errorString.contains('deadline exceeded') || errorString.contains('timeout')) {
      return 'Operation timed out. Please check your connection and try again.';
    }
    
    // Rate limiting
    if (errorString.contains('resource-exhausted') || errorString.contains('quota exceeded')) {
      return 'Service temporarily busy. Please try again in a moment.';
    }
    
    return 'Operation failed: ${error.toString()}';
  }
  
  /// Log debug information
  void logDebug(String message) {
    if (kDebugMode) {
      debugPrint('🔍 $runtimeType: $message');
    }
  }
  
  /// Log error information
  void logError(String message, [dynamic error, StackTrace? stackTrace]) {
    debugPrint('❌ $runtimeType: $message');
    if (error != null) {
      debugPrint('❌ $runtimeType: Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('❌ $runtimeType: Stack trace: $stackTrace');
    }
  }
  
  /// Log success information
  void logSuccess(String message) {
    debugPrint('✅ $runtimeType: $message');
  }
  
  /// Validate required fields
  void validateRequired(Map<String, dynamic> data, List<String> requiredFields) {
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null || data[field].toString().isEmpty) {
        throw ArgumentError('Required field missing: $field');
      }
    }
  }
  
  /// Clean and validate mobile number
  String cleanMobileNumber(String mobile) {
    var clean = mobile.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.length > 10 && clean.startsWith('91')) {
      clean = clean.substring(2);
    }
    return clean;
  }
  
  /// Validate mobile number format
  bool isValidMobileNumber(String mobile) {
    final clean = cleanMobileNumber(mobile);
    return clean.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(clean);
  }
  
  /// Validate email format
  bool isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }
}
