import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
/// Realtime Database Service for Firebase Realtime Database
/// This replaces Firestore for better performance and real-time capabilities
class RealtimeDatabaseService {
  static final RealtimeDatabaseService _instance = RealtimeDatabaseService._internal();
  factory RealtimeDatabaseService() => _instance;
  RealtimeDatabaseService._internal();

  late final DatabaseReference _database;

  /// Initialize the database
  void initialize() {
    try {
      _database = FirebaseDatabase.instance.ref();
      debugPrint('✅ RealtimeDatabaseService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService initialization failed: $e');
      rethrow;
    }
  }

  /// Get current user ID
  String? get currentUserId {
    // This should be called after authentication
    return null; // Will be set by AuthService
  }

  /// Save user data to Realtime Database
  Future<Map<String, dynamic>> saveUser(Map<String, dynamic> userData) async {
    try {
      if (userData['id'] == null || userData['id'].toString().isEmpty) {
        throw Exception('saveUser: User ID is required');
      }

      final userId = userData['id'] as String;
      debugPrint('🔍 RealtimeDatabaseService: Saving user $userId');

      final userRef = _database.child('users').child(userId);
      
      await userRef.set(userData).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏰ RealtimeDatabaseService: TIMEOUT saving user $userId');
          throw Exception('Database timeout after 10 seconds');
        },
      );

      debugPrint('✅ RealtimeDatabaseService: User $userId saved successfully');
      return userData;
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: saveUser FAILED: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Get user by mobile number
  Future<Map<String, dynamic>?> getUserByMobile(String mobile) async {
    try {
      if (mobile.isEmpty) {
        debugPrint('❌ RealtimeDatabaseService: EMPTY mobile number provided');
        return null;
      }

      debugPrint('🔍 RealtimeDatabaseService: Searching for mobile $mobile');

      final usersRef = _database.child('users');
      final snapshot = await usersRef
          .orderByChild('mobile_number')
          .equalTo(mobile)
          .limitToFirst(1)
          .get()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('⏰ RealtimeDatabaseService: TIMEOUT searching mobile $mobile');
              throw Exception('Database timeout after 8 seconds');
            },
          );

      if (snapshot.value == null) {
        debugPrint('🔍 RealtimeDatabaseService: No user found for mobile $mobile');
        return null;
      }

      final usersData = snapshot.value as Map<dynamic, dynamic>?;
      if (usersData == null || usersData.isEmpty) {
        debugPrint('🔍 RealtimeDatabaseService: No user found for mobile $mobile');
        return null;
      }

      final userEntry = usersData.entries.first;
      final userData = Map<String, dynamic>.from(userEntry.value);
      userData['id'] = userEntry.key; // Add the document ID

      debugPrint('✅ RealtimeDatabaseService: Found user for mobile $mobile');
      return userData;
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: getUserByMobile FAILED: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Get user by ID
  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('❌ RealtimeDatabaseService: EMPTY userId provided');
        return null;
      }

      debugPrint('🔍 RealtimeDatabaseService: Searching for user $userId');

      final userRef = _database.child('users').child(userId);
      final snapshot = await userRef.get().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('⏰ RealtimeDatabaseService: TIMEOUT getting user $userId');
          throw Exception('Database timeout after 8 seconds');
        },
      );

      if (!snapshot.exists) {
        debugPrint('🔍 RealtimeDatabaseService: No user found for ID $userId');
        return null;
      }

      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      userData['id'] = userId; // Ensure ID is included

      debugPrint('✅ RealtimeDatabaseService: Found user $userId');
      return userData;
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: getUserById FAILED: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Save MPIN for user
  Future<void> saveMpin(String userId, String hashedMpin) async {
    try {
      if (userId.isEmpty) {
        throw Exception('saveMpin: User ID cannot be empty');
      }

      debugPrint('🔐 RealtimeDatabaseService: Saving MPIN for user $userId');

      final mpinRef = _database.child('mpins').child(userId);
      final mpinData = {
        'uid': userId,
        'mpin_hash': hashedMpin,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await mpinRef.set(mpinData).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ RealtimeDatabaseService: TIMEOUT saving MPIN for $userId');
          throw Exception('Database timeout after 5 seconds');
        },
      );

      debugPrint('✅ RealtimeDatabaseService: MPIN saved successfully for $userId');
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: saveMpin FAILED: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Get MPIN hash for user
  Future<String?> getMpin(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('❌ RealtimeDatabaseService: EMPTY userId for getMpin');
        return null;
      }

      debugPrint('🔐 RealtimeDatabaseService: Getting MPIN for user $userId');

      final mpinRef = _database.child('mpins').child(userId);
      final snapshot = await mpinRef.get().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⏰ RealtimeDatabaseService: TIMEOUT getting MPIN for $userId');
          throw Exception('Database timeout after 3 seconds');
        },
      );

      if (!snapshot.exists) {
        debugPrint('🔐 RealtimeDatabaseService: No MPIN found for $userId');
        return null;
      }

      final mpinData = snapshot.value as Map<dynamic, dynamic>?;
      final mpinHash = mpinData?['mpin_hash'] as String?;

      debugPrint('✅ RealtimeDatabaseService: MPIN retrieved for $userId');
      return mpinHash;
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: getMpin FAILED: $e');
      return null;
    }
  }

  /// Update user profile data
  Future<void> updateUserProfile(String userId, Map<String, dynamic> updates) async {
    try {
      if (userId.isEmpty) {
        throw Exception('updateUserProfile: User ID cannot be empty');
      }

      debugPrint('🔍 RealtimeDatabaseService: Updating user $userId');

      final userRef = _database.child('users').child(userId);
      final cleanUpdates = Map<String, dynamic>.from(updates);
      cleanUpdates.removeWhere((_, v) => v == null);
      cleanUpdates['updated_at'] = DateTime.now().toIso8601String();

      await userRef.update(cleanUpdates).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏰ RealtimeDatabaseService: TIMEOUT updating user $userId');
          throw Exception('Database timeout after 10 seconds');
        },
      );

      debugPrint('✅ RealtimeDatabaseService: User $userId updated successfully');
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: updateUserProfile FAILED: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Record profile view
  Future<void> recordProfileView(String viewerUserId, String viewedProfileId) async {
    try {
      final viewId = '${viewerUserId}_$viewedProfileId';
      final viewRef = _database.child('profile_views').child(viewId);
      
      final viewData = {
        'viewer_user_id': viewerUserId,
        'viewed_profile_id': viewedProfileId,
        'created_at': DateTime.now().toIso8601String(),
      };

      await viewRef.set(viewData).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Database timeout recording profile view');
        },
      );
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: recordProfileView FAILED: $e');
      // Non-fatal - don't rethrow
    }
  }

  /// Get all users (with optional filters)
  Future<List<Map<String, dynamic>>> getAllUsers({Map<String, dynamic>? filters, int? limit}) async {
    try {
      debugPrint('🔍 RealtimeDatabaseService: Getting all users');

      Query usersQuery = _database.child('users');
      
      // Apply filters if provided
      if (filters != null) {
        filters.forEach((key, value) {
          if (value != null && key != 'limit') {
            usersQuery = usersQuery.orderByChild(key).equalTo(value);
          }
        });
      }

      if (limit != null) {
        usersQuery = usersQuery.limitToFirst(limit);
      }

      final snapshot = await usersQuery.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Database timeout getting all users');
        },
      );

      final usersData = snapshot.value as Map<dynamic, dynamic>?;
      if (usersData == null) {
        return [];
      }

      final usersList = usersData.entries.map((entry) {
        final userData = Map<String, dynamic>.from(entry.value);
        userData['id'] = entry.key; // Add the document ID
        return userData;
      }).toList();

      debugPrint('✅ RealtimeDatabaseService: Retrieved ${usersList.length} users');
      return usersList;
    } catch (e) {
      debugPrint('❌ RealtimeDatabaseService: getAllUsers FAILED: $e');
      rethrow;
    }
  }
}
