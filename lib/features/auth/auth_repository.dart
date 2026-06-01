import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/user.dart' as app_models;
import '../../utils/firestore_cache_read.dart';
import '../../core/contract.dart';

/// Authentication Repository
/// 
/// Handles data operations for authentication
/// Separates data layer from business logic
class AuthRepository {
  static final AuthRepository _instance = AuthRepository._internal();
  factory AuthRepository() => _instance;
  AuthRepository._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get user by ID
  Future<app_models.User?> getUserById(String userId) async {
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return null;
      
      return app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
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
      
      return app_models.User.fromFirestore(query.docs.first.data(), query.docs.first.id);
    } catch (e) {
      debugPrint('Failed to get user by email: $e');
      return null;
    }
  }

  /// Create user document
  Future<void> createUserDocument(String userId, Map<String, dynamic> userData) async {
    try {
      await _db.collection(Collections.users).doc(userId).set({
        ...userData,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'auth_uid': userId,
      });
    } catch (e) {
      debugPrint('Failed to create user document: $e');
      rethrow;
    }
  }

  /// Update user document
  Future<void> updateUserDocument(String userId, Map<String, dynamic> userData) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        ...userData,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to update user document: $e');
      rethrow;
    }
  }

  /// Delete user document
  Future<void> deleteUserDocument(String userId) async {
    try {
      await _db.collection(Collections.users).doc(userId).delete();
    } catch (e) {
      debugPrint('Failed to delete user document: $e');
      rethrow;
    }
  }

  /// Check if email exists
  Future<bool> emailExists(String email) async {
    try {
      final query = await _db
          .collection(Collections.users)
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check email existence: $e');
      return false;
    }
  }

  /// Check if phone number exists
  Future<bool> phoneExists(String phone) async {
    try {
      final query = await _db
          .collection(Collections.users)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check phone existence: $e');
      return false;
    }
  }

  /// Get user by phone number
  Future<app_models.User?> getUserByPhone(String phone) async {
    try {
      final query = await getQueryCachedFirst(
        _db.collection(Collections.users).where('phone', isEqualTo: phone).limit(1),
      );
      
      if (query.docs.isEmpty) return null;
      
      return app_models.User.fromFirestore(query.docs.first.data(), query.docs.first.id);
    } catch (e) {
      debugPrint('Failed to get user by phone: $e');
      return null;
    }
  }

  /// Sync auth UID with Firestore
  Future<void> syncAuthUid(String userId) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        'auth_uid': _auth.currentUser?.uid,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to sync auth UID: $e');
      rethrow;
    }
  }

  /// Get user activity summary
  Future<Map<String, dynamic>> getUserActivitySummary(String userId) async {
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return {};
      
      final data = doc.data() ?? {};
      return {
        'profile_views': data['profile_views'] ?? 0,
        'interests_sent': data['interests_sent'] ?? 0,
        'interests_received': data['interests_received'] ?? 0,
        'likes_sent': data['likes_sent'] ?? 0,
        'likes_received': data['likes_received'] ?? 0,
        'last_active': data['last_active'],
        'created_at': data['created_at'],
      };
    } catch (e) {
      debugPrint('Failed to get user activity summary: $e');
      return {};
    }
  }

  /// Update user activity
  Future<void> updateUserActivity(String userId, String activityType) async {
    try {
      final batch = _db.batch();
      final userRef = _db.collection(Collections.users).doc(userId);
      
      // Update last active
      batch.update(userRef, {
        'last_active': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      
      // Update activity counters
      switch (activityType.toLowerCase()) {
        case 'profile_view':
          batch.update(userRef, {'profile_views': FieldValue.increment(1)});
          break;
        case 'interest_sent':
          batch.update(userRef, {'interests_sent': FieldValue.increment(1)});
          break;
        case 'interest_received':
          batch.update(userRef, {'interests_received': FieldValue.increment(1)});
          break;
        case 'like_sent':
          batch.update(userRef, {'likes_sent': FieldValue.increment(1)});
          break;
        case 'like_received':
          batch.update(userRef, {'likes_received': FieldValue.increment(1)});
          break;
      }
      
      await batch.commit();
    } catch (e) {
      debugPrint('Failed to update user activity: $e');
      rethrow;
    }
  }

  /// Get user preferences
  Future<Map<String, dynamic>> getUserPreferences(String userId) async {
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(userId));
      if (!doc.exists) return {};
      
      final data = doc.data() ?? {};
      return {
        'notifications_enabled': data['notifications_enabled'] ?? true,
        'email_notifications': data['email_notifications'] ?? true,
        'push_notifications': data['push_notifications'] ?? true,
        'profile_visibility': data['profile_visibility'] ?? 'public',
        'show_online_status': data['show_online_status'] ?? true,
      };
    } catch (e) {
      debugPrint('Failed to get user preferences: $e');
      return {};
    }
  }

  /// Update user preferences
  Future<void> updateUserPreferences(String userId, Map<String, dynamic> preferences) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        ...preferences,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to update user preferences: $e');
      rethrow;
    }
  }

  /// Stream user document changes
  Stream<app_models.User?> userStream(String userId) {
    return _db
        .collection(Collections.users)
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id) : null);
  }

  /// Search users by name
  Future<List<app_models.User>> searchUsersByName(String query, {int limit = 20}) async {
    try {
      final snapshot = await _db
          .collection(Collections.users)
          .where('search_name', arrayContains: query.toLowerCase())
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Failed to search users by name: $e');
      return [];
    }
  }

  /// Get users by IDs
  Future<List<app_models.User>> getUsersByIds(List<String> userIds) async {
    try {
      if (userIds.isEmpty) return [];
      
      final chunks = _chunkList(userIds, 10); // Firestore limit
      List<app_models.User> users = [];
      
      for (final chunk in chunks) {
        final snapshot = await getQueryCachedFirst(
          _db.collection(Collections.users).where(FieldPath.documentId, whereIn: chunk),
        );
        
        users.addAll(snapshot.docs
            .map((doc) => app_models.User.fromFirestore(doc.data(), doc.id)));
      }
      
      return users;
    } catch (e) {
      debugPrint('Failed to get users by IDs: $e');
      return [];
    }
  }

  /// Split list into chunks
  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }
}
