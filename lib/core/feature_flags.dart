import 'package:flutter/foundation.dart';

// 🔥 FEATURE FLAGS - Control V2 rollout safely
// Prevents double writes/listeners during migration

class FeatureFlags {
  /// Use new LikeServiceV2 (repository pattern)
  static bool useLikesV2 = true;  // 🔥 ENABLED FOR V2 MIGRATION TESTING
  
  /// Use new InterestServiceV2 (repository pattern)
  static bool useInterestsV2 = false;
  
  /// Use new NotificationServiceV2
  static bool useNotificationsV2 = false;
  
  /// Use FirestoreRepository for all Firestore access
  static bool useRepositoryPattern = false;
  
  /// Use centralized error handling
  static bool useErrorFirewall = true;
  
  /// Use AppIdentity for all identity access
  static bool useAppIdentity = true;
  
  /// Enable `Result<T>` pattern everywhere.
  static bool useResultPattern = false;
  
  /// Enable batch profile fetching (N+1 fix)
  static bool useBatchProfileFetch = true;
  
  /// Show technical error details (debug only)
  static bool showTechnicalErrors = false;
  
  /// Log all Firestore operations
  static bool logFirestoreOperations = true;
  
  /// Enable all V2 features at once (USE CAREFULLY)
  static void enableAllV2() {
    useLikesV2 = true;
    useInterestsV2 = true;
    useNotificationsV2 = true;
    useRepositoryPattern = true;
    useResultPattern = true;
  }
  
  /// Reset to safe defaults (for testing)
  static void resetToDefaults() {
    useLikesV2 = false;
    useInterestsV2 = false;
    useNotificationsV2 = false;
    useRepositoryPattern = false;
    useErrorFirewall = true;
    useAppIdentity = true;
    useResultPattern = false;
    useBatchProfileFetch = true;
    showTechnicalErrors = false;
    logFirestoreOperations = true;
  }
  
  /// Print current flag state
  static void printStatus() {
    debugPrint('🔧 Feature Flags:');
    debugPrint('  useLikesV2: $useLikesV2');
    debugPrint('  useInterestsV2: $useInterestsV2');
    debugPrint('  useNotificationsV2: $useNotificationsV2');
    debugPrint('  useRepositoryPattern: $useRepositoryPattern');
    debugPrint('  useErrorFirewall: $useErrorFirewall');
    debugPrint('  useAppIdentity: $useAppIdentity');
    debugPrint('  useResultPattern: $useResultPattern');
    debugPrint('  useBatchProfileFetch: $useBatchProfileFetch');
  }
}
