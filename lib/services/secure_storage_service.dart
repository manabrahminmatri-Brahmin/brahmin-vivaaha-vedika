import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../models/user.dart';

/// Service for securely storing sensitive data using flutter_secure_storage
/// Falls back to SharedPreferences for non-sensitive data
class SecureStorageService {
  // encryptedSharedPreferences = true uses EncryptedSharedPreferences on Android,
  // which is significantly faster than the default Keystore-backed implementation.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final SharedPreferences _prefs;

  SecureStorageService(this._prefs);

  // Keys for secure storage
  static const String _passwordKey = 'secure_password';
  static const String _mpinKey = 'secure_mpin';
  static const String _appLockedKey = 'app_locked';

  // Keys for regular storage (non-sensitive)
  static const String _userKey = 'mana_Vivaaha Vedika_user';
  static const String _usersDbKey = 'mana_Vivaaha Vedika_users_db';

  /// Save password securely using profile_id (more reliable than user.id)
  /// 
  /// IMPORTANT: Passwords stored here never expire. They remain valid indefinitely
  /// until explicitly deleted or overwritten by a password reset.
  Future<void> savePassword(String profileId, String passwordHash) async {
    await _storage.write(key: '${_passwordKey}_$profileId', value: passwordHash);
  }

  /// Get password hash securely by profile_id
  /// 
  /// Returns the password hash if it exists. Passwords never expire - they remain
  /// valid until explicitly reset or deleted.
  Future<String?> getPasswordHash(String profileId) async {
    return await _storage.read(key: '${_passwordKey}_$profileId');
  }

  /// Save MPIN hash to FlutterSecureStorage AND SharedPreferences fallback.
  /// FlutterSecureStorage can be wiped on Android (app update, data clear).
  /// SharedPreferences fallback ensures MPIN is never permanently lost.
  Future<void> saveMpin(String profileId, String mpinHash) async {
    // Primary: FlutterSecureStorage
    try {
      await _storage.write(key: '${_mpinKey}_$profileId', value: mpinHash);
    } catch (e) {
      debugPrint('⚠️ saveMpin: SecureStorage write failed: $e');
    }
    // Fallback: SharedPreferences (MPIN is already hashed — safe to store)
    await _prefs.setString('mpin_hash_$profileId', mpinHash);
  }

  /// Get MPIN hash from FlutterSecureStorage, fall back to SharedPreferences.
  Future<String?> getMpinHash(String profileId) async {
    // Try SecureStorage first
    try {
      final val = await _storage.read(key: '${_mpinKey}_$profileId');
      if (val != null && val.isNotEmpty) return val;
    } catch (e) {
      debugPrint('⚠️ getMpinHash: SecureStorage read failed: $e');
    }
    // Fallback: SharedPreferences
    final fallback = _prefs.getString('mpin_hash_$profileId') ?? '';
    if (fallback.isNotEmpty) {
      debugPrint('✅ getMpinHash: recovered from SharedPreferences fallback');
      // Restore to SecureStorage
      try {
        await _storage.write(key: '${_mpinKey}_$profileId', value: fallback);
      } catch (e) {
        debugPrint('⚠️ getMpinHash: SecureStorage restore from prefs failed: $e');
      }
    }
    return fallback.isNotEmpty ? fallback : null;
  }

  /// Get MPIN hash (alias for getMpinHash)
  Future<String?> getMpin(String profileId) async {
    return await getMpinHash(profileId);
  }

  /// Legacy: Save password by user ID (for migration)
  Future<void> savePasswordByUserId(String userId, String passwordHash) async {
    await _storage.write(key: '${_passwordKey}_user_$userId', value: passwordHash);
  }

  /// Legacy: Get password hash by user ID (for migration)
  Future<String?> getPasswordHashByUserId(String userId) async {
    return await _storage.read(key: '${_passwordKey}_user_$userId');
  }

  /// Legacy: Save MPIN by user ID (for migration)
  Future<void> saveMpinByUserId(String userId, String mpinHash) async {
    await _storage.write(key: '${_mpinKey}_user_$userId', value: mpinHash);
  }

  /// Legacy: Get MPIN hash by user ID (for migration)
  Future<String?> getMpinHashByUserId(String userId) async {
    try {
      final val = await _storage.read(key: '${_mpinKey}_user_$userId');
      if (val != null && val.isNotEmpty) return val;
    } catch (e) {
      debugPrint('⚠️ getMpinHashByUserId: SecureStorage read failed: $e');
    }
    // Fallback: SharedPreferences
    final fb = _prefs.getString('mpin_hash_user_$userId') ?? '';
    return fb.isNotEmpty ? fb : null;
  }

  /// Delete password by profile_id
  Future<void> deletePassword(String profileId) async {
    await _storage.delete(key: '${_passwordKey}_$profileId');
    // Also delete legacy user ID-based storage
    await _storage.delete(key: '${_passwordKey}_user_$profileId');
  }

  /// Delete MPIN by profile_id
  Future<void> deleteMpin(String profileId) async {
    await _storage.delete(key: '${_mpinKey}_$profileId');
    // Also delete legacy user ID-based storage
    await _storage.delete(key: '${_mpinKey}_user_$profileId');
  }

  /// Migrate credentials from user ID to profile_id
  /// This helps transition existing users to the new system
  Future<void> migrateCredentialsToProfileId(String userId, String profileId) async {
    // Try to get password by user ID
    final passwordHash = await getPasswordHashByUserId(userId);
    if (passwordHash != null) {
      await savePassword(profileId, passwordHash);
      debugPrint('✅ Migrated password from user ID $userId to profile_id $profileId');
    }

    // Try to get MPIN by user ID
    final mpinHash = await getMpinHashByUserId(userId);
    if (mpinHash != null) {
      await saveMpin(profileId, mpinHash);
      debugPrint('✅ Migrated MPIN from user ID $userId to profile_id $profileId');
    }
  }

  /// Save user data (non-sensitive parts) to SharedPreferences
  Future<void> saveUserData(User user) async {
    // Create a copy of user without sensitive data for storage
    // FIX: Use toLocalCacheJson() instead of deprecated toJson() for local storage
    final userForStorage = user.toLocalCacheJson();
    // Remove password and MPIN from JSON before storing
    userForStorage.remove('password');
    userForStorage.remove('mpin');
    
    await _prefs.setString(_userKey, jsonEncode(userForStorage));
    await _updateUserInDb(user);
  }

  /// Load user data from SharedPreferences
  User? loadUserData() {
    try {
      final userJson = _prefs.getString(_userKey);
      if (userJson != null && userJson.isNotEmpty) {
        final decoded = jsonDecode(userJson);
        if (decoded is Map<String, dynamic>) {
          // Validate required fields
          final id = decoded['id'] as String? ?? '';
          if (id.isNotEmpty &&
              decoded.containsKey('email') &&
              decoded.containsKey('mobile_number')) {
            // Set empty password/mpin - will be loaded from secure storage
            decoded['password'] = '';
            decoded['mpin'] = null;
            return User.fromJson(decoded);
          }
        }
      }
    } catch (e) {
      // Clear corrupted data
      _prefs.remove(_userKey);
    }
    return null;
  }

  /// Get current user from local storage
  Future<User?> getCurrentUser() async {
    try {
      final userJson = _prefs.getString(_userKey);
      if (userJson == null) return null;

      final decoded = jsonDecode(userJson);
      // Validate required fields
      final id = decoded['id'] as String? ?? '';
      if (id.isNotEmpty &&
          decoded.containsKey('email') &&
          decoded.containsKey('mobile_number')) {
        // Set empty password/mpin - will be loaded from secure storage
        decoded['password'] = '';
        decoded['mpin'] = null;
        return User.fromJson(decoded);
      }
    } catch (e) {
      // Clear corrupted data
      _prefs.remove(_userKey);
    }
    return null;
  }

  /// Update user in database (non-sensitive data only)
  Future<void> _updateUserInDb(User user) async {
    final users = await getAllUsers();
    final index = users.indexWhere((u) => u.id == user.id);

    if (index >= 0) {
      users[index] = user;
    } else {
      users.add(user);
    }

    await _saveAllUsers(users);
  }

  /// Get all users from database
  Future<List<User>> getAllUsers() async {
    final usersJson = _prefs.getString(_usersDbKey);
    if (usersJson == null) return [];

    try {
      final List<dynamic> usersList = jsonDecode(usersJson);
      return usersList.map((json) {
        // Remove sensitive data from stored users
        final userMap = Map<String, dynamic>.from(json);
        userMap['password'] = '';
        userMap['mpin'] = null;
        return User.fromJson(userMap);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Save all users to database (non-sensitive data only)
  Future<void> _saveAllUsers(List<User> users) async {
    final usersJson = jsonEncode(users.map((u) {
      // FIX: Use toLocalCacheJson() instead of deprecated toJson()
      final json = u.toLocalCacheJson();
      // Remove sensitive data
      json.remove('password');
      json.remove('mpin');
      return json;
    }).toList());
    await _prefs.setString(_usersDbKey, usersJson);
  }

  /// Clear all user data
  Future<void> clearUserData() async {
    debugPrint('🔍 PROFILE DATA CLEARING: clearUserData() called');

    // Log current user before clearing
    final currentUser = await _getCurrentUser();
    if (currentUser != null) {
      debugPrint('🔍 USER BEING CLEARED: ${currentUser.uid} - ${currentUser.email}');
    }
    
    // 🔥 SAFEGUARD: Only allow clearing if user is explicitly logging out
    // This prevents accidental data clearing during app usage
    final isLoggingOut = await _isUserLoggingOut();
    
    if (!isLoggingOut) {
      debugPrint('🚨 PROFILE DATA CLEARING BLOCKED: User not logging out - potential data corruption!');
      debugPrint('🚨 Call stack: ${StackTrace.current}');
      return; // Block the clear operation
    }
    
    await _prefs.remove(_userKey);
    debugPrint('🔍 PROFILE DATA CLEARED: clearUserData() completed');
  }

  /// Check if user is currently in logout process
  Future<bool> _isUserLoggingOut() async {
    try {
      // Check if logout was called in the last 5 seconds
      final prefs = await SharedPreferences.getInstance();
      final logoutTimestamp = prefs.getInt('logout_timestamp');
      if (logoutTimestamp == null) return false;
      
      final logoutTime = DateTime.fromMillisecondsSinceEpoch(logoutTimestamp);
      final now = DateTime.now();
      final timeDiff = now.difference(logoutTime);
      
      return timeDiff.inSeconds <= 5; // Within 5 seconds of logout
    } catch (e) {
      debugPrint('⚠️ Error checking logout status: $e');
      return false;
    }
  }

  Future<fb_auth.User?> _getCurrentUser() async {
    return fb_auth.FirebaseAuth.instance.currentUser;
  }

  /// Clear all secure storage on logout — intentionally preserves MPIN
  /// so the user can log back in immediately without re-registering.
  Future<void> clearAll() async {
    // ✅ Do NOT call _storage.deleteAll() — that wipes MPIN and password
    // which would break login after logout.
    // Instead, only clear session/user data, preserve credentials.
    await _prefs.remove(_userKey);
    await _prefs.remove(_usersDbKey);
    await _prefs.remove(_appLockedKey);
    await _prefs.remove('current_user_id');
    debugPrint('✅ Cleared session data (MPIN preserved for re-login)');
  }

  /// Full wipe — only called on account deletion or factory reset.
  /// This removes MPIN and all credentials permanently.
  Future<void> clearAllPermanently() async {
    await _storage.deleteAll();
    await _prefs.remove(_userKey);
    await _prefs.remove(_usersDbKey);
    await _prefs.remove(_appLockedKey);
    await _prefs.remove('current_user_id');
    debugPrint('✅ Permanently cleared all data including MPIN');
  }

  /// Save app lock state (whether app needs MPIN to unlock)
  Future<void> saveAppLocked(bool isLocked) async {
    await _prefs.setBool(_appLockedKey, isLocked);
  }

  /// Get app lock state
  bool isAppLocked() {
    return _prefs.getBool(_appLockedKey) ?? false; // Default to unlocked
  }

  /// Clear app lock state (unlock app)
  Future<void> clearAppLocked() async {
    await _prefs.remove(_appLockedKey);
  }

  /// Clear all user-related data for debugging/fresh start
  Future<void> clearAllUserData() async {
    await clearUserData();
    await clearAppLocked();
  }

  /// Save email verification code
  Future<void> saveVerificationCode(String userId, String code) async {
    await _storage.write(key: 'verification_code_$userId', value: code);
  }

  /// Get email verification code
  Future<String?> getVerificationCode(String userId) async {
    return await _storage.read(key: 'verification_code_$userId');
  }

  /// Clear email verification code
  Future<void> clearVerificationCode(String userId) async {
    await _storage.delete(key: 'verification_code_$userId');
  }

  // BUG 05 FIX: Write userId to BOTH SharedPreferences (fast) AND
  // FlutterSecureStorage (survives reinstall on same device via
  // EncryptedSharedPreferences on Android). Reinstall wipes SharedPreferences
  // but FlutterSecureStorage persists, so user is recognised and routed
  // to MPIN login instead of re-registration.

  /// Save current user ID to SharedPreferences ONLY.
  /// IMPORTANT: We intentionally do NOT write to FlutterSecureStorage here.
  /// FlutterSecureStorage on Android uses EncryptedSharedPreferences which
  /// is included in Google Account Backup and restored to other devices.
  /// If we stored the admin UID in FlutterSecureStorage, every user who
  /// installs the app on a phone tied to the same Google account would have
  /// the admin ID injected — loading the admin profile on their cold start.
  Future<void> saveCurrentUserId(String userId) async {
    await _prefs.setString('current_user_id', userId);
    // DO NOT write to _storage (FlutterSecureStorage) — cross-device contamination risk
  }

  /// Get current user ID from SharedPreferences only.
  Future<String?> getCurrentUserId() async {
    final prefsId = _prefs.getString('current_user_id') ?? '';
    if (prefsId.isNotEmpty) return prefsId;
    // No fallback to FlutterSecureStorage — see saveCurrentUserId comment above
    return null;
  }

  /// Clear user ID from SharedPreferences on logout.
  Future<void> clearCurrentUserId() async {
    await _prefs.remove('current_user_id');
  }
}
