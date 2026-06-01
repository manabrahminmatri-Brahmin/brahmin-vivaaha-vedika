import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Security-related audit events (device risk, misuse tracing).
abstract final class SecurityAuditService {
  SecurityAuditService._();

  static const String _collection = 'security_audit_logs';
  static const String eventDeviceSecurityRisk = 'device_security_risk';

  static Future<void> logDeviceSecurityRisk({
    String? userId,
    String? profileId,
    bool limitedModeAccepted = false,
  }) async {
    final payload = <String, dynamic>{
      'event': eventDeviceSecurityRisk,
      'user_id': userId ?? '',
      'profile_id': profileId ?? '',
      'limited_mode': limitedModeAccepted,
      'created_at': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    };
    try {
      await FirebaseFirestore.instance.collection(_collection).add(payload);
    } catch (e) {
      debugPrint('SecurityAuditService.logDeviceSecurityRisk: $e');
    }
  }
}
