import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Realtime Database Service
/// 
/// Consolidates Realtime Database operations from:
/// - realtime_database_service.dart
/// - realtime_sync_service.dart
class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  late final DatabaseReference _database;
  bool _isInitialized = false;

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;
      debugPrint('✅ RealtimeService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ RealtimeService initialization failed: $e');
      rethrow;
    }
  }

  /// Ensure database is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Save data to Realtime Database
  Future<Map<String, dynamic>> saveData(
    String path, 
    Map<String, dynamic> data
  ) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child(path);
      await ref.set(data);
      
      debugPrint('✅ Data saved to path: $path');
      return {'success': true, 'message': 'Data saved successfully'};
    } catch (e) {
      debugPrint('❌ Failed to save data: $e');
      return {'success': false, 'message': 'Failed to save data: $e'};
    }
  }

  /// Update data in Realtime Database
  Future<Map<String, dynamic>> updateData(
    String path, 
    Map<String, dynamic> data
  ) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child(path);
      await ref.update(data);
      
      debugPrint('✅ Data updated at path: $path');
      return {'success': true, 'message': 'Data updated successfully'};
    } catch (e) {
      debugPrint('❌ Failed to update data: $e');
      return {'success': false, 'message': 'Failed to update data: $e'};
    }
  }

  /// Get data from Realtime Database
  Future<Map<String, dynamic>?> getData(String path) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child(path);
      final snapshot = await ref.get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        debugPrint('✅ Data retrieved from path: $path');
        return data;
      }
      
      debugPrint('⚠️ No data found at path: $path');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to get data: $e');
      return null;
    }
  }

  /// Delete data from Realtime Database
  Future<Map<String, dynamic>> deleteData(String path) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child(path);
      await ref.remove();
      
      debugPrint('✅ Data deleted from path: $path');
      return {'success': true, 'message': 'Data deleted successfully'};
    } catch (e) {
      debugPrint('❌ Failed to delete data: $e');
      return {'success': false, 'message': 'Failed to delete data: $e'};
    }
  }

  /// Stream data from Realtime Database
  Stream<Map<String, dynamic>?> streamData(String path) {
    return _database.child(path).onValue.map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  /// Save user data to Realtime Database
  Future<Map<String, dynamic>> saveUser(Map<String, dynamic> userData) async {
    try {
      await _ensureInitialized();
      
      final userId = userData['id'] as String?;
      if (userId == null || userId.isEmpty) {
        return {'success': false, 'message': 'User ID is required'};
      }

      final ref = _database.child('users').child(userId);
      
      // Add metadata
      final enrichedData = {
        ...userData,
        'last_updated': ServerValue.timestamp,
        'realtime_sync_enabled': true,
      };

      await ref.set(enrichedData);
      
      debugPrint('✅ User data saved for user: $userId');
      return {'success': true, 'message': 'User data saved successfully'};
    } catch (e) {
      debugPrint('❌ Failed to save user data: $e');
      return {'success': false, 'message': 'Failed to save user data: $e'};
    }
  }

  /// Update user presence status
  Future<void> updateUserPresence(String userId, bool isOnline) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child('presence').child(userId);
      await ref.update({
        'online': isOnline,
        'last_seen': ServerValue.timestamp,
      });
      
      debugPrint('✅ User presence updated for: $userId (online: $isOnline)');
    } catch (e) {
      debugPrint('❌ Failed to update user presence: $e');
    }
  }

  /// Get user presence
  Stream<Map<String, dynamic>?> getUserPresence(String userId) {
    return _database.child('presence').child(userId).onValue.map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  /// Save chat message
  Future<Map<String, dynamic>> saveChatMessage({
    required String chatId,
    required String messageId,
    required Map<String, dynamic> messageData,
  }) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child('chats').child(chatId).child('messages').child(messageId);
      
      final enrichedMessage = {
        ...messageData,
        'timestamp': ServerValue.timestamp,
        'synced': true,
      };

      await ref.set(enrichedMessage);
      
      // Update chat metadata
      await _database.child('chats').child(chatId).update({
        'last_message': enrichedMessage,
        'last_activity': ServerValue.timestamp,
      });
      
      debugPrint('✅ Chat message saved: $messageId');
      return {'success': true, 'message': 'Message saved successfully'};
    } catch (e) {
      debugPrint('❌ Failed to save chat message: $e');
      return {'success': false, 'message': 'Failed to save message: $e'};
    }
  }

  /// Stream chat messages
  Stream<List<Map<String, dynamic>>> streamChatMessages(String chatId) {
    return _database
        .child('chats')
        .child(chatId)
        .child('messages')
        .orderByChild('created_at')
        .onValue
        .map((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          final messages = data.entries
              .map((entry) => Map<String, dynamic>.from(entry.value as Map))
              .toList();
          return messages;
        }
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// Save notification
  Future<Map<String, dynamic>> saveNotification({
    required String userId,
    required String notificationId,
    required Map<String, dynamic> notificationData,
  }) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child('notifications').child(userId).child(notificationId);
      
      final enrichedNotification = {
        ...notificationData,
        'created_at': ServerValue.timestamp,
        'delivered': false,
        'read': false,
      };

      await ref.set(enrichedNotification);
      
      debugPrint('✅ Notification saved: $notificationId');
      return {'success': true, 'message': 'Notification saved successfully'};
    } catch (e) {
      debugPrint('❌ Failed to save notification: $e');
      return {'success': false, 'message': 'Failed to save notification: $e'};
    }
  }

  /// Stream user notifications
  Stream<List<Map<String, dynamic>>> streamUserNotifications(String userId) {
    return _database
        .child('notifications')
        .child(userId)
        .orderByChild('created_at')
        .limitToLast(50)
        .onValue
        .map((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          final notifications = data.entries
              .map((entry) => Map<String, dynamic>.from(entry.value as Map))
              .toList()
              .reversed
              .toList();
          return notifications;
        }
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// Mark notification as read
  Future<void> markNotificationRead(String userId, String notificationId) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child('notifications').child(userId).child(notificationId);
      await ref.update({
        'read': true,
        'read_at': ServerValue.timestamp,
      });
      
      debugPrint('✅ Notification marked as read: $notificationId');
    } catch (e) {
      debugPrint('❌ Failed to mark notification as read: $e');
    }
  }

  /// Sync data between Firestore and Realtime Database
  Future<void> syncData({
    required String firestorePath,
    required String realtimePath,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _ensureInitialized();
      
      final ref = _database.child(realtimePath);
      
      final syncData = {
        ...data,
        'synced_at': ServerValue.timestamp,
        'sync_source': 'firestore',
        'firestore_path': firestorePath,
      };

      await ref.set(syncData);
      
      debugPrint('✅ Data synced from Firestore to Realtime: $firestorePath -> $realtimePath');
    } catch (e) {
      debugPrint('❌ Failed to sync data: $e');
      rethrow;
    }
  }

  /// Listen for real-time updates
  StreamSubscription<Map<String, dynamic>>? listenForUpdates(
    String path,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    try {
      final subscription = _database.child(path).onValue.listen((event) {
        if (event.snapshot.exists) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          onUpdate(data);
        }
      });
      
      debugPrint('✅ Started listening for updates at path: $path');
      return subscription as StreamSubscription<Map<String, dynamic>>;
    } catch (e) {
      debugPrint('❌ Failed to start listening for updates: $e');
      return null;
    }
  }

  /// Get database reference
  DatabaseReference getReference(String path) {
    return _database.child(path);
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
