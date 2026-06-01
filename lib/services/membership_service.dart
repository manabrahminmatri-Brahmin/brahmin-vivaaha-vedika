import 'package:flutter/foundation.dart';

/// Service for managing user memberships and premium features
/// Note: This service is deprecated and should not be used
/// Use FirebaseService directly instead
class MembershipService extends ChangeNotifier {
  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal() {
    debugPrint('⚠️ MembershipService is deprecated. Use FirebaseService directly.');
  }

  /// Compatibility getter - always returns false since service is deprecated
  bool get isPremium => false;
}
