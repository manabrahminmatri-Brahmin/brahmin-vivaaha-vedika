import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'device_security_analytics.dart';
import 'security_audit_service.dart';

/// Root / jailbreak detection and sensitive-photo restriction policy.
abstract final class DeviceSecurityService {
  DeviceSecurityService._();

  static bool? _cachedCompromised;
  static bool _limitedModeAccepted = false;
  static bool _dialogShownThisSession = false;
  static bool _auditLoggedThisSession = false;

  /// Override platform check in tests.
  @visibleForTesting
  static Future<bool> Function()? platformCheckOverride;

  @visibleForTesting
  static void resetForTests() {
    _cachedCompromised = null;
    _limitedModeAccepted = false;
    _dialogShownThisSession = false;
    _auditLoggedThisSession = false;
    platformCheckOverride = null;
  }

  static void resetSessionFlags() {
    _dialogShownThisSession = false;
    _limitedModeAccepted = false;
    _cachedCompromised = null;
    _auditLoggedThisSession = false;
  }

  static bool get limitedModeAccepted => _limitedModeAccepted;

  /// True when sensitive member photos must be blocked or heavily blurred.
  static bool get shouldRestrictSensitivePhotos {
    if (_cachedCompromised != true) return false;
    return !_limitedModeAccepted;
  }

  /// Heavily blurred placeholder even in limited mode (still traceable via UI).
  static bool get useHeavyBlurOnSensitivePhotos {
    return _cachedCompromised == true;
  }

  static Future<bool> isCompromisedDevice({bool forceRefresh = false}) async {
    if (kIsWeb) {
      _cachedCompromised = false;
      return false;
    }
    if (!forceRefresh && _cachedCompromised != null) {
      return _cachedCompromised!;
    }
    if (platformCheckOverride != null) {
      _cachedCompromised = await platformCheckOverride!();
      return _cachedCompromised!;
    }
    // Jailbreak plugin temporarily disabled (see pubspec). Treat as not compromised.
    debugPrint(
      'DeviceSecurityService: jailbreak detection disabled (plugin removed for Android KGP migration).',
    );
    _cachedCompromised = false;
    return _cachedCompromised!;
  }

  static Future<void> recordCompromisedDetection({
    String? userId,
    String? profileId,
  }) async {
    if (_auditLoggedThisSession) return;
    _auditLoggedThisSession = true;
    await DeviceSecurityAnalytics.logCompromisedDeviceDetected(
      limitedMode: _limitedModeAccepted,
    );
    await SecurityAuditService.logDeviceSecurityRisk(
      userId: userId,
      profileId: profileId,
      limitedModeAccepted: _limitedModeAccepted,
    );
  }

  /// Shows warning once per app session when device is compromised.
  static Future<void> ensureCompromisedWarningAcknowledged(
    BuildContext context, {
    String? userId,
    String? profileId,
  }) async {
    final compromised = await isCompromisedDevice();
    if (!compromised || _dialogShownThisSession || !context.mounted) {
      return;
    }
    _dialogShownThisSession = true;
    await recordCompromisedDetection(
      userId: userId,
      profileId: profileId,
    );
    if (!context.mounted) return;

    final continueLimited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Security risk detected'),
        content: const Text(
          'Sensitive profile viewing is restricted on this device.\n\n'
          'You can continue with limited access (heavily restricted photos) '
          'or close and use a standard device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue Limited'),
          ),
        ],
      ),
    );

    if (continueLimited == true) {
      _limitedModeAccepted = true;
      await DeviceSecurityAnalytics.logCompromisedDeviceDetected(
        limitedMode: true,
      );
    }
  }
}
