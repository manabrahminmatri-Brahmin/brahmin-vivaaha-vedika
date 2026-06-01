import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// RealtimeAnalyticsService - Working implementation with Firebase integration
/// 
/// Provides real-time analytics functionality by integrating with Firebase Firestore
/// and ProfileAnalyticsService. This service monitors user activity, profile views,
/// and other metrics in real-time.
class RealtimeAnalyticsService {
  static final RealtimeAnalyticsService _instance =
      RealtimeAnalyticsService._internal();
  factory RealtimeAnalyticsService() => _instance;
  RealtimeAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isInitialized = false;
  String? _currentProfileId;

  /// Initialize the realtime analytics service
  void initialize() {
    if (_isInitialized) return;
    
    try {
      debugPrint('📊 Initializing RealtimeAnalyticsService...');
      _isInitialized = true;
      debugPrint('✅ RealtimeAnalyticsService initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize RealtimeAnalyticsService: $e');
    }
  }

  /// Refresh analytics for a specific profile
  Future<void> refreshAnalytics(String profileId) async {
    if (!_isInitialized) initialize();

    // Cancel subscriptions for any previous profile so keys like profile_views_<oldId>
    // are not left running when [_currentProfileId] already points at [profileId].
    await _cancelAllSubscriptions();

    _currentProfileId = profileId;

    try {
      debugPrint('🔄 Refreshing analytics for profile: $profileId');
      
      // Subscribe to real-time profile views
      await _subscribeToProfileViews(profileId);
      
      // Subscribe to real-time user activity
      await _subscribeToUserActivity(profileId);
      
      // Subscribe to real-time interests
      await _subscribeToInterests(profileId);
      
      debugPrint('✅ Analytics refreshed for profile: $profileId');
    } catch (e) {
      debugPrint('❌ Failed to refresh analytics: $e');
    }
  }

  /// Subscribe to profile views in real-time
  Future<void> _subscribeToProfileViews(String profileId) async {
    try {
      // Cancel existing subscription if any
      await _unsubscribeFromProfileViews();
      
      // Avoid composite index dependency: sort client-side.
      final viewsSubscription = _firestore
          .collection('profile_views')
          .where('viewed_profile_id', isEqualTo: profileId)
          .limit(200)
          .snapshots()
          .listen((snapshot) {
            final views = snapshot.docs.length;
            debugPrint('👁️ Profile views updated: $views views');
            final docs = snapshot.docs.toList()
              ..sort((a, b) {
                final aT = a.data()['viewed_at'];
                final bT = b.data()['viewed_at'];
                final aDt = aT is Timestamp ? aT.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                final bDt = bT is Timestamp ? bT.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                return bDt.compareTo(aDt);
              });
            _handleProfileViewsUpdate(docs.take(50).toList());
          });
      
      _subscriptions['profile_views_$profileId'] = viewsSubscription;
      debugPrint('✅ Subscribed to profile views for: $profileId');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to profile views: $e');
    }
  }

  /// Subscribe to user activity in real-time
  Future<void> _subscribeToUserActivity(String profileId) async {
    try {
      // Cancel existing subscription if any
      await _unsubscribeFromUserActivity();
      
      final activitySubscription = _firestore
          .collection('user_activity')
          .where('profile_id', isEqualTo: profileId)
          .orderBy('created_at', descending: true)
          .limit(100)
          .snapshots()
          .listen((snapshot) {
            debugPrint('📱 User activity updated: ${snapshot.docs.length} activities');
            _handleUserActivityUpdate(snapshot.docs);
          });
      
      _subscriptions['user_activity_$profileId'] = activitySubscription;
      debugPrint('✅ Subscribed to user activity for: $profileId');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to user activity: $e');
    }
  }

  /// Subscribe to interests in real-time
  Future<void> _subscribeToInterests(String profileId) async {
    try {
      // Cancel existing subscription if any
      await _unsubscribeFromInterests();
      
      // App uses from_user_id/to_user_id (doc ids). Avoid composite index: sort client-side.
      final interestsSubscription = _firestore
          .collection('interests')
          .where('from_user_id', isEqualTo: profileId)
          .limit(200)
          .snapshots()
          .listen((snapshot) {
            debugPrint('❤️ Interests updated: ${snapshot.docs.length} interests');
            final docs = snapshot.docs.toList()
              ..sort((a, b) {
                final aT = a.data()['created_at'];
                final bT = b.data()['created_at'];
                final aDt = aT is Timestamp ? aT.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                final bDt = bT is Timestamp ? bT.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                return bDt.compareTo(aDt);
              });
            _handleInterestsUpdate(docs.take(50).toList());
          });
      
      _subscriptions['interests_$profileId'] = interestsSubscription;
      debugPrint('✅ Subscribed to interests for: $profileId');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to interests: $e');
    }
  }

  /// Handle profile views update
  void _handleProfileViewsUpdate(List<DocumentSnapshot> documents) {
    // Process new profile views
    for (final doc in documents) {
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('👁️ New profile view from: ${data['viewer_user_id']}');
    }
  }

  /// Handle user activity update
  void _handleUserActivityUpdate(List<DocumentSnapshot> documents) {
    // Process new user activities
    for (final doc in documents) {
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('📱 New activity: ${data['activity_type']}');
    }
  }

  /// Handle interests update
  void _handleInterestsUpdate(List<DocumentSnapshot> documents) {
    // Process new interests
    for (final doc in documents) {
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('❤️ New interest from: ${data['from_user_id']}');
    }
  }

  /// Get real-time analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary(String profileId) async {
    try {
      final profileViews = await _firestore
          .collection('profile_views')
          .where('viewed_profile_id', isEqualTo: profileId)
          .get();
      
      final interests = await _firestore
          .collection('interests')
          .where('from_user_id', isEqualTo: profileId)
          .get();
      
      final activities = await _firestore
          .collection('user_activity')
          .where('profile_id', isEqualTo: profileId)
          .get();
      
      return {
        'profileViews': profileViews.docs.length,
        'interests_sent': interests.docs.length,
        'userActivities': activities.docs.length,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Failed to get analytics summary: $e');
      return {
        'profileViews': 0,
        'interests_sent': 0,
        'userActivities': 0,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Track custom analytics event
  Future<void> trackEvent(String eventName, Map<String, dynamic> data) async {
    if (!_isInitialized) initialize();
    
    try {
      await _firestore.collection('analytics_events').add({
        'event_name': eventName,
        'data': data,
        'profile_id': _currentProfileId,
        'created_at': FieldValue.serverTimestamp(),
      });
      debugPrint('📊 Tracked event: $eventName');
    } catch (e) {
      debugPrint('❌ Failed to track event: $e');
    }
  }

  Future<void> _cancelAllSubscriptions() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Unsubscribe from profile views
  Future<void> _unsubscribeFromProfileViews() async {
    final key = 'profile_views_${_currentProfileId ?? ''}';
    if (_subscriptions.containsKey(key)) {
      await _subscriptions[key]!.cancel();
      _subscriptions.remove(key);
      debugPrint('🔕 Unsubscribed from profile views');
    }
  }

  /// Unsubscribe from user activity
  Future<void> _unsubscribeFromUserActivity() async {
    final key = 'user_activity_${_currentProfileId ?? ''}';
    if (_subscriptions.containsKey(key)) {
      await _subscriptions[key]!.cancel();
      _subscriptions.remove(key);
      debugPrint('🔕 Unsubscribed from user activity');
    }
  }

  /// Unsubscribe from interests
  Future<void> _unsubscribeFromInterests() async {
    final key = 'interests_${_currentProfileId ?? ''}';
    if (_subscriptions.containsKey(key)) {
      await _subscriptions[key]!.cancel();
      _subscriptions.remove(key);
      debugPrint('🔕 Unsubscribed from interests');
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get current profile ID
  String? get currentProfileId => _currentProfileId;

  /// Get active subscriptions count
  int get activeSubscriptions => _subscriptions.length;

  /// Dispose the service
  void dispose() {
    // Cancel all active subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _isInitialized = false;
    _currentProfileId = null;
    debugPrint('🔕 RealtimeAnalyticsService disposed');
  }
}
