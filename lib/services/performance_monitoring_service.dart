import 'dart:async';
import 'package:flutter/material.dart';

import '../features/profile/analytics_service.dart';

/// Performance monitoring service.
/// PERF FIX: Removed two background timers (every 5s and 10s) that were
/// running forever, burning CPU/battery with simulated/hardcoded data.
/// Frame monitoring is kept because it uses Flutter's real timing callback.
/// Network and memory monitoring are now on-demand only (call checkOnce()).
class PerformanceMonitoringService extends ChangeNotifier {
  static PerformanceMonitoringService? _instance;
  static PerformanceMonitoringService get instance =>
      _instance ??= PerformanceMonitoringService._();

  PerformanceMonitoringService._();

  final Map<String, List<double>> _performanceMetrics = {};
  final Map<String, DateTime> _screenLoadTimes = {};
  final List<PerformanceAlert> _alerts = [];

  // PERF FIX: Single optional timer, only used when explicitly started
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  /// Performance thresholds
  static const double _frameTimeThreshold = 16.67; // 60 FPS
  static const double _networkLatencyThreshold = 1000.0; // ms

  /// Current performance metrics
  double _currentFPS = 60.0;
  double _currentNetworkLatency = 0.0;

  double get currentFPS => _currentFPS;
  double get currentNetworkLatency => _currentNetworkLatency;
  bool get isMonitoring => _isMonitoring;
  List<PerformanceAlert> get alerts => List.unmodifiable(_alerts);

  final StreamController<PerformanceMetrics> _metricsController =
      StreamController<PerformanceMetrics>.broadcast();
  Stream<PerformanceMetrics> get metricsStream => _metricsController.stream;

  /// Initialize performance monitoring.
  /// PERF FIX: Only starts frame monitoring passively via Flutter's timing
  /// callback. No background timers started by default.
  Future<void> initialize() async {
    if (_isMonitoring) return;

    try {
      _setupFrameMonitoring();
      _isMonitoring = true;
      notifyListeners();
      debugPrint(
          '🚀 Performance monitoring initialized (frame monitoring only)');
    } catch (e) {
      debugPrint('Failed to initialize performance monitoring: $e');
    }
  }

  /// Start periodic monitoring — only call this from the admin dashboard,
  /// and stop it when the dashboard is closed via stopMonitoring().
  /// PERF FIX: Moved from auto-start to explicit on-demand usage only.
  void startAdminMonitoring() {
    if (_monitoringTimer != null) return;
    _monitoringTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }
      _collectSystemMetrics();
      _checkPerformanceThresholds();
      _cleanupOldData();
      // Prevent memory leaks by limiting metric history
      if (_performanceMetrics.length > 100) {
        for (final key in _performanceMetrics.keys) {
          final list = _performanceMetrics[key]!;
          if (list.length > 50) list.removeRange(0, list.length - 50);
        }
      }
    });
    debugPrint('📊 Admin performance monitoring started');
  }

  /// Setup frame rate monitoring using Flutter's timing callback.
  void _setupFrameMonitoring() {
    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final frameTime = timing.totalSpan.inMilliseconds.toDouble();
        if (frameTime > 0) {
          _currentFPS = 1000.0 / frameTime;
          _recordMetric('frame_time', frameTime);
          _recordMetric('fps', _currentFPS);

          if (frameTime > _frameTimeThreshold) {
            _createAlert(
              PerformanceAlertType.lowFPS,
              'Low FPS detected: ${_currentFPS.toStringAsFixed(1)}',
            );
          }
          _broadcastMetrics();
        }
      }
    });
  }

  /// Collect system metrics (CPU simulation — call only on-demand).
  void _collectSystemMetrics() {
    // CPU usage is not available via public Flutter APIs on mobile.
    // Only track what we actually have real data for.
    _recordMetric('fps', _currentFPS);
    _recordMetric('network_latency', _currentNetworkLatency);
  }

  /// Check performance thresholds and broadcast.
  void _checkPerformanceThresholds() {
    AnalyticsService().trackPerformance('fps', _currentFPS, unit: 'fps');
    AnalyticsService()
        .trackPerformance('latency', _currentNetworkLatency, unit: 'ms');
    _broadcastMetrics();
  }

  /// Broadcast current metrics to stream listeners.
  void _broadcastMetrics() {
    if (!_metricsController.isClosed) {
      _metricsController.add(PerformanceMetrics(
        fps: _currentFPS,
        networkLatency: _currentNetworkLatency,
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Record a metric value.
  void _recordMetric(String name, double value) {
    _performanceMetrics.putIfAbsent(name, () => []).add(value);
  }

  /// Create a performance alert (deduplicates within 30s).
  void _createAlert(PerformanceAlertType type, String message) {
    final now = DateTime.now();
    final recentSame = _alerts.any(
        (a) => a.type == type && now.difference(a.timestamp).inSeconds < 30);
    if (!recentSame) {
      _alerts
          .add(PerformanceAlert(type: type, message: message, timestamp: now));
      if (_alerts.length > 50) _alerts.removeAt(0);
    }
  }

  /// Cleanup old screen load time entries.
  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    _screenLoadTimes.removeWhere((key, value) => value.isBefore(cutoff));
  }

  /// Record screen load time (call from screen's initState).
  void recordScreenLoad(String screenName, Duration loadTime) {
    _screenLoadTimes[screenName] = DateTime.now();
    _recordMetric(
        'screen_load_$screenName', loadTime.inMilliseconds.toDouble());
    if (loadTime.inMilliseconds > 500) {
      _createAlert(PerformanceAlertType.slowScreenLoad,
          'Slow screen load: $screenName took ${loadTime.inMilliseconds}ms');
    }
  }

  /// Record API call latency (call after each backend request).
  void recordApiLatency(String endpoint, Duration latency) {
    _currentNetworkLatency = latency.inMilliseconds.toDouble();
    _recordMetric('api_$endpoint', _currentNetworkLatency);
    if (_currentNetworkLatency > _networkLatencyThreshold) {
      _createAlert(PerformanceAlertType.highLatency,
          'Slow API: $endpoint took ${latency.inMilliseconds}ms');
    }
  }

  /// Get performance summary.
  PerformanceSummary getPerformanceSummary() {
    return PerformanceSummary(
      averageFPS: _calculateAverage('fps'),
      averageNetworkLatency: _calculateAverage('network_latency'),
      totalAlerts: _alerts.length,
      criticalAlerts: _alerts
          .where((a) => a.type.severity == AlertSeverity.critical)
          .length,
    );
  }

  double _calculateAverage(String metric) {
    final values = _performanceMetrics[metric] ?? [];
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Export performance data for debugging.
  String exportPerformanceData() {
    final data = {
      'summary': getPerformanceSummary().toJson(),
      'alerts': _alerts.map((a) => a.toJson()).toList(),
      'screen_load_times':
          _screenLoadTimes.map((k, v) => MapEntry(k, v.toIso8601String())),
      'export_timestamp': DateTime.now().toIso8601String(),
    };
    debugPrint('📤 Performance data exported');
    return data.toString();
  }

  /// Stop monitoring (call when admin dashboard is closed).
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('⏹️ Performance monitoring stopped');
  }

  void resetData() {
    _performanceMetrics.clear();
    _screenLoadTimes.clear();
    _alerts.clear();
    notifyListeners();
    debugPrint('🔄 Performance data reset');
  }

  @override
  void dispose() {
    stopMonitoring();
    if (!_metricsController.isClosed) _metricsController.close();
    super.dispose();
  }
}

/// Performance metrics model
class PerformanceMetrics {
  final double fps;
  final double networkLatency;
  final DateTime timestamp;

  PerformanceMetrics({
    required this.fps,
    required this.networkLatency,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'fps': fps,
        'network_latency': networkLatency,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Performance alert model
class PerformanceAlert {
  final PerformanceAlertType type;
  final String message;
  final DateTime timestamp;

  PerformanceAlert({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Performance alert types
enum PerformanceAlertType {
  lowFPS(AlertSeverity.warning),
  highLatency(AlertSeverity.warning),
  networkError(AlertSeverity.critical),
  slowScreenLoad(AlertSeverity.warning),
  slowAPI(AlertSeverity.warning);

  const PerformanceAlertType(this.severity);
  final AlertSeverity severity;
}

/// Alert severity levels
enum AlertSeverity { info, warning, critical }

/// Performance summary model
class PerformanceSummary {
  final double averageFPS;
  final double averageNetworkLatency;
  final int totalAlerts;
  final int criticalAlerts;

  PerformanceSummary({
    required this.averageFPS,
    required this.averageNetworkLatency,
    required this.totalAlerts,
    required this.criticalAlerts,
  });

  Map<String, dynamic> toJson() => {
        'average_fps': averageFPS,
        'average_network_latency': averageNetworkLatency,
        'total_alerts': totalAlerts,
        'critical_alerts': criticalAlerts,
      };

  @override
  String toString() => 'PerformanceSummary(\n'
      '  Average FPS: ${averageFPS.toStringAsFixed(1)}\n'
      '  Average Latency: ${averageNetworkLatency.toStringAsFixed(1)}ms\n'
      '  Total Alerts: $totalAlerts\n'
      '  Critical Alerts: $criticalAlerts\n'
      ')';
}
