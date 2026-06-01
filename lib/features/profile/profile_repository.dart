import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/user.dart' as app_models;
import '../../core/backend/firestore_service.dart';
import '../../core/call_function.dart';
import '../../core/backend/storage_service.dart';
import '../../core/contract.dart';
import '../../core/firestore_repository.dart';
import '../../core/identity_service.dart';
import '../../utils/firestore_cache_read.dart';
import '../../utils/profile_field_mapping.dart';
import '../../utils/ttl_cache.dart';
import '../../services/profile_views_privacy.dart';

/// Paginated profiles result
class PaginatedProfilesResult {
  final List<app_models.User> profiles;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;

  PaginatedProfilesResult({
    required this.profiles,
    this.lastDoc,
    required this.hasMore,
  });
}

/// Profile Repository
/// 
/// Consolidates profile data operations from:
/// - profile_analytics_service.dart (data parts)
/// - photo_service.dart (data parts)
class ProfileRepository {
  static final ProfileRepository _instance = ProfileRepository._internal();
  factory ProfileRepository() => _instance;
  ProfileRepository._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storage = StorageService();

  static const Duration _kProfileCacheTtl = Duration(minutes: 10);
  final TtlCache<String, app_models.User> _profileTtlCache =
      TtlCache<String, app_models.User>(ttl: _kProfileCacheTtl);

  /// Initialize repository
  Future<void> initialize() async {
    try {
      await _storage.initialize();
    } catch (e) {
      debugPrint('ProfileRepository initialization failed: $e');
      rethrow;
    }
  }

  /// Get user profile with caching
  Future<app_models.User?> getProfile(String userId) async {
    try {
      final cached = _profileTtlCache.get(userId);
      if (cached != null) {
        return cached;
      }

      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return null;

      final normalized =
          ProfileFieldMapping.convertProfileToSnakeCase(doc.data() as Map<String, dynamic>);
      final user = app_models.User.fromFirestore(normalized, doc.id);

      _profileTtlCache.set(userId, user);

      return user;
    } catch (e) {
      debugPrint('Failed to get profile: $e');
      return null;
    }
  }

  /// Raw `users/{userId}` data for settings UIs (cache-first via [getDocumentCachedFirst]).
  ///
  /// Not passed through [ProfileFieldMapping]; keys match stored Firestore (snake_case, dotted paths).
  Future<Map<String, dynamic>?> getUserDocumentDataCacheFirst(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint('ProfileRepository.getUserDocumentDataCacheFirst: $e');
      return null;
    }
  }

  /// Resolve a member by Firestore doc id, public `profile_id`, or Firebase `auth_uid`.
  Future<app_models.User?> lookupUserByAnyId(String rawId) =>
      FirestoreService().getUserByAnyId(rawId.trim());

  /// Real-time **`profile_views`** rows for **Who saw your profile** (deduped; see backend impl).
  Stream<List<Map<String, dynamic>>> profileViewersStream(String streamId) =>
      FirestoreService().profileViewersStream(streamId);

  /// Server-side cleanup of views and access requests involving deleted members.
  Future<void> pruneStaleProfileViewers() async {
    try {
      await CallFunction(
        functionName: 'pruneStaleEngagementForMe',
        data: const {},
      ).call();
    } catch (e) {
      debugPrint('ProfileRepository.pruneStaleProfileViewers: $e');
    }
  }

  /// One-shot fallback when streams fail / return empty (`viewed_profile_id` + `viewed_user_id` OR-queries).
  Future<List<Map<String, dynamic>>> loadProfileViewFallbackRows(
    Set<String> ids, {
    int limit = 100,
  }) async {
    final idList =
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty).take(10).toList();
    if (idList.isEmpty) return const [];

    final out = <Map<String, dynamic>>[];
    for (final field in const ['viewed_profile_id', 'viewed_user_id']) {
      try {
        Query<Map<String, dynamic>> q;
        if (idList.length == 1) {
          q = _db.collection(Collections.profileViews).where(field, isEqualTo: idList.first);
        } else {
          q = _db.collection(Collections.profileViews).where(field, whereIn: idList);
        }
        final s = await q.limit(limit).get();
        out.addAll(s.docs.map((d) => {'id': d.id, ...d.data()}));
      } catch (_) {}
    }

    final unique = <String, Map<String, dynamic>>{};
    for (final row in out) {
      final k = (row['id'] ?? '').toString();
      if (k.isEmpty) continue;
      unique[k] = row;
    }
    final rows = unique.values.toList();
    final visible = await ProfileViewsPrivacy.filterVisibleViewers(rows);
    return ProfileViewsPrivacy.filterActiveViewerProfiles(visible);
  }

  /// Deletes all **`profile_views`** docs matching **`viewed_profile_id`** or **`viewed_user_id`** in [ids].
  Future<int> deleteProfileViewsForTargets(Set<String> ids) async {
    final targetIds =
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty).take(10).toList();
    if (targetIds.isEmpty) return 0;

    final docRefs = <DocumentReference<Map<String, dynamic>>>[];

    Future<void> collect(String field) async {
      Query<Map<String, dynamic>> query;
      if (targetIds.length == 1) {
        query =
            _db.collection(Collections.profileViews).where(field, isEqualTo: targetIds.first);
      } else {
        query =
            _db.collection(Collections.profileViews).where(field, whereIn: targetIds);
      }
      final snap = await query.get();
      for (final d in snap.docs) {
        docRefs.add(d.reference);
      }
    }

    await collect('viewed_profile_id');
    await collect('viewed_user_id');

    final uniqueRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final ref in docRefs) {
      uniqueRefs[ref.id] = ref;
    }
    final refs = uniqueRefs.values.toList();
    if (refs.isEmpty) return 0;

    var deleted = 0;
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _db.batch();
      final end = i + 450 < refs.length ? i + 450 : refs.length;
      for (var j = i; j < end; j++) {
        batch.delete(refs[j]);
      }
      await batch.commit();
      deleted += end - i;
    }
    return deleted;
  }

  /// Update user profile with auth verification and field sanitization
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Verify user ownership — must not rely on stale cache for auth alignment.
      final userDoc = await _db
          .collection(Collections.users)
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      
      final userData = userDoc.data()!;
      final authUid = userData['auth_uid'] as String?;
      
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final firebaseAuthUid = await identityService.getFirebaseAuthUid();
      
      if (authUid != firebaseAuthUid) {
        throw Exception('Permission denied: User ID mismatch');
      }
      
      // Remove privileged fields from update
      final sanitizedData = Map<String, dynamic>.from(data);
      const privilegedFields = [
        'is_admin', 'is_premium', 'subscription_tier', 'premium_expiry',
        'membership_level', 'membership_tier', 'membership_status',
        'membership_json', 'membership_expiry_date', 'auth_uid'
      ];
      
      for (final field in privilegedFields) {
        sanitizedData.remove(field);
      }
      
      // Perform update through repository boundary with normalized keys.
      final normalized = ProfileFieldMapping.convertProfileToSnakeCase(sanitizedData);
      final result = await FirestoreRepository.updateDocument(
        Collections.users,
        userId,
        normalized,
      );
      if (result.isError) {
        throw Exception(result.message);
      }

      // Invalidate cache
      _profileTtlCache.remove(userId);
      
      debugPrint('✅ Profile updated for user: $userId');
      
    } on FirebaseException catch (e) {
      debugPrint('❌ Firebase error updating profile: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        throw Exception('Permission denied. Please check your authentication status.');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ Failed to update profile: $e');
      rethrow;
    }
  }

  /// Get profile completion percentage
  Future<double> getProfileCompletion(String userId) async {
    try {
      final profile = await getProfile(userId);
      if (profile == null) return 0.0;

      int completedFields = 0;
      int totalFields = 0;

      // Basic info fields
      final basicFields = [
        'first_name', 'last_name', 'gender', 'date_of_birth', 'age',
        'height', 'weight', 'religion', 'community', 'motherTongue'
      ];

      for (final field in basicFields) {
        totalFields++;
        final value = _getFieldValue(profile, field);
        if (value != null && value.toString().isNotEmpty) {
          completedFields++;
        }
      }

      // Location fields
      final locationFields = ['country', 'state', 'city'];
      for (final field in locationFields) {
        totalFields++;
        final value = _getFieldValue(profile, field);
        if (value != null && value.toString().isNotEmpty) {
          completedFields++;
        }
      }

      // Education and career
      final educationFields = ['education', 'occupation', 'income'];
      for (final field in educationFields) {
        totalFields++;
        final value = _getFieldValue(profile, field);
        if (value != null && value.toString().isNotEmpty) {
          completedFields++;
        }
      }

      // Family info
      final familyFields = ['familyType', 'familyValues', 'familyStatus'];
      for (final field in familyFields) {
        totalFields++;
        final value = _getFieldValue(profile, field);
        if (value != null && value.toString().isNotEmpty) {
          completedFields++;
        }
      }

      // Photos
      totalFields++;
      if (profile.photos.isNotEmpty) {
        completedFields++;
      }

      return totalFields > 0 ? (completedFields / totalFields) * 100 : 0.0;
    } catch (e) {
      debugPrint('Failed to calculate profile completion: $e');
      return 0.0;
    }
  }

  /// Get field value from user model
  dynamic _getFieldValue(app_models.User user, String fieldName) {
    switch (fieldName) {
      case 'first_name':
        return user.firstName;
      case 'last_name':
        return user.lastName;
      case 'gender':
        return user.gender;
      case 'date_of_birth':
        return user.dateOfBirth;
      case 'age':
        return user.age;
      case 'height':
        return user.height;
      case 'weight':
        return user.weight;
      case 'religion':
        return user.religion;
      case 'community':
        return user.community;
      case 'motherTongue':
        return user.motherTongue;
      case 'country':
        return user.country;
      case 'state':
        return user.state;
      case 'city':
        return user.city;
      case 'education':
        return user.education;
      case 'occupation':
        return user.occupation;
      case 'income':
        return user.income;
      case 'familyType':
        return user.familyType;
      case 'familyValues':
        return user.familyValues;
      case 'familyStatus':
        return user.familyStatus;
      case 'photos':
        return user.photos;
      default:
        return null;
    }
  }

  /// Get profile analytics
  Future<Map<String, dynamic>> getProfileAnalytics(String userId) async {
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return {};

      final data = doc.data() ?? {};
      
      return {
        'profileViews': data['profile_views'] ?? 0,
        'interests_sent': data['interests_sent'] ?? 0,
        'interests_received': data['interests_received'] ?? 0,
        'likes_sent': data['likes_sent'] ?? 0,
        'likes_received': data['likes_received'] ?? 0,
        'last_active': data['last_active'],
        'created_at': data['created_at'],
        'updated_at': data['updated_at'],
      };
    } catch (e) {
      debugPrint('Failed to get profile analytics: $e');
      return {};
    }
  }

  /// Update profile analytics
  Future<void> updateProfileAnalytics(String userId, String action) async {
    try {
      final updates = <String, dynamic>{
        'last_active': FieldValue.serverTimestamp(),
      };
      // Update specific counters
      switch (action.toLowerCase()) {
        case 'view':
          updates['profile_views'] = FieldValue.increment(1);
          break;
        case 'interest_sent':
          updates['interests_sent'] = FieldValue.increment(1);
          break;
        case 'interest_received':
          updates['interests_received'] = FieldValue.increment(1);
          break;
        case 'like_sent':
          updates['likes_sent'] = FieldValue.increment(1);
          break;
        case 'like_received':
          updates['likes_received'] = FieldValue.increment(1);
          break;
      }
      final result = await FirestoreRepository.updateDocument(
        Collections.users,
        userId,
        updates,
      );
      if (result.isError) {
        throw Exception(result.message);
      }
    } catch (e) {
      debugPrint('Failed to update profile analytics: $e');
    }
  }

  /// Get profile photos
  Future<List<Map<String, dynamic>>> getProfilePhotos(String userId) async {
    try {
      final profile = await getProfile(userId);
      if (profile?.photos == null) return [];

      final photos = <Map<String, dynamic>>[];
      
      for (int i = 0; i < profile!.photos.length; i++) {
        final photo = profile.photos[i];
        photos.add({
          'id': i.toString(),
          'url': photo,
          'isPrimary': i == 0,
          'uploadedAt': DateTime.now().toIso8601String(),
          'order': i,
        });
      }

      return photos;
    } catch (e) {
      debugPrint('Failed to get profile photos: $e');
      return [];
    }
  }

  /// Add profile photo with enhanced debugging and retry logic
  Future<Map<String, dynamic>> addProfilePhoto({
    required String userId,
    required String filePath,
    bool isPrimary = false,
  }) async {
    try {
      debugPrint('📸 Starting photo upload for user: $userId');
      debugPrint('📸 File path: $filePath');
      debugPrint('📸 Is primary: $isPrimary');
      
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }
      
      // Verify file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return {'success': false, 'message': 'File not found: $filePath'};
      }
      
      // Check file size (max 5MB)
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        return {'success': false, 'message': 'File too large. Maximum size is 5MB'};
      }
      
      debugPrint('📸 File size: ${fileSize / 1024}KB');
      
      // Initialize storage if needed
      if (!_storage.isInitialized) {
        debugPrint('⚠️ Initializing storage service...');
        await _storage.initialize();
      }
      
      // Upload to Firebase Storage with timeout
      debugPrint('📸 Uploading to Firebase Storage...');
      final result = await _storage.uploadUserFile(
        userId: userId,
        filePath: filePath,
        fileType: 'photos',
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Upload timed out after 60 seconds'),
      );
      
      if (result['success'] != true) {
        debugPrint('❌ Storage upload failed: ${result['message']}');
        return result;
      }
      
      final downloadUrl = result['downloadUrl'] as String?;
      if (downloadUrl == null || downloadUrl.isEmpty) {
        return {'success': false, 'message': 'Failed to get download URL'};
      }
      
      debugPrint('✅ Photo uploaded successfully: $downloadUrl');
      
      // Update Firestore with retry logic
      int retries = 3;
      Exception? lastError;
      
      while (retries > 0) {
        try {
          final photoData = {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'url': downloadUrl,
            'isPrimary': isPrimary,
            'uploadedAt': DateTime.now().toIso8601String(),
          };
          
          if (isPrimary) {
            // If primary, update profile picture fields as well
            await _db.collection(Collections.users).doc(userId).update({
              'photos': FieldValue.arrayUnion([photoData]),
              'profile.profile_picture': downloadUrl,
              'profile.photo_url': downloadUrl,
              'photo_url': downloadUrl,
              'updated_at': FieldValue.serverTimestamp(),
            });
          } else {
            // Just append to photos array
            await _db.collection(Collections.users).doc(userId).update({
              'photos': FieldValue.arrayUnion([photoData]),
              'updated_at': FieldValue.serverTimestamp(),
            });
          }
          
          _profileTtlCache.remove(userId);
          debugPrint('✅ Firestore updated with photo data');
          
          return {
            'success': true,
            'downloadUrl': downloadUrl,
            'message': 'Photo uploaded successfully',
          };
          
        } on FirebaseException catch (e) {
          lastError = e;
          retries--;
          
          if (e.code == 'permission-denied') {
            debugPrint('❌ Permission denied. Auth UID may not match.');
            return {
              'success': false,
              'message': 'Permission denied. Please log out and log in again.',
            };
          }
          
          if (retries > 0) {
            debugPrint('⚠️ Retrying Firestore update... ($retries left)');
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      
      return {
        'success': false,
        'message': 'Failed to update Firestore after 3 attempts: $lastError',
      };
      
    } catch (e, stack) {
      debugPrint('❌ Fatal error adding photo: $e');
      debugPrint('Stack trace: $stack');
      return {
        'success': false,
        'message': 'Failed to add photo: ${e.toString()}',
      };
    }
  }

  /// Remove profile photo
  Future<void> removeProfilePhoto({
    required String userId,
    required String photoId,
  }) async {
    try {
      final profile = await getProfile(userId);
      if (profile?.photos == null) return;

      final photoToRemove = profile!.photos.firstWhere(
        (photo) => photo == photoId,
        orElse: () => throw Exception('Photo not found'),
      );

      // Delete from storage
      final fileName = photoToRemove.split('/').last;
      await _storage.deleteUserFile(
        userId: userId,
        fileName: fileName,
        fileType: 'photos',
      );

      // Remove from user document
      await _db.collection(Collections.users).doc(userId).update({
        'photos': FieldValue.arrayRemove([photoToRemove]),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Invalidate cache
      _profileTtlCache.remove(userId);

      debugPrint('Profile photo removed for user: $userId');
    } catch (e) {
      debugPrint('Failed to remove profile photo: $e');
      rethrow;
    }
  }

  /// Set primary photo
  Future<void> setPrimaryPhoto({
    required String userId,
    required String photoId,
  }) async {
    try {
      final profile = await getProfile(userId);
      if (profile?.photos == null) return;

      // For string-based photos, move the selected photo to the front
      final photos = List<String>.from(profile!.photos);
      final photoIndex = photos.indexOf(photoId);
      
      if (photoIndex != -1) {
        // Move the selected photo to the beginning (make it primary)
        photos.removeAt(photoIndex);
        photos.insert(0, photoId);
        
        await _db.collection(Collections.users).doc(userId).update({
          'photos': photos,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      // Invalidate cache
      _profileTtlCache.remove(userId);

      debugPrint('Primary photo set for user: $userId');
    } catch (e) {
      debugPrint('Failed to set primary photo: $e');
      rethrow;
    }
  }

  /// Get profile visibility settings
  Future<Map<String, dynamic>> getProfileVisibility(String userId) async {
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return {};

      final data = doc.data() ?? {};
      
      return {
        'profileVisibility': data['profile_visibility'] ?? 'public',
        'showOnlineStatus': data['show_online_status'] ?? true,
        'allowMessages': data['allow_messages'] ?? true,
        'showLastSeen': data['show_last_seen'] ?? true,
        'whoCanView': data['who_can_view'] ?? 'everyone',
      };
    } catch (e) {
      debugPrint('Failed to get profile visibility: $e');
      return {};
    }
  }

  /// Update profile visibility settings
  Future<void> updateProfileVisibility(
    String userId, 
    Map<String, dynamic> settings
  ) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        ...settings,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Invalidate cache
      _profileTtlCache.remove(userId);

      debugPrint('Profile visibility updated for user: $userId');
    } catch (e) {
      debugPrint('Failed to update profile visibility: $e');
      rethrow;
    }
  }

  /// Search profiles
  Future<List<app_models.User>> searchProfiles({
    String? query,
    String? gender,
    String? religion,
    String? community,
    int? minAge,
    int? maxAge,
    int limit = 20,
  }) async {
    try {
      Query profileQuery = _db.collection(Collections.users);

      // Apply filters
      if (gender != null) {
        profileQuery = profileQuery.where('gender', isEqualTo: gender);
      }
      if (religion != null) {
        profileQuery = profileQuery.where('religion', isEqualTo: religion);
      }
      if (community != null) {
        profileQuery = profileQuery.where('community', isEqualTo: community);
      }
      if (minAge != null) {
        profileQuery = profileQuery.where('age', isGreaterThanOrEqualTo: minAge);
      }
      if (maxAge != null) {
        profileQuery = profileQuery.where('age', isLessThanOrEqualTo: maxAge);
      }

      // Search by name if query provided
      if (query != null && query.isNotEmpty) {
        profileQuery = profileQuery.where('search_name', arrayContains: query.toLowerCase());
      }

      profileQuery = profileQuery.limit(limit);

      final snapshot = await profileQuery.get();
      
      return snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('Failed to search profiles: $e');
      return [];
    }
  }

  /// Clear all cache
  void clearCache() {
    _profileTtlCache.clear();
  }

  /// Drop one cached profile (e.g. after photo privacy toggle).
  void invalidateProfileCache(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return;
    _profileTtlCache.remove(id);
  }

  /// Stream profile updates
  Stream<app_models.User?> streamProfile(String userId) {
    return _db
        .collection(Collections.users)
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final user = app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
          _profileTtlCache.set(userId, user);
          return user;
        });
  }

  /// Load paginated profiles
  Future<PaginatedProfilesResult> loadPaginatedProfiles({
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    try {
      Query query = _db
          .collection(Collections.users)
          .limit(limit);
      
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }
      
      final snapshot = await query.get();
      
      final users = snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      
      // Cache results
      for (final user in users) {
        _profileTtlCache.set(user.id, user);
      }
      
      final hasMore = users.length == limit;
      final newLastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      
      return PaginatedProfilesResult(
        profiles: users,
        lastDoc: newLastDoc,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('Failed to load paginated profiles: $e');
      return PaginatedProfilesResult(profiles: [], hasMore: false);
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _profileTtlCache.length,
      'ttlSeconds': _kProfileCacheTtl.inSeconds,
      'hitRate': 0.85, // Estimated
    };
  }
}
