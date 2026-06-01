import 'package:brahmin_vivaaha_vedika/models/membership.dart';
import 'package:brahmin_vivaaha_vedika/models/user.dart';
import 'package:brahmin_vivaaha_vedika/services/block_service.dart';
import 'package:brahmin_vivaaha_vedika/services/interests_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InterestsAccessPolicy', () {
    late BlockService blocks;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      blocks = BlockService(prefs);
      await blocks.seedForTests(blockerDocId: 'me', users: const []);
      BlockService.liveQueryOverride = ({required actorUserDocId, required peerUserDocId}) async => false;
    });

    tearDown(() {
      BlockService.liveQueryOverride = null;
    });

    test('blocks chat when interest not accepted', () async {
      final reason = await InterestsAccessPolicy.chatBlockReason(
        me: _user(premium: true),
        peerUserId: 'peer1',
        interestStatus: 'pending',
        blockService: blocks,
      );
      expect(reason, contains('accepted'));
    });

    test('blocks chat for non-premium member', () async {
      final reason = await InterestsAccessPolicy.chatBlockReason(
        me: _user(premium: false),
        peerUserId: 'peer1',
        interestStatus: 'accepted',
        blockService: blocks,
      );
      expect(reason, contains('Premium'));
    });

    test('blocked user cannot message (live verification)', () async {
      BlockService.liveQueryOverride = ({required actorUserDocId, required peerUserDocId}) async => true;

      final reason = await InterestsAccessPolicy.chatBlockReason(
        me: _user(premium: true),
        peerUserId: 'peer1',
        peerProfileId: 'BVV-M-99999',
        interestStatus: 'accepted',
        blockService: blocks,
      );
      expect(reason, contains('blocked'));
    });

    test('allows chat when accepted premium and live says not blocked', () async {
      final reason = await InterestsAccessPolicy.chatBlockReason(
        me: _user(premium: true),
        peerUserId: 'peer1',
        interestStatus: 'accepted',
        blockService: blocks,
      );
      expect(reason, isNull);
    });

    test('unblock restores chat eligibility when live clears', () async {
      BlockService.liveQueryOverride = ({required actorUserDocId, required peerUserDocId}) async => true;
      expect(
        await InterestsAccessPolicy.chatBlockReason(
          me: _user(premium: true),
          peerUserId: 'peer1',
          interestStatus: 'accepted',
          blockService: blocks,
        ),
        isNotNull,
      );

      BlockService.liveQueryOverride = ({required actorUserDocId, required peerUserDocId}) async => false;
      expect(
        await InterestsAccessPolicy.chatBlockReason(
          me: _user(premium: true),
          peerUserId: 'peer1',
          interestStatus: 'accepted',
          blockService: blocks,
        ),
        isNull,
      );
    });
  });
}

User _user({required bool premium}) {
  return User(
    id: 'me',
    profileId: 'BVV-M-00001',
    email: 'a@b.com',
    password: 'x',
    mobileNumber: '9999999999',
    membership: Membership(
      tier: premium ? MembershipTier.platinum : MembershipTier.free,
      expiryDate: premium
          ? DateTime.now().add(const Duration(days: 30))
          : null,
    ),
  );
}
