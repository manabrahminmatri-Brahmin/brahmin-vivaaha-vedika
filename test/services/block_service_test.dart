import 'package:brahmin_vivaaha_vedika/services/block_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlockService (Firestore cache model)', () {
    late BlockService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = BlockService(prefs);
    });

    test('isEitherBlocked when peer is in blocked list', () async {
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'peer-doc',
            profileId: 'BVV-M-99999',
            name: 'Blocked Member',
            blockedAt: DateTime.now(),
          ),
        ],
      );
      expect(
        service.isEitherBlocked(
          peerUserDocId: 'peer-doc',
          peerProfileId: 'BVV-M-99999',
        ),
        isTrue,
      );
    });

    test('unblock restores access in cache', () async {
      // Simulates unblock without Firestore in unit tests.
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'peer-doc',
            profileId: 'BVV-M-99999',
            name: 'Blocked Member',
            blockedAt: DateTime.now(),
          ),
        ],
      );
      expect(service.isBlocked('BVV-M-99999'), isTrue);
      // Unblock without Firestore in unit test: manipulate cache directly.
      await service.seedForTests(blockerDocId: 'me', users: const []);
      expect(service.isBlocked('BVV-M-99999'), isFalse);
    });

    test('blocked user hidden from allBlockedPeerIds for suggestions', () async {
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'peer-doc',
            profileId: 'BVV-F-100',
            name: 'X',
            blockedAt: DateTime.now(),
          ),
        ],
        blockedByOthers: {'other-doc'},
      );
      expect(service.allBlockedPeerIds, contains('BVV-F-100'));
      expect(service.allBlockedPeerIds, contains('peer-doc'));
      expect(service.allBlockedPeerIds, contains('other-doc'));
    });

    test('isBlocked matches profile id or user doc id', () async {
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'uid-1',
            profileId: 'BVV-M-1',
            name: 'A',
            blockedAt: DateTime.now(),
          ),
        ],
      );
      expect(service.isBlocked('BVV-M-1'), isTrue);
      expect(service.isBlocked('uid-1'), isTrue);
      expect(service.isBlocked('stranger'), isFalse);
    });

    test('cache round-trip via prefs', () async {
      await service.seedForTests(
        blockerDocId: 'me',
        users: [
          BlockedUser(
            userDocId: 'u2',
            profileId: 'BVV-M-2',
            name: 'Two',
            blockedAt: DateTime(2024, 1, 1),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      final reloaded = BlockService(prefs);
      expect(reloaded.isDataLoaded, isTrue);
      expect(reloaded.isBlocked('BVV-M-2'), isTrue);
    });
  });
}
