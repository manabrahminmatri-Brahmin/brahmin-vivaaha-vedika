import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage rate limiting and prevent brute force attacks
class RateLimitService {
  final SharedPreferences _prefs;
  
  // Rate limit configuration
  static const int maxLoginAttempts = 5;
  static const int lockoutDurationMinutes = 15;
  static const int maxMpinAttempts = 3; // Changed to 3 attempts as per requirement
  static const int mpinLockoutDurationMinutes = 3; // Changed to 3 minutes as per requirement
  
  RateLimitService(this._prefs);

  /// Check if login attempts are exceeded
  Future<bool> isLoginBlocked(String identifier) async {
    final attemptKey = 'login_attempts_$identifier';
    final lockoutKey = 'login_lockout_$identifier';
    
    // Check if locked out
    final lockoutUntil = _prefs.getInt(lockoutKey);
    if (lockoutUntil != null) {
      final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutUntil);
      if (DateTime.now().isBefore(lockoutTime)) {
        return true; // Still locked out
      } else {
        // Lockout expired, clear it
        await _prefs.remove(lockoutKey);
        await _prefs.remove(attemptKey);
        return false;
      }
    }
    
    // Check attempt count
    final attempts = _prefs.getInt(attemptKey) ?? 0;
    if (attempts >= maxLoginAttempts) {
      // Lock account
      final lockoutUntil = DateTime.now().add(Duration(minutes: lockoutDurationMinutes));
      await _prefs.setInt(lockoutKey, lockoutUntil.millisecondsSinceEpoch);
      return true;
    }
    
    return false;
  }

  /// Record a failed login attempt
  Future<void> recordFailedLogin(String identifier) async {
try {
  final attemptKey = 'login_attempts_$identifier';
    final attempts = (_prefs.getInt(attemptKey) ?? 0) + 1;
    await _prefs.setInt(attemptKey, attempts);
    
    // If max attempts reached, lock account
    if (attempts >= maxLoginAttempts) {
      final lockoutUntil = DateTime.now().add(Duration(minutes: lockoutDurationMinutes));
      await _prefs.setInt('login_lockout_$identifier', lockoutUntil.millisecondsSinceEpoch);
    }
    } catch (e) {
      debugPrint('⚠️ RateLimitService.recordFailedLogin: $e');
    }
  }

  /// Reset login attempts (on successful login)
  Future<void> resetLoginAttempts(String identifier) async {
try {
  await _prefs.remove('login_attempts_$identifier');
    await _prefs.remove('login_lockout_$identifier');
    } catch (e) {
      debugPrint('⚠️ RateLimitService.resetLoginAttempts: $e');
    }
  }

  /// Get remaining lockout time in minutes
  Future<int?> getRemainingLockoutMinutes(String identifier) async {
try {
  final lockoutKey = 'login_lockout_$identifier';
    final lockoutUntil = _prefs.getInt(lockoutKey);
    
    if (lockoutUntil == null) return null;
    
    final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutUntil);
    final now = DateTime.now();
    
    if (now.isAfter(lockoutTime)) {
      await _prefs.remove(lockoutKey);
      return null;
    }
    
    return lockoutTime.difference(now).inMinutes + 1;
    } catch (e) {
      debugPrint('⚠️ RateLimitService.getRemainingLockoutMinutes: $e');
      return null;
    }
  }

  /// Get remaining login attempts
  Future<int> getRemainingLoginAttempts(String identifier) async {
try {
  final attempts = _prefs.getInt('login_attempts_$identifier') ?? 0;
    return maxLoginAttempts - attempts;
    } catch (e) {
      debugPrint('⚠️ RateLimitService.getRemainingLoginAttempts: $e');
      return 5;
    }
  }

  /// Check if MPIN attempts are exceeded
  Future<bool> isMpinBlocked(String userId) async {
    final attemptKey = 'mpin_attempts_$userId';
    final lockoutKey = 'mpin_lockout_$userId';
    
    final lockoutUntil = _prefs.getInt(lockoutKey);
    if (lockoutUntil != null) {
      final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutUntil);
      if (DateTime.now().isBefore(lockoutTime)) {
        return true;
      } else {
        await _prefs.remove(lockoutKey);
        await _prefs.remove(attemptKey);
        return false;
      }
    }
    
    final attempts = _prefs.getInt(attemptKey) ?? 0;
    if (attempts >= maxMpinAttempts) {
      final lockoutUntil = DateTime.now().add(Duration(minutes: mpinLockoutDurationMinutes));
      await _prefs.setInt(lockoutKey, lockoutUntil.millisecondsSinceEpoch);
      return true;
    }
    
    return false;
  }

  /// Record a failed MPIN attempt
  Future<void> recordFailedMpin(String userId) async {
try {
  final attemptKey = 'mpin_attempts_$userId';
    final attempts = (_prefs.getInt(attemptKey) ?? 0) + 1;
    await _prefs.setInt(attemptKey, attempts);
    
    if (attempts >= maxMpinAttempts) {
      final lockoutUntil = DateTime.now().add(Duration(minutes: mpinLockoutDurationMinutes));
      await _prefs.setInt('mpin_lockout_$userId', lockoutUntil.millisecondsSinceEpoch);
    }
    } catch (e) {
      debugPrint('⚠️ RateLimitService.recordFailedMpin: $e');
    }
  }

  /// Reset MPIN attempts
  Future<void> resetMpinAttempts(String userId) async {
try {
  await _prefs.remove('mpin_attempts_$userId');
    await _prefs.remove('mpin_lockout_$userId');
    } catch (e) {
      debugPrint('⚠️ RateLimitService.resetMpinAttempts: $e');
    }
  }

  /// Get remaining MPIN lockout time in seconds (for precise timer display)
  Future<int?> getRemainingMpinLockoutSeconds(String userId) async {
try {
  final lockoutKey = 'mpin_lockout_$userId';
    final lockoutUntil = _prefs.getInt(lockoutKey);
    
    if (lockoutUntil == null) return null;
    
    final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutUntil);
    final now = DateTime.now();
    
    if (now.isAfter(lockoutTime)) {
      await _prefs.remove(lockoutKey);
      return null;
    }
    
    final seconds = lockoutTime.difference(now).inSeconds;
    return seconds > 0 ? seconds : null;
    } catch (e) {
      debugPrint('⚠️ RateLimitService.getRemainingMpinLockoutSeconds: $e');
      return null;
    }
  }

  /// Get remaining MPIN lockout time in minutes (for backward compatibility)
  Future<int?> getRemainingMpinLockoutMinutes(String userId) async {
try {
  final seconds = await getRemainingMpinLockoutSeconds(userId);
    if (seconds == null) return null;
    return (seconds / 60).ceil();
    } catch (e) {
      debugPrint('⚠️ RateLimitService.getRemainingMpinLockoutMinutes: $e');
      return null;
    }
  }

  /// Get remaining MPIN attempts
  Future<int> getRemainingMpinAttempts(String userId) async {
try {
  final attemptKey = 'mpin_attempts_$userId';
    final attempts = _prefs.getInt(attemptKey) ?? 0;
    return maxMpinAttempts - attempts;
    } catch (e) {
      debugPrint('⚠️ RateLimitService.getRemainingMpinAttempts: $e');
      return 5;
    }
  }
}
