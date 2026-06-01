import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../widgets/loading_widgets.dart';

/// Performance optimization utilities for the Brahmin Vivaaha Vedika app
class PerformanceOptimizer {
  
  /// Clear image cache to free memory
  static void clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      debugPrint('🧹 Image cache cleared');
    } catch (e) {
      debugPrint('❌ Error clearing image cache: $e');
    }
  }

  /// Optimize memory usage
  static void optimizeMemory() {
    // Force garbage collection
    SystemChannels.platform.invokeMethod('System.gc');
    debugPrint('🗑️ Garbage collection triggered');
  }

  /// Preload critical images
  static Future<void> preloadImages(List<String> imageUrls) async {
    for (final url in imageUrls) {
      try {
        await precacheImage(NetworkImage(url), WidgetsBinding.instance.rootElement! as BuildContext);
      } catch (e) {
        debugPrint('❌ Error preloading image $url: $e');
      }
    }
    debugPrint('📸 Preloaded ${imageUrls.length} images');
  }

  /// Monitor app performance
  static void monitorPerformance() {
    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        if (timing.totalSpan.inMilliseconds > 16) {
          debugPrint('⚠️ Slow frame detected: ${timing.totalSpan.inMilliseconds}ms');
        }
      }
    });
  }

  /// Optimize list performance
  static Widget optimizedListView({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    ScrollController? controller,
    bool shrinkWrap = false,
    EdgeInsets? padding,
    double? itemExtent,
  }) {
    return ListView.builder(
      controller: controller,
      shrinkWrap: shrinkWrap,
      padding: padding,
      itemCount: itemCount,
      // Use item extent for better performance
      itemExtent: itemExtent ?? 80.0,
      scrollCacheExtent: const ScrollCacheExtent.pixels(500.0),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      addSemanticIndexes: false,
      itemBuilder: itemBuilder,
    );
  }

  /// Performance-aware image widget
  static Widget optimizedImage({
    required String imageUrl,
    double? width,
    double? height,
    Widget? placeholder,
    Widget? errorWidget,
    bool enableCache = true,
  }) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      // Limit memory usage
      cacheWidth: width?.toInt(),
      cacheHeight: height?.toInt(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            const Center(child: LoadingIndicator(size: 40));
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Image error: $error');
        return errorWidget ?? const Icon(Icons.error);
      },
    );
  }

  /// Debounce function for search and other input-heavy operations
  static Function(String) debounce(Function(String) func, {int delay = 300}) {
    Timer? timer;
    return (value) {
      timer?.cancel();
      timer = Timer(Duration(milliseconds: delay), () => func(value));
    };
  }

  /// Throttle function for scroll events
  static Function() throttle(Function() func, {int interval = 100}) {
    Timer? timer;
    return () {
      if (timer == null) {
        func();
        timer = Timer(Duration(milliseconds: interval), () {});
      }
    };
  }

  /// Lazy load widgets for better performance
  static Widget lazyLoad({
    required Widget Function() builder,
    Widget? placeholder,
    Duration delay = const Duration(milliseconds: 100),
  }) {
    return FutureBuilder(
      future: Future.delayed(delay),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return builder();
        }
        return placeholder ?? const SizedBox.shrink();
      },
    );
  }

  /// Optimize animations based on device performance
  static bool shouldReduceAnimations() {
    if (kIsWeb) return false;
    // Check if device is low-end
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        // On mobile, check if device is older
        return false; // Assume modern devices for now
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false; // Desktop can handle animations
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Get optimized animation duration
  static Duration getOptimizedDuration(Duration original) {
    return shouldReduceAnimations() 
        ? Duration(milliseconds: original.inMilliseconds ~/ 2)
        : original;
  }

  /// Background task manager
  static Future<void> runInBackground(Future<void> Function() task) async {
    await task();
  }

  /// Memory monitoring
  static void monitorMemoryUsage() {
    if (kIsWeb) return;
    Timer.periodic(const Duration(minutes: 5), (timer) {
      // Process-level RSS memory is not available without dart:io.
      // Keep a lightweight periodic hook here for platforms where this is supported.
      optimizeMemory();
    });
  }

  /// Optimize font loading
  static void optimizeFontLoading() {
    // Preload critical fonts
    final fontLoader = FontLoader('CustomFont');
    // Add font families here if needed
    fontLoader.load();
  }

  /// Reduce widget rebuilds
  static Widget memoizedWidget(Widget Function() builder) {
    return RepaintBoundary(
      child: builder(),
    );
  }
}

/// Performance monitoring widget
class PerformanceMonitor extends StatefulWidget {
  final Widget child;
  final String? name;

  const PerformanceMonitor({
    super.key,
    required this.child,
    this.name,
  });

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    if (_stopwatch.elapsedMilliseconds > 100) {
      debugPrint('⏱️ ${widget.name ?? "Widget"} took ${_stopwatch.elapsedMilliseconds}ms to build');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Memory-efficient image cache manager
class ImageCacheManager {
  static const int maxCacheSize = 100;
  static const int maxCacheBytes = 50 * 1024 * 1024; // 50MB

  static void configureCache() {
    PaintingBinding.instance.imageCache.maximumSize = maxCacheSize;
    PaintingBinding.instance.imageCache.maximumSizeBytes = maxCacheBytes;
    debugPrint('📸 Image cache configured: $maxCacheSize images, $maxCacheBytes bytes');
  }

  static void clearOldCache() {
    final cache = PaintingBinding.instance.imageCache;
    if (cache.currentSize > maxCacheSize * 0.8) {
      cache.clear();
      debugPrint('🧹 Image cache cleared (threshold reached)');
    }
  }
}

/// Advanced performance monitoring
class AdvancedPerformanceMonitor {
  static final Map<String, List<int>> _performanceData = {};

  static void trackBuildTime(String widgetName, int milliseconds) {
    _performanceData.putIfAbsent(widgetName, () => []).add(milliseconds);
    
    // Keep only last 100 measurements
    if (_performanceData[widgetName]!.length > 100) {
      _performanceData[widgetName]!.removeAt(0);
    }
  }

  static Map<String, double> getAverageBuildTimes() {
    final result = <String, double>{};
    for (final entry in _performanceData.entries) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      result[entry.key] = avg;
    }
    return result;
  }

  static void printPerformanceReport() {
    debugPrint('📊 Performance Report:');
    final averages = getAverageBuildTimes();
    for (final entry in averages.entries) {
      debugPrint('  ${entry.key}: ${entry.value.toStringAsFixed(2)}ms');
    }
  }
}

/// Smart loading widget with progressive enhancement
class SmartLoadingWidget extends StatefulWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Duration loadingDelay;
  final bool enableLazyLoading;

  const SmartLoadingWidget({
    super.key,
    required this.child,
    this.loadingWidget,
    this.loadingDelay = const Duration(milliseconds: 200),
    this.enableLazyLoading = true,
  });

  @override
  State<SmartLoadingWidget> createState() => _SmartLoadingWidgetState();
}

class _SmartLoadingWidgetState extends State<SmartLoadingWidget> {
  bool _isLoading = true;
  bool _showLoading = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.enableLazyLoading) {
      // Show loading only after delay
      Future.delayed(widget.loadingDelay, () {
        if (mounted && _isLoading) {
          setState(() => _showLoading = true);
        }
      });

      // Simulate loading completion
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showLoading = false;
          });
        }
      });
    } else {
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _showLoading 
          ? (widget.loadingWidget ??
              const Center(child: LoadingIndicator(size: 44)))
          : const SizedBox.shrink();
    }
    
    return widget.child;
  }
}
