import 'package:flutter/foundation.dart';

/// Lightweight logger that does nothing in release mode.
class Log {
  static void d(Object message) {
    if (kDebugMode) debugPrint(message.toString());
  }

  static void w(Object message) {
    if (kDebugMode) debugPrint(message.toString());
  }

  static void e(Object message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    debugPrint(message.toString());
    if (error != null) debugPrint('error=$error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}

