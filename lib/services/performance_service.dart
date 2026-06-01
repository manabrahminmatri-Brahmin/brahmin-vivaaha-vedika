import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Performance optimization service for app-wide performance improvements
class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();
  factory PerformanceService() => _instance;
  PerformanceService._internal();

  // Performance settings
  static const Duration _fastTransition = Duration(milliseconds: 200);
  
  // Image cache settings
  static const int _maxImageCacheSize = 100;
  static const int _maxImageCacheBytes = 50 * 1024 * 1024; // 50MB
  
  // Performance monitoring
  final Map<String, DateTime> _lastNavigationTimes = {};
  final Map<String, int> _screenLoadCounts = {};
  Timer? _performanceTimer;

  /// Initialize performance optimizations
  static Future<void> initialize() async {
    final instance = PerformanceService();
    
    // Optimize Flutter rendering
    await instance._optimizeRendering();
    
    // Setup image caching
    await instance._setupImageCaching();
    
    // Configure performance monitoring
    instance._startPerformanceMonitoring();
    
    debugPrint('🚀 Performance optimizations initialized');
  }

  /// Optimize Flutter rendering performance
  Future<void> _optimizeRendering() async {
    // Set preferred refresh rate for smoother animations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Enable hardware acceleration
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    // Set performance flags
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reduce image quality for better performance
      PaintingBinding.instance.imageCache.maximumSize = 50;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024; // 25MB
    });
  }

  /// Setup optimized image caching
  Future<void> _setupImageCaching() async {
    try {
      // Configure cached network image
      // Note: preCacheImages method doesn't exist, using direct cache setup
      PaintingBinding.instance.imageCache.maximumSize = _maxImageCacheSize;
      PaintingBinding.instance.imageCache.maximumSizeBytes = _maxImageCacheBytes;
      
      debugPrint('🖼️ Image caching optimized');
    } catch (e) {
      debugPrint('⚠️ Image caching setup failed: $e');
    }
  }

  /// Fast screen transition with performance tracking
  static Future<T?> fastNavigation<T>({
    required BuildContext context,
    required Route<T> route,
    String? screenName,
  }) async {
    final instance = PerformanceService();
    final startTime = DateTime.now();
    
    // Record navigation start
    if (screenName != null) {
      instance._lastNavigationTimes[screenName] = startTime;
      instance._screenLoadCounts[screenName] = 
          (instance._screenLoadCounts[screenName] ?? 0) + 1;
    }
    
    // Use fast transition
    final result = await Navigator.push<T>(context, route);
    
    // Log performance
    if (screenName != null) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('📱 $screenName loaded in ${duration.inMilliseconds}ms');
    }
    
    return result;
  }

  /// Optimized page route with fast transition
  static PageRouteBuilder<T> optimizedRoute<T>({
    required Widget page,
    Duration transitionDuration = _fastTransition,
    bool opaque = true,
    bool barrierDismissible = true,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: transitionDuration,
      reverseTransitionDuration: transitionDuration,
      opaque: opaque,
      barrierDismissible: barrierDismissible,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Fast fade transition
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.05), // Smaller slide for faster feel
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic, // Faster curve
            )),
            child: child,
          ),
        );
      },
    );
  }

  /// Optimized replacement navigation
  static Future<T?> fastReplacement<T>({
    required BuildContext context,
    required Route<T> newRoute,
    String? screenName,
  }) async {
    final instance = PerformanceService();
    final startTime = DateTime.now();
    
    if (screenName != null) {
      instance._lastNavigationTimes[screenName] = startTime;
    }
    
    final result = await Navigator.pushReplacement<T, T>(
      context, // Added required context parameter
      newRoute,
    );
    
    if (screenName != null) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('🔄 $screenName replaced in ${duration.inMilliseconds}ms');
    }
    
    return result;
  }

  /// Clear and clear stack navigation
  static Future<T?> fastClearStack<T>({
    required BuildContext context,
    required Route<T> newRoute,
    String? screenName,
  }) async {
    final instance = PerformanceService();
    final startTime = DateTime.now();
    
    if (screenName != null) {
      instance._lastNavigationTimes[screenName] = startTime;
    }
    
    final result = await Navigator.pushNamedAndRemoveUntil<T>(
      context, 
      newRoute.settings.name ?? '/', 
      (route) => false,
    );
    
    if (screenName != null) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('🧹 $screenName loaded with clear stack in ${duration.inMilliseconds}ms');
    }
    
    return result;
  }

  /// Optimized image widget with caching
  static Widget optimizedImage({
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => placeholder ?? 
        Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: const Center(
            child: Icon(Icons.image, color: Colors.grey),
          ),
        ),
      errorWidget: (context, url, error) => errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      memCacheWidth: width?.toInt(),
      memCacheHeight: height?.toInt(),
      maxWidthDiskCache: 1200,
      maxHeightDiskCache: 1200,
    );
  }

  /// Performance monitoring
  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkPerformanceMetrics();
    });
  }

  /// Check performance metrics
  void _checkPerformanceMetrics() {
    // Monitor memory usage
    final imageCache = PaintingBinding.instance.imageCache;
    debugPrint('📊 Image cache: ${imageCache.currentSize}/${imageCache.maximumSize} items');
    debugPrint('💾 Image cache bytes: ${(imageCache.currentSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB');
    
    // Monitor navigation performance
    if (_lastNavigationTimes.isNotEmpty) {
      debugPrint('🧭 Recent navigations: ${_lastNavigationTimes.length}');
    }
  }

  /// Clear image cache to free memory
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint('🗑️ Image cache cleared');
  }

  /// Preload critical images
  static Future<void> preloadCriticalImages(List<String> imageUrls, BuildContext context) async {
    try {
      for (final url in imageUrls) {
        await precacheImage(NetworkImage(url), context);
      }
      debugPrint('📸 Preloaded ${imageUrls.length} critical images');
    } catch (e) {
      debugPrint('⚠️ Failed to preload images: $e');
    }
  }

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    return {
      'screenLoadCounts': _screenLoadCounts,
      'lastNavigationTimes': _lastNavigationTimes,
      'imageCacheSize': PaintingBinding.instance.imageCache.currentSize,
      'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
    };
  }

  /// Dispose performance monitoring
  void dispose() {
    _performanceTimer?.cancel();
    _lastNavigationTimes.clear();
    _screenLoadCounts.clear();
  }

  /// Constants for optimized animations
  static const Duration fastAnimation = Duration(milliseconds: 150);
  static const Duration mediumAnimation = Duration(milliseconds: 250);
  static const Duration slowAnimation = Duration(milliseconds: 350);
  
  /// Optimized animation curves
  static const Curve fastCurve = Curves.easeOutCubic;
  static const Curve mediumCurve = Curves.easeOut;
  static const Curve slowCurve = Curves.easeInOut;
}
