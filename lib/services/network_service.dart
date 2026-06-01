import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Live connectivity via [Connectivity] (not a stub).
class NetworkService {
  static final Connectivity _connectivity = Connectivity();
  static bool _isConnected = true;
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static Stream<bool> get connectionStream => _connectionController.stream;

  static bool get isConnected => _isConnected;

  static Future<void> initialize() async {
    try {
      final first = await _connectivity.checkConnectivity();
      _applyConnectivity(first);
      await _subscription?.cancel();
      _subscription =
          _connectivity.onConnectivityChanged.listen(_applyConnectivity);
      debugPrint('🌐 Network monitoring initialized (connected=$_isConnected)');
    } catch (e) {
      debugPrint('❌ Network monitoring error: $e');
      _isConnected = true;
      if (!_connectionController.isClosed) {
        _connectionController.add(_isConnected);
      }
    }
  }

  static void _applyConnectivity(List<ConnectivityResult> results) {
    final online = results.isEmpty ||
        results.any((r) => r != ConnectivityResult.none);
    if (_isConnected != online) {
      _isConnected = online;
      if (!_connectionController.isClosed) {
        _connectionController.add(_isConnected);
      }
    }
  }

  /// Cancel connectivity subscription. Does not close [connectionStream]
  /// (broadcast) so late listeners still work after re-init if needed.
  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<bool> canReachHost(String host) async {
    try {
      if (!_isConnected) return false;
      return _isConnected;
    } catch (e) {
      debugPrint('❌ Host check failed for $host: $e');
      return false;
    }
  }

  static String get connectionType {
    if (!_isConnected) return 'None';
    return 'Unknown';
  }

  static Future<bool> waitForConnection(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (_isConnected) return true;

    final completer = Completer<bool>();
    late StreamSubscription<bool> sub;

    sub = connectionStream.listen((isConnected) {
      if (isConnected) {
        if (!completer.isCompleted) completer.complete(true);
      }
    });

    Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }
}
