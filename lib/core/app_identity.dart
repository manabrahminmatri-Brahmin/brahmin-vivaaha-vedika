// 🔥 APP IDENTITY - Single Identity Manager
// Loaded once at startup, used everywhere
// NO identity confusion anywhere in the app

import 'package:cloud_firestore/cloud_firestore.dart';
import 'contract.dart';
import 'result.dart';

/// AppIdentity - Cached user identity for entire app session
class AppIdentity {
  // The three IDs (NEVER use any other ID)
  final String authUid; // Firebase Auth UID
  final String userDocId; // users/{docId} Firestore document ID
  final String profileId; // Public visible member ID

  // Metadata
  final String? email;
  final String? phone;
  final DateTime loadedAt;

  AppIdentity._({
    required this.authUid,
    required this.userDocId,
    required this.profileId,
    this.email,
    this.phone,
  }) : loadedAt = DateTime.now();

  bool get isValid =>
      authUid.isNotEmpty && userDocId.isNotEmpty && profileId.isNotEmpty;

  static String _profileIdOrProvisional(
    Map<String, dynamic> data,
    String userDocId,
  ) {
    final profileId = data[Fields.profileId] as String? ?? '';
    if (profileId.isNotEmpty) return profileId;

    // Legacy rows may be valid for discovery without `profile_id` or stale
    // `is_profile_complete`. Never return empty — fall back to the doc id so
    // session recovery and routing keep working until IDs are backfilled.
    return userDocId;
  }

  /// Factory: Load identity from Firestore using auth UID
  static Future<Result<AppIdentity>> load(String authUid) async {
    if (authUid.isEmpty) {
      return Result.error(
        'not-authenticated',
        'No authentication UID provided',
      );
    }

    try {
      final db = FirebaseFirestore.instance;

      // Query user by auth_uid field (not document ID)
      final snapshot = await db
          .collection(Collections.users)
          .where(Fields.authUid, isEqualTo: authUid)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return Result.error(
          'user-not-found',
          'User document not found for auth UID',
        );
      }

      final doc = snapshot.docs.first;
      final data = doc.data();
      final userDocId = doc.id;
      final profileId = _profileIdOrProvisional(data, userDocId);

      if (profileId.isEmpty) {
        return Result.error(
          'invalid-data',
          'User missing profile ID',
        );
      }

      return Result.success(AppIdentity._(
        authUid: authUid,
        userDocId: userDocId,
        profileId: profileId,
        email: data['email'] as String?,
        phone: data['phone'] as String?,
      ));
    } on FirebaseException catch (e) {
      return Result.error(
        e.code,
        'Failed to load identity: ${e.message}',
        rawError: e,
      );
    } catch (e) {
      return Result.error(
        'unknown',
        'Unexpected error loading identity: $e',
        rawError: e,
      );
    }
  }

  /// Load identity from Firestore using user document ID
  static Future<Result<AppIdentity>> loadByUserId(
      String userId, String authUid) async {
    try {
      final db = FirebaseFirestore.instance;

      // Get user document by ID
      final doc = await db.collection(Collections.users).doc(userId).get();

      if (!doc.exists) {
        return Result.error(
          'user-not-found',
          'User document not found',
        );
      }

      final data = doc.data() as Map<String, dynamic>;
      final profileId = _profileIdOrProvisional(data, userId);

      if (profileId.isEmpty) {
        return Result.error(
          'invalid-data',
          'User missing profile ID',
        );
      }

      return Result.success(AppIdentity._(
        authUid: authUid,
        userDocId: userId,
        profileId: profileId,
        email: data['email'] as String?,
        phone: data['phone'] as String?,
      ));
    } on FirebaseException catch (e) {
      return Result.error(
        e.code,
        'Failed to load identity: ${e.message}',
        rawError: e,
      );
    } catch (e) {
      return Result.error(
        'unknown',
        'Unexpected error loading identity: $e',
        rawError: e,
      );
    }
  }

  /// Factory: Create from known values (e.g., cached)
  static AppIdentity fromValues({
    required String authUid,
    required String userDocId,
    required String profileId,
    String? email,
    String? phone,
  }) {
    return AppIdentity._(
      authUid: authUid,
      userDocId: userDocId,
      profileId: profileId,
      email: email,
      phone: phone,
    );
  }

  @override
  String toString() {
    return 'AppIdentity{authUid: $authUid, userDocId: $userDocId, profileId: $profileId}';
  }
}

/// IdentityProvider - Global identity access
class IdentityProvider {
  static AppIdentity? _current;
  static final _listeners = <void Function(AppIdentity?)>[];

  static AppIdentity? get current => _current;
  static bool get hasIdentity => _current != null && _current!.isValid;

  static String get authUid => _current?.authUid ?? '';
  static String get userDocId => _current?.userDocId ?? '';
  static String get profileId => _current?.profileId ?? '';

  static void setIdentity(AppIdentity? identity) {
    _current = identity;
    for (final listener in _listeners) {
      listener(identity);
    }
  }

  static void clear() {
    _current = null;
    for (final listener in _listeners) {
      listener(null);
    }
  }

  static void addListener(void Function(AppIdentity?) listener) {
    _listeners.add(listener);
  }

  static void removeListener(void Function(AppIdentity?) listener) {
    _listeners.remove(listener);
  }
}
