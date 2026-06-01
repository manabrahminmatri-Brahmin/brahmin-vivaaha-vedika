import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

abstract final class DeviceSecurityAnalytics {
  DeviceSecurityAnalytics._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static Future<void> logCompromisedDeviceDetected({
    bool limitedMode = false,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'compromised_device_detected',
        parameters: {
          'limited_mode': limitedMode ? 1 : 0,
        },
      );
    } catch (e) {
      debugPrint('DeviceSecurityAnalytics: $e');
    }
  }
}
