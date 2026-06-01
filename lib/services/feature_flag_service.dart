import 'package:flutter/foundation.dart';

/// A/B Testing and Feature Flag service for gradual rollouts
/// Note: This service is deprecated and should not be used
/// Use FirebaseService directly instead
class FeatureFlagService extends ChangeNotifier {
  static final FeatureFlagService _instance = FeatureFlagService._internal();
  factory FeatureFlagService() => _instance;
  FeatureFlagService._internal() {
    throw Exception('FeatureFlagService is deprecated. Use FirebaseService directly instead.');
  }
}
