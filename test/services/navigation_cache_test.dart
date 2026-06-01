import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigationService', () {
    test('should be singleton', () {
      final service1 = NavigationService();
      final service2 = NavigationService();
      expect(identical(service1, service2), true);
    });

    test('should track current route', () {
      final service = NavigationService();
      expect(service.currentRoute, isNull);
    });

    test('should invalidate caches', () {
      final service = NavigationService();
      service.invalidateCaches();
      expect(service.currentRoute, isNull);
    });

    test('should determine if user is logged in', () {
      final service = NavigationService();
      expect(service.isLoggedIn, isA<bool>());
    });

    test('should check if user has MPIN', () {
      final service = NavigationService();
      expect(service.hasMpin, isA<bool>());
    });
  });

  group('CacheService', () {
    test('should store and retrieve values', () {
      final cache = CacheService();
      cache.set('key1', 'value1');
      expect(cache.get('key1'), 'value1');
    });

    test('should return null for missing keys', () {
      final cache = CacheService();
      expect(cache.get('nonexistent'), isNull);
    });

    test('should check if key exists', () {
      final cache = CacheService();
      cache.set('key2', 'value2');
      expect(cache.has('key2'), true);
      expect(cache.has('key3'), false);
    });

    test('should delete values', () {
      final cache = CacheService();
      cache.set('key4', 'value4');
      cache.delete('key4');
      expect(cache.get('key4'), isNull);
    });

    test('should clear all values', () {
      final cache = CacheService();
      cache.set('key5', 'value5');
      cache.set('key6', 'value6');
      cache.clear();
      expect(cache.get('key5'), isNull);
      expect(cache.get('key6'), isNull);
    });

    test('should respect TTL', () async {
      final cache = CacheService();
      cache.set('ttl_key', 'ttl_value', ttl: const Duration(milliseconds: 50));
      expect(cache.get('ttl_key'), 'ttl_value');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(cache.get('ttl_key'), isNull);
    });

    test('should get all keys', () {
      final cache = CacheService();
      cache.set('a', '1');
      cache.set('b', '2');
      final keys = cache.keys;
      expect(keys, contains('a'));
      expect(keys, contains('b'));
    });
  });

  group('NetworkCacheService', () {
    test('should cache network responses', () {
      final service = NetworkCacheService();
      final response = {'data': 'test'};
      service.cacheResponse('/api/test', response);
      expect(service.getCachedResponse('/api/test'), response);
    });

    test('should check if response is cached', () {
      final service = NetworkCacheService();
      service.cacheResponse('/api/cached', {'test': true});
      expect(service.isCached('/api/cached'), true);
      expect(service.isCached('/api/uncached'), false);
    });

    test('should clear network cache', () {
      final service = NetworkCacheService();
      service.cacheResponse('/api/clear', {'test': true});
      service.clearCache();
      expect(service.isCached('/api/clear'), false);
    });
  });
}

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  String? _currentRoute;
  bool _isLoggedIn = false;
  bool _hasMpin = false;

  String? get currentRoute => _currentRoute;
  bool get isLoggedIn => _isLoggedIn;
  bool get hasMpin => _hasMpin;

  void invalidateCaches() {
    _currentRoute = null;
  }
}

class CacheService {
  final Map<String, _CacheEntry> _cache = {};

  void set(String key, dynamic value, {Duration? ttl}) {
    final expiry = ttl != null ? DateTime.now().add(ttl) : null;
    _cache[key] = _CacheEntry(value: value, expiry: expiry);
  }

  dynamic get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  bool has(String key) => get(key) != null;

  void delete(String key) => _cache.remove(key);

  void clear() => _cache.clear();

  List<String> get keys => _cache.keys.toList();
}

class _CacheEntry {
  final dynamic value;
  final DateTime? expiry;

  _CacheEntry({required this.value, this.expiry});

  bool get isExpired {
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry!);
  }
}

class NetworkCacheService {
  final Map<String, dynamic> _responses = {};

  void cacheResponse(String url, dynamic response) {
    _responses[url] = response;
  }

  dynamic getCachedResponse(String url) => _responses[url];

  bool isCached(String url) => _responses.containsKey(url);

  void clearCache() => _responses.clear();
}
