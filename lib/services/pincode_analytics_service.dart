import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics events for profile-wizard PIN → location autofill.
abstract final class PinCodeAnalyticsService {
  PinCodeAnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static Future<void> logInvalidPin() => _log('invalid_pin');

  static Future<void> logNetworkTimeout() => _log('network_timeout');

  static Future<void> logMalformedResponse() => _log('malformed_response');

  static Future<void> logUnknownFailure() => _log('pin_lookup_unknown');

  /// User set country/state/city without a completed 6-digit PIN lookup.
  static Future<void> logManualLocationEntry() => _log('manual_location_entry');

  /// Successful autofill from local cache (offline-friendly).
  static Future<void> logCacheHit({required String source}) => _log(
        'pin_lookup_cache_hit',
        {'source': source},
      );

  /// Successful autofill after network response (cached for next time).
  static Future<void> logNetworkSuccess() => _log('pin_lookup_network_success');

  static Future<void> _log(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('PinCodeAnalyticsService: $name failed: $e');
    }
  }
}
