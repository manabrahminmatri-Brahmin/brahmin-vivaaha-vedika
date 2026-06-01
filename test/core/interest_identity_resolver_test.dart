import 'package:brahmin_vivaaha_vedika/core/interest_identity_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InterestIdentityResolver', () {
    test('normalizeInterestRow fills from/to from composite doc id', () {
      final row = InterestIdentityResolver.normalizeInterestRow({
        'id': 'userA_userB',
      });
      expect(row['from_user_id'], 'userA');
      expect(row['to_user_id'], 'userB');
    });

    test('peerDisplayName uses snapshot when live name empty', () {
      final name = InterestIdentityResolver.peerDisplayName(
        {
          'to_first_name': 'Ravi',
          'to_last_name': 'Sharma',
          'to_profile_id': 'BVV-M-12345',
        },
        isReceived: false,
      );
      expect(name, 'Ravi Sharma');
    });

    test('peerDisplayName falls back to unknown member', () {
      final name = InterestIdentityResolver.peerDisplayName(
        const {},
        isReceived: true,
      );
      expect(name, InterestIdentityResolver.unknownMember);
    });

    test('accessOwnerUserId parses legacy doc id suffix', () {
      final owner = InterestIdentityResolver.accessOwnerUserId({
        'id': 'fromUid_toUid',
      });
      expect(owner, 'toUid');
    });

    test('snapshotPhotoUrl rejects non-http values', () {
      expect(
        InterestIdentityResolver.snapshotPhotoUrl(
          {'from_photo_url': 'not-a-url'},
          isReceived: true,
        ),
        isNull,
      );
    });
  });
}
