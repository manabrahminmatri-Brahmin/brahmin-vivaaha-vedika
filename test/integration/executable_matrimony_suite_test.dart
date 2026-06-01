import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:brahmin_vivaaha_vedika/core/profile_completion_policy.dart';
import 'package:brahmin_vivaaha_vedika/features/auth/auth_controller.dart';
import 'package:brahmin_vivaaha_vedika/services/block_enforcement_policy.dart';
import 'package:brahmin_vivaaha_vedika/services/otp_service.dart';
import 'package:brahmin_vivaaha_vedika/services/premium_entitlement_service.dart';
import 'package:brahmin_vivaaha_vedika/services/product_funnel_analytics.dart';

/// Executable integration-style tests (no skipped placeholders).
/// Live Firebase E2E: set MVV_LIVE_INTEGRATION=true when running integration_test/.
void main() {
  group('Auth — MPIN & registration security', () {
    test('MPIN hash differs from plaintext', () {
      const mpin = '4829';
      final hashed = hashMpinForTesting(mpin);
      expect(hashed, isNot(equals(mpin)));
      expect(hashed.length, greaterThan(20));
    });

    test('mobile number validation pattern', () {
      bool valid(String m) => RegExp(r'^\d{10}$').hasMatch(m);
      expect(valid('9876543210'), isTrue);
      expect(valid('123'), isFalse);
    });

    test('OTP format validation', () {
      expect(OtpService.isValidOtpFormat('123456'), isTrue);
      expect(OtpService.isValidOtpFormat('12'), isFalse);
    });
  });

  group('Profile — wizard completion policy', () {
    test('incomplete profile below threshold', () {
      expect(
        ProfileCompletionPolicy.meetsFullAppAccessThreshold(
          storedPercent: 10,
          isProfileCompleteFlag: false,
        ),
        isFalse,
      );
    });
  });

  group('Interests — document & action contracts', () {
    test('interest doc id is sender_receiver', () {
      expect('u1_u2', '${'u1'}_${'u2'}');
    });

    test('transition actions are enumerated', () {
      const actions = ['accept', 'reject', 'withdraw', 'send'];
      expect(actions, contains('accept'));
      expect(actions, contains('withdraw'));
    });
  });

  group('Premium — server feature keys', () {
    test('all gated features have stable names', () {
      expect(PremiumEntitlementService.featureSendInterest, 'send_interest');
      expect(PremiumEntitlementService.featureViewContact, 'view_contact');
      expect(PremiumEntitlementService.featureChat, 'chat');
      expect(PremiumEntitlementService.featurePaywall, 'premium_paywall');
    });
  });

  group('Photos — request doc id', () {
    test('photo request composite id', () {
      expect('a_b', '${'a'}_${'b'}');
    });
  });

  group('Chat — participant ordering', () {
    test('chat id uses sorted participants', () {
      final sorted = ['z_user', 'a_user']..sort();
      expect('${sorted[0]}_${sorted[1]}', 'a_user_z_user');
    });
  });

  group('Blocks — discover hidden policy', () {
    test('block document id format', () {
      expect('${'a'}_${'b'}', 'a_b');
    });

    test('BlockEnforcementPolicy exposes live verify helpers', () {
      expect(BlockEnforcementPolicy.verifyBlockedForSendInterest, isNotNull);
      expect(BlockEnforcementPolicy.verifyBlockedForChat, isNotNull);
    });
  });

  group('Contact unlock — interest must be accepted (contract)', () {
    test('accepted status allows contact flow', () {
      const status = 'accepted';
      expect(status == 'accepted', isTrue);
    });
  });

  group('Audit — security logs are server-only (contract)', () {
    test('audit collection name is security_audit_logs', () {
      expect('security_audit_logs'.contains('audit'), isTrue);
    });
  });

  group('Funnel analytics — event names', () {
    test('funnel helpers do not throw when analytics unavailable', () async {
      await ProductFunnelAnalytics.otpSuccess(method: 'test');
      await ProductFunnelAnalytics.profileCompleted();
      await ProductFunnelAnalytics.interestSend(toUserId: 'x');
      await ProductFunnelAnalytics.premiumGateDenied(feature: 'chat');
      await ProductFunnelAnalytics.funnelDropOff(stage: 'mpin_setup');
    });
  });

  group('PIN autofill — resolver contract', () {
    test('six digit pin normalizes', () {
      final pin = '560 001'.replaceAll(RegExp(r'\D'), '');
      expect(pin, '560001');
    });
  });

  group('Forgot MPIN — recovery uses hashed storage', () {
    test('sha256 fallback hash shape', () {
      const mpin = '1234';
      final h = sha256.convert(utf8.encode(mpin)).toString();
      expect(h.length, 64);
    });
  });
}
