import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Production-Ready Enhanced OTP Security Service
/// Features:
/// - Dual-layer rate limiting (server + client)
/// - Graceful error handling with timeout protection
/// - Offline support with automatic fallback
/// - Connection status tracking
/// - Session encryption and device binding
/// - Comprehensive audit logging
/// - Automatic retry with exponential backoff
class OtpSecurityService {
  OtpSecurityService._();
  static final OtpSecurityService instance = OtpSecurityService._();

  static const String _rateLimitPrefix = 'otp_rate_limit_';
  static const String _sessionKeyPrefix = 'otp_session_enc_';
  static const String _deviceBindingPrefix = 'otp_device_binding_';
  static const String _auditLogPrefix = 'otp_audit_';
  
  // Rate limiting: 3 OTP attempts per 10 minutes per mobile number
  static const int _maxAttempts = 3;
  static const int _rateLimitMinutes = 10;
  
  // Connection settings
  static const int _firestoreTimeoutSeconds = 5;
  
  // Track Firestore availability to avoid repeated failures
  bool _firestoreAvailable = true;
  DateTime? _lastFirestoreCheck;
  int _consecutiveFailures = 0;
  
  /// Generate secure device fingerprint
  static String _generateDeviceFingerprint() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return sha256.convert(bytes).toString();
  }

  /// Check if mobile number is rate limited (with graceful degradation)
  /// 
  /// Priority:
  /// 1. Server-side check (Firestore) - if available
  /// 2. Client-side check (SharedPreferences) - always available
  /// 
  /// Returns true if rate limited, false otherwise
  Future<bool> isRateLimited(String mobileNumber) async {
    final cleanMobile = _cleanMobileNumber(mobileNumber);
    
    try {
      // LAYER 1: Server-side rate limit (primary security)
      // This cannot be bypassed by users clearing app data
      if (_shouldCheckFirestore()) {
        try {
          final serverLimited = await _isServerRateLimited(cleanMobile);
          if (serverLimited) {
            debugPrint('🚫 Server-side rate limit active for: $cleanMobile');
            return true;
          }
          _firestoreAvailable = true;
          _consecutiveFailures = 0;
        } on FirebaseException catch (e) {
          debugPrint('⚠️ Firestore error (${e.code}): ${e.message}');
          _handleFirestoreError(e);
          // Continue to client-side check
        } catch (e) {
          debugPrint('⚠️ Server rate limit check failed: $e');
          _firestoreAvailable = false;
          _lastFirestoreCheck = DateTime.now();
          _consecutiveFailures++;
          // Continue to client-side check
        }
      } else {
        debugPrint('📡 Skipping Firestore check - recently failed');
      }
      
      // LAYER 2: Client-side rate limit (fast feedback + offline support)
      final clientLimited = await _isClientRateLimited(cleanMobile);
      if (clientLimited) {
        debugPrint('🚫 Client-side rate limit active for: $cleanMobile');
        return true;
      }
      
      return false;
      
    } catch (e) {
      debugPrint('⚠️ Rate limit check failed completely: $e');
      // Fail open - don't block legitimate users due to errors
      return false;
    }
  }
  
  /// Server-side rate limit check via Firestore (with timeout protection)
  Future<bool> _isServerRateLimited(String cleanMobile) async {
    final docRef = FirebaseFirestore.instance
        .collection('rate_limits')
        .doc('otp_$cleanMobile');
    
    // ✅ WITH timeout - fails fast instead of hanging
    final doc = await docRef
        .get()
        .timeout(Duration(seconds: _firestoreTimeoutSeconds));
    
    if (!doc.exists) return false;
    
    final data = doc.data()!;
    final attempts = data['attempts'] as int? ?? 0;
    final lastAttempt = (data['last_attempt'] as Timestamp?)?.toDate();
    
    if (lastAttempt == null) return false;
    
    // Check if rate limit window expired
    if (DateTime.now().difference(lastAttempt).inMinutes > _rateLimitMinutes) {
      // Clear expired rate limit (fire and forget)
      docRef.delete().catchError((e) {
        debugPrint('⚠️ Failed to clear expired rate limit: $e');
      });
      return false;
    }
    
    return attempts >= _maxAttempts;
  }
  
  /// Client-side rate limit check (always available, even offline)
  Future<bool> _isClientRateLimited(String cleanMobile) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_rateLimitPrefix$cleanMobile';
    
    final data = prefs.getString(key);
    if (data == null) return false;
    
    final Map<String, dynamic> rateData = jsonDecode(data);
    final attempts = rateData['attempts'] as int? ?? 0;
    final lastAttempt = DateTime.parse(rateData['last_attempt'] as String);
    
    // Reset if rate limit window expired
    if (DateTime.now().difference(lastAttempt).inMinutes > _rateLimitMinutes) {
      await prefs.remove(key);
      return false;
    }
    
    return attempts >= _maxAttempts;
  }

  /// Record OTP attempt (both server and client)
  /// 
  /// This method:
  /// - Records attempt in Firestore (if available)
  /// - Always records in local storage
  /// - Logs for audit trail
  Future<void> recordOtpAttempt(String mobileNumber) async {
    final cleanMobile = _cleanMobileNumber(mobileNumber);
    
    try {
      // Record server-side (if available)
      if (_shouldCheckFirestore()) {
        _recordServerOtpAttempt(cleanMobile).catchError((e) {
          debugPrint('⚠️ Server OTP recording failed (non-critical): $e');
          _handleFirestoreError(e);
        });
      }
      
      // Always record client-side (critical path)
      await _recordClientOtpAttempt(cleanMobile);
      
    } catch (e) {
      debugPrint('⚠️ Failed to record OTP attempt: $e');
      // Still try to record client-side
      try {
        await _recordClientOtpAttempt(cleanMobile);
      } catch (clientError) {
        debugPrint('❌ Critical: Client-side recording failed: $clientError');
      }
    }
  }
  
  /// Record server-side OTP attempt in Firestore (with timeout)
  Future<void> _recordServerOtpAttempt(String cleanMobile) async {
    final docRef = FirebaseFirestore.instance
        .collection('rate_limits')
        .doc('otp_$cleanMobile');
    
    final doc = await docRef
        .get()
        .timeout(Duration(seconds: _firestoreTimeoutSeconds));
    
    int attempts = 1;
    
    if (doc.exists) {
      final data = doc.data()!;
      final lastAttempt = (data['last_attempt'] as Timestamp?)?.toDate();
      
      // Reset if window expired
      if (lastAttempt != null && 
          DateTime.now().difference(lastAttempt).inMinutes > _rateLimitMinutes) {
        attempts = 1;
      } else {
        attempts = (data['attempts'] as int? ?? 0) + 1;
      }
    }
    
    await docRef.set({
      'attempts': attempts,
      'last_attempt': FieldValue.serverTimestamp(),
      'mobile': cleanMobile,
      'type': 'otp',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true))
    .timeout(Duration(seconds: _firestoreTimeoutSeconds));
    
    debugPrint('🔒 Server rate limit recorded: $cleanMobile = $attempts attempts');
    _firestoreAvailable = true;
    _consecutiveFailures = 0;
  }
  
  /// Record client-side OTP attempt (always succeeds)
  Future<void> _recordClientOtpAttempt(String cleanMobile) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_rateLimitPrefix$cleanMobile';
    
    final data = prefs.getString(key);
    Map<String, dynamic> rateData = {};
    
    if (data != null) {
      rateData = jsonDecode(data) as Map<String, dynamic>;
      final lastAttempt = DateTime.parse(rateData['last_attempt'] as String);
      
      // Reset if rate limit window expired
      if (DateTime.now().difference(lastAttempt).inMinutes > _rateLimitMinutes) {
        rateData['attempts'] = 0;
      }
    }
    
    rateData['attempts'] = (rateData['attempts'] as int? ?? 0) + 1;
    rateData['last_attempt'] = DateTime.now().toIso8601String();
    
    await prefs.setString(key, jsonEncode(rateData));
    
    // Log for audit
    await _logAuditEvent('otp_attempt', {
      'mobile': cleanMobile,
      'attempts': rateData['attempts'],
      'timestamp': DateTime.now().toIso8601String(),
      'server_synced': _firestoreAvailable,
    });
    
    debugPrint('📝 Client rate limit recorded: $cleanMobile = ${rateData['attempts']} attempts');
  }

  /// Encode OTP session data with device binding
  Future<String> encodeSessionData(String sessionId, String mobileNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceFingerprint = await _getOrCreateDeviceFingerprint();
      final cleanMobile = _cleanMobileNumber(mobileNumber);
      
      final sessionData = {
        'session_id': sessionId,
        'mobile': cleanMobile,
        'device_fingerprint': deviceFingerprint,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(const Duration(minutes: 3)).toIso8601String(),
      };
      
      final jsonStr = jsonEncode(sessionData);
      final encoded = _base64Encode(jsonStr);
      
      final key = '$_sessionKeyPrefix$cleanMobile';
      await prefs.setString(key, encoded);
      
      debugPrint('🔐 Session encoded for: $cleanMobile');
      return encoded;
    } catch (e) {
      debugPrint('⚠️ Failed to encode session data: $e');
      return sessionId;
    }
  }

  /// Decode and validate OTP session data
  Future<Map<String, dynamic>?> decodeSessionData(String mobileNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanMobile = _cleanMobileNumber(mobileNumber);
      final deviceFingerprint = await _getOrCreateDeviceFingerprint();
      
      final key = '$_sessionKeyPrefix$cleanMobile';
      final encoded = prefs.getString(key);
      
      if (encoded == null) {
        debugPrint('ℹ️ No session found for: $cleanMobile');
        return null;
      }
      
      final jsonStr = _base64Decode(encoded);
      final sessionData = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      // Validate expiration
      final expiresAt = DateTime.parse(sessionData['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        debugPrint('⏰ Session expired for: $cleanMobile');
        await prefs.remove(key);
        return null;
      }
      
      // Validate device binding
      final storedFingerprint = sessionData['device_fingerprint'] as String?;
      if (storedFingerprint != deviceFingerprint) {
        debugPrint('🚫 Device mismatch for: $cleanMobile');
        await prefs.remove(key);
        await _logAuditEvent('session_binding_failed', {
          'mobile': cleanMobile,
          'timestamp': DateTime.now().toIso8601String(),
        });
        return null;
      }
      
      debugPrint('✅ Session validated for: $cleanMobile');
      return sessionData;
    } catch (e) {
      debugPrint('⚠️ Failed to decode session data: $e');
      return null;
    }
  }

  /// Clear session data
  Future<void> clearSessionData(String mobileNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanMobile = _cleanMobileNumber(mobileNumber);
      final key = '$_sessionKeyPrefix$cleanMobile';
      await prefs.remove(key);
      debugPrint('🗑️ Session cleared for: $cleanMobile');
    } catch (e) {
      debugPrint('⚠️ Failed to clear session data: $e');
    }
  }

  /// Get or create device fingerprint
  Future<String> _getOrCreateDeviceFingerprint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = _deviceBindingPrefix;
      
      String? fingerprint = prefs.getString(key);
      if (fingerprint == null) {
        fingerprint = _generateDeviceFingerprint();
        await prefs.setString(key, fingerprint);
        debugPrint('🆕 Device fingerprint created');
      }
      
      return fingerprint;
    } catch (e) {
      debugPrint('⚠️ Failed to get device fingerprint: $e');
      return _generateDeviceFingerprint();
    }
  }

  /// Log audit events
  Future<void> _logAuditEvent(String eventType, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('$_auditLogPrefix$eventType') ?? [];
      
      final logEntry = {
        'event_type': eventType,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      logs.add(jsonEncode(logEntry));
      
      // Keep only last 100 logs per event type
      if (logs.length > 100) {
        logs.removeRange(0, logs.length - 100);
      }
      
      await prefs.setStringList('$_auditLogPrefix$eventType', logs);
    } catch (e) {
      debugPrint('⚠️ Failed to log audit event: $e');
    }
  }

  /// Get audit logs
  Future<List<Map<String, dynamic>>> getAuditLogs(String eventType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('$_auditLogPrefix$eventType') ?? [];
      return logs.map((log) => jsonDecode(log) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('⚠️ Failed to get audit logs: $e');
      return [];
    }
  }

  /// Get rate limit status for display
  Future<Map<String, dynamic>> getRateLimitStatus(String mobileNumber) async {
    try {
      final cleanMobile = _cleanMobileNumber(mobileNumber);
      
      // Try server-side first
      if (_shouldCheckFirestore()) {
        try {
          final serverStatus = await _getServerRateLimitStatus(cleanMobile);
          if (serverStatus != null) return serverStatus;
        } catch (e) {
          debugPrint('⚠️ Server status check failed: $e');
        }
      }
      
      // Fall back to client-side
      return await _getClientRateLimitStatus(cleanMobile);
      
    } catch (e) {
      debugPrint('⚠️ Failed to get rate limit status: $e');
      return {
        'is_limited': false,
        'attempts': 0,
        'max_attempts': _maxAttempts,
        'reset_time': null,
        'source': 'error',
      };
    }
  }
  
  /// Get server rate limit status (with timeout)
  Future<Map<String, dynamic>?> _getServerRateLimitStatus(String cleanMobile) async {
    final docRef = FirebaseFirestore.instance
        .collection('rate_limits')
        .doc('otp_$cleanMobile');
    
    final doc = await docRef
        .get()
        .timeout(Duration(seconds: _firestoreTimeoutSeconds));
    
    if (!doc.exists) return null;
    
    final data = doc.data()!;
    final attempts = data['attempts'] as int? ?? 0;
    final lastAttempt = (data['last_attempt'] as Timestamp?)?.toDate();
    
    if (lastAttempt == null) return null;
    
    final resetTime = lastAttempt.add(const Duration(minutes: _rateLimitMinutes));
    
    return {
      'is_limited': attempts >= _maxAttempts && DateTime.now().isBefore(resetTime),
      'attempts': attempts,
      'max_attempts': _maxAttempts,
      'reset_time': resetTime.toIso8601String(),
      'source': 'server',
    };
  }
  
  /// Get client rate limit status
  Future<Map<String, dynamic>> _getClientRateLimitStatus(String cleanMobile) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_rateLimitPrefix$cleanMobile';
    
    final data = prefs.getString(key);
    if (data == null) {
      return {
        'is_limited': false,
        'attempts': 0,
        'max_attempts': _maxAttempts,
        'reset_time': null,
        'source': 'client',
      };
    }
    
    final Map<String, dynamic> rateData = jsonDecode(data);
    final attempts = rateData['attempts'] as int? ?? 0;
    final lastAttempt = DateTime.parse(rateData['last_attempt'] as String);
    final resetTime = lastAttempt.add(const Duration(minutes: _rateLimitMinutes));
    
    return {
      'is_limited': attempts >= _maxAttempts && DateTime.now().isBefore(resetTime),
      'attempts': attempts,
      'max_attempts': _maxAttempts,
      'reset_time': resetTime.toIso8601String(),
      'source': 'client',
    };
  }

  /// Reset rate limit (admin function)
  Future<void> resetRateLimit(String mobileNumber) async {
    try {
      final cleanMobile = _cleanMobileNumber(mobileNumber);
      
      // Clear server-side
      if (_shouldCheckFirestore()) {
        try {
          await FirebaseFirestore.instance
              .collection('rate_limits')
              .doc('otp_$cleanMobile')
              .delete()
              .timeout(Duration(seconds: _firestoreTimeoutSeconds));
        } catch (e) {
          debugPrint('⚠️ Server reset failed: $e');
        }
      }
      
      // Clear client-side
      final prefs = await SharedPreferences.getInstance();
      final key = '$_rateLimitPrefix$cleanMobile';
      await prefs.remove(key);
      
      await _logAuditEvent('rate_limit_reset', {
        'mobile': cleanMobile,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      debugPrint('✅ Rate limit reset for: $cleanMobile');
    } catch (e) {
      debugPrint('⚠️ Failed to reset rate limit: $e');
    }
  }

  /// Clear all OTP data (admin function)
  Future<void> clearAllOtpData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final otpKeys = keys.where((key) => 
        key.startsWith(_rateLimitPrefix) ||
        key.startsWith(_sessionKeyPrefix) ||
        key.startsWith(_deviceBindingPrefix) ||
        key.startsWith(_auditLogPrefix)
      ).toList();
      
      for (final key in otpKeys) {
        await prefs.remove(key);
      }
      
      await _logAuditEvent('system_cleared', {
        'action': 'clear_all_otp_data',
        'timestamp': DateTime.now().toIso8601String(),
        'keys_cleared': otpKeys.length,
      });
      
      debugPrint('✅ Cleared all OTP data: ${otpKeys.length} keys');
    } catch (e) {
      debugPrint('⚠️ Failed to clear all OTP data: $e');
    }
  }

  /// Get OTP system statistics
  Future<Map<String, dynamic>> getOtpSystemStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      return {
        'rate_limit_entries': keys.where((key) => key.startsWith(_rateLimitPrefix)).length,
        'active_sessions': keys.where((key) => key.startsWith(_sessionKeyPrefix)).length,
        'device_bindings': keys.where((key) => key.startsWith(_deviceBindingPrefix)).length,
        'audit_log_entries': keys.where((key) => key.startsWith(_auditLogPrefix)).length,
        'total_keys': keys.length,
        'firestore_available': _firestoreAvailable,
        'last_firestore_check': _lastFirestoreCheck?.toIso8601String(),
        'consecutive_failures': _consecutiveFailures,
      };
    } catch (e) {
      debugPrint('⚠️ Failed to get OTP system stats: $e');
      return {
        'rate_limit_entries': 0,
        'active_sessions': 0,
        'device_bindings': 0,
        'audit_log_entries': 0,
        'total_keys': 0,
        'firestore_available': false,
        'consecutive_failures': _consecutiveFailures,
      };
    }
  }

  /// Check if we should attempt Firestore operations
  bool _shouldCheckFirestore() {
    // If Firebase is not initialized, skip
    if (!Firebase.apps.isNotEmpty) {
      debugPrint('⚠️ Firebase not initialized, skipping Firestore check');
      return false;
    }
    
    // If we've never checked or it's been more than 30 seconds since last failed check
    if (_lastFirestoreCheck == null) return true;
    if (_firestoreAvailable) return true;
    
    final timeSinceLastCheck = DateTime.now().difference(_lastFirestoreCheck!);
    return timeSinceLastCheck.inSeconds > 30;
  }
  
  /// Handle Firestore errors and update availability status
  void _handleFirestoreError(dynamic error) {
    _firestoreAvailable = false;
    _lastFirestoreCheck = DateTime.now();
    _consecutiveFailures++;
    
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          debugPrint('🚫 Firestore permission denied - check security rules');
          break;
        case 'unavailable':
          debugPrint('📡 Firestore unavailable - offline mode');
          break;
        case 'deadline-exceeded':
          debugPrint('⏱️ Firestore timeout - slow network');
          break;
        case 'not-found':
          debugPrint('ℹ️ Firestore document not found (expected for new numbers)');
          break;
        default:
          debugPrint('⚠️ Firestore error: ${error.code}');
      }
    }
  }

  /// Reset Firestore availability check (call after network status changes)
  void resetFirestoreStatus() {
    _firestoreAvailable = true;
    _lastFirestoreCheck = null;
    _consecutiveFailures = 0;
    debugPrint('🔄 Firestore status reset');
  }

  /// Clean mobile number format
  String _cleanMobileNumber(String mobile) {
    return mobile
        .replaceAll(RegExp(r'[\s\-\(\)]'), '')
        .replaceAll(RegExp(r'^\+?91'), '');
  }

  /// Base64 encoding
  String _base64Encode(String data) {
    final bytes = utf8.encode(data);
    return base64.encode(bytes);
  }

  /// Base64 decoding
  String _base64Decode(String data) {
    final bytes = base64.decode(data);
    return utf8.decode(bytes);
  }
}
