import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/identity_service.dart';
import '../../core/contract.dart';
import '../../services/profile_views_privacy.dart';
import '../../services/engagement_gateway_service.dart';

/// Profile Analytics Service
///
/// Consolidates analytics operations from:
/// - profile_analytics_service.dart
/// - user_activity_service.dart
class AnalyticsService extends ChangeNotifier {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  SharedPreferences? _prefs;

  bool _isInitialized = false;

  // Stream controllers for real-time updates
  final StreamController<Map<String, dynamic>> _analyticsStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  bool get isInitialized => _isInitialized;
  Stream<Map<String, dynamic>> get analyticsStream =>
      _analyticsStreamController.stream;

  static const String _lastSyncKey = 'analytics_last_sync';

  final List<_QueuedProfileView> _profileViewQueue = [];
  Timer? _profileViewFlushTimer;
  bool _profileViewFlushInProgress = false;
  static const int _kProfileViewFlushMaxBatch = 20;
  static const Duration _kProfileViewFlushDelay = Duration(seconds: 30);

  /// Initialize analytics service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('✅ AnalyticsService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ AnalyticsService initialization failed: $e');
      rethrow;
    }
  }

  /// Track profile view with permission-denied handling
  Future<void> trackProfileView({
    required String viewerId,
    required String viewedUserId,
  }) async {
    try {
      await _ensureInitialized();
      _profileViewQueue.add(_QueuedProfileView(viewerId, viewedUserId));
      _profileViewFlushTimer?.cancel();
      if (_profileViewQueue.length >= _kProfileViewFlushMaxBatch) {
        await _flushProfileViewQueue();
      } else {
        _profileViewFlushTimer = Timer(_kProfileViewFlushDelay, () {
          // ignore: discarded_futures
          _flushProfileViewQueue();
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to queue profile view: $e');
    }
  }

  Future<void> _flushProfileViewQueue() async {
    if (_profileViewFlushInProgress) return;
    _profileViewFlushTimer?.cancel();
    _profileViewFlushTimer = null;
    if (_profileViewQueue.isEmpty) return;

    _profileViewFlushInProgress = true;
    final queued = List<_QueuedProfileView>.from(_profileViewQueue);
    _profileViewQueue.clear();

    final incognitoCache = <String, bool>{};
    final writable = <_QueuedProfileView>[];
    for (final q in queued) {
      if (await ProfileViewsPrivacy.viewerIsIncognito(
        q.viewerId,
        cache: incognitoCache,
      )) {
        continue;
      }
      writable.add(q);
    }
    if (writable.isEmpty) {
      _profileViewFlushInProgress = false;
      return;
    }

    try {
      var applied = 0;
      for (final q in writable) {
        final result = await EngagementGatewayService.recordProfileView(
          viewedUserId: q.viewedUserId,
        );
        if (result['success'] == true) {
          applied++;
          _emitAnalyticsUpdate(q.viewedUserId, 'profile_view', {
            'viewer_user_id': q.viewerId,
            'viewed_at': DateTime.now().toIso8601String(),
          });
        }
      }
      debugPrint(
        '✅ Profile views flushed via gateway: $applied/${writable.length}',
      );
    } catch (e) {
      debugPrint('❌ Failed to flush profile views: $e');
    } finally {
      _profileViewFlushInProgress = false;
    }
  }

  /// 🔥 SYNC AUTH UID: Ensure auth_uid is synced for security rule compliance
  Future<void> _syncAuthUid(String userId) async {
    try {
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final firebaseAuthUid = await identityService.getFirebaseAuthUid();
      if (firebaseAuthUid == null) return;

      await _db.collection(Collections.users).doc(userId).set({
        'auth_uid': firebaseAuthUid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ Failed to sync auth_uid in AnalyticsService: $e');
    }
  }

  /// Track interest sent with permission handling
  Future<void> trackInterestSent({
    required String senderId,
    required String receiverId,
  }) async {
    try {
      await _ensureInitialized();

      // 🔥 CRITICAL: Sync auth_uid before any writes for security rule compliance
      await _syncAuthUid(senderId);

      final batch = _db.batch();

      // Update sender's activity
      final senderRef = _db.collection(Collections.users).doc(senderId);
      batch.update(senderRef, {
        'interests_sent': FieldValue.increment(1),
        'last_active': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Update receiver's analytics
      final receiverRef = _db.collection(Collections.users).doc(receiverId);
      batch.update(receiverRef, {
        'interests_received': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Create interest record
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final interestRef = _db.collection('interests').doc();
      batch.set(interestRef, {
        'from_user_id': senderId,
        'to_user_id': receiverId,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Emit analytics update
      // 🔥 FIX: Use snake_case field names
      _emitAnalyticsUpdate(senderId, 'interest_sent', {
        'to_user_id': receiverId,
        'sent_at': DateTime.now().toIso8601String(),
      });

      _emitAnalyticsUpdate(receiverId, 'interest_received', {
        'from_user_id': senderId,
        'received_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Interest tracked: $senderId -> $receiverId');
    } on FirebaseException catch (e) {
      // 🔥 PROFESSIONAL FIX: Handle permission denied gracefully
      if (e.code == 'permission-denied') {
        debugPrint(
            '🔒 Permission denied tracking interest (non-critical): $senderId -> $receiverId');
        return;
      }
      debugPrint(
          '❌ Firebase error tracking interest: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('❌ Failed to track interest: $e');
    }
  }

  /// Track like sent with permission handling
  Future<void> trackLikeSent({
    required String senderId,
    required String receiverId,
  }) async {
    try {
      await _ensureInitialized();

      // 🔥 CRITICAL: Sync auth_uid before any writes for security rule compliance
      await _syncAuthUid(senderId);

      final batch = _db.batch();

      // Update sender's activity
      final senderRef = _db.collection(Collections.users).doc(senderId);
      batch.update(senderRef, {
        'likes_sent': FieldValue.increment(1),
        'last_active': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Update receiver's analytics
      final receiverRef = _db.collection(Collections.users).doc(receiverId);
      batch.update(receiverRef, {
        'likes_received': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Create like record
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final likeRef = _db.collection('likes').doc();
      batch.set(likeRef, {
        'from_user_id': senderId,
        'to_user_id': receiverId,
        'created_at': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Emit analytics update
      // 🔥 FIX: Use snake_case field names
      _emitAnalyticsUpdate(senderId, 'like_sent', {
        'to_user_id': receiverId,
        'liked_at': DateTime.now().toIso8601String(),
      });

      // 🔥 FIX: Use snake_case field names
      _emitAnalyticsUpdate(receiverId, 'like_received', {
        'from_user_id': senderId,
        'liked_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Like tracked: $senderId -> $receiverId');
    } on FirebaseException catch (e) {
      // 🔥 PROFESSIONAL FIX: Handle permission denied gracefully
      if (e.code == 'permission-denied') {
        debugPrint(
            '🔒 Permission denied tracking like (non-critical): $senderId -> $receiverId');
        return;
      }
      debugPrint('❌ Firebase error tracking like: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('❌ Failed to track like: $e');
    }
  }

  /// Get user analytics summary
  Future<Map<String, dynamic>> getUserAnalytics(String userId) async {
    try {
      await _ensureInitialized();

      final userDoc = await _db.collection(Collections.users).doc(userId).get();
      if (!userDoc.exists) return {};

      final userData = userDoc.data() ?? {};

      return {
        'profileViewsSent': userData['profile_views_sent'] ?? 0,
        'profileViewsReceived': userData['profile_views_received'] ?? 0,
        'interests_sent': userData['interests_sent'] ?? 0,
        'interests_received': userData['interests_received'] ?? 0,
        'likes_sent': userData['likes_sent'] ?? 0,
        'likes_received': userData['likes_received'] ?? 0,
        'last_active': userData['last_active'],
        'created_at': userData['created_at'],
        'updated_at': userData['updated_at'],
      };
    } catch (e) {
      debugPrint('❌ Failed to get user analytics: $e');
      return {};
    }
  }

  /// Get detailed profile views
  Future<List<Map<String, dynamic>>> getProfileViews({
    required String userId,
    bool received = true,
    int limit = 50,
  }) async {
    try {
      await _ensureInitialized();

      Query query = _db.collection('profile_views');

      // 🔥 FIX: Use snake_case field names matching Firestore rules
      if (received) {
        query = query.where('viewed_profile_id', isEqualTo: userId);
      } else {
        query = query.where('viewer_user_id', isEqualTo: userId);
      }

      query = query.orderBy('viewed_at', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data =
            (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        return {
          'id': doc.id,
          // 🔥 FIX: Read with fallback for both conventions
          'viewerId': data['viewer_user_id'] ?? data['viewerId'] ?? '',
          'viewedUserId':
              data['viewed_profile_id'] ?? data['viewedUserId'] ?? '',
          'viewedAt': data['viewed_at'] ?? data['viewedAt'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get profile views: $e');
      return [];
    }
  }

  /// Get detailed interests
  Future<List<Map<String, dynamic>>> getInterests({
    required String userId,
    bool received = true,
    String? status,
    int limit = 50,
  }) async {
    try {
      await _ensureInitialized();

      Query query = _db.collection('interests');

      // 🔥 FIX: Use snake_case field names matching Firestore rules
      if (received) {
        query = query.where('to_user_id', isEqualTo: userId);
      } else {
        query = query.where('from_user_id', isEqualTo: userId);
      }

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      query = query.orderBy('created_at', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data =
            (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        return {
          'id': doc.id,
          // 🔥 FIX: Read with fallback for both conventions
          'senderId': data['from_user_id'] ?? data['senderId'] ?? '',
          'receiverId': data['to_user_id'] ?? data['receiverId'] ?? '',
          'status': data['status'] ?? '',
          'sentAt': data['created_at'] ?? data['sentAt'] ?? '',
          'respondedAt': data['responded_at'] ?? data['respondedAt'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get interests: $e');
      return [];
    }
  }

  /// Get detailed likes
  Future<List<Map<String, dynamic>>> getLikes({
    required String userId,
    bool received = true,
    int limit = 50,
  }) async {
    try {
      await _ensureInitialized();

      Query query = _db.collection('likes');

      // 🔥 FIX: Use snake_case field names in queries and reads
      if (received) {
        query = query.where('to_user_id', isEqualTo: userId);
      } else {
        query = query.where('from_user_id', isEqualTo: userId);
      }

      query = query.orderBy('created_at', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data =
            (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        return {
          'id': doc.id,
          // 🔥 FIX: Read with fallback for both conventions
          'senderId': data['from_user_id'] ?? data['senderId'] ?? '',
          'receiverId': data['to_user_id'] ?? data['receiverId'] ?? '',
          'likedAt': data['created_at'] ?? data['likedAt'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get likes: $e');
      return [];
    }
  }

  /// Get daily activity stats
  Future<Map<String, dynamic>> getDailyActivityStats({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      await _ensureInitialized();

      final now = DateTime.now();
      final start = startDate ?? DateTime(now.year, now.month, now.day);
      final end = endDate ?? start.add(const Duration(days: 1));

      // This would typically use a more sophisticated aggregation
      // For now, we'll return basic stats
      // 🔥 FIX: Use snake_case field names in queries
      final profileViews = await _db
          .collection('profile_views')
          .where('viewed_profile_id', isEqualTo: userId)
          .where('viewed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('viewed_at', isLessThan: Timestamp.fromDate(end))
          .get();

      final interests = await _db
          .collection('interests')
          .where('to_user_id', isEqualTo: userId)
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('created_at', isLessThan: Timestamp.fromDate(end))
          .get();

      final likes = await _db
          .collection('likes')
          .where('to_user_id', isEqualTo: userId)
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('created_at', isLessThan: Timestamp.fromDate(end))
          .get();

      return {
        'date': start.toIso8601String(),
        'profileViews': profileViews.docs.length,
        'interests_received': interests.docs.length,
        'likes_received': likes.docs.length,
      };
    } catch (e) {
      debugPrint('❌ Failed to get daily activity stats: $e');
      return {};
    }
  }

  /// Get weekly activity stats
  Future<List<Map<String, dynamic>>> getWeeklyActivityStats(
      String userId) async {
    try {
      await _ensureInitialized();

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final stats = <Map<String, dynamic>>[];

      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final dayStats = await getDailyActivityStats(
          userId: userId,
          startDate: DateTime(day.year, day.month, day.day),
          endDate: DateTime(day.year, day.month, day.day + 1),
        );

        stats.add(dayStats);
      }

      return stats;
    } catch (e) {
      debugPrint('❌ Failed to get weekly activity stats: $e');
      return [];
    }
  }

  /// Get monthly activity stats
  Future<Map<String, dynamic>> getMonthlyActivityStats(String userId) async {
    try {
      await _ensureInitialized();

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0);

      // 🔥 FIX: Use snake_case field names in queries
      final profileViews = await _db
          .collection('profile_views')
          .where('viewed_profile_id', isEqualTo: userId)
          .where('viewed_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('viewed_at', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      final interests = await _db
          .collection('interests')
          .where('to_user_id', isEqualTo: userId)
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('created_at', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      final likes = await _db
          .collection('likes')
          .where('to_user_id', isEqualTo: userId)
          .where('created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('created_at', isLessThan: Timestamp.fromDate(monthEnd))
          .get();

      return {
        'month': monthStart.toIso8601String(),
        'totalProfileViews': profileViews.docs.length,
        'totalInterestsReceived': interests.docs.length,
        'totalLikesReceived': likes.docs.length,
        'averageDailyViews':
            profileViews.docs.length / DateTime(now.year, now.month + 1, 0).day,
      };
    } catch (e) {
      debugPrint('❌ Failed to get monthly activity stats: $e');
      return {};
    }
  }

  /// Get top viewers
  Future<List<Map<String, dynamic>>> getTopViewers(String userId,
      {int limit = 10}) async {
    try {
      await _ensureInitialized();

      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final snapshot = await _db
          .collection('profile_views')
          .where('viewed_profile_id', isEqualTo: userId)
          .orderBy('viewed_at', descending: true)
          .limit(limit * 3) // Get more to aggregate
          .get();

      final viewerCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // 🔥 FIX: Read with fallback for both conventions
        final viewerId =
            (data['viewer_user_id'] ?? data['viewerId']) as String?;
        if (viewerId == null) continue;
        viewerCounts[viewerId] = (viewerCounts[viewerId] ?? 0) + 1;
      }

      final sortedViewers = viewerCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final topViewers = <Map<String, dynamic>>[];

      for (final entry in sortedViewers.take(limit)) {
        final userDoc = await _db.collection(Collections.users).doc(entry.key).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          // 🔥 FIX: Read from nested profile map with snake_case keys
          final profileMap =
              (userData['profile'] as Map<String, dynamic>?) ?? {};
          topViewers.add({
            'user_id': entry.key,
            'viewCount': entry.value,
            'name':
                '${profileMap['first_name'] ?? ''} ${profileMap['last_name'] ?? ''}',
            'photoUrl': profileMap['photo_url'],
          });
        }
      }

      return topViewers;
    } catch (e) {
      debugPrint('❌ Failed to get top viewers: $e');
      return [];
    }
  }

  /// Sync analytics data
  Future<void> syncAnalyticsData() async {
    try {
      await _ensureInitialized();

      final lastSync = _prefs?.getInt(_lastSyncKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Sync only if more than 1 hour has passed
      if (now - lastSync < 3600000) {
        return;
      }

      // Perform sync operations here
      // This would typically sync with analytics backend

      await _prefs?.setInt(_lastSyncKey, now);

      debugPrint('✅ Analytics data synced');
    } catch (e) {
      debugPrint('❌ Failed to sync analytics data: $e');
    }
  }

  /// Track app performance metrics from shared monitoring services.
  void trackPerformance(String metric, double value, {String? unit}) {
    debugPrint('⚡ Performance: $metric = $value${unit ?? ''}');
    _analyticsStreamController.add({
      'type': 'performance',
      'data': {
        'metric': metric,
        'value': value,
        if (unit != null) 'unit': unit,
      },
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Emit analytics update
  void _emitAnalyticsUpdate(
      String userId, String type, Map<String, dynamic> data) {
    _analyticsStreamController.add({
      'user_id': userId,
      'type': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  Map<String, dynamic>? _cachedAnalytics;
  int get totalProfileViews =>
      (_cachedAnalytics?['profileViewsReceived'] as int?) ?? 0;
  int get todayProfileViews =>
      (_cachedAnalytics?['profileViewsReceived'] as int?) ??
      0; // Same as total for now
  int get totalInterestsReceived =>
      (_cachedAnalytics?['interests_received'] as int?) ?? 0;
  int get totalInterestsSent =>
      (_cachedAnalytics?['interests_sent'] as int?) ?? 0;

  Future<void> loadAnalyticsForUser(String userId) async {
    _cachedAnalytics = await getUserAnalytics(userId);
    notifyListeners(); // if ChangeNotifier
  }

  Future<void> recordProfileView({
    required String viewerId,
    required String viewedUserId,
  }) =>
      trackProfileView(viewerId: viewerId, viewedUserId: viewedUserId);

  /// Dispose resources
  @override
  void dispose() {
    _profileViewFlushTimer?.cancel();
    // ignore: discarded_futures
    _flushProfileViewQueue();
    _analyticsStreamController.close();
    super.dispose();
  }
}

class _QueuedProfileView {
  const _QueuedProfileView(this.viewerId, this.viewedUserId);
  final String viewerId;
  final String viewedUserId;
}
