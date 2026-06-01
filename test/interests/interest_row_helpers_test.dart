import 'package:brahmin_vivaaha_vedika/core/interest_identity_resolver.dart';
import 'package:brahmin_vivaaha_vedika/screens/interests/interest_row_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InterestRowHelpers received row', () {
    final receivedRow = {
      'id': 'peer_me',
      'from_user_id': 'peer',
      'from_first_name': 'Anita',
      'from_last_name': 'Iyer',
      'from_profile_id': 'BVV-F-55555',
      'from_city': 'Hyderabad',
      'from_state': 'Telangana',
      'from_age': 26,
    };

    test('peerName from snapshot', () {
      expect(
        InterestRowHelpers.peerName(receivedRow, isReceived: true),
        'Anita Iyer',
      );
    });

    test('peerLocation from snapshot without live user', () {
      expect(
        InterestRowHelpers.peerLocation(receivedRow, null, isReceived: true),
        'Hyderabad, Telangana',
      );
    });

    test('hasSnapshotIdentity true', () {
      expect(
        InterestRowHelpers.hasSnapshotIdentity(receivedRow, isReceived: true),
        isTrue,
      );
    });

    test('incomingRequesterLabel for photo row', () {
      expect(
        InterestRowHelpers.incomingRequesterLabel({
          'requester_first_name': 'Vikram',
          'requester_last_name': 'N',
        }),
        'Vikram N',
      );
    });
  });

  group('InterestRowHelpers sent row', () {
    test('empty row resolves to unknown via resolver', () {
      expect(
        InterestIdentityResolver.peerDisplayName(const {}, isReceived: false),
        InterestIdentityResolver.unknownMember,
      );
    });

    test('peerAge uses snapshot when no user', () {
      expect(
        InterestRowHelpers.peerAge(
          {'to_age': 31},
          null,
          isReceived: false,
        ),
        31,
      );
    });
  });
}
