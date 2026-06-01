import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/profile_completion_policy.dart';
import '../../models/gender.dart';
import '../../models/user.dart' as app_models;
import '../../core/contract.dart';

/// Recommendation Engine
/// 
/// Consolidates recommendation operations from:
/// - recommendation_service.dart
/// - app_recommendation_service.dart
class RecommendationEngine {
  static final RecommendationEngine _instance = RecommendationEngine._internal();
  factory RecommendationEngine() => _instance;
  RecommendationEngine._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Random _random = Random();

  bool _isInitialized = false;

  /// Initialize recommendation engine
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('✅ RecommendationEngine: Initialized successfully');
    } catch (e) {
      debugPrint('❌ RecommendationEngine initialization failed: $e');
      rethrow;
    }
  }

  /// Get personalized recommendations for user
  Future<List<app_models.User>> getPersonalizedRecommendations({
    required String userId,
    int limit = 20,
    bool includeRandom = true,
  }) async {
    try {
      await _ensureInitialized();
      
      // Get user profile for personalization
      final userDoc = await _db.collection(Collections.users).doc(userId).get();
      if (!userDoc.exists) return [];

      final userData = userDoc.data()!;

      // Interactions + candidates only depend on userId + userData — run in parallel.
      final parallel = await Future.wait([
        _getUserInteractions(userId),
        _getCandidateProfiles(userId, userData),
      ]);
      final interactions = parallel[0] as Map<String, dynamic>;
      final candidates = parallel[1] as List<app_models.User>;
      
      // Score and rank candidates
      final scoredCandidates = await _scoreCandidates(
        candidates,
        userData,
        interactions,
      );
      
      // Sort by score and apply diversity
      scoredCandidates.sort((a, b) => b['score'].compareTo(a['score']));
      
      // Apply diversity algorithm if requested
      final recommendations = includeRandom 
          ? _applyDiversity(scoredCandidates, limit)
          : scoredCandidates.take(limit).map((item) => item['user'] as app_models.User).toList();
      
      debugPrint('✅ Generated ${recommendations.length} recommendations for user: $userId');
      return recommendations;
    } catch (e) {
      debugPrint('❌ Failed to get personalized recommendations: $e');
      return [];
    }
  }

  /// Get trending profiles
  Future<List<app_models.User>> getTrendingProfiles({
    int limit = 20,
    String? gender,
  }) async {
    try {
      await _ensureInitialized();
      
      Query query = _db.collection(Collections.users)
          .where('profile_views_received', isGreaterThan: 0)
          .orderBy('profile_views_received', descending: true)
          .limit(limit * 2); // Get more to filter

      if (gender != null) {
        query = query.where('gender', isEqualTo: gender);
      }

      final snapshot = await query.get();
      final users = snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .where(ProfileCompletionPolicy.isEligibleForDiscovery)
          .toList();

      // Apply additional scoring for trending
      final trendingUsers = users.map((user) {
        double score = 0.0; // Will be calculated from analytics
        
        // Boost for recent activity
        final lastActive = user.lastActive;
        if (lastActive != null) {
          final daysSinceActive = DateTime.now().difference(lastActive).inDays;
          if (daysSinceActive <= 7) {
            score *= 1.5; // 50% boost for recently active
          } else if (daysSinceActive <= 30) {
            score *= 1.2; // 20% boost for moderately active
          }
        }
        
        // Boost for high engagement (will be calculated from analytics)
        final totalInteractions = 0; // Placeholder - will be calculated from analytics
        score += totalInteractions * 0.1;
        
        return {'user': user, 'score': score};
      }).toList();

      // Sort by trending score
      trendingUsers.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
      
      return trendingUsers
          .take(limit)
          .map((item) => item['user'] as app_models.User)
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to get trending profiles: $e');
      return [];
    }
  }

  /// Get new profiles
  Future<List<app_models.User>> getNewProfiles({
    int limit = 20,
    String? gender,
    DateTime? since,
  }) async {
    try {
      await _ensureInitialized();
      
      final cutoff = since ?? DateTime.now().subtract(const Duration(days: 30));
      
      Query query = _db.collection(Collections.users)
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('created_at', descending: true)
          .limit(limit);

      if (gender != null) {
        query = query.where('gender', isEqualTo: gender);
      }

      final snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => app_models.User.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .where(ProfileCompletionPolicy.isEligibleForDiscovery)
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to get new profiles: $e');
      return [];
    }
  }

  /// Get similar profiles to a given user
  Future<List<app_models.User>> getSimilarProfiles({
    required String targetUserId,
    int limit = 10,
  }) async {
    try {
      await _ensureInitialized();
      
      final targetUserDoc = await _db.collection(Collections.users).doc(targetUserId).get();
      if (!targetUserDoc.exists) return [];

      final targetUserData = targetUserDoc.data()!;
      
      // Get candidate profiles
      final candidates = await _getCandidateProfiles(targetUserId, targetUserData);
      
      // Calculate similarity scores
      final similarProfiles = candidates.map((candidate) {
        final similarity = _calculateSimilarity(targetUserData, candidate.toDatabaseJson());
        return {'user': candidate, 'similarity': similarity};
      }).toList();

      // Sort by similarity
      similarProfiles.sort((a, b) => ((b['similarity'] as num?) ?? 0.0).compareTo((a['similarity'] as num?) ?? 0.0));
      
      return similarProfiles
          .take(limit)
          .map((item) => item['user'] as app_models.User)
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to get similar profiles: $e');
      return [];
    }
  }

  /// Firestore `whereIn` supports at most 30 values per query.
  static const int _whereInMaxChunk = 30;

  /// Chunked `users` reads by document ID (parallel chunks).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _batchGetUsersByDocIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < ids.length; i += _whereInMaxChunk) {
      final end = i + _whereInMaxChunk > ids.length ? ids.length : i + _whereInMaxChunk;
      final chunk = ids.sublist(i, end);
      futures.add(
        _db
            .collection(Collections.users)
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      );
    }
    final results = await Future.wait(futures);
    return results.expand((s) => s.docs).toList();
  }

  /// Get user's interaction history
  ///
  /// Firestore: canonical snake_case only (`viewer_user_id`, `viewed_profile_id`,
  /// `from_user_id`, `to_user_id`, composite indexes on orderBy fields).
  Future<Map<String, dynamic>> _getUserInteractions(String userId) async {
    try {
      String peerId(Map<String, dynamic> data, String key) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        return '';
      }

      final viewsFuture = _db
          .collection('profile_views')
          .where('viewer_user_id', isEqualTo: userId)
          .orderBy('viewed_at', descending: true)
          .limit(100)
          .get();

      final interestsFuture = _db
          .collection('interests')
          .where('from_user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .limit(100)
          .get();

      final likesFuture = _db
          .collection('likes')
          .where('from_user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .limit(100)
          .get();

      final snaps = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        viewsFuture,
        interestsFuture,
        likesFuture,
      ]);
      final viewsSnapshot = snaps[0];
      final interestsSnapshot = snaps[1];
      final likesSnapshot = snaps[2];

      final viewedIds = viewsSnapshot.docs
          .map((doc) => peerId(doc.data(), 'viewed_profile_id'))
          .where((id) => id.isNotEmpty)
          .toSet();
      final interestedIds = interestsSnapshot.docs
          .map((doc) => peerId(doc.data(), 'to_user_id'))
          .where((id) => id.isNotEmpty)
          .toSet();
      final likedIds = likesSnapshot.docs
          .map((doc) => peerId(doc.data(), 'to_user_id'))
          .where((id) => id.isNotEmpty)
          .toSet();

      // Get common attributes from interactions (skip empty whereIn).
      final commonAttributes = <String, Map<String, int>>{};
      final allPeerIds = viewedIds.union(interestedIds).union(likedIds).toList();
      if (allPeerIds.isNotEmpty) {
        final interactedDocs = await _batchGetUsersByDocIds(allPeerIds);

        for (final doc in interactedDocs) {
          final data = doc.data();

          _incrementAttributeCount(
              commonAttributes, 'religion', data['religion'] as String?);
          _incrementAttributeCount(
              commonAttributes, 'community', data['community'] as String?);
          _incrementAttributeCount(
              commonAttributes, 'motherTongue', data['mother_tongue'] as String?);
          _incrementAttributeCount(
              commonAttributes, 'location', data['city'] as String?);
        }
      }

      return {
        'viewedIds': viewedIds,
        'interestedIds': interestedIds,
        'likedIds': likedIds,
        'commonAttributes': commonAttributes,
      };
    } catch (e) {
      debugPrint('Failed to get user interactions: $e');
      return {};
    }
  }

  /// Get candidate profiles for recommendations
  Future<List<app_models.User>> _getCandidateProfiles(
    String userId, 
    Map<String, dynamic> userData
  ) async {
    try {
      final myGender = genderFromUserDocumentData(userData);
      if (myGender == null) return [];

      const fetchSize = 100;
      Query<Map<String, dynamic>> activeQuery() => _db
          .collection(Collections.users)
          .where('is_deleted', isEqualTo: false)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);

      Query<Map<String, dynamic>> anyQuery() => _db
          .collection(Collections.users)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);

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

      final out = <app_models.User>[];
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
        out.add(user);
      }
      return out;
    } catch (e) {
      debugPrint('Failed to get candidate profiles: $e');
      return [];
    }
  }

  /// Score candidates based on various factors
  Future<List<Map<String, dynamic>>> _scoreCandidates(
    List<app_models.User> candidates,
    Map<String, dynamic> userData,
    Map<String, dynamic> interactions,
  ) async {
    final scoredCandidates = <Map<String, dynamic>>[];
    final viewedIds = interactions['viewedIds'] as Set<String>? ?? {};
    final interestedIds = interactions['interestedIds'] as Set<String>? ?? {};
    final likedIds = interactions['likedIds'] as Set<String>? ?? {};
    final commonAttributes = interactions['commonAttributes'] as Map<String, Map<String, int>>? ?? {};

    for (final candidate in candidates) {
      double score = 0.0;
      final candidateData = candidate.toDatabaseJson();

      // Skip if already interacted with
      if (viewedIds.contains(candidate.id) || 
          interestedIds.contains(candidate.id) || 
          likedIds.contains(candidate.id)) {
        continue;
      }

      // Basic compatibility scoring
      score += _calculateBasicCompatibility(userData, candidateData);

      // Attribute preference scoring
      score += _calculateAttributeScore(userData, candidateData, commonAttributes);

      // Activity scoring
      score += _calculateActivityScore(candidateData);

      // Profile completeness scoring
      score += _calculateCompletenessScore(candidateData);

      // Random factor for diversity
      score += _random.nextDouble() * 5;

      scoredCandidates.add({
        'user': candidate,
        'score': score,
      });
    }

    return scoredCandidates;
  }

  /// Calculate basic compatibility score
  double _calculateBasicCompatibility(Map<String, dynamic> userData, Map<String, dynamic> candidateData) {
    double score = 0.0;

    // Religion match
    if (userData['religion'] == candidateData['religion']) {
      score += 25.0;
    }

    // Community match
    if (userData['community'] == candidateData['community']) {
      score += 20.0;
    }

    // Mother tongue match
    if (userData['mother_tongue'] == candidateData['mother_tongue']) {
      score += 15.0;
    }

    // Location match
    if (userData['city'] == candidateData['city']) {
      score += 15.0;
    }

    // Age compatibility
    final userAge = userData['age'] as int? ?? 0;
    final candidateAge = candidateData['age'] as int? ?? 0;
    final ageDiff = (userAge - candidateAge).abs();
    
    if (ageDiff <= 3) {
      score += 10.0;
    } else if (ageDiff <= 5) {
      score += 5.0;
    }

    return score;
  }

  /// Calculate attribute preference score
  double _calculateAttributeScore(
    Map<String, dynamic> userData,
    Map<String, dynamic> candidateData,
    Map<String, Map<String, int>> commonAttributes,
  ) {
    double score = 0.0;

    // Score based on user's interaction patterns
    for (final attribute in ['religion', 'community', 'mother_tongue', 'city']) {
      final userAttr = userData[attribute] as String?;
      final candidateAttr = candidateData[attribute] as String?;
      
      if (userAttr != null && candidateAttr != null) {
        final attrCounts = commonAttributes[attribute] ?? {};
        final count = attrCounts[candidateAttr] ?? 0;
        
        // Boost score based on how often user interacted with this attribute
        score += count * 2.0;
      }
    }

    return score;
  }

  /// Calculate activity score
  double _calculateActivityScore(Map<String, dynamic> candidateData) {
    double score = 0.0;

    // Profile views received
    final viewsReceived = candidateData['profile_views_received'] as int? ?? 0;
    score += min(viewsReceived * 0.1, 5.0); // Cap at 5 points

    // Interactions received
    final interestsReceived = candidateData['interests_received'] as int? ?? 0;
    final likesReceived = candidateData['likes_received'] as int? ?? 0;
    score += min((interestsReceived + likesReceived) * 0.2, 3.0);

    // Recent activity
    final lastActive = candidateData['last_active'] as Timestamp?;
    if (lastActive != null) {
      final daysSinceActive = DateTime.now().difference(lastActive.toDate()).inDays;
      if (daysSinceActive <= 7) {
        score += 2.0;
      } else if (daysSinceActive <= 30) {
        score += 1.0;
      }
    }

    return score;
  }

  /// Calculate profile completeness score
  double _calculateCompletenessScore(Map<String, dynamic> candidateData) {
    int filledFields = 0;
    int totalFields = 0;

    final importantFields = [
      'first_name', 'last_name', 'gender', 'age', 'height', 'weight',
      'religion', 'community', 'mother_tongue', 'education', 'occupation',
      'income', 'city', 'state', 'country'
    ];

    for (final field in importantFields) {
      totalFields++;
      final value = candidateData[field];
      if (value != null && value.toString().isNotEmpty) {
        filledFields++;
      }
    }

    // Check for photos
    final photos = candidateData['photos'] as List? ?? [];
    if (photos.isNotEmpty) {
      filledFields++;
    }
    totalFields++;

    return (filledFields / totalFields) * 10.0;
  }

  /// Calculate similarity between two users
  double _calculateSimilarity(Map<String, dynamic> userData1, Map<String, dynamic> userData2) {
    double similarity = 0.0;
    int factors = 0;

    final attributes = ['religion', 'community', 'mother_tongue', 'city', 'education', 'occupation'];

    for (final attr in attributes) {
      final value1 = userData1[attr];
      final value2 = userData2[attr];
      
      if (value1 != null && value2 != null) {
        if (value1 == value2) {
          similarity += 1.0;
        }
        factors++;
      }
    }

    // Age similarity
    final age1 = userData1['age'] as int? ?? 0;
    final age2 = userData2['age'] as int? ?? 0;
    final ageDiff = (age1 - age2).abs();
    
    if (ageDiff <= 2) {
      similarity += 1.0;
    } else if (ageDiff <= 5) {
      similarity += 0.5;
    }
    factors++;

    return factors > 0 ? similarity / factors : 0.0;
  }

  /// Apply diversity algorithm to recommendations
  List<app_models.User> _applyDiversity(List<Map<String, dynamic>> scoredCandidates, int limit) {
    if (scoredCandidates.isEmpty) return [];

    final diversified = <app_models.User>[];
    final usedAttributes = <String, Set<String>>{
      'religion': <String>{},
      'community': <String>{},
      'location': <String>{},
    };

    // First pass: add top candidates with diversity
    for (final candidate in scoredCandidates) {
      if (diversified.length >= limit) break;

      final user = candidate['user'] as app_models.User;
      final userData = user.toDatabaseJson();

      // Check diversity constraints
      int diversityViolations = 0;

      for (final attr in usedAttributes.keys) {
        final value = userData[attr] as String?;
        if (value != null && usedAttributes[attr]!.contains(value)) {
          diversityViolations++;
        }
      }

      // Allow some violations to ensure we have enough recommendations
      if (diversityViolations <= 2 || diversified.length < limit / 2) {
        diversified.add(user);
        
        // Mark used attributes
        for (final attr in usedAttributes.keys) {
          final value = userData[attr] as String?;
          if (value != null) {
            usedAttributes[attr]!.add(value);
          }
        }
      }
    }

    // Second pass: fill remaining slots if needed
    if (diversified.length < limit) {
      for (final candidate in scoredCandidates) {
        if (diversified.length >= limit) break;

        final user = candidate['user'] as app_models.User;
        if (!diversified.contains(user)) {
          diversified.add(user);
        }
      }
    }

    return diversified;
  }

  /// Increment attribute count in common attributes map
  void _incrementAttributeCount(
    Map<String, Map<String, int>> commonAttributes,
    String attribute,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      final attrMap = commonAttributes.putIfAbsent(attribute, () => <String, int>{});
      attrMap[value] = (attrMap[value] ?? 0) + 1;
    }
  }

  /// Update recommendation weights based on user feedback
  Future<void> updateRecommendationWeights({
    required String userId,
    required String profileId,
    required String action, // 'view', 'interest', 'like', 'skip'
  }) async {
    try {
      await _ensureInitialized();
      
      // Store feedback for learning algorithm
      final feedbackData = {
        'user_id': userId,
        'profile_id': profileId,
        'action': action,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _db.collection('recommendation_feedback').add(feedbackData);

      debugPrint('✅ Recommendation feedback recorded: $userId -> $profileId ($action)');
    } catch (e) {
      debugPrint('Failed to update recommendation weights: $e');
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

  /// Show app recommendation share dialog
  static void showRecommendationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Brahmin Vivaaha Vedika'),
        content: const Text('Invite your friends and family to find their perfect match!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Use share_plus to share the app
              // Share.share('Check out Brahmin Vivaaha Vedika - https://play.google.com/store/apps/details?id=com.brahminvivaahavedika');
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }
}
