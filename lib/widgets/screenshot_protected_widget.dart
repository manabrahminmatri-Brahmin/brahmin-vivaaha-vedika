import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

/// Utility class to block screenshots and screen recording
class ScreenshotBlocker {
  static const MethodChannel _channel = MethodChannel('com.manavivaahavedika/screenshot');

  /// Enable screenshot blocking for the current screen
  /// This prevents screenshots and screen recordings on Android
  static Future<void> blockScreenshots() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _channel.invokeMethod('blockScreenshots');
      }
      // Note: iOS doesn't support blocking screenshots directly
      // Screenshots can only be detected, not prevented
    } catch (e) {
      // Silently fail if platform channel is not available
      debugPrint('Screenshot blocking not available: $e');
    }
  }

  /// Disable screenshot blocking (allow screenshots again)
  static Future<void> allowScreenshots() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _channel.invokeMethod('allowScreenshots');
      }
    } catch (e) {
      // Silently fail
      debugPrint('Screenshot unblocking not available: $e');
    }
  }
}

/// Mixin to protect a StatefulWidget from screenshots
/// 
/// Usage:
/// ```dart
/// class MyScreen extends StatefulWidget {
///   @override
///   State<MyScreen> createState() => _MyScreenState();
/// }
/// 
/// class _MyScreenState extends State<MyScreen> with ScreenshotProtection {
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(...);
///   }
/// }
/// ```
mixin ScreenshotProtection<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenshotBlocker.blockScreenshots();
  }

  @override
  void dispose() {
    ScreenshotBlocker.allowScreenshots();
    super.dispose();
  }
}

