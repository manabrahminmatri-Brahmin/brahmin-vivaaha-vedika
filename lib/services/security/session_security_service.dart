import 'dart:math';

import 'package:flutter/foundation.dart';

/// In-memory per-app-session watermark token for traceable profile photos.
///
/// Never persisted to [SharedPreferences] or disk.
abstract final class SessionSecurityService {
  SessionSecurityService._();

  static const _tokenChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final Random _random = Random.secure();

  static String? _token;
  static int _sessionGeneration = 0;

  /// Injectable clock for watermark timestamps (tests).
  @visibleForTesting
  static DateTime Function() watermarkClock = DateTime.now;

  /// Starts a new in-memory session (login / session restore).
  static void beginSession() {
    _sessionGeneration++;
    _token = _generateToken();
    debugPrint(
      '🔐 SessionSecurityService: watermark session #$_sessionGeneration',
    );
  }

  /// Current 4-character fragment shown on protected photos.
  static String currentWatermarkToken() {
    _token ??= _generateToken();
    return _token!;
  }

  /// Monotonic session id — changes on each [beginSession].
  @visibleForTesting
  static int get sessionGeneration => _sessionGeneration;

  static void clearSession() {
    _token = null;
    debugPrint('🔐 SessionSecurityService: session cleared');
  }

  @visibleForTesting
  static String generateTokenForTests() => _generateToken();

  static String _generateToken() {
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buffer.write(_tokenChars[_random.nextInt(_tokenChars.length)]);
    }
    return buffer.toString();
  }
}
