import 'dart:async' show unawaited;

// 🔥 APP INITIALIZER - Proper startup flow
// Loads identity once, provides globally
// All services use cached identity

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_cache_read.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'app_identity.dart';
import 'identity_service.dart';
import 'result.dart';
import 'error_firewall.dart';
import 'contract.dart';
import '../services/block_service.dart';
import '../services/presence_service.dart';

/// AppInitializer - Handles app startup sequence
class AppInitializer {
  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// 🔥 CRITICAL: Verify and sync auth_uid for security rule compliance
  static Future<void> _verifyAndSyncAuthUid(String userId, String expectedAuthUid) async {
    try {
      final db = FirebaseFirestore.instance;
      final doc = await getDocumentCachedFirst(db.collection(Collections.users).doc(userId));
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final storedAuthUid = data['auth_uid'] as String? ?? 'NOT_FOUND';

        // Sync if mismatched (only log when we actually write or on anomaly)
        if (storedAuthUid != expectedAuthUid) {
          await db.collection(Collections.users).doc(userId).set({
            'auth_uid': expectedAuthUid,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint('✅ AppInitializer: auth_uid synced for $userId (was: $storedAuthUid)');
        }
      } else {
        debugPrint('⚠️ AppInitializer: user doc not found for $userId (auth_uid check)');
      }
    } catch (e) {
      debugPrint('⚠️ AppInitializer: auth_uid verify/sync failed — $e');
    }
  }

  /// 🔥 FALLBACK: Find user document ID by auth_uid when IdentityService is not available
  static Future<String> _findUserDocIdByAuthUid(String authUid) async {
    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: authUid)
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        final userId = snapshot.docs.first.id;
        debugPrint('🔍 FALLBACK: Found user doc $userId for auth_uid $authUid');
        return userId;
      }
      
      debugPrint('🔍 FALLBACK: No user doc found for auth_uid $authUid');
      return '';
    } catch (e) {
      debugPrint('🔍 FALLBACK: Error finding user doc - $e');
      return '';
    }
  }

  /// Fast path when identity was already loaded this session.
  static Future<Result<void>> ensureInitialized() async {
    if (_initialized && IdentityProvider.hasIdentity) {
      return Result.success(null, message: 'Already initialized');
    }
    return initialize();
  }

  /// Initialize app on login
  /// Call this immediately after successful authentication
  static Future<Result<void>> initialize() async {
    if (_initialized && IdentityProvider.hasIdentity) {
      return Result.success(null, message: 'Already initialized');
    }
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      
      if (authUser == null) {
        return Result.error(
          'not-authenticated',
          'No authenticated user',
        );
      }

      // 🔥 CRITICAL: Get Firebase Auth UID first (doesn't depend on IdentityService)
      final firebaseAuthUid = FirebaseAuth.instance.currentUser?.uid;
      if (firebaseAuthUid == null || firebaseAuthUid.isEmpty) {
        return Result.error(
          'not-authenticated',
          'No Firebase Auth session found',
        );
      }

      // Try to get user ID from IdentityService, fallback to direct lookup
      String userId = '';
      try {
        final identityService = IdentityService();
        userId = await identityService.getUserId();
      } catch (e) {
        debugPrint('⚠️ IdentityService not available, using fallback: $e');
        // Fallback: Find user document by auth_uid
        userId = await _findUserDocIdByAuthUid(firebaseAuthUid);
      }
      
      if (userId.isEmpty) {
        return Result.error(
          'not-authenticated',
          'No authenticated user found',
        );
      }
      
      // 🔥 CRITICAL: Verify and sync auth_uid before proceeding
      await _verifyAndSyncAuthUid(userId, firebaseAuthUid);
      
      // Load user document using proper user ID
      final identityResult = await AppIdentity.loadByUserId(userId, firebaseAuthUid);

      if (identityResult.isError) {
        ErrorFirewall.logError(
          identityResult.rawError,
          context: 'AppInitializer.initialize',
        );
        return Result.error(
          identityResult.errorCode,
          identityResult.message,
        );
      }

      // Set global identity
      IdentityProvider.setIdentity(identityResult.data);

      await BlockService.instance?.syncFromFirestore(blockerDocId: userId);

      // Presence must never block login; start in background.
      unawaited(() async {
        try {
          await PresenceService()
              .startTracking(firebaseAuthUid)
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('⚠️ AppInitializer: presence start skipped (non-fatal): $e');
        }
      }());

      _initialized = true;

      return Result.success(null, message: 'App initialized');

    } catch (e) {
      ErrorFirewall.logError(e, context: 'AppInitializer.initialize');
      return Result.error(
        'unknown',
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Clear identity on logout
  static void logout() {
    // ignore: discarded_futures
    PresenceService().stopTracking();
    IdentityProvider.clear();
    _initialized = false;
    // ignore: discarded_futures
    BlockService.instance?.clearOnLogout();
    debugPrint('👋 App identity cleared');
  }

  /// Throws if identity was not loaded (sync guard for services).
  static void requireInitialized() {
    if (!_initialized || !IdentityProvider.hasIdentity) {
      throw StateError(
        'App not initialized. Call AppInitializer.initialize() after login.',
      );
    }
  }
}
