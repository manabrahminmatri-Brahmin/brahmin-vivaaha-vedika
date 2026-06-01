import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';

/// Service to manage activity feed showing recent activity
class ActivityFeedService extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<ActivityItem> _activities = [];
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose
  
  ActivityFeedService(this._prefs) {
    _loadActivities();
  }

  /// 🔥 FIX: Safe notify that checks disposed state
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
  
  /// Load activities from storage
  void _loadActivities() {
    final userId = _prefs.getString('current_user_id');
    if (userId == null) return;
    
    // In a real app, this would load from a database
    // For now, we'll create sample activities
    _activities = [];
    _safeNotify();
  }
  
  /// Get recent activities
  List<ActivityItem> getRecentActivities({int limit = 20}) {
    return _activities.take(limit).toList();
  }
  
  /// Add activity
  Future<void> addActivity(ActivityItem activity) async {
    _activities.insert(0, activity);
    
    // Keep only last 100 activities
    if (_activities.length > 100) {
      _activities = _activities.take(100).toList();
    }
    
    _safeNotify();
  }
  
  /// Record new profile activity
  Future<void> recordNewProfile(User user) async {
    final activity = ActivityItem(
      type: ActivityItemType.newProfile,
      title: 'New Profile Added',
      description: '${user.profile?.fullName ?? user.profileId} joined recently',
      userId: user.id,
      profileId: user.profileId,
      timestamp: DateTime.now(),
      profilePicture: user.profile?.profilePicture,
    );
    await addActivity(activity);
  }
  
  /// Record profile update activity
  Future<void> recordProfileUpdate(String userId, String profileId, String name) async {
    final activity = ActivityItem(
      type: ActivityItemType.profileUpdate,
      title: 'Profile Updated',
      description: '$name updated their profile',
      userId: userId,
      profileId: profileId,
      timestamp: DateTime.now(),
    );
    await addActivity(activity);
  }
  
  /// Record mutual interest activity
  Future<void> recordMutualInterest(String userId, String profileId, String name) async {
    final activity = ActivityItem(
      type: ActivityItemType.mutualInterest,
      title: 'Mutual Interest!',
      description: 'You and $name have mutual interest',
      userId: userId,
      profileId: profileId,
      timestamp: DateTime.now(),
    );
    await addActivity(activity);
  }
}

/// Activity item model
class ActivityItem {
  final ActivityItemType type;
  final String title;
  final String description;
  final String userId;
  final String profileId;
  final DateTime timestamp;
  final String? profilePicture;
  
  ActivityItem({
    required this.type,
    required this.title,
    required this.description,
    required this.userId,
    required this.profileId,
    required this.timestamp,
    this.profilePicture,
  });
}

enum ActivityItemType {
  newProfile,
  profileUpdate,
  mutualInterest,
  interestReceived,
  messageReceived,
  profileView,
}
