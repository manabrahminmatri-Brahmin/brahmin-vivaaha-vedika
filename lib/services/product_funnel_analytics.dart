import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Product funnel events for OTP, profile, interests, premium, and chat.
abstract final class ProductFunnelAnalytics {
  ProductFunnelAnalytics._();

  static FirebaseAnalytics? get _analytics {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _log(
    String name, {
    Map<String, Object>? params,
  }) async {
    try {
      await _analytics?.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('ProductFunnelAnalytics.$name: $e');
    }
  }

  static void recordNonFatal(String reason, [Object? error, StackTrace? stack]) {
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.log(reason);
      if (error != null) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stack ?? StackTrace.current,
          reason: reason,
        );
      }
    } catch (_) {}
  }

  static Future<void> otpSuccess({String? method}) => _log(
        'otp_success',
        params: {if (method != null && method.isNotEmpty) 'method': method},
      );

  static Future<void> otpFailure({String? reason}) => _log(
        'otp_failure',
        params: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );

  static Future<void> profileWizardStep({
    required String step,
    int? percent,
  }) =>
      _log(
        'profile_wizard_step',
        params: {
          'step': step,
          if (percent != null) 'percent': percent,
        },
      );

  static Future<void> profileCompleted() => _log('profile_completed');

  static Future<void> photoUploadSuccess() => _log('photo_upload_success');

  static Future<void> photoUploadFailure({String? reason}) => _log(
        'photo_upload_failure',
        params: {if (reason != null) 'reason': reason},
      );

  static Future<void> interestSend({String? toUserId}) => _log(
        'interest_send',
        params: {if (toUserId != null && toUserId.isNotEmpty) 'to_user_id': toUserId},
      );

  static Future<void> interestAccept({String? interestId}) => _log(
        'interest_accept',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> interestReject({String? interestId}) => _log(
        'interest_reject',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> interestWithdraw({String? interestId}) => _log(
        'interest_withdraw',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> premiumPurchaseSuccess({String? planId}) => _log(
        'premium_purchase_success',
        params: {if (planId != null && planId.isNotEmpty) 'plan_id': planId},
      );

  static Future<void> premiumPurchaseFailure({String? reason}) => _log(
        'premium_purchase_failure',
        params: {if (reason != null) 'reason': reason},
      );

  static Future<void> premiumGateDenied({required String feature}) => _log(
        'premium_gate_denied',
        params: {'feature': feature},
      );

  static Future<void> chatCreate({String? peerUserId}) => _log(
        'chat_create',
        params: {
          if (peerUserId != null && peerUserId.isNotEmpty) 'peer_user_id': peerUserId,
        },
      );

  static Future<void> contactUnlock({String? interestId}) => _log(
        'contact_unlock',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> funnelDropOff({
    required String stage,
    String? reason,
  }) =>
      _log(
        'funnel_drop_off',
        params: {
          'stage': stage,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
}
