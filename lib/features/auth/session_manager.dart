import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart' as app_models;
import '../../core/contract.dart';

/// Session Manager
/// 
/// Handles user session state, persistence, and lifecycle
/// Consolidates session logic from session_service.dart
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  SharedPreferences? _prefs;

  // State
  app_models.User? _currentUser;
  bool _isInitialized = false;
  Timer? _sessionTimer;
  
  // Stream controller for user state changes
  final StreamController<app_models.User?> _userStreamController = 
      StreamController<app_models.User?>.broadcast();

  static const String _lastActiveKey = 'last_active_timestamp';
  static const String _sessionDurationKey = 'session_duration_minutes';
  static const Duration _defaultSessionTimeout = Duration(hours: 24);
  static const Duration _sessionCheckInterval = Duration(minutes: 5);

  // Getters
  app_models.User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;
  Stream<app_models.User?> get userStream => _userStreamController.stream;

  /// Initialize session manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Listen to Firebase auth state changes
      _auth.authStateChanges().listen(_onAuthStateChanged);
      
      // Start session monitoring
      _startSessionMonitoring();
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('SessionManager initialization failed: $e');
      rethrow;
    }
  }

  /// Clear all session data
  Future<void> clearSession() async {
    try {
      await _ensureInitialized();
      
      // Clear Firebase auth
      await _auth.signOut();
      
      // Clear local data
      await _prefs?.remove(_lastActiveKey);
      await _prefs?.remove(_sessionDurationKey);
      
      _currentUser = null;
      _sessionTimer?.cancel();
      
      // Notify listeners
      _userStreamController.add(null);
    } catch (e) {
      debugPrint('Failed to clear session: $e');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Start user session
  Future<void> startSession(app_models.User user) async {
    try {
      _currentUser = user;
      await _updateLastActive();
      await _saveSessionInfo();
      _userStreamController.add(user);
      
      debugPrint('Session started for user: ${user.id}');
    } catch (e) {
      debugPrint('Failed to start session: $e');
      rethrow;
    }
  }

  /// End user session
  Future<void> endSession() async {
    try {
      _currentUser = null;
      await _clearSessionInfo();
      _userStreamController.add(null);
      
      debugPrint('Session ended');
    } catch (e) {
      debugPrint('Failed to end session: $e');
    }
  }

  /// Update session with new user data
  Future<void> updateSession(app_models.User user) async {
    try {
      _currentUser = user;
      await _updateLastActive();
      _userStreamController.add(user);
    } catch (e) {
      debugPrint('Failed to update session: $e');
    }
  }

  /// Check if session is still valid
  Future<bool> isSessionValid() async {
    try {
      if (_currentUser == null) return false;
      
      final lastActive = await _getLastActive();
      if (lastActive == null) return false;
      
      final sessionDuration = await _getSessionDuration();
      final now = DateTime.now();
      
      return now.difference(lastActive) < sessionDuration;
    } catch (e) {
      debugPrint('Failed to check session validity: $e');
      return false;
    }
  }

  /// Extend session
  Future<void> extendSession() async {
    try {
      await _updateLastActive();
      debugPrint('Session extended');
    } catch (e) {
      debugPrint('Failed to extend session: $e');
    }
  }

  /// Get session duration
  Duration getSessionDuration() {
    final minutes = _prefs?.getInt(_sessionDurationKey) ?? 1440; // 24 hours default
    return Duration(minutes: minutes);
  }

  /// Set session duration
  Future<void> setSessionDuration(Duration duration) async {
    try {
      await _prefs?.setInt(_sessionDurationKey, duration.inMinutes);
      debugPrint('Session duration set to: ${duration.inMinutes} minutes');
    } catch (e) {
      debugPrint('Failed to set session duration: $e');
    }
  }

  /// Handle Firebase auth state changes
  void _onAuthStateChanged(User? firebaseUser) async {
    try {
      if (firebaseUser == null) {
        await endSession();
        return;
      }

      // If we have a Firebase user but no session user, try to load from Firestore.
      // Cross-device installs often produce a different Firebase UID, so we must
      // support both doc-id lookup and auth_uid lookup.
      if (_currentUser == null) {
        DocumentSnapshot<Map<String, dynamic>>? matchedDoc;

        final byDocId = await _db.collection(Collections.users).doc(firebaseUser.uid).get();
        if (byDocId.exists) {
          matchedDoc = byDocId;
        } else {
          final byAuthUid = await _db
              .collection(Collections.users)
              .where('auth_uid', isEqualTo: firebaseUser.uid)
              .limit(1)
              .get();
          if (byAuthUid.docs.isNotEmpty) {
            matchedDoc = byAuthUid.docs.first;
          }
        }

        if (matchedDoc != null && matchedDoc.data() != null) {
          final user = app_models.User.fromFirestore(matchedDoc.data()!, matchedDoc.id);
          await startSession(user);
        }
      }
    } catch (e) {
      debugPrint('Error handling auth state change: $e');
    }
  }

  /// Start session monitoring timer
  void _startSessionMonitoring() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(_sessionCheckInterval, (_) async {
      if (_currentUser != null) {
        final isValid = await isSessionValid();
        if (!isValid) {
          debugPrint('Session expired, logging out');
          await endSession();
        }
      }
    });
  }

  /// Update last active timestamp
  Future<void> _updateLastActive() async {
    try {
      await _prefs?.setInt(_lastActiveKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Failed to update last active: $e');
    }
  }

  /// Get last active timestamp
  Future<DateTime?> _getLastActive() async {
    try {
      final timestamp = _prefs?.getInt(_lastActiveKey);
      return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
    } catch (e) {
      debugPrint('Failed to get last active: $e');
      return null;
    }
  }

  /// Get session duration from preferences
  Future<Duration> _getSessionDuration() async {
    try {
      final minutes = _prefs?.getInt(_sessionDurationKey) ?? 1440;
      return Duration(minutes: minutes);
    } catch (e) {
      debugPrint('Failed to get session duration: $e');
      return _defaultSessionTimeout;
    }
  }

  /// Save session info
  Future<void> _saveSessionInfo() async {
    try {
      if (_currentUser != null) {
        await _prefs?.setString('current_user_id', _currentUser!.id);
        await _prefs?.setString('current_user_name', 
            '${_currentUser!.profile!.firstName} ${_currentUser!.profile!.lastName}');
      }
    } catch (e) {
      debugPrint('Failed to save session info: $e');
    }
  }

  /// Clear session info
  Future<void> _clearSessionInfo() async {
    try {
      // Preserve remembered account identity across session end/logout.
      // Explicit account switching and fresh registration clear these keys
      // themselves; session expiry should only require MPIN/biometric again.
      await _prefs?.remove(_lastActiveKey);
    } catch (e) {
      debugPrint('Failed to clear session info: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _sessionTimer?.cancel();
    _userStreamController.close();
  }
}
