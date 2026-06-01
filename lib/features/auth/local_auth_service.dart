import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

/// Local Authentication Service
/// 
/// Consolidates MPIN and biometric authentication logic from:
/// - mpin_service.dart
/// - biometric_auth_service.dart
class LocalAuthService {
  static final LocalAuthService _instance = LocalAuthService._internal();
  factory LocalAuthService() => _instance;
  LocalAuthService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  static const String _mpinKey = 'user_mpin';
  static const String _biometricEnabledKey = 'biometric_enabled';

  bool _isInitialized = false;

  /// Initialize local authentication
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
    } catch (e) {
      debugPrint('LocalAuthService initialization failed: $e');
      rethrow;
    }
  }

  /// Verify MPIN
  Future<bool> verifyMpin(String mpin) async {
    try {
      await _ensureInitialized();
      
      final storedHash = await _secureStorage.read(key: _mpinKey);
      if (storedHash == null || storedHash.isEmpty) {
        return false;
      }

      final inputHash = _hashMpin(mpin);
      return storedHash == inputHash;
    } catch (e) {
      debugPrint('MPIN verification failed: $e');
      return false;
    }
  }

  /// Get stored MPIN hash
  Future<String?> getMpinHash() async {
    // Return stored MPIN hash
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mpin_hash');
  }

  /// Check if biometrics are available
  Future<bool> canCheckBiometrics() async {
    final auth = LocalAuthentication();
    return await auth.canCheckBiometrics;
  }

  /// Save MPIN
  Future<void> saveMpin(String hashedMpin) async {
    try {
      await _ensureInitialized();
      await _secureStorage.write(key: _mpinKey, value: hashedMpin);
    } catch (e) {
      debugPrint('Failed to save MPIN: $e');
      rethrow;
    }
  }

  /// Check if MPIN is set
  Future<bool> isMpinSet() async {
    try {
      await _ensureInitialized();
      final stored = await _secureStorage.read(key: _mpinKey);
      return stored != null && stored.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check MPIN status: $e');
      return false;
    }
  }

  /// Authenticate with biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      if (kIsWeb) return false;
      await _ensureInitialized();
      
      final isBiometricEnabled = _prefs?.getBool(_biometricEnabledKey) ?? false;
      if (!isBiometricEnabled) {
        return false;
      }

      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        return false;
      }

      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) {
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your account',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return didAuthenticate;
    } catch (e) {
      debugPrint('Biometric authentication failed: $e');
      return false;
    }
  }

  /// Setup biometric authentication
  Future<bool> setupBiometrics() async {
    try {
      if (kIsWeb) return false;
      await _ensureInitialized();
      
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        return false;
      }

      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) {
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Enable biometric authentication for quick access',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
        ),
      );

      if (didAuthenticate) {
        await _prefs?.setBool(_biometricEnabledKey, true);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Failed to setup biometrics: $e');
      return false;
    }
  }

  /// Disable biometric authentication
  Future<void> disableBiometrics() async {
    try {
      await _ensureInitialized();
      await _prefs?.setBool(_biometricEnabledKey, false);
    } catch (e) {
      debugPrint('Failed to disable biometrics: $e');
    }
  }

  /// Check if biometrics is enabled
  Future<bool> isBiometricsEnabled() async {
    try {
      await _ensureInitialized();
      return _prefs?.getBool(_biometricEnabledKey) ?? false;
    } catch (e) {
      debugPrint('Failed to check biometrics status: $e');
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      await _ensureInitialized();
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Failed to get available biometrics: $e');
      return [];
    }
  }

  /// Clear all authentication data
  Future<void> clearAuthData() async {
    try {
      await _ensureInitialized();
      await _secureStorage.delete(key: _mpinKey);
      await _prefs?.remove(_biometricEnabledKey);
    } catch (e) {
      debugPrint('Failed to clear auth data: $e');
    }
  }

  /// Check if device can use biometrics (matches BiometricAuthService interface)
  Future<bool> canUseBiometrics() async {
    try {
      if (kIsWeb) return false;
      await _ensureInitialized();
      
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = await _localAuth.getAvailableBiometrics();
      
      if (canCheck && enrolled.isNotEmpty) return true;
      return supported;
    } on PlatformException catch (e) {
      debugPrint('[Biometric] canUseBiometrics: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Biometric] canUseBiometrics: $e');
      return false;
    }
  }

  /// Authenticate with biometrics (matches BiometricAuthService interface)
  Future<bool> authenticate({
    String reason = 'Verify your identity to continue',
  }) async {
    try {
      if (kIsWeb) return false;
      await _ensureInitialized();
      
      if (!await _localAuth.isDeviceSupported()) {
        debugPrint('[Biometric] authenticate: device not supported');
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint(
        '[Biometric] PlatformException code=${e.code} details=${e.details} message=${e.message}',
      );
      return false;
    } catch (e, st) {
      debugPrint('[Biometric] authenticate error=$e\n$st');
      return false;
    }
  }

  /// Check if biometrics is enabled for specific user
  Future<bool> isEnabledForUser(String userId) async {
    try {
      await _ensureInitialized();
      return _prefs?.getBool('biometric_enabled_$userId') ?? false;
    } catch (e) {
      debugPrint('Failed to check biometrics enabled for user: $e');
      return false;
    }
  }

  /// Enable/disable biometrics for specific user
  Future<void> setEnabledForUser(String userId, bool enabled) async {
    try {
      await _ensureInitialized();
      await _prefs?.setBool('biometric_enabled_$userId', enabled);
      
      if (enabled) {
        await _prefs?.setString('biometric_last_enabled_user_id', userId);
      } else {
        final lastUserId = _prefs?.getString('biometric_last_enabled_user_id') ?? '';
        if (lastUserId == userId) {
          await _prefs?.remove('biometric_last_enabled_user_id');
        }
      }
    } catch (e) {
      debugPrint('Failed to set biometrics enabled for user: $e');
    }
  }

  /// Get last user ID that enabled biometrics
  Future<String?> getLastEnabledUserId() async {
    try {
      await _ensureInitialized();
      final userId = _prefs?.getString('biometric_last_enabled_user_id') ?? '';
      return userId.isEmpty ? null : userId;
    } catch (e) {
      debugPrint('Failed to get last enabled user ID: $e');
      return null;
    }
  }

  /// Hash MPIN using SHA256
  String _hashMpin(String mpin) {
    // This should match the hashing in auth_controller.dart
    const String salt = 'mana_matrimony_mpin_salt';
    final bytes = utf8.encode('$salt$mpin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}
