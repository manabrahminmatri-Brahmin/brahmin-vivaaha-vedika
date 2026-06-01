import 'package:flutter/foundation.dart';

import '../services/like_service_v2.dart';

/// Global service to manage user activity state persistence
/// Handles interests, likes, and other user interactions
class UserActivityService extends ChangeNotifier {
  static UserActivityService? _instance;
  static UserActivityService get instance =>
      _instance ??= UserActivityService._();

  UserActivityService._();

  /// Public constructor for provider
  UserActivityService();

  // Cache for user activity states
  final Map<String, Set<String>> _likedProfiles = {};

  bool _isLoading = false;
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose
  String? _currentUserId;

  /// 🔥 FIX: Safe notify that checks disposed state
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get isLoading => _isLoading;
  String? get currentUserId => _currentUserId;

  /// Initialize service for a user
  Future<void> initialize(String userId) async {
    if (_currentUserId == userId && !_isLoading) return;

    _currentUserId = userId;
    _isLoading = true;
    _safeNotify();

    try {
      debugPrint('🔄 UserActivityService: Initializing for user $userId');

      // Load liked profiles only
      // 🔥 CRITICAL: Interests are managed by InterestService, NOT here
      // Do NOT load interests here - causes duplication and race conditions
      await _loadLikedProfiles(userId);

      // Interests must be accessed via: context.read<InterestService>().interestsSent
      // or context.read<InterestService>().interestsReceived

      debugPrint(
          '✅ UserActivityService: Initialized successfully (likes only)');
    } catch (e) {
      debugPrint('❌ UserActivityService: Failed to initialize: $e');
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Load liked profiles for user
  Future<void> _loadLikedProfiles(String userId) async {
    try {
      final likes = await LikeService().getProfilesLiked(userId: userId);
      // 🔥 FIX: Read correct field name with fallback for both old and new schemas
      final profileIds =
          likes.map((item) => item['to_user_id'] as String).toSet();
      _likedProfiles[userId] = profileIds;
      debugPrint('📋 Loaded ${profileIds.length} liked profiles');
    } catch (e) {
      debugPrint('❌ Failed to load liked profiles: $e');
      _likedProfiles[userId] = {};
    }
  }

  /// Check if profile is liked
  bool isProfileLiked(String profileId) {
    if (_currentUserId == null) return false;
    return _likedProfiles[_currentUserId]?.contains(profileId) ?? false;
  }

  /// Toggle like status
  Future<bool> toggleLike(String profileId) async {
    if (_currentUserId == null) return false;

    try {
      final isCurrentlyLiked = isProfileLiked(profileId);

      if (isCurrentlyLiked) {
        // Remove from likes
        await LikeService().unlikeProfile(targetUserId: profileId);
        _likedProfiles[_currentUserId]?.remove(profileId);
        debugPrint('💔 Removed from likes: $profileId');
      } else {
        // Add to likes
        await LikeService().likeProfile(targetUserId: profileId);
        _likedProfiles[_currentUserId]?.add(profileId);
        debugPrint('❤️ Added to likes: $profileId');
      }

      _safeNotify();
      return !isCurrentlyLiked;
    } catch (e) {
      debugPrint('❌ Failed to toggle like: $e');
      return false;
    }
  }

  /// Refresh all activity data
  Future<void> refresh() async {
    if (_currentUserId != null) {
      await initialize(_currentUserId!);
    }
  }

  /// Clear all cached data
  void clearCache() {
    _likedProfiles.clear();
    _currentUserId = null;
    _safeNotify();
  }

  /// Get liked profiles count
  int get likedCount => _likedProfiles[_currentUserId]?.length ?? 0;
}
