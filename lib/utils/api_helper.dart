import 'package:flutter/foundation.dart';

/// Safe API Call Wrapper - Production Ready
/// 
/// Prevents app crashes from API errors and centralizes error handling.
/// 
/// Usage:
/// final profiles = await safeApiCall(() => authService.getMatchingProfiles());
/// 
/// Returns null on error, allowing graceful fallback handling.
Future<T?> safeApiCall<T>(
  Future<T> Function() apiCall, {
  String? operationName,
  bool logErrors = true,
}) async {
  try {
    return await apiCall();
  } catch (e, stackTrace) {
    if (logErrors) {
      debugPrint('🚨 API Error${operationName != null ? " in $operationName" : ""}: $e');
      debugPrint('📍 Stack trace: $stackTrace');
    }
    
    // In production, you could send this to crash reporting service
    if (kReleaseMode && operationName != null) {
      // Example: FirebaseCrashlytics.instance.recordError(e, stackTrace);
    }
    
    return null;
  }
}

/// Safe API Call with fallback value
/// 
/// Similar to safeApiCall but returns a fallback value instead of null.
/// 
/// Usage:
/// final profiles = await safeApiCallWithFallback(
///   () => authService.getMatchingProfiles(),
///   fallback: [],
/// );
Future<T> safeApiCallWithFallback<T>(
  Future<T> Function() apiCall, {
  required T fallback,
  String? operationName,
  bool logErrors = true,
}) async {
  try {
    return await apiCall();
  } catch (e, stackTrace) {
    if (logErrors) {
      debugPrint('🚨 API Error${operationName != null ? " in $operationName" : ""}: $e');
      debugPrint('📍 Stack trace: $stackTrace');
    }
    
    // In production, you could send this to crash reporting service
    if (kReleaseMode && operationName != null) {
      // Example: FirebaseCrashlytics.instance.recordError(e, stackTrace);
    }
    
    return fallback;
  }
}

/// Batch API Call Wrapper
/// 
/// Executes multiple API calls safely and returns results.
/// Useful for parallel operations where some calls might fail.
/// 
/// Usage:
/// final results = await safeBatchCall([
///   () => authService.getProfile(),
///   () => filterService.getFilters(),
/// ]);
Future<List<T?>> safeBatchCall<T>(
  List<Future<T> Function()> apiCalls, {
  String? operationName,
  bool logErrors = true,
}) async {
  final results = <T?>[];
  
  for (int i = 0; i < apiCalls.length; i++) {
    try {
      final result = await apiCalls[i]();
      results.add(result);
    } catch (e, stackTrace) {
      if (logErrors) {
        debugPrint('🚨 Batch API Error${operationName != null ? " in $operationName" : ""} [${i + 1}/${apiCalls.length}]: $e');
        debugPrint('📍 Stack trace: $stackTrace');
      }
      results.add(null);
    }
  }
  
  return results;
}
