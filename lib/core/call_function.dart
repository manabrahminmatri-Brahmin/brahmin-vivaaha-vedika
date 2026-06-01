/// Cloud Function wrapper for callable Firebase Functions
/// Provides type-safe interface for calling Cloud Functions
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'app_firebase_functions.dart';

/// Cloud Function operation
class CallFunction {
  final String functionName;
  final Map<String, dynamic> data;

  const CallFunction({
    required this.functionName,
    required this.data,
  });

  /// Execute Cloud Function
  Future<HttpsCallableResult> call() async {
    try {
      final functions = appFirebaseFunctions;
      debugPrint('🔥 CALLING CLOUD FUNCTION: $functionName with data: $data');
      
      final result = await functions.httpsCallable(functionName).call(data);
      
      debugPrint('✅ CLOUD FUNCTION COMPLETED: $functionName - Result: ${result.data}');
      return result;
    } catch (e) {
      debugPrint('❌ CLOUD FUNCTION FAILED: $functionName - Error: $e');
      rethrow;
    }
  }
}
