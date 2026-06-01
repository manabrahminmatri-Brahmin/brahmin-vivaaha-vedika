import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/profile_completion_policy.dart';
import '../../models/gender.dart';
import '../../models/user.dart' as app_models;
import '../../screens/search/filter_screen.dart' show FilterPreferences;
import '../../core/contract.dart';

/// Match Engine
/// 
/// Consolidates matching operations from:
/// - matching_preferences_service.dart
class MatchEngine {
  static final MatchEngine _instance = MatchEngine._internal();
  factory MatchEngine() => _instance;
  MatchEngine._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isInitialized = false;

  /// Initialize match engine
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('✅ MatchEngine: Initialized successfully');
    } catch (e) {
      debugPrint('❌ MatchEngine initialization failed: $e');
      rethrow;
    }
  }

  /// Get current user's Firestore document ID
  /// Resolves from SharedPreferences first, then queries by auth_uid if needed
  Future<String?> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('current_user_id')?.trim();
      if (stored != null && stored.isNotEmpty) return stored;
      
      // If no stored ID, resolve from Firebase Auth UID via auth_uid field
      final authUid = _auth.currentUser?.uid;
      if (authUid == null) return null;
      
      // Query users collection where auth_uid matches
      final snap = await _db
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: authUid)
          .limit(1)
          .get();
      
      if (snap.docs.isNotEmpty) {
        final docId = snap.docs.first.id;
        debugPrint('✅ MatchEngine: Resolved auth_uid=$authUid to docId=$docId');
        // Cache for future use
        await prefs.setString('current_user_id', docId);
        return docId;
      }
      
      // Fallback: try direct lookup (some users may have auth_uid as doc ID)
      final directSnap = await _db.collection(Collections.users).doc(authUid).get();
      if (directSnap.exists) {
        return authUid;
      }
      
      debugPrint('⚠️ MatchEngine: No user document found for auth_uid=$authUid');
      return null;
    } catch (e) {
      debugPrint('❌ MatchEngine: Failed to get current user ID: $e');
      return null;
    }
  }

  /// Cached current user gender to avoid repeated lookups
  String? _cachedCurrentGender;
  String? _cachedUserId;
  
  /// Clear cached data (call on logout)
  void clearCache() {
    _cachedCurrentGender = null;
    _cachedUserId = null;
    debugPrint('🚀 MatchEngine: Cache cleared');
  }

  /// Get matching profiles with pagination (optimized)
  Future<MatchingProfilesPage> getMatchingProfiles({
    FilterPreferences? filters,
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    try {
      await _ensureInitialized();
      
      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null) {
        return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
      }

      Gender? myGender;
      if (_cachedUserId == currentUserId && _cachedCurrentGender != null) {
        myGender = genderFromDynamic(_cachedCurrentGender);
        debugPrint('🚀 MatchEngine: Using cached gender: $_cachedCurrentGender');
      } else {
        final currentUserDoc =
            await _db.collection(Collections.users).doc(currentUserId).get();
        if (!currentUserDoc.exists) {
          return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
        }

        final currentUserData = currentUserDoc.data()!;
        myGender = genderFromUserDocumentData(currentUserData);
        _cachedUserId = currentUserId;
        _cachedCurrentGender = myGender?.genderName;
        debugPrint(
            '🚀 MatchEngine: Cached gender for user $currentUserId: $_cachedCurrentGender');
      }

      if (myGender == null) {
        debugPrint('⚠️ MatchEngine: User gender unknown, cannot load profiles');
        return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
      }

      final fetchSize = (limit * 4).clamp(40, 400);
      Query<Map<String, dynamic>> activeQuery() {
        var q = _db
            .collection(Collections.users)
            .where('is_deleted', isEqualTo: false)
            .orderBy('created_at', descending: true)
            .limit(fetchSize);
        if (lastDoc != null) {
          q = q.startAfterDocument(lastDoc);
        }
        return q;
      }

      Query<Map<String, dynamic>> anyQuery() {
        var q = _db
            .collection(Collections.users)
            .orderBy('created_at', descending: true)
            .limit(fetchSize);
        if (lastDoc != null) {
          q = q.startAfterDocument(lastDoc);
        }
        return q;
      }

      late final QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await activeQuery().get();
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition' ||
            e.code == 'permission-denied') {
          snapshot = await anyQuery().get();
        } else {
          rethrow;
        }
      }

      final users = <app_models.User>[];
      for (final doc in snapshot.docs) {
        if (doc.id == currentUserId) continue;
        late final app_models.User user;
        try {
          user = app_models.User.fromFirestore(doc.data(), doc.id);
        } catch (_) {
          continue;
        }
        if (user.isDeleted) continue;
        if (!ProfileCompletionPolicy.isEligibleForDiscovery(user)) continue;
        final peer =
            user.profile?.gender ?? genderFromUserDocumentData(doc.data());
        if (peer == null || peer == myGender) continue;
        users.add(user);
        if (users.length >= limit) break;
      }

      return MatchingProfilesPage(
        users: users,
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length >= fetchSize,
      );
    } catch (e) {
      debugPrint('Failed to get matching profiles: $e');
      return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
    }
  }

  /// Get user matches (mutual interests/likes)
  Future<List<app_models.User>> getUserMatches(String userId) async {
    try {
      await _ensureInitialized();
      
      // Get users who sent interest to current user
      final receivedInterests = await _db
          .collection('interests')
          .where('receiverId', isEqualTo: userId)
          .where('status', isEqualTo: 'accepted')
          .get();

      // Get users who current user sent interest to and was accepted
      final sentInterests = await _db
          .collection('interests')
          .where('senderId', isEqualTo: userId)
          .where('status', isEqualTo: 'accepted')
          .get();

      final matchedUserIds = <String>{};
      
      for (final doc in receivedInterests.docs) {
        matchedUserIds.add(doc['senderId'] as String);
      }
      
      for (final doc in sentInterests.docs) {
        matchedUserIds.add(doc['receiverId'] as String);
      }

      if (matchedUserIds.isEmpty) return [];

      // Get user profiles for matched users
      final chunks = _chunkList(matchedUserIds.toList(), 10);
      final matchedUsers = <app_models.User>[];

      for (final chunk in chunks) {
        final snapshot = await _db
            .collection(Collections.users)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        
        matchedUsers.addAll(snapshot.docs
            .map((doc) => app_models.User.fromFirestore(doc.data(), doc.id)));
      }

      return matchedUsers;
    } catch (e) {
      debugPrint('Failed to get user matches: $e');
      return [];
    }
  }

  /// Check if two users are matched
  Future<bool> areUsersMatched(String userId1, String userId2) async {
    try {
      await _ensureInitialized();
      
      // Check if there's an accepted interest between them
      final snapshot = await _db
          .collection('interests')
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'] as String;
        final receiverId = data['receiverId'] as String;
        
        if ((senderId == userId1 && receiverId == userId2) ||
            (senderId == userId2 && receiverId == userId1)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Failed to check if users are matched: $e');
      return false;
    }
  }

  /// Save matching preferences
  Future<void> saveMatchingPreferences({
    required String userId,
    required FilterPreferences preferences,
  }) async {
    try {
      await _ensureInitialized();
      
      // 🔥 FIX: Use snake_case field names for Firestore
      final preferencesData = {
        'min_age': preferences.minAge,
        'max_age': preferences.maxAge,
        'religion': preferences.religion,
        'community': preferences.community,
        'mother_tongue': preferences.motherTongue,
        'location': preferences.location,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await _db.collection(Collections.users).doc(userId).update({
        'matching_preferences': preferencesData,
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Matching preferences saved for user: $userId');
    } catch (e) {
      debugPrint('Failed to save matching preferences: $e');
      rethrow;
    }
  }

  /// Get matching preferences
  Future<FilterPreferences> getMatchingPreferences(String userId) async {
    try {
      await _ensureInitialized();
      
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) {
        return FilterPreferences(); // Return empty preferences
      }

      final data = doc.data()!;
      final preferencesData = data['matching_preferences'] as Map<String, dynamic>? ?? {};

      // 🔥 FIX: Read with fallback for both conventions
      return FilterPreferences(
        minAge: preferencesData['min_age'] ?? preferencesData['minAge'] as int?,
        maxAge: preferencesData['max_age'] ?? preferencesData['maxAge'] as int?,
        religion: preferencesData['religion'] as String?,
        community: preferencesData['community'] as String?,
        motherTongue: preferencesData['mother_tongue'] ?? preferencesData['motherTongue'] as String?,
        location: preferencesData['location'] as String?,
      );
    } catch (e) {
      debugPrint('Failed to get matching preferences: $e');
      return FilterPreferences(); // Return empty preferences on error
    }
  }

  /// Get compatibility score between two users
  Future<double> getCompatibilityScore(String userId1, String userId2) async {
    try {
      await _ensureInitialized();
      
      final user1Doc = await _db.collection(Collections.users).doc(userId1).get();
      final user2Doc = await _db.collection(Collections.users).doc(userId2).get();

      if (!user1Doc.exists || !user2Doc.exists) return 0.0;

      final user1Data = user1Doc.data()!;
      final user2Data = user2Doc.data()!;

      double score = 0.0;
      int factors = 0;

      // Religion compatibility
      if (user1Data['religion'] == user2Data['religion']) {
        score += 20.0;
      }
      factors++;

      // Community compatibility
      if (user1Data['community'] == user2Data['community']) {
        score += 15.0;
      }
      factors++;

      // Mother tongue compatibility
      if (user1Data['mother_tongue'] == user2Data['mother_tongue']) {
        score += 10.0;
      }
      factors++;

      // Location compatibility
      if (user1Data['city'] == user2Data['city']) {
        score += 15.0;
      }
      factors++;

      // Age compatibility (within 5 years)
      final age1 = user1Data['age'] as int? ?? 0;
      final age2 = user2Data['age'] as int? ?? 0;
      final ageDiff = (age1 - age2).abs();
      if (ageDiff <= 5) {
        score += 10.0;
      } else if (ageDiff <= 10) {
        score += 5.0;
      }
      factors++;

      // Height compatibility (within reasonable range)
      final height1 = user1Data['height'] as double? ?? 0.0;
      final height2 = user2Data['height'] as double? ?? 0.0;
      if (height1 > 0 && height2 > 0) {
        final heightDiff = (height1 - height2).abs();
        if (heightDiff <= 10.0) {
          score += 5.0;
        }
      }
      factors++;

      return factors > 0 ? score : 0.0;
    } catch (e) {
      debugPrint('Failed to calculate compatibility score: $e');
      return 0.0;
    }
  }

  /// Get recommended profiles based on preferences
  Future<List<app_models.User>> getRecommendedProfiles({
    required String userId,
    int limit = 20,
  }) async {
    try {
      await _ensureInitialized();
      
      // Get user's matching preferences
      final preferences = await getMatchingPreferences(userId);
      
      // Get matching profiles with those preferences
      final result = await getMatchingProfiles(
        filters: preferences,
        limit: limit,
      );

      // Calculate compatibility scores and sort
      final profilesWithScores = <Map<String, dynamic>>[];
      
      for (final user in result.users) {
        final score = await getCompatibilityScore(userId, user.id);
        profilesWithScores.add({
          'user': user,
          'score': score,
        });
      }

      // Sort by compatibility score (highest first)
      profilesWithScores.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      return profilesWithScores
          .map((item) => item['user'] as app_models.User)
          .take(limit)
          .toList();
    } catch (e) {
      debugPrint('Failed to get recommended profiles: $e');
      return [];
    }
  }

  /// Block user
  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await _ensureInitialized();
      
      final blockData = {
        'blockerId': blockerId,
        'blockedId': blockedId,
        'blockedAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('blocks').add(blockData);

      // Remove any existing interests or likes between these users
      await _removeInterestsAndLikes(blockerId, blockedId);

      debugPrint('✅ User blocked: $blockerId -> $blockedId');
    } catch (e) {
      debugPrint('Failed to block user: $e');
      rethrow;
    }
  }

  /// Unblock user
  Future<void> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await _ensureInitialized();
      
      final snapshot = await _db
          .collection('blocks')
          .where('blockerId', isEqualTo: blockerId)
          .where('blockedId', isEqualTo: blockedId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }

      debugPrint('✅ User unblocked: $blockerId -> $blockedId');
    } catch (e) {
      debugPrint('Failed to unblock user: $e');
      rethrow;
    }
  }

  /// Check if user is blocked
  Future<bool> isUserBlocked({
    required String userId,
    required String targetUserId,
  }) async {
    try {
      await _ensureInitialized();
      
      final snapshot = await _db
          .collection('blocks')
          .where('blockerId', isEqualTo: userId)
          .where('blockedId', isEqualTo: targetUserId)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check if user is blocked: $e');
      return false;
    }
  }

  /// Get blocked users
  Future<List<app_models.User>> getBlockedUsers(String userId) async {
    try {
      await _ensureInitialized();
      
      final snapshot = await _db
          .collection('blocks')
          .where('blockerId', isEqualTo: userId)
          .get();

      final blockedUserIds = snapshot.docs
          .map((doc) => doc['blockedId'] as String)
          .toList();

      if (blockedUserIds.isEmpty) return [];

      final chunks = _chunkList(blockedUserIds, 10);
      final blockedUsers = <app_models.User>[];

      for (final chunk in chunks) {
        final userSnapshot = await _db
            .collection(Collections.users)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        
        blockedUsers.addAll(userSnapshot.docs
            .map((doc) => app_models.User.fromFirestore(doc.data(), doc.id)));
      }

      return blockedUsers;
    } catch (e) {
      debugPrint('Failed to get blocked users: $e');
      return [];
    }
  }

  /// Remove interests and likes between two users
  Future<void> _removeInterestsAndLikes(String userId1, String userId2) async {
    try {
      // Remove interests
      final interestsSnapshot = await _db
          .collection('interests')
          .where('senderId', whereIn: [userId1, userId2])
          .where('receiverId', whereIn: [userId1, userId2])
          .get();

      for (final doc in interestsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Remove likes
      final likesSnapshot = await _db
          .collection('likes')
          .where('senderId', whereIn: [userId1, userId2])
          .where('receiverId', whereIn: [userId1, userId2])
          .get();

      for (final doc in likesSnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Failed to remove interests and likes: $e');
    }
  }

  /// Split list into chunks for Firestore queries
  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}

/// Matching profiles page class
class MatchingProfilesPage {
  final List<app_models.User> users;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;
  
  const MatchingProfilesPage({
    required this.users,
    required this.lastDoc,
    required this.hasMore,
  });
}
