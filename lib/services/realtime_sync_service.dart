import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'user_activity_service.dart';
import '../core/contract.dart';
import '../models/user.dart' as app_models;

/// Realtime synchronization service for live updates
/// Integrates with Firebase Firestore for real-time data synchronization
class RealtimeSyncService extends ChangeNotifier {
  static final RealtimeSyncService _instance = RealtimeSyncService._internal();
  factory RealtimeSyncService() => _instance;
  static RealtimeSyncService get instance => _instance;
  RealtimeSyncService._internal() {
    debugPrint('✅ RealtimeSyncService initialized with Firebase integration');
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isInitialized = false;
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose
  String? _currentUserId;

  /// 🔥 FIX: Safe notify that checks disposed state
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
  /// Last user id passed to [subscribeToMessaging] (may differ from [_currentUserId] ordering).
  String? _messagingUserId;

  /// Initialize the realtime sync service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('🔄 Initializing RealtimeSyncService...');
      _isInitialized = true;
      _safeNotify();
    } catch (e) {
      debugPrint('❌ Failed to initialize RealtimeSyncService: $e');
    }
  }

  /// Subscribe to profile updates for a specific user
  Future<void> subscribeToProfileUpdates(String userId) async {
    if (!_isInitialized) await initialize();

    final previousUserId = _currentUserId;
    if (previousUserId != null &&
        previousUserId.isNotEmpty &&
        previousUserId != userId) {
      final key = 'profile_$previousUserId';
      await _subscriptions[key]?.cancel();
      _subscriptions.remove(key);
    }

    _currentUserId = userId;

    try {
      // Cancel existing subscription if any
      await _unsubscribeFromProfileUpdates();
      
      // Subscribe to profile document changes
      final profileSubscription = _firestore
          .collection(Collections.users)
          .doc(userId)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              final data = snapshot.data()!;
              debugPrint('📱 Profile updated for user: $userId');
              _handleProfileUpdate(data);
            }
          });
      
      _subscriptions['profile_$userId'] = profileSubscription;
      debugPrint('✅ Subscribed to profile updates for: $userId');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to profile updates: $e');
    }
  }

  /// Subscribe to messaging updates for a user
  Future<void> subscribeToMessaging(String userId) async {
    if (!_isInitialized) await initialize();

    final previousMessaging = _messagingUserId;
    if (previousMessaging != null &&
        previousMessaging.isNotEmpty &&
        previousMessaging != userId) {
      final key = 'messages_$previousMessaging';
      await _subscriptions[key]?.cancel();
      _subscriptions.remove(key);
    }
    _messagingUserId = userId;

    try {
      // Cancel existing subscription if any
      await _unsubscribeFromMessaging();
      
      // Subscribe to messages collection
      final messagesSubscription = _firestore
          .collection('messages')
          .where('participants', arrayContains: userId)
          .orderBy('created_at', descending: true)
          .snapshots()
          .listen((snapshot) {
            debugPrint('💬 Messages updated for user: $userId');
            _handleMessagesUpdate(snapshot.docs);
          });
      
      _subscriptions['messages_$userId'] = messagesSubscription;
      debugPrint('✅ Subscribed to messaging updates for: $userId');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to messaging updates: $e');
    }
  }

  /// Subscribe to online status updates
  Future<void> subscribeToOnlineStatus() async {
    if (!_isInitialized) await initialize();
    
    try {
      // Cancel existing subscription if any
      await _unsubscribeFromOnlineStatus();
      
      // Subscribe to online status collection
      final onlineStatusSubscription = _firestore
          .collection('user_status')
          .where('is_online', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
            debugPrint('🟢 Online status updated');
            _handleOnlineStatusUpdate(snapshot.docs);
          });
      
      _subscriptions['online_status'] = onlineStatusSubscription;
      debugPrint('✅ Subscribed to online status updates');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to online status: $e');
    }
  }

  /// Handle profile update events
  void _handleProfileUpdate(Map<String, dynamic> data) {
    // Notify listeners about profile update
    _safeNotify();
    
    // You can add specific logic here for handling different types of profile updates
    if (data.containsKey('last_seen')) {
      debugPrint('👁️ User last seen updated: ${data['last_seen']}');
    }
  }

  /// Handle messages update events
  void _handleMessagesUpdate(List<DocumentSnapshot> documents) {
    // Process new messages
    for (final doc in documents) {
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('📩 New message: ${data['message_id']}');
    }
    _safeNotify();
  }

  /// Handle online status update events
  void _handleOnlineStatusUpdate(List<DocumentSnapshot> documents) {
    // Process online status changes
    for (final doc in documents) {
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('🟢 User ${data['user_id']} is online');
    }
    _safeNotify();
  }

  /// Unsubscribe from profile updates
  Future<void> _unsubscribeFromProfileUpdates() async {
    final key = 'profile_${_currentUserId ?? ''}';
    if (_subscriptions.containsKey(key)) {
      await _subscriptions[key]!.cancel();
      _subscriptions.remove(key);
      debugPrint('🔕 Unsubscribed from profile updates');
    }
  }

  /// Unsubscribe from messaging updates
  Future<void> _unsubscribeFromMessaging() async {
    final key = 'messages_${_messagingUserId ?? _currentUserId ?? ''}';
    if (_subscriptions.containsKey(key)) {
      await _subscriptions[key]!.cancel();
      _subscriptions.remove(key);
      debugPrint('🔕 Unsubscribed from messaging updates');
    }
  }

  /// Unsubscribe from online status updates
  Future<void> _unsubscribeFromOnlineStatus() async {
    if (_subscriptions.containsKey('online_status')) {
      await _subscriptions['online_status']!.cancel();
      _subscriptions.remove('online_status');
      debugPrint('🔕 Unsubscribed from online status updates');
    }
  }

  /// Update user's online status
  Future<void> updateOnlineStatus(bool isOnline) async {
    if (_currentUserId == null) return;
    
    try {
      await _firestore.collection('user_status').doc(_currentUserId).set({
        'user_id': _currentUserId,
        'is_online': isOnline,
        'last_seen': FieldValue.serverTimestamp(),
      });
      debugPrint('🟢 Updated online status: $isOnline');
    } catch (e) {
      debugPrint('❌ Failed to update online status: $e');
    }
  }

  /// Get current online users count
  Future<int> getOnlineUsersCount() async {
    try {
      final snapshot = await _firestore
          .collection('user_status')
          .where('is_online', isEqualTo: true)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ Failed to get online users count: $e');
      return 0;
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get current user ID
  String? get currentUserId => _currentUserId;

  /// Get active subscriptions count
  int get activeSubscriptions => _subscriptions.length;

  @override
  void dispose() {
    _disposed = true; // 🔥 FIX: Mark as disposed first
    // Cancel all active subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _messagingUserId = null;
    _isInitialized = false;
    debugPrint('🔕 RealtimeSyncService disposed');
    super.dispose();
  }
}
