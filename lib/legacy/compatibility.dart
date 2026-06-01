// Legacy Compatibility Layer
// Re-exports services for screens that import from legacy/compatibility.dart.
// This file bridges old imports to the new architecture.

// ── Straightforward re-exports ──────────────────────────────────────────────
export '../services/auth_service.dart' show AuthService;
export '../services/filter_service.dart' show FilterService;

// The REAL LikeService / InterestService (registered by main.dart as Providers).
// Screens that call context.select<LikeService, ...> or context.read<InterestService>()
// need the same concrete type that MultiProvider registers.
export '../services/like_service_v2.dart' show LikeService;
export '../services/interest_service_v2.dart' show InterestService;

// AnalyticsService is the canonical analytics implementation.
export '../features/profile/analytics_service.dart' show AnalyticsService;

// FirestoreClient lives in data/ so that NotificationRepository can import it.
export '../data/firestore_client.dart' show FirestoreClient;

// ── Dart/Flutter imports needed by classes defined below ────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../features/profile/analytics_service.dart';
import '../core/contract.dart';
import '../core/backend/firestore_service.dart';

// ── ProfileAnalyticsService ─────────────────────────────────────────────────
// Alias pointing at the real AnalyticsService so that screens that use
// Consumer<ProfileAnalyticsService> or context.read<ProfileAnalyticsService>()
// resolve to the same provider that main.dart registers as AnalyticsService.
typedef ProfileAnalyticsService = AnalyticsService;

// ── Exception types ──────────────────────────────────────────────────────────

class LikeWriteException implements Exception {
  final String message;
  final String code;
  LikeWriteException(this.message, {this.code = 'unknown'});
  @override
  String toString() => 'LikeWriteException: $message (code: $code)';
}

class InterestException implements Exception {
  final String message;
  final String code;
  InterestException(this.message, {this.code = 'unknown'});
  @override
  String toString() => 'InterestException: $message (code: $code)';
}

// ── FirebaseService ──────────────────────────────────────────────────────────
/// Compatibility wrapper. Prefer FirestoreRepository for new code.
class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static FirebaseFirestore get firestore => _db;
  static CollectionReference collection(String path) => _db.collection(path);
  static DocumentReference doc(String path) => _db.doc(path);

  /// Look up by Firestore doc-id, falls back to profile_id/auth_uid query.
  Future<User?> getUserByAnyId(String id) async {
    debugPrint('🔧 FirebaseService.getUserByAnyId($id)');
    try {
      final snap = await _db.collection(Collections.users).doc(id).get();
      if (snap.exists && snap.data() != null) {
        return User.fromFirestore(snap.data()!, snap.id);
      }
      final byProfile = await getUserByProfileId(id);
      if (byProfile != null) return byProfile;
      final byAuthUid = await _db
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: id)
          .limit(1)
          .get();
      if (byAuthUid.docs.isNotEmpty) {
        return User.fromFirestore(
          byAuthUid.docs.first.data(),
          byAuthUid.docs.first.id,
        );
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ getUserByAnyId error: $e');
      return null;
    }
  }

  /// Look up by Firestore document ID.
  Future<User?> getUserById(String id) async {
    debugPrint('🔧 FirebaseService.getUserById($id)');
    try {
      final snap = await _db.collection(Collections.users).doc(id).get();
      if (snap.exists && snap.data() != null) {
        return User.fromFirestore(snap.data()!, snap.id);
      }
    } catch (e) {
      debugPrint('⚠️ getUserById error: $e');
    }
    return null;
  }

  /// Look up by profile_id field value.
  Future<User?> getUserByProfileId(String profileId) async {
    debugPrint('🔧 FirebaseService.getUserByProfileId($profileId)');
    try {
      final q = await _db
          .collection(Collections.users)
          .where('profile_id', isEqualTo: profileId)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        return User.fromFirestore(q.docs.first.data(), q.docs.first.id);
      }
    } catch (e) {
      debugPrint('⚠️ getUserByProfileId error: $e');
    }
    return null;
  }

  /// Delegates to [FirestoreService] (incognito filtering, alias resolution, dedup).
  Stream<List<Map<String, dynamic>>> profileViewersStream(String streamId) =>
      FirestoreService().profileViewersStream(streamId);

  Future<void> updateUserProfile(
      String userId, Map<String, dynamic> data) async {
    await _db
        .collection(Collections.users)
        .doc(userId)
        .set(data, SetOptions(merge: true));
  }

  /// [userId] – Firestore doc id
  /// [profileId] – current profile_id value
  /// [gender] – gender prefix string
  Future<String?> updateProfileIdGenderPrefix(
    String userId,
    String profileId,
    String gender,
  ) async {
    debugPrint(
        '🔧 [STUB] updateProfileIdGenderPrefix($userId, $profileId, $gender)');
    return null;
  }

  Future<List<Map<String, dynamic>>> getMembershipPlans() async => [];
}
