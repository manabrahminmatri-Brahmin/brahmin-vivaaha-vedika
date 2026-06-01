import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Short-lived disk cache for sensitive member profile photos.
abstract final class ProtectedImageCacheService {
  ProtectedImageCacheService._();

  static const String _cacheKey = 'protected_profile_photos_v1';
  static const Duration _stalePeriod = Duration(hours: 2);
  static const Duration _maxCacheAge = Duration(hours: 6);

  static CacheManager? _manager;

  /// Disk cache is not available on Flutter web (`path_provider` plugin).
  static CacheManager? get cacheManagerOrNull => kIsWeb ? null : cacheManager;

  static CacheManager get cacheManager {
    if (kIsWeb) {
      throw UnsupportedError(
        'ProtectedImageCacheService.cacheManager is not available on web',
      );
    }
    return _manager ??= CacheManager(
      Config(
        _cacheKey,
        stalePeriod: _stalePeriod,
        maxNrOfCacheObjects: 80,
        repo: JsonCacheInfoRepository(databaseName: _cacheKey),
      ),
    );
  }

  /// Drops one URL from disk + memory caches (call after photo replace/delete).
  static Future<void> evictUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    if (kIsWeb) {
      await _clearMemoryImageCacheOnly();
      return;
    }
    for (final candidate in {trimmed, _stripVersionParam(trimmed)}) {
      try {
        await cacheManager.removeFile(candidate);
      } catch (e) {
        debugPrint('ProtectedImageCacheService.evictUrl($candidate): $e');
      }
    }
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      debugPrint('ProtectedImageCacheService.evictUrl.imageCache: $e');
    }
  }

  static String _stripVersionParam(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.queryParameters.containsKey('v')) return url;
    final params = Map<String, String>.from(uri.queryParameters)..remove('v');
    return uri.replace(queryParameters: params).toString();
  }

  static Future<void> _clearMemoryImageCacheOnly() async {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      debugPrint('ProtectedImageCacheService.imageCache: $e');
    }
  }

  /// Clears protected photo disk cache and in-memory image cache.
  static Future<void> clearProtectedImageCache() async {
    if (!kIsWeb) {
      try {
        await cacheManager.emptyCache();
      } catch (e) {
        debugPrint('ProtectedImageCacheService.emptyCache: $e');
      }
    }
    await _clearMemoryImageCacheOnly();
    debugPrint('🔐 ProtectedImageCacheService: cache cleared');
  }

  @visibleForTesting
  static void resetCacheManagerForTests() {
    _manager = null;
  }

  @visibleForTesting
  static Duration get stalePeriodForTests => _stalePeriod;

  @visibleForTesting
  static Duration get maxCacheAgeForTests => _maxCacheAge;
}
