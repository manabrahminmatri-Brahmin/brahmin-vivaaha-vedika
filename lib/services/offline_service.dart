import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/profile_completion_policy.dart';
import '../models/user.dart';
import '../models/membership.dart';

/// Offline support service for seamless app experience.
/// PERF FIX: Replaced two background timers (every 5s and 10s — ~17 callbacks/min)
/// with a single connectivity_plus stream listener. Sync now triggers only when
/// the connection state actually changes, not on a fixed interval.
/// Periodic sync interval changed from 5min to 15min to reduce battery drain.
class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, int> _syncQueue = {};

  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  static const Duration _cacheExpiry = Duration(hours: 24);

  // PERF FIX: Increased from 5min to 15min — syncs on connectivity change anyway
  static const Duration _syncInterval = Duration(minutes: 15);

  int get _cacheSize => _cache.length;

  /// Initialize offline service
  Future<void> initialize() async {
    await _loadCachedData();
    _startConnectivityMonitoring();
    _startPeriodicSync();
    debugPrint('📱 Offline service initialized');
  }

  /// Cache complete User objects for offline access
  Future<void> cacheMatchUsersData(List<Map<String, dynamic>> usersData) async {
    try {
      const key = 'match_users_data';
      _cache[key] = usersData;
      _cacheTimestamps[key] = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(usersData));
      await prefs.setString('${key}_timestamp', DateTime.now().toIso8601String());

      debugPrint('📱 Cached ${usersData.length} complete user objects for offline access');
    } catch (e) {
      debugPrint('📱 Error caching match users data: $e');
    }
  }

  /// Get cached User objects (complete user data)
  Future<List<User>> getCachedMatchUsersData() async {
    try {
      const key = 'match_users_data';

      if (_cache.containsKey(key)) {
        final timestamp = _cacheTimestamps[key];
        if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
          final usersData = _cache[key] as List;
          final users = usersData
              .map((userData) => _createUserFromJson(userData as Map<String, dynamic>))
              .whereType<User>()
              .where(ProfileCompletionPolicy.isEligibleForDiscovery)
              .toList();
          debugPrint('📱 Retrieved ${users.length} user objects from memory cache');
          return users;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(key);
      final timestampStr = prefs.getString('${key}_timestamp');

      if (cachedData != null && timestampStr != null) {
        final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
        if (DateTime.now().difference(timestamp) < _cacheExpiry) {
          final usersData = jsonDecode(cachedData);
          _cache[key] = usersData;
          _cacheTimestamps[key] = timestamp;

          final users = (usersData as List)
              .map((userData) => _createUserFromJson(userData as Map<String, dynamic>))
              .whereType<User>()
              .where(ProfileCompletionPolicy.isEligibleForDiscovery)
              .toList();

          debugPrint('📱 Retrieved ${users.length} user objects from SharedPreferences');
          return users;
        }
      }

      debugPrint('📱 No cached user data available or expired');
      return [];
    } catch (e) {
      debugPrint('📱 Error getting cached match users data: $e');
      return [];
    }
  }

  /// Create User object from cached JSON data (requires non-empty Firestore id).
  User? _createUserFromJson(Map<String, dynamic> userData) {
    // Cached data uses camelCase (written by home_screen).
    // Use snake_case field names only.
    T? v<T>(String snake) => userData[snake] as T?;

    final id = userData['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      debugPrint('📱 Skipping cached user row: missing id');
      return null;
    }
    try {
      return User(
        id: id,
        email: userData['email'] as String,
        password: '',
        mobileNumber: v<String>('mobile_number') ?? '0000000000',
        profileId: v<String>('profile_id'),
        profile: UserProfile.fromJson((userData['profile'] as Map).cast<String, dynamic>()),
        createdAt: DateTime.tryParse(
            (v<String>('created_at')) ?? '') ?? DateTime.now(),
        isDeleted:
            v<bool>('is_deleted') ?? v<bool>('isDeleted') ?? false,
        membership: userData['membership'] != null
            ? Membership.fromJson((userData['membership'] as Map).cast<String, dynamic>())
            : Membership.free(),
      );
    } catch (e) {
      debugPrint('📱 Error creating User from JSON: $e');
      return null;
    }
  }

  Future<void> cacheUserData(String userId, UserProfile profile) async {
    try {
      final key = 'user_profile_$userId';
      _cache[key] = profile.toJson();
      _cacheTimestamps[key] = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(profile.toJson()));
      await prefs.setString('${key}_timestamp', DateTime.now().toIso8601String());

      debugPrint('📱 Cached user data: $userId');
    } catch (e) {
      debugPrint('📱 Error caching user data: $e');
    }
  }

  /// Get cached user data
  Future<UserProfile?> getCachedUserData(String userId) async {
    try {
      final key = 'user_profile_$userId';

      if (_cache.containsKey(key)) {
        final timestamp = _cacheTimestamps[key];
        if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
          return UserProfile.fromJson((_cache[key] as Map).cast<String, dynamic>());
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(key);
      final timestampStr = prefs.getString('${key}_timestamp');

      if (cachedData != null && timestampStr != null) {
        final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
        if (DateTime.now().difference(timestamp) < _cacheExpiry) {
          final userData = jsonDecode(cachedData);
          _cache[key] = userData;
          _cacheTimestamps[key] = timestamp;
          return UserProfile.fromJson((userData as Map).cast<String, dynamic>());
        }
      }

      return null;
    } catch (e) {
      debugPrint('📱 Error getting cached user data: $e');
      return null;
    }
  }

  /// Cache match data (only legitimate profiles)
  Future<void> cacheMatchData(List<UserProfile> matches) async {
    try {
      final legitimateMatches = matches.where(_isLegitimateProfile).toList();

      const key = 'matches_data';
      final matchesData = legitimateMatches.map((m) => m.toJson()).toList();
      _cache[key] = matchesData;
      _cacheTimestamps[key] = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(matchesData));
      await prefs.setString('${key}_timestamp', DateTime.now().toIso8601String());

      debugPrint('📱 Cached ${legitimateMatches.length} matches');
    } catch (e) {
      debugPrint('📱 Error caching match data: $e');
    }
  }

  bool _isLegitimateProfile(UserProfile profile) {
    return profile.firstName.isNotEmpty &&
        profile.age > 18 &&
        profile.age < 100 &&
        profile.height != null &&
        profile.height!.isNotEmpty &&
        profile.education != null &&
        profile.education!.isNotEmpty;
  }

  /// Get cached match data (only legitimate profiles)
  Future<List<UserProfile>> getCachedMatchData() async {
    try {
      const key = 'matches_data';

      List<dynamic>? rawData;

      if (_cache.containsKey(key)) {
        final timestamp = _cacheTimestamps[key];
        if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
          rawData = _cache[key] as List;
        }
      }

      if (rawData == null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedData = prefs.getString(key);
        final timestampStr = prefs.getString('${key}_timestamp');

        if (cachedData != null && timestampStr != null) {
          final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
          if (DateTime.now().difference(timestamp) < _cacheExpiry) {
            rawData = jsonDecode(cachedData) as List;
            _cache[key] = rawData;
            _cacheTimestamps[key] = timestamp;
          }
        }
      }

      if (rawData == null) return [];

      final profiles = rawData
          .map((m) => UserProfile.fromJson((m as Map).cast<String, dynamic>()))
          .where(_isLegitimateProfile)
          .toList();

      debugPrint('📱 Retrieved ${profiles.length} cached profiles');
      return profiles;
    } catch (e) {
      debugPrint('📱 Error getting cached match data: $e');
      return [];
    }
  }

  /// Queue action for sync when online
  Future<void> queueAction(String actionType, Map<String, dynamic> data) async {
    try {
      final actionId = DateTime.now().millisecondsSinceEpoch.toString();
      final action = {
        'id': actionId,
        'type': actionType,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': false,
      };

      final prefs = await SharedPreferences.getInstance();
      final actions = prefs.getStringList('sync_queue') ?? [];
      actions.add(jsonEncode(action));
      await prefs.setStringList('sync_queue', actions);

      _syncQueue[actionId] = 1;

      debugPrint('📱 Queued action: $actionType');

      if (_isOnline) {
        await _syncActions();
      }
    } catch (e) {
      debugPrint('📱 Error queuing action: $e');
    }
  }

  /// Sync queued actions when online
  Future<void> _syncActions() async {
    if (!_isOnline) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final actions = prefs.getStringList('sync_queue') ?? [];
      final remainingActions = <String>[];

      for (final actionStr in actions) {
        try {
          final action = jsonDecode(actionStr);
          final success = await _performSyncAction(action);

          if (success) {
            _syncQueue.remove(action['id']);
            debugPrint('📱 Synced action: ${action['type']}');
          } else {
            remainingActions.add(actionStr);
          }
        } catch (e) {
          debugPrint('📱 Error syncing action: $e');
          remainingActions.add(actionStr);
        }
      }

      await prefs.setStringList('sync_queue', remainingActions);
    } catch (e) {
      debugPrint('📱 Error during sync: $e');
    }
  }

  /// Perform individual sync action
  Future<bool> _performSyncAction(Map<String, dynamic> action) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      switch (action['type']) {
        case 'send_interest':
          return true;
        case 'update_profile':
          return true;
        case 'like_profile':
          return true;
        default:
          return false;
      }
    } catch (e) {
      debugPrint('📱 Error performing sync action: $e');
      return false;
    }
  }

  /// PERF FIX: Replaced Timer.periodic(10s) with connectivity_plus stream.
  /// Now triggers sync only when connectivity actually changes — not on a
  /// fixed 10-second tick that fires regardless of what's happening.
  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      final wasOnline = _isOnline;
      _isOnline = results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);

      if (!wasOnline && _isOnline) {
        debugPrint('📱 Back online — triggering queued sync');
        if (_syncQueue.isNotEmpty) {
          await _syncActions();
        }
      } else if (wasOnline && !_isOnline) {
        debugPrint('📱 Went offline');
      }
    });

    // Set initial status
    Connectivity().checkConnectivity().then((results) {
      _isOnline = results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);
    });
  }

  /// PERF FIX: Sync timer interval increased from 5min to 15min.
  /// The connectivity listener handles the important case (coming back online).
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(_syncInterval, (timer) {
      if (_isOnline && _syncQueue.isNotEmpty) {
        _syncActions();
      }
    });
  }

  /// Load cached data on startup
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('user_profile_') || key.startsWith('matches_data')) {
          final data = prefs.getString(key);
          final timestampStr = prefs.getString('${key}_timestamp');

          if (data != null && timestampStr != null) {
            final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
            if (DateTime.now().difference(timestamp) < _cacheExpiry) {
              _cache[key] = jsonDecode(data);
              _cacheTimestamps[key] = timestamp;
            }
          }
        }
      }

      debugPrint('📱 Loaded ${_cache.length} cached items');
    } catch (e) {
      debugPrint('📱 Error loading cached data: $e');
    }
  }

  /// Clear expired cache
  Future<void> clearExpiredCache() async {
    try {
      final now = DateTime.now();
      final expiredKeys = <String>[];

      for (final entry in _cacheTimestamps.entries) {
        if (now.difference(entry.value) > _cacheExpiry) {
          expiredKeys.add(entry.key);
        }
      }

      for (final key in expiredKeys) {
        _cache.remove(key);
        _cacheTimestamps.remove(key);

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
        await prefs.remove('${key}_timestamp');
      }

      debugPrint('📱 Cleared ${expiredKeys.length} expired cache items');
    } catch (e) {
      debugPrint('📱 Error clearing expired cache: $e');
    }
  }

  bool get isOnline => _isOnline;
  int get syncQueueSize => _syncQueue.length;
  int get cacheSize => _cache.length;

  Future<void> forceSync() async {
    if (_isOnline) await _syncActions();
  }

  Future<void> clearAllCache() async {
    try {
      _cache.clear();
      _cacheTimestamps.clear();

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('user_profile_') ||
            key.startsWith('matches_data') ||
            key.startsWith('sync_queue')) {
          await prefs.remove(key);
        }
      }

      debugPrint('📱 Cleared all cached data');
    } catch (e) {
      debugPrint('📱 Error clearing cache: $e');
    }
  }

  Map<String, dynamic> getOfflineStats() => {
        'is_online': _isOnline,
        'cache_size': _cacheSize,
        'sync_queue_size': syncQueueSize,
        'last_sync': DateTime.now().toIso8601String(),
      };

  Future<void> cacheImage(String imageUrl, String imageId) async {
    try {
      final key = 'image_$imageId';
      _cache[key] = imageUrl;
      _cacheTimestamps[key] = DateTime.now();
      debugPrint('📱 Cached image: $imageId');
    } catch (e) {
      debugPrint('📱 Error caching image: $e');
    }
  }

  String? getCachedImage(String imageId) {
    final key = 'image_$imageId';
    if (_cache.containsKey(key)) {
      final timestamp = _cacheTimestamps[key];
      if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _cache[key] as String?;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> exportOfflineData() async => {
        'cache': _cache,
        'timestamps': _cacheTimestamps.map((k, v) => MapEntry(k, v.toIso8601String())),
        'sync_queue_size': syncQueueSize,
        'export_timestamp': DateTime.now().toIso8601String(),
      };

  Future<void> importOfflineData(Map<String, dynamic> data) async {
    try {
      _cache.clear();
      _cacheTimestamps.clear();
      _cache.addAll(data['cache'] as Map<String, dynamic>);
      final timestamps = data['timestamps'] as Map<String, dynamic>;
      for (final entry in timestamps.entries) {
        _cacheTimestamps[entry.key] = DateTime.tryParse(entry.value as String? ?? '') ?? DateTime.now();
      }
      debugPrint('📱 Imported offline data');
    } catch (e) {
      debugPrint('📱 Error importing offline data: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    debugPrint('📱 Offline service disposed');
  }
}

/// Offline action types
enum OfflineActionType {
  sendInterest,
  updateProfile,
  likeProfile,
  sendMessage,
  updatePreferences,
}

/// Offline status widget.
/// PERF FIX: Replaced Timer.periodic(5s) + setState with a connectivity stream
/// listener. No more forced rebuilds every 5 seconds.
class OfflineStatusIndicator extends StatefulWidget {
  const OfflineStatusIndicator({super.key});

  @override
  State<OfflineStatusIndicator> createState() => _OfflineStatusIndicatorState();
}

class _OfflineStatusIndicatorState extends State<OfflineStatusIndicator> {
  bool _isOnline = true;
  int _syncQueueSize = 0;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _isOnline = OfflineService().isOnline;
    _syncQueueSize = OfflineService().syncQueueSize;

    // PERF FIX: Listen to real connectivity events instead of polling every 5s
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOnline = results.isNotEmpty &&
              results.any((r) => r != ConnectivityResult.none);
          _syncQueueSize = OfflineService().syncQueueSize;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline && _syncQueueSize == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isOnline ? Colors.orange : Colors.red,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOnline ? Icons.sync : Icons.cloud_off,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _isOnline ? 'Syncing ($_syncQueueSize)' : 'Offline',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
