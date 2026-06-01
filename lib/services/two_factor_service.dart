import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/build_secrets.dart';

typedef TwoFactorHttpGet =
    Future<http.Response> Function(
      Uri url, {
      required Duration timeout,
      required String debugLabel,
    });

/// 2Factor.in OTP Service - Direct SMS OTP (NO reCAPTCHA required)
/// Replaces Firebase phone auth which requires CAPTCHA verification
class TwoFactorService {
  static final TwoFactorService _instance = TwoFactorService._internal();
  factory TwoFactorService() => _instance;
  TwoFactorService._internal({
    TwoFactorHttpGet? httpGet,
    String? apiKey,
    String? otpTemplate,
  }) : _httpGetOverride = httpGet,
       _apiKeyOverride = apiKey,
       _otpTemplateOverride = otpTemplate;

  @visibleForTesting
  factory TwoFactorService.forTesting({
    TwoFactorHttpGet? httpGet,
    String? apiKey,
    String? otpTemplate,
  }) => TwoFactorService._internal(
    httpGet: httpGet,
    apiKey: apiKey,
    otpTemplate: otpTemplate,
  );

  static const String _baseUrl = 'https://2factor.in/API/V1';

  final TwoFactorHttpGet? _httpGetOverride;
  final String? _apiKeyOverride;
  final String? _otpTemplateOverride;

  /// 2factor.in returns PascalCase keys (`Status`, `Details`); some proxies may lowercase them.
  static String? _readStatus(Map<String, dynamic> data) {
    final v = data['Status'] ?? data['status'];
    return v?.toString();
  }

  static dynamic _readDetails(Map<String, dynamic> data) {
    return data['Details'] ?? data['details'];
  }

  static bool _isSuccessStatus(String? status) {
    if (status == null) return false;
    return status.toLowerCase() == 'success';
  }

  static String? _sessionIdFromDetails(dynamic details) {
    if (details == null) return null;
    if (details is String) {
      return details.trim().isEmpty ? null : details.trim();
    }
    if (details is Map) {
      final id = details['session_id'] ?? details['SessionId'] ?? details['id'];
      if (id != null) return id.toString();
    }
    return null;
  }

  // Store session IDs for verification (memory cache + persistent storage)
  final Map<String, String> _sessionIds = {};
  static const String _sessionPrefKey = '2fa_sessions';
  static const Duration _sessionExpiry = Duration(minutes: 10);
  static const Duration _sendTimeout = Duration(seconds: 25);
  static const Duration _verifyTimeoutPrimary = Duration(seconds: 30);
  static const Duration _verifyTimeoutRetry = Duration(seconds: 35);
  String? _assetApiKeyCache;
  String? _assetOtpTemplateCache;

  /// Builds the 2factor send-OTP URL. [otpTemplate] must be empty or a safe name.
  @visibleForTesting
  static String buildSendOtpUrl(
    String apiKey,
    String cleanMobile,
    String otpTemplate,
  ) {
    final base = '$_baseUrl/$apiKey/SMS/$cleanMobile/AUTOGEN';
    final template = otpTemplate.trim();
    if (template.isEmpty) return base;
    return '$base/$template';
  }

  static final RegExp _otpTemplateNamePattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Example names from docs — not valid until created in 2factor CP.
  static const Set<String> _placeholderOtpTemplates = {
    'MyAppOTP',
    'MyTemplate',
    'template_name',
  };

  static void _warnIfPlaceholderOtpTemplate(String template) {
    if (!kDebugMode) return;
    if (_placeholderOtpTemplates.contains(template)) {
      debugPrint(
        '⚠️ TWO_FACTOR_OTP_TEMPLATE="$template" looks like a placeholder. '
        'Use the exact approved name from 2factor → OTP Services → Manage OTP Templates. '
        'Wrong names can cause voice fallback while the API still returns 200.',
      );
    }
  }

  static String? _sanitizeOtpTemplate(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (!_otpTemplateNamePattern.hasMatch(t)) {
      debugPrint(
        '⚠️ Invalid TWO_FACTOR_OTP_TEMPLATE "$t" — use letters, digits, _ or - only',
      );
      return null;
    }
    return t;
  }

  Future<http.Response> _httpGet(
    Uri url, {
    required Duration timeout,
    required String debugLabel,
  }) {
    final override = _httpGetOverride;
    if (override != null) {
      return override(url, timeout: timeout, debugLabel: debugLabel);
    }

    return http
        .get(url)
        .timeout(
          timeout,
          onTimeout: () {
            debugPrint('⏱️ $debugLabel exceeded ${timeout.inSeconds}s');
            throw TimeoutException('$debugLabel timed out');
          },
        );
  }

  Future<String> _resolveApiKey() async {
    final override = _apiKeyOverride?.trim();
    if (override != null && override.isNotEmpty) return override;

    final buildKey = BuildSecrets.twoFactorApiKey.trim();
    if (buildKey.isNotEmpty) return buildKey;

    final cached = _assetApiKeyCache?.trim();
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final raw = await rootBundle.loadString('dart_defines.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return '';
      final key =
          (decoded['TWO_FACTOR_API_KEY'] ??
                  decoded['Two_Factor_API_Key'] ??
                  decoded['TWO_FACTOR_KEY'] ??
                  decoded['TWO_FACTOR_APIKEY'])
              ?.toString()
              .trim();
      _assetApiKeyCache = key;
      return key ?? '';
    } catch (e) {
      debugPrint('⚠️ Could not load bundled OTP config: $e');
      return '';
    }
  }

  Future<String> _resolveOtpTemplate() async {
    final fromOverride = _sanitizeOtpTemplate(_otpTemplateOverride);
    if (fromOverride != null) return fromOverride;

    final fromBuild = _sanitizeOtpTemplate(BuildSecrets.twoFactorOtpTemplate);
    if (fromBuild != null) return fromBuild;

    final cached = _assetOtpTemplateCache?.trim();
    if (cached != null && cached.isNotEmpty) {
      return _sanitizeOtpTemplate(cached) ?? '';
    }

    try {
      final raw = await rootBundle.loadString('dart_defines.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return '';
      final key = (decoded['TWO_FACTOR_OTP_TEMPLATE'] ??
              decoded['Two_Factor_Otp_Template'])
          ?.toString();
      _assetOtpTemplateCache = key;
      return _sanitizeOtpTemplate(key) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Send OTP to mobile number using 2Factor.in
  Future<TwoFactorResult> sendOtp(String mobile) async {
    try {
      final cleanMobile = _cleanMobile(mobile);

      // Validate 10-digit Indian mobile
      if (cleanMobile.length != 10 ||
          !RegExp(r'^[6-9][0-9]{9}$').hasMatch(cleanMobile)) {
        return TwoFactorResult.failure(
          'Invalid mobile number. Enter 10 digits starting with 6-9',
        );
      }

      final apiKey = await _resolveApiKey();
      if (apiKey.isEmpty) {
        return TwoFactorResult.failure(
          'OTP service not configured. Add TWO_FACTOR_API_KEY in dart_defines.json and rebuild the mobile app.',
        );
      }

      final otpTemplate = await _resolveOtpTemplate();
      final url = Uri.parse(
        buildSendOtpUrl(apiKey, cleanMobile, otpTemplate),
      );

      debugPrint('📱 Sending OTP to: $cleanMobile');
      debugPrint('📱 2Factor send URL: ${url.path}');
      if (otpTemplate.isNotEmpty) {
        debugPrint('📱 OTP template: $otpTemplate');
        _warnIfPlaceholderOtpTemplate(otpTemplate);
      } else if (kDebugMode) {
        debugPrint(
          'ℹ️ No TWO_FACTOR_OTP_TEMPLATE — using default /AUTOGEN. '
          'For reliable SMS in India, register a DLT template in 2factor CP.',
        );
      }

      final response = await _httpGet(
        url,
        timeout: _sendTimeout,
        debugLabel: 'OTP send',
      );

      debugPrint('📱 2Factor response: ${response.statusCode}');
      if (kDebugMode && response.body.isNotEmpty) {
        debugPrint('📱 2Factor body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          return TwoFactorResult.failure('Invalid OTP provider response');
        }
        final data = Map<String, dynamic>.from(decoded);
        final status = _readStatus(data);
        final detailsRaw = _readDetails(data);
        final sessionId = _sessionIdFromDetails(detailsRaw);

        if (_isSuccessStatus(status) && sessionId != null) {
          await _saveSession(cleanMobile, sessionId);

          debugPrint(
            '✅ OTP sent. Session: ${sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId}...',
          );
          return TwoFactorResult.success(
            message: 'OTP sent to +91 $cleanMobile',
            sessionId: sessionId,
          );
        }

        final errMsg = detailsRaw?.toString();
        return TwoFactorResult.failure(
          (errMsg != null && errMsg.isNotEmpty) ? errMsg : 'Failed to send OTP',
        );
      } else {
        return TwoFactorResult.failure(
          'Failed to send OTP (${response.statusCode})',
        );
      }
    } catch (e) {
      debugPrint('❌ Send OTP error: $e');
      return TwoFactorResult.failure('Network error. Check connection.');
    }
  }

  /// Verify OTP code
  Future<TwoFactorResult> verifyOtp(String mobile, String otp) async {
    try {
      final cleanMobile = _cleanMobile(mobile);
      // 🔥 FIX: Load session from persistent storage (survives app kill)
      final sessionId = await _loadSession(cleanMobile);

      if (sessionId == null || sessionId.isEmpty) {
        return TwoFactorResult.failure('Session expired. Request new OTP');
      }

      final cleanOtp = otp.trim();
      if (cleanOtp.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(cleanOtp)) {
        return TwoFactorResult.failure('Invalid OTP. Enter 6 digits');
      }

      final apiKey = await _resolveApiKey();
      if (apiKey.isEmpty) {
        return TwoFactorResult.failure(
          'OTP service not configured. Add TWO_FACTOR_API_KEY in dart_defines.json and rebuild the mobile app.',
        );
      }
      final url = Uri.parse(
        '$_baseUrl/$apiKey/SMS/VERIFY/$sessionId/$cleanOtp',
      );

      debugPrint('📱 Verifying OTP for: $cleanMobile');

      http.Response response;
      try {
        response = await _httpGet(
          url,
          timeout: _verifyTimeoutPrimary,
          debugLabel: 'OTP verification',
        );
      } on TimeoutException catch (_) {
        debugPrint('📱 Verify: retrying once after timeout...');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          response = await _httpGet(
            url,
            timeout: _verifyTimeoutRetry,
            debugLabel: 'OTP verification (retry)',
          );
        } on TimeoutException {
          return TwoFactorResult.failure(
            'Verification timed out. Check your connection, then try again or request a new OTP.',
          );
        }
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          return TwoFactorResult.failure('Invalid OTP provider response');
        }
        final data = Map<String, dynamic>.from(decoded);
        final status = _readStatus(data);
        final details = _readDetails(data)?.toString() ?? '';

        if (_isSuccessStatus(status) &&
            details.toLowerCase() == 'otp matched') {
          await _clearSession(cleanMobile);
          return TwoFactorResult.success(message: 'OTP verified');
        }
        return TwoFactorResult.failure(
          details.isNotEmpty ? details : 'Invalid OTP',
        );
      } else {
        return TwoFactorResult.failure(
          'Verification failed (${response.statusCode})',
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('❌ Verify OTP error: $e');
      return TwoFactorResult.failure(
        'Verification timed out. Check your connection, then try again or request a new OTP.',
      );
    } catch (e) {
      debugPrint('❌ Verify OTP error: $e');
      return TwoFactorResult.failure(
        'Could not reach OTP service. Check your connection and try again.',
      );
    }
  }

  String _cleanMobile(String mobile) {
    var clean = mobile
        .replaceAll('+91', '')
        .replaceAll('+', '')
        .replaceAll(RegExp(r'[\s\-\(\)]'), '')
        .trim();

    // 🔥 FIX: Strip bare 91 country code (12-digit input like "918985123456")
    if (clean.length == 12 && clean.startsWith('91')) {
      clean = clean.substring(2);
    }
    return clean;
  }

  void clearSession(String mobile) {
    _sessionIds.remove(_cleanMobile(mobile));
    _clearSession(_cleanMobile(mobile));
  }

  // ── Session Persistence (BUG 4 FIX) ─────────────────────────────────────

  /// Save session to SharedPreferences to survive app kill
  Future<void> _saveSession(String cleanMobile, String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefKey);
      final map = raw != null
          ? Map<String, dynamic>.from(jsonDecode(raw))
          : <String, dynamic>{};
      map[cleanMobile] = {
        'id': sessionId,
        'expires_at': DateTime.now().add(_sessionExpiry).toIso8601String(),
      };
      await prefs.setString(_sessionPrefKey, jsonEncode(map));
      _sessionIds[cleanMobile] =
          sessionId; // also keep in memory for fast reads
      debugPrint('💾 Session saved for $cleanMobile');
    } catch (e) {
      debugPrint('⚠️ Failed to save session: $e');
      // Fallback: at least keep in memory
      _sessionIds[cleanMobile] = sessionId;
    }
  }

  /// Load session from SharedPreferences (with expiry check)
  Future<String?> _loadSession(String cleanMobile) async {
    // Memory first (fast path)
    if (_sessionIds.containsKey(cleanMobile)) {
      return _sessionIds[cleanMobile];
    }
    // Prefs fallback (survives app kill)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefKey);
      if (raw == null) return null;
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      final entry = map[cleanMobile] as Map<String, dynamic>?;
      if (entry == null) return null;
      final expiresAt = DateTime.tryParse(entry['expires_at'] as String? ?? '');
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        debugPrint('⏰ Session expired for $cleanMobile');
        await _clearSession(cleanMobile);
        return null;
      }
      final sessionId = entry['id'] as String;
      _sessionIds[cleanMobile] = sessionId; // cache in memory
      debugPrint('📂 Session loaded from storage for $cleanMobile');
      return sessionId;
    } catch (e) {
      debugPrint('⚠️ Failed to load session: $e');
      return null;
    }
  }

  /// Clear session from both memory and persistent storage
  Future<void> _clearSession(String cleanMobile) async {
    _sessionIds.remove(cleanMobile);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefKey);
      if (raw == null) return;
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      map.remove(cleanMobile);
      await prefs.setString(_sessionPrefKey, jsonEncode(map));
      debugPrint('🗑️ Session cleared for $cleanMobile');
    } catch (e) {
      debugPrint('⚠️ Failed to clear session: $e');
    }
  }
}

class TwoFactorResult {
  final bool success;
  final String message;
  final String? sessionId;

  TwoFactorResult.success({required this.message, this.sessionId})
    : success = true;
  TwoFactorResult.failure(this.message) : success = false, sessionId = null;
}
