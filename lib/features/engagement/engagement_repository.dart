import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/identity_service.dart';
import '../../core/contract.dart';

/// Engagement Repository
/// 
/// Consolidates engagement data operations from:
/// - interest_repository.dart
/// - like_repository.dart
/// - user_action_service.dart (data parts)
class EngagementRepository {
  static final EngagementRepository _instance = EngagementRepository._internal();
  factory EngagementRepository() => _instance;
  EngagementRepository._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isInitialized = false;

  /// Initialize engagement repository
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('✅ EngagementRepository: Initialized successfully');
    } catch (e) {
      debugPrint('❌ EngagementRepository initialization failed: $e');
      rethrow;
    }
  }

  /// Get user engagement summary
  Future<Map<String, dynamic>> getUserEngagementSummary(String userId) async {
    try {
      await _ensureInitialized();
      
      // Get all engagement data
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final interestsSent = await _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .get();

      final interestsReceived = await _db
          .collection('interests')
          .where('to_user_id', isEqualTo: userId)
          .get();

      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final likesSent = await _db
          .collection('likes')
          .where('from_user_id', isEqualTo: userId)
          .get();

      final likesReceived = await _db
          .collection('likes')
          .where('to_user_id', isEqualTo: userId)
          .get();

      final profileViews = await _db
          .collection('profile_views')
          .where('viewer_user_id', isEqualTo: userId)
          .get();

      // Calculate statistics
      final interestsSentByStatus = <String, int>{};
      final interestsReceivedByStatus = <String, int>{};

      for (final doc in interestsSent.docs) {
        final status = doc['status'] as String;
        interestsSentByStatus[status] = (interestsSentByStatus[status] ?? 0) + 1;
      }

      for (final doc in interestsReceived.docs) {
        final status = doc['status'] as String;
        interestsReceivedByStatus[status] = (interestsReceivedByStatus[status] ?? 0) + 1;
      }

      // Get mutual connections
      final mutualInterests = await _getMutualInterests(userId);
      final mutualLikes = await _getMutualLikes(userId);

      return {
        'interests': {
          'sent': interestsSentByStatus,
          'received': interestsReceivedByStatus,
          'totalSent': interestsSent.docs.length,
          'totalReceived': interestsReceived.docs.length,
        },
        'likes': {
          'sent': likesSent.docs.length,
          'received': likesReceived.docs.length,
          'mutual': mutualLikes.length,
        },
        'profileViews': profileViews.docs.length,
        'mutualInterests': mutualInterests.length,
        'totalEngagements': interestsSent.docs.length + interestsReceived.docs.length + 
                            likesSent.docs.length + likesReceived.docs.length + 
                            profileViews.docs.length,
      };
    } catch (e) {
      debugPrint('❌ Failed to get user engagement summary: $e');
      return {};
    }
  }

  /// Get mutual interests
  Future<List<Map<String, dynamic>>> _getMutualInterests(String userId) async {
    try {
      final mutualInterests = <Map<String, dynamic>>[];
      
      // Get accepted interests sent by user
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final sentInterests = await _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .where('status', isEqualTo: 'accepted')
          .get();

      // Check for reciprocal interests
      for (final sentDoc in sentInterests.docs) {
        final data = sentDoc.data();
        // 🔥 FIX: Read with fallback for both conventions
        final receiverId = (data['to_user_id'] ?? data['receiverId']) as String?;
        if (receiverId == null) continue;

        final reciprocalDoc = await _db
            .collection('interests')
            .where('from_user_id', isEqualTo: receiverId)
            .where('to_user_id', isEqualTo: userId)
            .where('status', isEqualTo: 'accepted')
            .get();

        if (reciprocalDoc.docs.isNotEmpty) {
          final recipData = reciprocalDoc.docs.first.data();
          mutualInterests.add({
            'user_id': receiverId,
            'sentInterestId': sentDoc.id,
            'receivedInterestId': reciprocalDoc.docs.first.id,
            // 🔥 FIX: Read with fallback for both conventions
            'matchedAt': recipData['responded_at'] ?? recipData['respondedAt'],
          });
        }
      }

      return mutualInterests;
    } catch (e) {
      debugPrint('Failed to get mutual interests: $e');
      return [];
    }
  }

  /// Get mutual likes
  Future<List<Map<String, dynamic>>> _getMutualLikes(String userId) async {
    try {
      final mutualLikes = <Map<String, dynamic>>[];
      
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      // Get likes sent by user
      final sentLikes = await _db
          .collection('likes')
          .where('from_user_id', isEqualTo: userId)
          .get();

      // Check for reciprocal likes
      for (final sentDoc in sentLikes.docs) {
        final data = sentDoc.data();
        final likedUserId = (data['to_user_id'] ?? data['likedUserId']) as String?;
        if (likedUserId == null) continue;
        
        final reciprocalDoc = await _db
            .collection('likes')
            .where('from_user_id', isEqualTo: likedUserId)
            .where('to_user_id', isEqualTo: userId)
            .get();

        if (reciprocalDoc.docs.isNotEmpty) {
          final recipData = reciprocalDoc.docs.first.data();
          mutualLikes.add({
            'user_id': likedUserId,
            'sentLikeId': sentDoc.id,
            'receivedLikeId': reciprocalDoc.docs.first.id,
            'mutualLikedAt': recipData['created_at'] ?? recipData['likedAt'],
          });
        }
      }

      return mutualLikes;
    } catch (e) {
      debugPrint('Failed to get mutual likes: $e');
      return [];
    }
  }

  /// Get engagement history
  Future<List<Map<String, dynamic>>> getEngagementHistory({
    required String userId,
    String? type, // 'interest', 'like', 'view'
    int limit = 50,
    DocumentSnapshot? lastDoc,
  }) async {
    try {
      await _ensureInitialized();
      
      final history = <Map<String, dynamic>>[];
      
      // Get interests
      if (type == null || type == 'interest') {
        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final interestsQuery = _db.collection('interests')
            .where('from_user_id', isEqualTo: userId)
            .orderBy('created_at', descending: true);

        final interestsSnapshot = await (lastDoc != null
            ? interestsQuery.startAfterDocument(lastDoc)
            : interestsQuery).limit(limit ~/ 3).get();

        for (final doc in interestsSnapshot.docs) {
          final data = doc.data();
          history.add({
            'id': doc.id,
            'type': 'interest',
            'action': 'sent',
            // 🔥 FIX: Read with fallback for both conventions
            'targetUserId': data['to_user_id'] ?? data['receiverId'],
            'timestamp': data['created_at'] ?? data['sentAt'],
            'status': data['status'],
            'data': data,
          });
        }
      }

      // Get likes
      if (type == null || type == 'like') {
        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final likesQuery = _db.collection('likes')
            .where('from_user_id', isEqualTo: userId)
            .orderBy('created_at', descending: true);

        final likesSnapshot = await (lastDoc != null 
            ? likesQuery.startAfterDocument(lastDoc)
            : likesQuery).limit(limit ~/ 3).get();

        for (final doc in likesSnapshot.docs) {
          final data = doc.data();
          history.add({
            'id': doc.id,
            'type': 'like',
            'action': 'sent',
            // 🔥 FIX: Read with fallbacks for both old and new field names
            'targetUserId': data['to_user_id'] ?? data['likedUserId'],
            'timestamp': data['created_at'] ?? data['likedAt'],
            'data': data,
          });
        }
      }

      // Get profile views
      if (type == null || type == 'view') {
        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final viewsQuery = _db.collection('profile_views')
            .where('viewer_user_id', isEqualTo: userId)
            .orderBy('viewed_at', descending: true);

        final viewsSnapshot = await (lastDoc != null
            ? viewsQuery.startAfterDocument(lastDoc)
            : viewsQuery).limit(limit ~/ 3).get();

        for (final doc in viewsSnapshot.docs) {
          final data = doc.data();
          history.add({
            'id': doc.id,
            'type': 'view',
            'action': 'viewed',
            // 🔥 FIX: Read with fallback for both conventions
            'targetUserId': data['viewed_profile_id'] ?? data['viewedUserId'],
            'timestamp': data['viewed_at'] ?? data['viewedAt'],
            'data': data,
          });
        }
      }

      // Sort by timestamp and limit
      history.sort((a, b) => (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));
      
      return history.take(limit).toList();
    } catch (e) {
      debugPrint('❌ Failed to get engagement history: $e');
      return [];
    }
  }

  /// Get engagement trends
  Future<Map<String, dynamic>> getEngagementTrends({
    required String userId,
    int days = 30,
  }) async {
    try {
      await _ensureInitialized();
      
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));
      
      // Get daily engagement data
      final dailyData = <Map<String, dynamic>>[];
      
      for (int i = 0; i < days; i++) {
        final date = startDate.add(Duration(days: i));
        final dayStart = DateTime(date.year, date.month, date.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        
        // Get counts for this day
        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final interestsCount = await _db
            .collection('interests')
            .where('from_user_id', isEqualTo: userId)
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
            .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
            .get();

        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final likesCount = await _db
            .collection('likes')
            .where('from_user_id', isEqualTo: userId)
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
            .where('created_at', isLessThan: Timestamp.fromDate(dayEnd))
            .get();

        // 🔥 FIX: Use snake_case field names matching Firestore rules
        final viewsCount = await _db
            .collection('profile_views')
            .where('viewer_user_id', isEqualTo: userId)
            .where('viewed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
            .where('viewed_at', isLessThan: Timestamp.fromDate(dayEnd))
            .get();

        dailyData.add({
          'date': dayStart.toIso8601String(),
          'interests': interestsCount.docs.length,
          'likes': likesCount.docs.length,
          'views': viewsCount.docs.length,
          'total': interestsCount.docs.length + likesCount.docs.length + viewsCount.docs.length,
        });
      }

      // Calculate trends
      final totalInterests = dailyData.fold<int>(0, (acc, day) => acc + day['interests'] as int);
      final totalLikes = dailyData.fold<int>(0, (acc, day) => acc + day['likes'] as int);
      final totalViews = dailyData.fold<int>(0, (acc, day) => acc + day['views'] as int);
      
      final avgDailyInterests = totalInterests / days;
      final avgDailyLikes = totalLikes / days;
      final avgDailyViews = totalViews / days;

      return {
        'period': '$days days',
        'dailyData': dailyData,
        'totals': {
          'interests': totalInterests,
          'likes': totalLikes,
          'views': totalViews,
          'total': totalInterests + totalLikes + totalViews,
        },
        'averages': {
          'dailyInterests': avgDailyInterests,
          'dailyLikes': avgDailyLikes,
          'dailyViews': avgDailyViews,
          'dailyTotal': avgDailyInterests + avgDailyLikes + avgDailyViews,
        },
      };
    } catch (e) {
      debugPrint('❌ Failed to get engagement trends: $e');
      return {};
    }
  }

  /// Get top engaged users
  Future<List<Map<String, dynamic>>> getTopEngagedUsers({
    required String userId,
    int limit = 10,
  }) async {
    try {
      await _ensureInitialized();
      
      // Get all users the current user has engaged with
      final engagedUsers = <String, Map<String, dynamic>>{};
      
      // From interests
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final interestsSent = await _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .get();

      for (final doc in interestsSent.docs) {
        final data = doc.data();
        // 🔥 FIX: Read with fallback for both conventions
        final targetUserId = (data['to_user_id'] ?? data['receiverId']) as String?;
        if (targetUserId == null) continue;
        engagedUsers.putIfAbsent(targetUserId, () => {'interests': 0, 'likes': 0, 'views': 0});
        engagedUsers[targetUserId]!['interests'] = (engagedUsers[targetUserId]!['interests'] as int) + 1;
      }

      // From likes
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final likesSent = await _db
          .collection('likes')
          .where('from_user_id', isEqualTo: userId)
          .get();

      for (final doc in likesSent.docs) {
        final data = doc.data();
        final targetUserId = (data['to_user_id'] ?? data['likedUserId']) as String?;
        if (targetUserId == null) continue;
        engagedUsers.putIfAbsent(targetUserId, () => {'interests': 0, 'likes': 0, 'views': 0});
        engagedUsers[targetUserId]!['likes'] = (engagedUsers[targetUserId]!['likes'] as int) + 1;
      }

      // From profile views
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final profileViews = await _db
          .collection('profile_views')
          .where('viewer_user_id', isEqualTo: userId)
          .get();

      for (final doc in profileViews.docs) {
        final data = doc.data();
        // 🔥 FIX: Read with fallback for both conventions
        final targetUserId = (data['viewed_profile_id'] ?? data['viewedUserId']) as String?;
        if (targetUserId == null) continue;
        engagedUsers.putIfAbsent(targetUserId, () => {'interests': 0, 'likes': 0, 'views': 0});
        engagedUsers[targetUserId]!['views'] = (engagedUsers[targetUserId]!['views'] as int) + 1;
      }

      // Convert to list and sort by total engagement
      final sortedUsers = engagedUsers.entries.map((entry) {
        final data = entry.value;
        final total = (data['interests'] as int) + (data['likes'] as int) + (data['views'] as int);
        
        return {
          'user_id': entry.key,
          'interests': data['interests'],
          'likes': data['likes'],
          'views': data['views'],
          'total': total,
        };
      }).toList();

      sortedUsers.sort((a, b) => b['total'].compareTo(a['total']));

      // Get user details for top users
      final topUsers = <Map<String, dynamic>>[];
      
      for (final userData in sortedUsers.take(limit)) {
        final userDoc = await _db.collection(Collections.users).doc(userData['user_id'] as String).get();
        if (userDoc.exists) {
          final userInfo = userDoc.data()!;
          // 🔥 FIX: Read from nested profile map with snake_case keys
          final profileMap = (userInfo['profile'] as Map<String, dynamic>?) ?? {};
          topUsers.add({
            ...userData,
            'name': '${profileMap['first_name'] ?? ''} ${profileMap['last_name'] ?? ''}',
            'photoUrl': profileMap['photo_url'],
            'age': profileMap['age'],
            'location': profileMap['city'],
          });
        }
      }

      return topUsers;
    } catch (e) {
      debugPrint('❌ Failed to get top engaged users: $e');
      return [];
    }
  }

  /// Get engagement score
  Future<double> getEngagementScore(String userId) async {
    try {
      await _ensureInitialized();
      
      final summary = await getUserEngagementSummary(userId);
      
      // Calculate engagement score based on various factors
      double score = 0.0;
      
      // Interest engagement (40% weight)
      final interestScore = (summary['interests']['totalSent'] as int? ?? 0) * 2.0 +
                           (summary['interests']['totalReceived'] as int? ?? 0) * 1.5;
      score += interestScore * 0.4;
      
      // Like engagement (30% weight)
      final likeScore = (summary['likes']['sent'] as int? ?? 0) * 1.5 +
                       (summary['likes']['received'] as int? ?? 0) * 1.0;
      score += likeScore * 0.3;
      
      // Profile view engagement (20% weight)
      final viewScore = (summary['profileViews'] as int? ?? 0) * 0.5;
      score += viewScore * 0.2;
      
      // Mutual connections bonus (10% weight)
      final mutualScore = (summary['mutualInterests'] as int? ?? 0) * 5.0 +
                         (summary['likes']['mutual'] as int? ?? 0) * 3.0;
      score += mutualScore * 0.1;
      
      return score;
    } catch (e) {
      debugPrint('❌ Failed to get engagement score: $e');
      return 0.0;
    }
  }

  /// Batch update engagement data
  Future<void> batchUpdateEngagement({
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _ensureInitialized();
      
      final batch = _db.batch();
      
      for (final entry in updates.entries) {
        final userId = entry.key;
        final userUpdates = entry.value as Map<String, dynamic>;
        
        final userRef = _db.collection(Collections.users).doc(userId);
        batch.update(userRef, {
          ...userUpdates,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      
      debugPrint('✅ Batch engagement update completed');
    } catch (e) {
      debugPrint('❌ Failed to batch update engagement: $e');
      rethrow;
    }
  }

  /// Clean up old engagement data
  Future<void> cleanupOldEngagementData({int daysToKeep = 90}) async {
    try {
      await _ensureInitialized();
      
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      
      // Clean up old profile views
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final oldViews = await _db
          .collection('profile_views')
          .where('viewed_at', isLessThan: Timestamp.fromDate(cutoffDate))
          .limit(1000)
          .get();

      for (final doc in oldViews.docs) {
        await doc.reference.delete();
      }
      
      debugPrint('✅ Cleaned up ${oldViews.docs.length} old profile views');
    } catch (e) {
      debugPrint('❌ Failed to cleanup old engagement data: $e');
    }
  }

  /// Send interest to a user
  Future<bool> sendInterest(String targetUserId) async {
    try {
      await _ensureInitialized();
      
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final userId = await identityService.getUserId();

      // Check if interest already exists
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final existingInterest = await _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .where('to_user_id', isEqualTo: targetUserId)
          .get();

      if (existingInterest.docs.isNotEmpty) {
        return false; // Interest already sent
      }

      // Create new interest
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      await _db.collection('interests').add({
        'from_user_id': userId,
        'to_user_id': targetUserId,
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      debugPrint('✅ Interest sent to user: $targetUserId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send interest: $e');
      return false;
    }
  }

  /// Remove interest from a user
  Future<bool> removeInterest(String targetUserId) async {
    try {
      await _ensureInitialized();
      
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final userId = await identityService.getUserId();

      // Find and delete existing interest
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final existingInterest = await _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .where('to_user_id', isEqualTo: targetUserId)
          .get();

      for (final doc in existingInterest.docs) {
        await doc.reference.delete();
      }

      debugPrint('✅ Interest removed for user: $targetUserId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to remove interest: $e');
      return false;
    }
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
