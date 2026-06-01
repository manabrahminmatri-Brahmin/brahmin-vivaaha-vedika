import 'package:brahmin_vivaaha_vedika/services/block_enforcement_policy.dart';
import 'package:brahmin_vivaaha_vedika/services/block_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live block verification', () {
    late BlockService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = BlockService(prefs);
      await service.seedForTests(blockerDocId: 'me', users: const []);
      BlockService.liveQueryOverride = null;
    });

    tearDown(() {
      BlockService.liveQueryOverride = null;
    });

    test('cache empty but live query blocks send interest', () async {
      expect(service.isEitherBlocked(peerUserDocId: 'peer'), isFalse);

      BlockService.liveQueryOverride = ({
        required String actorUserDocId,
        required String peerUserDocId,
      }) async =>
          actorUserDocId == 'me' && peerUserDocId == 'peer';

      final blocked = await BlockEnforcementPolicy.verifyBlockedForSendInterest(
        actorUserDocId: 'me',
        peerUserDocId: 'peer',
      );
      expect(blocked, isTrue);
    });

    test('live query allows when no block on server', () async {
      BlockService.liveQueryOverride = ({
        required String actorUserDocId,
        required String peerUserDocId,
      }) async =>
          false;

      expect(
        await BlockEnforcementPolicy.verifyBlockedForPhotoRequest(
          actorUserDocId: 'me',
          peerUserDocId: 'peer',
        ),
        isFalse,
      );
    });

    test('isHiddenFromDiscovery uses cache only', () async {
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'peer',
            profileId: 'BVV-M-9',
            name: 'P',
            blockedAt: DateTime.now(),
          ),
        ],
      );

      BlockService.liveQueryOverride = ({
        required String actorUserDocId,
        required String peerUserDocId,
      }) async =>
          false;

      expect(
        BlockEnforcementPolicy.isHiddenFromDiscovery(
          blocks: service,
          peerUserDocId: 'peer',
        ),
        isTrue,
      );
      expect(
        await BlockService.verifyEitherBlockedLive(
          actorUserDocId: 'me',
          peerUserDocId: 'peer',
        ),
        isFalse,
      );
    });
  });
}
