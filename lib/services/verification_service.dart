import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/verification.dart';

/// Service to manage profile verifications (photo, phone, email, ID)
class VerificationService extends ChangeNotifier {
  final SharedPreferences _prefs;
  
  // Verification statuses
  final Map<VerificationType, ProfileVerification> _verifications = {};
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose
  
  VerificationService(this._prefs) {
    _loadVerifications();
  }

  /// 🔥 FIX: Safe notify that checks disposed state
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
  
  /// Load verifications from storage
  void _loadVerifications() {
    // In a real app, this would load from a database
    // For now, we'll use SharedPreferences
    final userId = _prefs.getString('current_user_id');
    if (userId == null) return;
    
    // Load each verification type
    for (final type in VerificationType.values) {
      final key = 'verification_${userId}_${type.name}';
      final statusStr = _prefs.getString(key);
      if (statusStr != null) {
        final status = VerificationStatus.values.firstWhere(
          (e) => e.name == statusStr,
          orElse: () => VerificationStatus.pending,
        );
        _verifications[type] = ProfileVerification(
          userId: userId,
          type: type,
          status: status,
        );
      }
    }
    
    _safeNotify();
  }
  
  /// Get verification status for a type
  VerificationStatus? getVerificationStatus(VerificationType type) {
    return _verifications[type]?.status;
  }
  
  /// Check if profile is verified (has at least one verification)
  bool get isVerified {
    return _verifications.values.any((v) => v.status == VerificationStatus.verified);
  }
  
  /// Get verification badge count (number of verified items)
  int get verificationBadgeCount {
    return _verifications.values
        .where((v) => v.status == VerificationStatus.verified)
        .length;
  }
  
  /// Check if phone is verified
  bool get isPhoneVerified {
    return _verifications[VerificationType.phone]?.status == VerificationStatus.verified;
  }
  
  /// Check if email is verified
  bool get isEmailVerified {
    return _verifications[VerificationType.email]?.status == VerificationStatus.verified;
  }
  
  /// Check if ID is verified
  bool get isIdVerified {
    return _verifications[VerificationType.id]?.status == VerificationStatus.verified;
  }
  
  /// Submit verification request
  Future<bool> submitVerification({
    required VerificationType type,
    String? documentUrl,
  }) async {
    final userId = _prefs.getString('current_user_id');
    if (userId == null) return false;
    
    final verification = ProfileVerification(
      userId: userId,
      type: type,
      status: VerificationStatus.pending,
      documentUrl: documentUrl,
    );
    
    _verifications[type] = verification;
    
    // Save to storage
    final key = 'verification_${userId}_${type.name}';
    await _prefs.setString(key, VerificationStatus.pending.name);
    
    _safeNotify();
    
    // In a real app, this would send to backend for verification
    // For demo, we'll auto-verify after a delay
    if (kDebugMode) {
      Future.delayed(const Duration(seconds: 2), () {
        _autoVerify(type);
      });
    }
    
    return true;
  }
  
  /// Auto-verify for demo purposes
  void _autoVerify(VerificationType type) {
    final userId = _prefs.getString('current_user_id');
    if (userId == null) return;
    
    final verification = _verifications[type];
    if (verification != null) {
      _verifications[type] = ProfileVerification(
        id: verification.id,
        userId: verification.userId,
        type: verification.type,
        status: VerificationStatus.verified,
        submittedAt: verification.submittedAt,
        verifiedAt: DateTime.now(),
        verifiedBy: 'System',
        documentUrl: verification.documentUrl,
      );
      
      final key = 'verification_${userId}_${type.name}';
      _prefs.setString(key, VerificationStatus.verified.name);
      
      _safeNotify();
    }
  }
  
  /// Get all verifications
  Map<VerificationType, ProfileVerification> get verifications => Map.unmodifiable(_verifications);
}
