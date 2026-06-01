/// Simple in-memory cache (static map, per-key TTL).
///
/// For TTL disk/network caching see [TtlCache] and [ProfileRepository].
class CacheService {
  static final Map<String, CacheItem> _cache = {};
  static const Duration _defaultCacheDuration = Duration(minutes: 5);

  /// Store data in cache with timestamp
  static void set(String key, dynamic data, [Duration? duration]) {
    _cache[key] = CacheItem(
      data: data,
      timestamp: DateTime.now(),
      duration: duration ?? _defaultCacheDuration,
    );
  }

  /// Get data from cache if still valid
  static T? get<T>(String key) {
    final item = _cache[key];
    if (item == null) return null;

    if (DateTime.now().difference(item.timestamp) > item.duration) {
      _cache.remove(key);
      return null;
    }

    return item.data as T?;
  }

  /// Check if data exists and is valid
  static bool has(String key) {
    final item = _cache[key];
    if (item == null) return false;

    if (DateTime.now().difference(item.timestamp) > item.duration) {
      _cache.remove(key);
      return false;
    }

    return true;
  }

  /// Remove specific item from cache
  static void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cache
  static void clear() {
    _cache.clear();
  }

  /// Clear expired items
  static void clearExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, item) {
      return now.difference(item.timestamp) > item.duration;
    });
  }

  /// Get cache statistics
  static Map<String, dynamic> getStats() {
    return {
      'totalItems': _cache.length,
      'expiredItems': _cache.values.where((item) => 
          DateTime.now().difference(item.timestamp) > item.duration).length,
    };
  }
}

/// Individual cache item with metadata
class CacheItem {
  final dynamic data;
  final DateTime timestamp;
  final Duration duration;

  CacheItem({
    required this.data,
    required this.timestamp,
    required this.duration,
  });
}
