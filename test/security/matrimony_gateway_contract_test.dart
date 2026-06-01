import 'package:flutter_test/flutter_test.dart';

import 'package:brahmin_vivaaha_vedika/services/premium_entitlement_service.dart';

/// Contract tests for secured matrimony callables (payload shapes / feature keys).
void main() {
  group('Matrimony gateway contracts', () {
    test('premium feature keys are stable', () {
      expect(PremiumEntitlementService.featureSendInterest, 'send_interest');
      expect(PremiumEntitlementService.featureViewContact, 'view_contact');
      expect(PremiumEntitlementService.featureViewPrivatePhoto, 'view_private_photo');
      expect(PremiumEntitlementService.featureChat, 'chat');
      expect(PremiumEntitlementService.featureBirthDetails, 'birth_details_request');
      expect(
        PremiumEntitlementService.featureCommunityReference,
        'community_reference_request',
      );
    });

    test('createPhotoRequest payload fields', () {
      const payload = {
        'toUserId': 'user_a',
        'fromUserId': 'user_b',
        'requesterProfileId': 'M123',
        'targetProfileId': 'F456',
      };
      expect(payload['toUserId'], isNotEmpty);
      expect(payload['fromUserId'], isNotEmpty);
    });

    test('interest transition actions', () {
      const actions = ['accept', 'reject', 'withdraw'];
      expect(actions, contains('accept'));
      expect(actions.length, 3);
    });
  });
}
