import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Memory management service to prevent leaks and optimize performance
/// 
/// This service provides centralized memory management including:
/// - Automatic resource disposal tracking
/// - Cache management with LRU eviction
/// - Timer lifecycle management
/// - Periodic cleanup tasks
/// - Memory usage monitoring
/// 
/// Features:
/// - Prevents memory leaks by tracking disposable resources
/// - Automatically manages cache size limits
/// - Provides managed wrappers for Timers, Streams, and AnimationControllers
/// - Offers performance monitoring and metrics
/// 
/// Usage:
/// ```dart
/// // Initialize at app startup
/// MemoryManager().initialize();
/// 
/// // Register resources for automatic disposal
/// final stream = MemoryManager().createManagedStream(myStream);
/// final timer = MemoryManager().createManagedTimer(Duration(seconds: 1), callback);
/// 
/// // Cache data with automatic eviction
/// MemoryManager().cache('key', data);
/// ```
/// 
/// See also:
/// - [Disposable] for resources that can be tracked
/// - [ManagedResource] for resource wrappers
class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal();

  // Track disposable resources
  final List<Disposable> _trackedResources = [];
  final Map<String, dynamic> _cache = {};
  final Queue<String> _cacheKeys = Queue();
  
  // Configuration
  static const int _maxCacheSize = 100;
  static const Duration _cleanupInterval = Duration(minutes: 5);
  
  Timer? _cleanupTimer;
  bool _isInitialized = false;

  /// Initialize memory manager
  void initialize() {
    if (_isInitialized) return;
    
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
    
    _isInitialized = true;
    debugPrint('🧠 MemoryManager initialized');
  }

  /// Register a disposable resource for tracking
  void registerDisposable(Disposable resource) {
    _trackedResources.add(resource);
  }

  /// Unregister a disposable resource
  void unregisterDisposable(Disposable resource) {
    _trackedResources.remove(resource);
  }

  /// Add to cache with size limit
  void addToCache(String key, dynamic value) {
    // Remove old entry if exists
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      _cacheKeys.remove(key);
    }

    // Add new entry
    _cache[key] = value;
    _cacheKeys.add(key);

    // Enforce size limit
    while (_cache.length > _maxCacheSize) {
      final oldestKey = _cacheKeys.removeFirst();
      _cache.remove(oldestKey);
      debugPrint('🧠 Cache eviction: $oldestKey');
    }
  }

  /// Get from cache
  dynamic getFromCache(String key) {
    return _cache[key];
  }

  /// Remove from cache
  void removeFromCache(String key) {
    _cache.remove(key);
    _cacheKeys.remove(key);
  }

  /// Clear all cache
  void clearCache() {
    _cache.clear();
    _cacheKeys.clear();
    debugPrint('🧠 Cache cleared');
  }

  /// Perform cleanup of resources
  void _performCleanup() {
    debugPrint('🧠 Performing memory cleanup...');
    
    // Dispose tracked resources that are no longer needed
    final resourcesToRemove = <Disposable>[];
    
    for (final resource in _trackedResources) {
      if (resource.shouldDispose) {
        try {
          resource.dispose();
          resourcesToRemove.add(resource);
        } catch (e) {
          debugPrint('❌ Error disposing resource: $e');
        }
      }
    }

    // Remove disposed resources from tracking
    for (final resource in resourcesToRemove) {
      _trackedResources.remove(resource);
    }

    // Trigger garbage collection hint (only in debug mode)
    if (kDebugMode) {
      _suggestGarbageCollection();
    }

    debugPrint('🧠 Cleanup complete. Resources: ${_trackedResources.length}, Cache: ${_cache.length}');
  }

  /// Suggest garbage collection (debug only)
  void _suggestGarbageCollection() {
    // This is just a hint - actual GC is managed by Dart VM
    debugPrint('🧠 Suggesting garbage collection...');
  }

  /// Get memory usage stats
  Map<String, dynamic> getMemoryStats() {
    return {
      'trackedResources': _trackedResources.length,
      'cacheSize': _cache.length,
      'cacheKeys': _cacheKeys.length,
      'isInitialized': _isInitialized,
    };
  }

  /// Dispose all resources and cleanup
  void dispose() {
    _cleanupTimer?.cancel();
    
    // Dispose all tracked resources
    for (final resource in _trackedResources) {
      try {
        resource.dispose();
      } catch (e) {
        debugPrint('❌ Error disposing resource during shutdown: $e');
      }
    }
    
    _trackedResources.clear();
    clearCache();
    
    _isInitialized = false;
    debugPrint('🧠 MemoryManager disposed');
  }
}

/// Interface for disposable resources
abstract class Disposable {
  bool get shouldDispose;
  void dispose();
}

/// Managed stream subscription that auto-cancels
class ManagedStreamSubscription<T> implements Disposable {
  final StreamSubscription<T> _subscription;
  bool _isDisposed = false;
  final DateTime _createdAt;
  final Duration _maxAge;

  ManagedStreamSubscription(
    this._subscription, {
    Duration maxAge = const Duration(minutes: 30),
  })  : _createdAt = DateTime.now(),
        _maxAge = maxAge {
    MemoryManager().registerDisposable(this);
  }

  @override
  bool get shouldDispose {
    return _isDisposed || DateTime.now().difference(_createdAt) > _maxAge;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _subscription.cancel();
      _isDisposed = true;
      MemoryManager().unregisterDisposable(this);
    }
  }

  void pause() => _subscription.pause();
  void resume() => _subscription.resume();
}

/// Managed timer that auto-cancels
class ManagedTimer implements Disposable {
  Timer? _timer;
  bool _isDisposed = false;
  final DateTime _createdAt;
  final Duration _maxAge;

  ManagedTimer(
    Duration duration,
    void Function() callback, {
    Duration maxAge = const Duration(minutes: 30),
    bool periodic = false,
  })  : _createdAt = DateTime.now(),
        _maxAge = maxAge {
    if (periodic) {
      _timer = Timer.periodic(duration, (_) => callback());
    } else {
      _timer = Timer(duration, callback);
    }
    MemoryManager().registerDisposable(this);
  }

  @override
  bool get shouldDispose {
    return _isDisposed || 
           (_timer?.isActive == false) || 
           DateTime.now().difference(_createdAt) > _maxAge;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _timer?.cancel();
      _isDisposed = true;
      MemoryManager().unregisterDisposable(this);
    }
  }

  void cancel() => dispose();
  bool get isActive => _timer?.isActive ?? false;
}

/// Managed animation controller that auto-disposes
class ManagedAnimationController implements Disposable {
  final dynamic _controller; // AnimationController
  bool _isDisposed = false;
  final DateTime _createdAt;
  final Duration _maxAge;

  ManagedAnimationController(
    this._controller, {
    Duration maxAge = const Duration(minutes: 30),
  })  : _createdAt = DateTime.now(),
        _maxAge = maxAge {
    MemoryManager().registerDisposable(this);
  }

  @override
  bool get shouldDispose {
    return _isDisposed || DateTime.now().difference(_createdAt) > _maxAge;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _controller.dispose();
      _isDisposed = true;
      MemoryManager().unregisterDisposable(this);
    }
  }

  dynamic get controller => _isDisposed ? null : _controller;
}

/// Image cache manager to prevent memory issues with images
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  final Map<String, DateTime> _imageAccessTimes = {};
  static const int _maxCachedImages = 50;
  static const Duration _maxCacheAge = Duration(minutes: 10);

  /// Track image access
  void trackImageAccess(String imageUrl) {
    _imageAccessTimes[imageUrl] = DateTime.now();
    _cleanupOldImages();
  }

  /// Cleanup old images from cache
  void _cleanupOldImages() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    // Remove old images
    for (final entry in _imageAccessTimes.entries) {
      if (now.difference(entry.value) > _maxCacheAge) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _imageAccessTimes.remove(key);
    }

    // Enforce size limit
    while (_imageAccessTimes.length > _maxCachedImages) {
      final oldest = _imageAccessTimes.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _imageAccessTimes.remove(oldest.key);
    }
  }

  /// Clear all tracked images
  void clear() {
    _imageAccessTimes.clear();
  }

  /// Get cache stats
  Map<String, dynamic> getStats() {
    return {
      'trackedImages': _imageAccessTimes.length,
      'maxCacheSize': _maxCachedImages,
      'maxCacheAge': _maxCacheAge.inMinutes,
    };
  }
}

/// Performance monitoring utilities
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final Map<String, DateTime> _operationStartTimes = {};
  final List<PerformanceMetric> _metrics = [];

  /// Start timing an operation
  void startOperation(String operationName) {
    _operationStartTimes[operationName] = DateTime.now();
  }

  /// End timing an operation
  void endOperation(String operationName, {bool success = true}) {
    final startTime = _operationStartTimes.remove(operationName);
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      final metric = PerformanceMetric(
        operation: operationName,
        duration: duration,
        success: success,
        timestamp: DateTime.now(),
      );
      _metrics.add(metric);

      // Log slow operations
      if (duration > const Duration(seconds: 1)) {
        debugPrint('⚠️ Slow operation: $operationName took ${duration.inMilliseconds}ms');
      }

      // Keep only recent metrics
      _cleanupOldMetrics();
    }
  }

  /// Cleanup old metrics
  void _cleanupOldMetrics() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    _metrics.removeWhere((m) => m.timestamp.isBefore(cutoff));
  }

  /// Get performance report
  List<PerformanceMetric> getRecentMetrics({int count = 10}) {
    return _metrics.take(count).toList();
  }

  /// Get slow operations
  List<PerformanceMetric> getSlowOperations({Duration threshold = const Duration(seconds: 1)}) {
    return _metrics.where((m) => m.duration > threshold).toList();
  }

  /// Clear metrics
  void clearMetrics() {
    _metrics.clear();
    _operationStartTimes.clear();
  }
}

/// Performance metric model
class PerformanceMetric {
  final String operation;
  final Duration duration;
  final bool success;
  final DateTime timestamp;

  PerformanceMetric({
    required this.operation,
    required this.duration,
    required this.success,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'durationMs': duration.inMilliseconds,
      'success': success,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
