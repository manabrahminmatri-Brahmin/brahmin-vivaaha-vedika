import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/interest_hub_cache.dart';
import 'package:brahmin_vivaaha_vedika/core/interest_badge_aggregator.dart';

void main() {
  group('InterestHubCache', () {
    late InterestHubCache cache;

    setUp(() {
      cache = InterestHubCache();
    });

    Map<String, dynamic> sentRow({
      String id = 'userA_userB',
      String status = 'pending',
    }) =>
        {
          'id': id,
          'interestId': id,
          'from_user_id': 'userA',
          'to_user_id': 'userB',
          'status': status,
        };

    test('withdraw hides row instantly via optimistic overlay', () {
      cache.applySentSnapshot([sentRow()]);
      expect(cache.visibleSent.length, 1);

      cache.optimisticHide('userA_userB', rowHint: sentRow());
      expect(cache.visibleSent, isEmpty);
      expect(cache.sent, isEmpty);
      expect(cache.revision, greaterThan(0));
    });

    test('failed withdraw restores row', () {
      cache.applySentSnapshot([sentRow()]);
      cache.optimisticHide('userA_userB', rowHint: sentRow());
      expect(cache.visibleSent, isEmpty);

      cache.restoreHide('userA_userB', rowHint: sentRow());
      expect(cache.visibleSent.length, 1);
    });

    test('send upsert adds row immediately', () {
      cache.upsertSentLocal(
        interestId: 'sender_receiver',
        fromUserId: 'sender',
        toUserId: 'receiver',
      );
      expect(cache.visibleSent.length, 1);
      expect(
        InterestBadgeAggregator.interestDocumentId(cache.visibleSent.first),
        'sender_receiver',
      );
    });

    test('empty snapshot preserves pending local send until Firestore catches up',
        () {
      cache.upsertSentLocal(
        interestId: 'sender_receiver',
        fromUserId: 'sender',
        toUserId: 'receiver',
      );
      cache.applySentSnapshot(const []);
      expect(cache.visibleSent.length, 1);
      expect(cache.visibleSent.first['_pendingFirestoreSync'], isTrue);
    });

    test('prune clears hide after server removes row', () {
      cache.applySentSnapshot([sentRow()]);
      cache.optimisticHide('userA_userB', rowHint: sentRow());
      cache.applySentSnapshot(const []);
      cache.pruneOptimisticHidden();
      expect(cache.visibleSent, isEmpty);
    });

    test('prune clears hide when status becomes withdrawn', () {
      cache.applySentSnapshot([sentRow()]);
      cache.optimisticHide('userA_userB', rowHint: sentRow());
      cache.applySentSnapshot([sentRow(status: 'withdrawn')]);
      cache.pruneOptimisticHidden();
      expect(cache.visibleSent, isEmpty);
    });

    test('dedupe keeps newest snapshot on apply', () {
      cache.applySentSnapshot([
        {
          ...sentRow(),
          'updated_at': '2020-01-01T00:00:00.000Z',
          'status': 'pending',
        },
        {
          ...sentRow(),
          'updated_at': '2024-01-01T00:00:00.000Z',
          'status': 'accepted',
        },
      ]);
      expect(cache.visibleSent.length, 1);
      expect(cache.visibleSent.first['status'], 'accepted');
    });

    test('optimistic hide matches composite id when withdraw uses alias', () {
      cache.applySentSnapshot([
        {
          'id': 'doc123',
          'from_user_id': 'userA',
          'to_user_id': 'userB',
          'status': 'pending',
        },
      ]);
      cache.optimisticHide('userA_userB');
      expect(cache.visibleSent, isEmpty);
    });

    test('hub visible excludes withdrawn without optimistic hide', () {
      cache.applySentSnapshot([
        sentRow(status: 'withdrawn'),
        sentRow(id: 'x_y', status: 'pending'),
      ]);
      expect(cache.visibleSent.length, 1);
      expect(
        InterestBadgeAggregator.interestDocumentId(cache.visibleSent.first),
        'x_y',
      );
    });
  });
}
