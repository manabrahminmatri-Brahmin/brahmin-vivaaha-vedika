import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/gender.dart';
import '../../models/user.dart' as app_models;
import '../../utils/firestore_cache_read.dart';
import '../identity_service.dart';
import '../profile_completion_policy.dart';
import '../../screens/search/filter_screen.dart' show FilterPreferences;
import '../../services/plan_service.dart';
import '../contract.dart';
import '../firestore_doc_map.dart';
import '../../services/profile_views_privacy.dart';
import '../../services/notification_service.dart';
import '../../services/matrimony_gateway_service.dart';
import '../../services/success_story_service.dart';

/// Cache helper class
class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();
  bool isExpired(DateTime now, Duration ttl) => now.difference(timestamp) > ttl;
}

/// Firestore Service
///
/// Consolidates many Firestore operations (including **`users`** listing/search).
/// For other **`users`** call sites see `FirestoreUsersAccessMap`.
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Cache for getUserById optimization
  final Map<String, _CacheEntry<app_models.User>> _userCache = {};
  static const Duration _cacheTTL = Duration(minutes: 2);

  /// Clears expired cache entries
  void _cleanupCache() {
    final now = DateTime.now();
    _userCache.removeWhere((key, entry) => entry.isExpired(now, _cacheTTL));
  }

  /// Clear entire user cache
  void clearUserCache() {
    _userCache.clear();
    debugPrint('💾 FirestoreService: User cache cleared');
  }

  Future<app_models.User?> getUserById(String userId) async {
    try {
      // 🔥 GAP 4 FIX: Removed _syncAuthUid - now only synced at login/registration
      // via FirestoreRepository.syncAuthUid() to avoid permission issues
      
      // Check cache first
      final cached = _userCache[userId];
      if (cached != null && !cached.isExpired(DateTime.now(), _cacheTTL)) {
        return cached.data;
      }

      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) return null;

      final user = app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
      
      // Cache the result
      _userCache[userId] = _CacheEntry(user);
      
      // Periodic cleanup
      if (_userCache.length > 100) {
        _cleanupCache();
      }

      return user;
    } catch (e) {
      debugPrint('Failed to get user by ID: $e');
      return null;
    }
  }

  /// Get user by email
  Future<app_models.User?> getUserByEmail(String email) async {
    try {
      final query = await getQueryCachedFirst(
        _db
            .collection(Collections.users)
            .where('email', isEqualTo: email.toLowerCase())
            .limit(1),
      );
      
      if (query.docs.isEmpty) return null;
      final doc = query.docs.first;
      return app_models.User.fromFirestore(doc.data(), doc.id);
    } catch (e) {
      debugPrint('Failed to get user by email: $e');
      return null;
    }
  }

  /// Create user document
  Future<void> createUser(String userId, Map<String, dynamic> userData) async {
    try {
      await _db.collection(Collections.users).doc(userId).set({
        ...userData,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to create user: $e');
      rethrow;
    }
  }

  /// Update user document
  Future<void> updateUser(String userId, Map<String, dynamic> userData) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        ...userData,
        'updated_at': FieldValue.serverTimestamp(),
      });
      
      // Invalidate cache for this user
      _userCache.remove(userId);
    } catch (e) {
      debugPrint('Failed to update user: $e');
      rethrow;
    }
  }

  /// Delete user document
  Future<void> deleteUser(String userId) async {
    try {
      await _db.collection(Collections.users).doc(userId).delete();
      
      // Remove from cache
      _userCache.remove(userId);
    } catch (e) {
      debugPrint('Failed to delete user: $e');
      rethrow;
    }
  }

  /// Get matching profiles with pagination
  Future<MatchingProfilesPage> getMatchingProfiles({
    FilterPreferences? filters,
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    try {
      final identityService = IdentityService();
      final userId = await identityService.getUserId();

      final currentUserDoc =
          await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!currentUserDoc.exists) {
        return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
      }

      final currentUserData = currentUserDoc.data()!;
      final myGender = genderFromUserDocumentData(currentUserData);
      if (myGender == null) {
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
        if (doc.id == userId) continue;
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

  /// Search users
  Future<List<app_models.User>> searchUsers(String query, {int limit = 20}) async {
    try {
      final snapshot = await _db
          .collection(Collections.users)
          .where('search_name', arrayContains: query.toLowerCase())
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data(), doc.id))
          .where(ProfileCompletionPolicy.isEligibleForDiscovery)
          .toList();
    } catch (e) {
      debugPrint('Failed to search users: $e');
      return [];
    }
  }

  /// Get collection with pagination
  Future<QuerySnapshot> getCollection(
    String collectionPath, {
    Map<String, dynamic>? whereConditions,
    String? orderBy,
    bool descending = false,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _db.collection(collectionPath);

      // Apply where conditions
      if (whereConditions != null) {
        whereConditions.forEach((field, value) {
          if (value is List && value.length == 2) {
            // Handle range queries [operator, value]
            final operator = value[0];
            final val = value[1];
            switch (operator) {
              case '==':
                query = query.where(field, isEqualTo: val);
                break;
              case '>':
                query = query.where(field, isGreaterThan: val);
                break;
              case '>=':
                query = query.where(field, isGreaterThanOrEqualTo: val);
                break;
              case '<':
                query = query.where(field, isLessThan: val);
                break;
              case '<=':
                query = query.where(field, isLessThanOrEqualTo: val);
                break;
              case 'array-contains':
                query = query.where(field, arrayContains: val);
                break;
              case 'in':
                if (val is List) query = query.where(field, whereIn: val);
                break;
              case 'array-contains-any':
                if (val is List) query = query.where(field, arrayContainsAny: val);
                break;
            }
          } else {
            query = query.where(field, isEqualTo: value);
          }
        });
      }

      // Apply ordering
      if (orderBy != null) {
        query = query.orderBy(orderBy, descending: descending);
      }

      // Apply pagination
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(limit);

      return await query.get();
    } catch (e) {
      debugPrint('Failed to get collection: $e');
      rethrow;
    }
  }

  /// Stream collection
  Stream<QuerySnapshot> streamCollection(
    String collectionPath, {
    Map<String, dynamic>? whereConditions,
    String? orderBy,
    bool descending = false,
    int limit = 20,
  }) {
    Query query = _db.collection(collectionPath);

    // Apply where conditions
    if (whereConditions != null) {
      whereConditions.forEach((field, value) {
        if (value is List && value.length == 2) {
          final operator = value[0];
          final val = value[1];
          switch (operator) {
            case '==':
              query = query.where(field, isEqualTo: val);
              break;
            case '>':
              query = query.where(field, isGreaterThan: val);
              break;
            case '>=':
              query = query.where(field, isGreaterThanOrEqualTo: val);
              break;
            case '<':
              query = query.where(field, isLessThan: val);
              break;
            case '<=':
              query = query.where(field, isLessThanOrEqualTo: val);
              break;
            case 'array-contains':
              query = query.where(field, arrayContains: val);
              break;
            case 'in':
              if (val is List) query = query.where(field, whereIn: val);
              break;
            case 'array-contains-any':
              if (val is List) query = query.where(field, arrayContainsAny: val);
              break;
          }
        } else {
          query = query.where(field, isEqualTo: value);
        }
      });
    }

    // Apply ordering
    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    // Apply limit
    if (limit > 0) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }

  /// Batch write operations
  Future<void> batchWrite(List<BatchOperation> operations) async {
    try {
      final batch = _db.batch();
      
      for (final operation in operations) {
        switch (operation.type) {
          case BatchOperationType.set:
            batch.set(operation.reference, operation.data!);
            break;
          case BatchOperationType.update:
            batch.update(operation.reference, operation.data!);
            break;
          case BatchOperationType.delete:
            batch.delete(operation.reference);
            break;
        }
      }
      
      await batch.commit();
    } catch (e) {
      debugPrint('Failed to execute batch write: $e');
      rethrow;
    }
  }

  /// Run transaction
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler,
  ) async {
    try {
      return await _db.runTransaction(transactionHandler);
    } catch (e) {
      debugPrint('Failed to run transaction: $e');
      rethrow;
    }
  }

  /// Get document reference
  DocumentReference getDocumentReference(String collectionPath, String documentId) {
    return _db.collection(collectionPath).doc(documentId);
  }

  /// Get collection reference
  CollectionReference getCollectionReference(String collectionPath) {
    return _db.collection(collectionPath);
  }

  // ─── Message Service Methods ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPhotoRequestsReceived(String userId) async {
    final snap = await _db.collection('photo_requests')
        .where('to_user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getPhotoRequestsSent(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return const [];

    Query<Map<String, dynamic>> baseQuery(String field) => _db
        .collection('photo_requests')
        .where(field, isEqualTo: uid);

    Future<List<Map<String, dynamic>>> runQuery(
      Query<Map<String, dynamic>> query,
    ) async {
      final snap = await query.limit(50).get();
      return snap.docs.map(photoRequestRowFromDoc).toList();
    }

    try {
      return await runQuery(
        baseQuery('from_user_id').orderBy('created_at', descending: true),
      );
    } catch (e) {
      debugPrint(
        '⚠️ getPhotoRequestsSent orderBy failed for $uid, retrying: $e',
      );
      try {
        final rows = await runQuery(baseQuery('from_user_id'));
        rows.sort((a, b) {
          int ms(Map<String, dynamic> m, String key) {
            final v = m[key];
            if (v == null) return 0;
            if (v is Timestamp) return v.millisecondsSinceEpoch;
            if (v is String) {
              return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
            }
            return 0;
          }

          final ua = ms(a, 'updated_at') > 0 ? ms(a, 'updated_at') : ms(a, 'created_at');
          final ub = ms(b, 'updated_at') > 0 ? ms(b, 'updated_at') : ms(b, 'created_at');
          return ub.compareTo(ua);
        });
        return rows;
      } catch (e2) {
        debugPrint('❌ getPhotoRequestsSent failed for $uid: $e2');
        return const [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> getBirthdayWishes(String userId) async {
    final snap = await _db.collection('birthday_wishes')
        .where('to_user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getAnniversaryMessages(String userId) async {
    final snap = await _db.collection('anniversary_messages')
        .where('to_user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getSystemNotifications(String userId) async {
    final snap = await _db.collection('system_notifications')
        .where('user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(30)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> deletePhotoRequestForUser(String requestId, String userId) async {
    throw UnsupportedError(
      'Direct photo_request delete is blocked; use withdraw/revoke lifecycle actions.',
    );
  }

  Future<void> deleteMessageForUser(String messageId, String userId) async {
    await _db.collection('messages').doc(messageId).delete();
  }

  Future<app_models.User?> getUserByProfileId(String profileId) async {
    // 🔥 FIX: Use snake_case field name matching Firestore rules
    final snap = await _db.collection(Collections.users).where('profile_id', isEqualTo: profileId).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return app_models.User.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
  }

  Future<app_models.User?> getUserByMobile(String mobile) async {
    // Field is stored as 'mobile_number' in Firestore (see profile_field_mapping.dart / user.dart toMap).
    // The old query used 'mobile' which never matched any document → always returned NOT FOUND.
    final snap = await _db.collection(Collections.users).where('mobile_number', isEqualTo: mobile).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return app_models.User.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
  }

  Future<List<Map<String, dynamic>>> getAllUsers({int pageSize = 100}) async {
    final snap = await _db.collection(Collections.users).limit(pageSize).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<String> upsertUser(Map<String, dynamic> data) async {
    final id = data['id'] as String? ?? _db.collection(Collections.users).doc().id;
    await _db.collection(Collections.users).doc(id).set(data, SetOptions(merge: true));
    return id;
  }

  Future<String> generateProfileId({String? gender}) async {
    final prefix = gender?.toLowerCase() == 'female' ? 'BVV-F-' : 'BVV-M-';
    final ts = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return '$prefix$ts';
  }

  Future<void> updateUserProfile(String userId, Map<String, dynamic> data) async {
    await _db.collection(Collections.users).doc(userId).update({...data, 'updated_at': FieldValue.serverTimestamp()});
  }

  Future<List<Map<String, dynamic>>> getDuplicatesByMobile(String mobile) async {
    final snap = await _db.collection(Collections.users).where('mobile_number', isEqualTo: mobile).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<String?> mergeDuplicateUsers(String mobile) async {
    final duplicates = await getDuplicatesByMobile(mobile);
    if (duplicates.length < 2) return null;
    return duplicates.first['id'] as String?;
  }

  // ─── Additional methods for screen compatibility ─────────────────────────

  Future<bool> canViewPhoto(String viewerId, String ownerId) async {
    final viewer = viewerId.trim();
    final owner = ownerId.trim();
    if (viewer.isEmpty || owner.isEmpty) return false;

    // Own photo is always viewable.
    if (viewer == owner) return true;

    // Approved photo request unlocks hidden/private photos for this viewer.
    for (final status in const ['granted', 'accepted', 'approved']) {
      final snap = await _db
          .collection('photo_requests')
          .where('from_user_id', isEqualTo: viewer)
          .where('to_user_id', isEqualTo: owner)
          .where('status', isEqualTo: status)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;
    }
    final composite = await _db
        .collection('photo_requests')
        .doc('${viewer}_$owner')
        .get();
    if (composite.exists) {
      final raw =
          (composite.data()?['status'] ?? '').toString().trim().toLowerCase();
      if (raw == 'granted' || raw == 'accepted' || raw == 'approved') {
        return true;
      }
    }

    // Hidden/private without an approved request — deny.
    final ownerSnap = await _db.collection(Collections.users).doc(owner).get();
    if (ownerSnap.exists) {
      final d = ownerSnap.data() ?? const <String, dynamic>{};
      final profile = d['profile'];
      final rootPrivate =
          (d['is_photo_private'] ?? d['isPhotoPrivate'] ?? d['photo_private']);
      final nestedPrivate = profile is Map
          ? (profile['is_photo_private'] ??
              profile['isPhotoPrivate'] ??
              profile['photo_private'])
          : null;
      final isPrivate = rootPrivate == true || nestedPrivate == true;
      if (isPrivate) return false;
    }

    return false;
  }

  Future<Map<String, dynamic>?> getInterest(String fromUserId, String toUserId) async {
    // 🔥 FIX: Use snake_case field names matching Firestore rules
    final snap = await _db.collection('interests')
        .where('from_user_id', isEqualTo: fromUserId)
        .where('to_user_id', isEqualTo: toUserId)
        .limit(1).get();
    if (snap.docs.isEmpty) return null;
    return {'id': snap.docs.first.id, ...snap.docs.first.data()};
  }

  /// Interest doc id from InterestServiceV2: `{fromDocId}_{toDocId}`
  Future<Map<String, dynamic>?> getInterestByDocId(String interestDocId) async {
    if (interestDocId.isEmpty) return null;
    final doc = await _db.collection('interests').doc(interestDocId).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  Future<void> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    await _db.collection('reports').add({
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'reason': reason,
      'details': details ?? '',
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getSuccessStories({int limit = 50}) async {
    return SuccessStoryService.fetchPublishedStories(limit: limit);
  }

  Future<List<Map<String, dynamic>>> getMembershipPlans() async {
    final ps = PlanService.instance;
    if (ps.activePlans.isEmpty) {
      await ps.loadPlans(force: true);
    }
    return ps.activePlans
        .map(
          (p) => <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'tier': 'platinum',
            'days': _planDaysFromMonths(p.durationMonths),
            'price': p.discountedFee,
            'original_price':
                p.actualFee > p.discountedFee ? p.actualFee : null,
            'description': p.description,
            'is_popular': p.isPopular,
            'features': p.features,
            'is_active': p.isActive,
            'duration_months': p.durationMonths,
            'actual_fee': p.actualFee,
            'discounted_fee': p.discountedFee,
          },
        )
        .toList();
  }

  static int _planDaysFromMonths(int m) {
    switch (m) {
      case 1:
        return 30;
      case 3:
        return 90;
      case 6:
        return 180;
      case 12:
        return 365;
      default:
        return (m * 30).clamp(1, 9999);
    }
  }

  Future<app_models.User?> getUserByAnyId(String id) async {
    try {
      final byId = await getUserById(id);
      if (byId != null) return byId;
      // 🔥 FIX: Use snake_case field name matching Firestore rules
      final snap = await _db.collection(Collections.users).where('profile_id', isEqualTo: id).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return app_models.User.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
      }
      final byAuthUid = await getQueryCachedFirst(
        _db.collection(Collections.users).where('auth_uid', isEqualTo: id).limit(1),
      );
      if (byAuthUid.docs.isNotEmpty) {
        return app_models.User.fromFirestore(byAuthUid.docs.first.data(), byAuthUid.docs.first.id);
      }
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('🔒 getUserByAnyId: permission denied for id=$id');
        return null;
      }
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> profileViewersStream(String profileId) async* {
    if (profileId.isEmpty) {
      debugPrint('⚠️ profileViewersStream: empty profileId');
      yield <Map<String, dynamic>>[];
      return;
    }

    final ids = <String>{profileId};
    try {
      // 1) Treat input as users/{docId}
      final userDoc =
          await getDocumentCachedFirst(_db.collection(Collections.users).doc(profileId));
      final data = userDoc.data();
      if (data != null) {
        final authUid = (data['auth_uid'] as String? ?? '').trim();
        if (authUid.isNotEmpty) ids.add(authUid);
        // Omit profile_id (e.g. MB74450) from whereIn — rules only match doc id / auth uid.
      } else {
        // 2) Treat input as profile_id (e.g. MG12345)
        final byProfileId = await getQueryCachedFirst(
          _db
              .collection(Collections.users)
              .where('profile_id', isEqualTo: profileId)
              .limit(1),
        );
        if (byProfileId.docs.isNotEmpty) {
          final row = byProfileId.docs.first.data();
          final docId = byProfileId.docs.first.id.trim();
          final authUid = (row['auth_uid'] as String? ?? '').trim();
          if (docId.isNotEmpty) ids.add(docId);
          if (authUid.isNotEmpty) ids.add(authUid);
        } else {
          // 3) Treat input as auth_uid
          final byAuthUid = await getQueryCachedFirst(
            _db
                .collection(Collections.users)
                .where('auth_uid', isEqualTo: profileId)
                .limit(1),
          );
          if (byAuthUid.docs.isNotEmpty) {
            final row = byAuthUid.docs.first.data();
            final docId = byAuthUid.docs.first.id.trim();
            final authUid = (row['auth_uid'] as String? ?? '').trim();
            if (docId.isNotEmpty) ids.add(docId);
            if (authUid.isNotEmpty) ids.add(authUid);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ profileViewersStream id resolution failed: $e');
    }

    final targetIds = ids.take(10).toList();
    String lookupField = 'viewed_profile_id';
    try {
      Query<Map<String, dynamic>> probe;
      if (targetIds.length == 1) {
        probe = _db
            .collection('profile_views')
            .where('viewed_profile_id', isEqualTo: targetIds.first);
      } else {
        probe = _db
            .collection('profile_views')
            .where('viewed_profile_id', whereIn: targetIds);
      }
      final probeSnap = await probe.limit(1).get();
      if (probeSnap.docs.isEmpty) {
        lookupField = 'viewed_user_id';
      }
    } catch (_) {
      // Keep viewed_profile_id default if probe fails.
    }

    Query<Map<String, dynamic>> query;
    if (targetIds.length == 1) {
      query = _db
          .collection('profile_views')
          .where(lookupField, isEqualTo: targetIds.first);
    } else {
      query = _db
          .collection('profile_views')
          .where(lookupField, whereIn: targetIds);
    }

    DateTime parseViewedAt(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) {
        return DateTime.tryParse(raw) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    Future<List<Map<String, dynamic>>> rowsFromSnapshot(
      QuerySnapshot<Map<String, dynamic>> s,
    ) async {
      final latestByViewer = <String, Map<String, dynamic>>{};
      for (final d in s.docs) {
        final row = firestoreRowFromDoc(d);
        if (ProfileViewsPrivacy.shouldHideViewerRow(row)) continue;
        final viewerId = (row['viewer_user_id'] ??
                row['viewer_id'] ??
                row['from_user_id'] ??
                row['from_user'] ??
                row['user_id'] ??
                '')
            .toString()
            .trim();
        if (viewerId.isEmpty) continue;

        row['viewer_user_id'] = viewerId;
        final currentAt = parseViewedAt(row['viewed_at'] ?? row['created_at']);
        final prev = latestByViewer[viewerId];
        if (prev == null) {
          latestByViewer[viewerId] = row;
          continue;
        }
        final prevAt = parseViewedAt(prev['viewed_at'] ?? prev['created_at']);
        if (currentAt.isAfter(prevAt)) {
          latestByViewer[viewerId] = row;
        }
      }

      final rows = latestByViewer.values.toList()
        ..sort((a, b) {
          final aDt = parseViewedAt(a['viewed_at'] ?? a['created_at']);
          final bDt = parseViewedAt(b['viewed_at'] ?? b['created_at']);
          return bDt.compareTo(aDt);
        });

      final visible = await ProfileViewsPrivacy.filterVisibleViewers(rows);
      final active =
          await ProfileViewsPrivacy.filterActiveViewerProfiles(visible);
      if (active.length > 50) return active.sublist(0, 50);
      return active;
    }

    var permissionDeniedLogged = false;
    try {
      await for (final snap in query.limit(200).snapshots()) {
        yield await rowsFromSnapshot(snap);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!permissionDeniedLogged) {
          permissionDeniedLogged = true;
          debugPrint(
            '🔒 Permission denied for profile_views - returning empty',
          );
        }
        yield <Map<String, dynamic>>[];
        return;
      }
      rethrow;
    }
  }

  Future<String?> updateProfileIdGenderPrefix(String firestoreDocId, String currentProfileId, String gender) async {
    final prefix = gender.toLowerCase() == 'female' ? 'BVV-F-' : 'BVV-M-';
    if (currentProfileId.startsWith(prefix)) return currentProfileId;
    final newId = '$prefix${currentProfileId.replaceAll(RegExp(r'^BVV-[MF]-'), '')}';
    // 🔥 FIX: Use snake_case field name matching Firestore rules
    await _db.collection(Collections.users).doc(firestoreDocId).update({'profile_id': newId});
    return newId;
  }

  /// Respond to a photo request (approve or reject) via Cloud Function.
  Future<void> respondToPhotoRequest({
    required String requestId,
    required String status, // 'approved' or 'rejected'
  }) async {
    final normalized = status.trim().toLowerCase();
    final approve = normalized == 'approved' ||
        normalized == 'granted' ||
        normalized == 'accepted' ||
        normalized == 'approve';
    final gateway = await MatrimonyGatewayService.transitionPhotoRequest(
      requestId: requestId,
      action: approve ? 'approve' : 'reject',
    );
    if (gateway['success'] != true) {
      throw Exception(
        gateway['error']?.toString() ?? 'Photo request update failed',
      );
    }
    final storedStatus =
        (gateway['status'] as String?) ?? (approve ? 'accepted' : 'denied');
    final settledStatus = {
      'approved': 'granted',
      'accepted': 'granted',
      'granted': 'granted',
      'rejected': 'denied',
      'declined': 'denied',
      'denied': 'denied',
    }[storedStatus.trim().toLowerCase()] ??
        (approve ? 'granted' : 'denied');
    // ignore: discarded_futures
    NotificationService().markPrivacyNotificationsReadForRequestDoc(
      requestId,
      settledStatus: settledStatus,
    );
  }
}

/// Batch operation class
class BatchOperation {
  final BatchOperationType type;
  final DocumentReference reference;
  final Map<String, dynamic>? data;

  BatchOperation({
    required this.type,
    required this.reference,
    this.data,
  });

  BatchOperation.set(this.reference, this.data) : type = BatchOperationType.set;
  BatchOperation.update(this.reference, this.data) : type = BatchOperationType.update;
  BatchOperation.delete(this.reference) : type = BatchOperationType.delete, data = null;
}

/// Batch operation types
enum BatchOperationType { set, update, delete }

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