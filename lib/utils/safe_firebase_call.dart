import 'package:flutter/foundation.dart';

/// Guard Firestore/Firebase operations from crashing UI flows.
Future<T?> safeFirebaseCall<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e, s) {
    debugPrint('🔥 Firebase Error: $e');
    debugPrint('$s');
    return null;
  }
}
