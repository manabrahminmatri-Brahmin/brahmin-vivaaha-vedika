import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network connectivity service for handling connection issues
class NetworkConnectivityService {
  static final NetworkConnectivityService _instance = NetworkConnectivityService._internal();
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  bool _isOnline = true;
  bool _isChecking = false;
  DateTime? _lastCheck;
  String? _lastError;
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Timer? _reachabilityTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Getters
  bool get isOnline => _isOnline;
  bool get isChecking => _isChecking;
  String? get lastError => _lastError;
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Check if backend is reachable
  Future<bool> isBackendReachable({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isChecking) return _isOnline; // Return cached result while checking

    _isChecking = true;
    _lastCheck = DateTime.now();
    
    try {
      debugPrint('🌐 Starting comprehensive connectivity check...');
      
      // Step 1: Check basic connectivity first
      final hasInternet = await _checkBasicInternet(timeout);
      if (!hasInternet) {
        _updateConnectivity(false, 'No internet connection');
        return false;
      }

      debugPrint('✅ Basic internet confirmed, checking Firebase...');

      // Step 2: Check Firebase specifically
      final firebaseReachable = await _checkFirebaseEndpoint(timeout);
      
      // Step 3: Additional verification if needed
      if (!firebaseReachable) {
        debugPrint('⚠️ Firebase unreachable, trying alternative verification...');
        final altReachable = await _checkAlternativeFirebaseAccess();
        _updateConnectivity(altReachable, altReachable ? null : 'Firebase unreachable - try different network');
        return altReachable;
      }
      
      _updateConnectivity(true, null);
      return true;
    } catch (e) {
      debugPrint('❌ Network check failed: $e');
      _updateConnectivity(false, e.toString());
      return false;
    } finally {
      _isChecking = false;
    }
  }

  /// Check basic internet connectivity
  Future<bool> _checkBasicInternet(Duration timeout) async {
    try {
      debugPrint('🌐 Checking basic internet connectivity...');
      
      // First check connectivity type
      final connectivityResult = await Connectivity().checkConnectivity();
      debugPrint('📡 Current connectivity: $connectivityResult');
      
      if (connectivityResult.contains(ConnectivityResult.none) ||
          connectivityResult.isEmpty) {
        debugPrint('❌ No connectivity detected');
        return false;
      }
      
      // Try multiple reliable endpoints with different protocols
      final endpoints = [
        // HTTPS endpoints
        'https://google.com',
        'https://cloudflare.com',
        'https://github.com',
        // HTTP endpoint (fallback)
        'http://httpbin.org/get',
        // DNS check
        'https://8.8.8.8',
      ];

      for (int i = 0; i < endpoints.length; i++) {
        final endpoint = endpoints[i];
        try {
          debugPrint('🔍 Testing endpoint $i+1/$endpoints: $endpoint');
          
          final response = await http.get(
            Uri.parse(endpoint),
          ).timeout(const Duration(seconds: 5));
          
          if (response.statusCode >= 200 && response.statusCode < 300) {
            debugPrint('✅ Internet reachable via: $endpoint (status: ${response.statusCode})');
            return true;
          } else {
            debugPrint('⚠️ Endpoint $endpoint returned: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('⚠️ Endpoint $endpoint failed: $e');
          
          // For last endpoint, don't continue
          if (i == endpoints.length - 1) {
            debugPrint('❌ All endpoints failed');
            return false;
          }
          continue;
        }
      }
      
      debugPrint('❌ No internet connectivity');
      return false;
    } catch (e) {
      debugPrint('❌ Basic internet check failed: $e');
      return false;
    }
  }

  /// Alternative Firebase access verification
  Future<bool> _checkAlternativeFirebaseAccess() async {
    try {
      debugPrint('🔄 Trying alternative Firebase access methods...');
      
      // Method 1: DNS lookup
      try {
        debugPrint('🔍 Testing DNS resolution for Firebase...');
        final uri = Uri.parse('https://firebase.google.com');
        final addresses = await InternetAddress.lookup(uri.host);
        
        if (addresses.isNotEmpty) {
          debugPrint('✅ DNS resolution successful for Firebase');
          return true;
        }
      } catch (e) {
        debugPrint('❌ DNS resolution failed for Firebase: $e');
      }
      
      // Method 2: Ping-like check via HEAD request
      try {
        debugPrint('🔍 Testing HEAD request to Firebase...');
        final response = await http.head(
          Uri.parse('https://firebase.google.com'),
          headers: {
            'User-Agent': 'BrahminVivaaha Vedika-Connectivity/1.0',
          },
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode >= 200 && response.statusCode < 400) {
          debugPrint('✅ HEAD request successful to Firebase');
          return true;
        }
      } catch (e) {
        debugPrint('❌ HEAD request failed for Firebase: $e');
      }
      
      debugPrint('❌ All alternative Firebase access methods failed');
      return false;
    } catch (e) {
      debugPrint('❌ Alternative Firebase access failed: $e');
      return false;
    }
  }

  /// Check Firebase endpoint specifically
  Future<bool> _checkFirebaseEndpoint(Duration timeout) async {
    try {
      debugPrint('🔍 Testing Firebase endpoint connectivity...');
      
      // Test Firebase Auth endpoint
      final response = await http.get(
        Uri.parse('https://firebase.google.com'),
        headers: {
          'User-Agent': 'BrahminVivaaha Vedika-Connectivity/1.0',
        },
      ).timeout(timeout);
      
      // Any response (even errors) means Firebase is reachable
      if (response.statusCode >= 200 && response.statusCode < 600) {
        debugPrint('✅ Firebase endpoint reachable: ${response.statusCode}');
        return true;
      }
      
      debugPrint('❌ Firebase endpoint unreachable: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ Firebase endpoint check failed: $e');
      return false;
    }
  }

  /// Get network diagnostics
  Future<Map<String, dynamic>> getNetworkDiagnostics() async {
    final diagnostics = <String, dynamic>{};
    
    try {
      // Check connectivity type
      final connectivityResult = await Connectivity().checkConnectivity();
      diagnostics['connectivity_type'] = connectivityResult.toString();
      
      // Check if online
      diagnostics['is_online'] = await isBackendReachable();
      
      // Last check time
      diagnostics['last_check'] = _lastCheck?.toIso8601String();
      
      // Last error
      diagnostics['last_error'] = _lastError;
      
      // Backend URL
      diagnostics['firebase_url'] = 'https://firebase.google.com';
      
      // Platform info
      diagnostics['platform'] = kIsWeb ? 'web' : Platform.operatingSystem;
      
    } catch (e) {
      diagnostics['error'] = e.toString();
    }
    
    return diagnostics;
  }

  /// Monitor connectivity continuously
  void startConnectivityMonitoring() {
    debugPrint('📡 Starting connectivity monitoring...');

    _reachabilityTimer?.cancel();
    _connectivitySubscription?.cancel();

    // Check immediately
    isBackendReachable();

    // Check every 30 seconds (must be cancellable on dispose / logout)
    _reachabilityTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isChecking) {
        await isBackendReachable();
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      debugPrint('📡 Connectivity changed: $result');
      Future.delayed(const Duration(seconds: 2), () {
        isBackendReachable();
      });
    });
  }

  /// Update connectivity status
  void _updateConnectivity(bool isOnline, String? error) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      _lastError = error;
      _connectivityController.add(isOnline);
      
      debugPrint('📡 Connectivity updated: ${isOnline ? "ONLINE" : "OFFLINE"}');
      if (error != null) {
        debugPrint('📡 Error: $error');
      }
    }
  }

  /// Get user-friendly error message
  String getErrorMessage() {
    if (_lastError == null) return 'Unknown network error';
    
    final error = _lastError!.toLowerCase();
    
    if (error.contains('timeout') || error.contains('timed out')) {
      return 'Connection timed out. Try switching to mobile hotspot or different WiFi.';
    } else if (error.contains('no internet') || error.contains('network')) {
      return 'No internet connection. Check your WiFi/mobile data.';
    } else if (error.contains('firebase') && error.contains('unreachable')) {
      return 'Cannot reach Firebase. Try:\n• Different network\n• Mobile hotspot\n• Check if project is active';
    } else if (error.contains('socket') || error.contains('connection')) {
      return 'Network connection failed. Firewalls may be blocking the connection.';
    } else {
      return 'Network error: $_lastError';
    }
  }

  /// Dispose resources
  void dispose() {
    _reachabilityTimer?.cancel();
    _reachabilityTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityController.close();
  }
}
