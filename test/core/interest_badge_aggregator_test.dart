import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/interest_badge_aggregator.dart';

void main() {
  group('InterestBadgeAggregator', () {
    test('normalizeInterestStatus handles legacy and empty', () {
      expect(InterestBadgeAggregator.normalizeInterestStatus(null), 'pending');
      expect(InterestBadgeAggregator.normalizeInterestStatus(''), 'pending');
      expect(InterestBadgeAggregator.normalizeInterestStatus('  SENT '), 'pending');
      expect(InterestBadgeAggregator.normalizeInterestStatus('Approved'), 'accepted');
      expect(InterestBadgeAggregator.normalizeInterestStatus('GRANTED'), 'accepted');
      expect(InterestBadgeAggregator.normalizeInterestStatus('denied'), 'rejected');
      expect(InterestBadgeAggregator.normalizeInterestStatus('Declined'), 'rejected');
      expect(InterestBadgeAggregator.normalizeInterestStatus('  accepted '), 'accepted');
      expect(InterestBadgeAggregator.normalizeInterestStatus('weird'), 'weird');
    });

    test('viewedByRecipientIsTruthy accepts common truthy variants', () {
      bool v(Map<String, dynamic> row) =>
          InterestBadgeAggregator.viewedByRecipientIsTruthy(row);

      expect(v({'viewed_by_recipient': true}), isTrue);
      expect(v({'viewed_by_recipient': 'true'}), isTrue);
      expect(v({'viewed_by_recipient': '1'}), isTrue);
      expect(v({'viewed_by_recipient': 1}), isTrue);
      expect(v({'viewed_by_recipient': 'YES'}), isTrue);
      expect(v({'viewedByRecipient': 'true'}), isTrue);
      expect(v({'viewed_by_recipient': false}), isFalse);
      expect(v({'viewed_by_recipient': '0'}), isFalse);
      expect(v(<String, dynamic>{}), isFalse);
    });

    test('receivedInterestUnviewed counts accepted rows until opened', () {
      final received = [
        {'id': '1', 'status': 'pending', 'viewed_by_recipient': false},
        {'id': '2', 'status': 'accepted', 'viewed_by_recipient': false},
        {'id': '3', 'status': 'accepted', 'viewed_by_recipient': true},
      ];
      expect(InterestBadgeAggregator.receivedInterestUnviewed(received), 2);
    });

    test('interestRowClearsReceivedNotification when viewed or responded', () {
      bool clears(Map<String, dynamic> row) =>
          InterestBadgeAggregator.interestRowClearsReceivedNotification(row);

      expect(
        clears({'status': 'pending', 'viewed_by_recipient': false}),
        isFalse,
      );
      expect(
        clears({'status': 'pending', 'viewed_by_recipient': true}),
        isTrue,
      );
      expect(clears({'status': 'accepted'}), isTrue);
      expect(clears({'status': 'rejected'}), isTrue);
      expect(clears({'status': 'withdrawn'}), isTrue);
    });

    test('hidden rows excluded from pending and visible totals', () {
      final received = [
        {'id': '1', 'status': 'pending', 'viewed_by_recipient': false},
        {'id': '2', 'status': 'withdrawn', 'viewed_by_recipient': false},
        {'id': '3', 'status': 'inactive'},
        {'id': '4', 'status': 'deleted'},
      ];
      expect(InterestBadgeAggregator.pendingReceivedUnviewed(received), 1);
      expect(InterestBadgeAggregator.visibleReceivedTotal(received), 1);
    });

    test('interestDocumentId reads interest_id alias', () {
      expect(
        InterestBadgeAggregator.interestDocumentId({
          'interest_id': 'userA_userB',
          'from_user_id': 'userA',
          'to_user_id': 'userB',
        }),
        'userA_userB',
      );
    });

    test('interestRowMatchesDocId resolves composite and explicit ids', () {
      final row = {
        'id': 'docExplicit',
        'from_user_id': 'userA',
        'to_user_id': 'userB',
      };
      expect(
        InterestBadgeAggregator.interestRowMatchesDocId(row, 'docExplicit'),
        isTrue,
      );
      expect(
        InterestBadgeAggregator.interestRowMatchesDocId(row, 'userA_userB'),
        isTrue,
      );
      expect(
        InterestBadgeAggregator.interestRowMatchesDocId(row, 'other'),
        isFalse,
      );
    });

    test('sentHubBadgeCount matches hubVisibleInterestRows length for unviewed', () {
      final sent = [
        {'id': '1', 'status': 'pending', 'viewed_by_sender': false},
        {'id': '2', 'status': 'withdrawn', 'viewed_by_sender': false},
        {'id': '3', 'status': 'accepted', 'viewed_by_sender': false},
      ];
      final visible = InterestBadgeAggregator.hubVisibleInterestRows(sent);
      expect(visible.length, 2);
      expect(
        InterestBadgeAggregator.sentHubBadgeCount(
          interestsSent: visible,
          outgoingPrivacyRequests: const [],
        ),
        InterestBadgeAggregator.sentInterestUnviewed(visible),
      );
    });

    test('dedupeInterestRows keeps newest by updated_at', () {
      final t0 = Timestamp.fromDate(DateTime(2020));
      final t1 = Timestamp.fromDate(DateTime(2021));
      final rows = [
        {
          'id': 'a_b',
          'status': 'pending',
          'viewed_by_recipient': false,
          'updated_at': t0,
        },
        {
          'id': 'a_b',
          'status': 'pending',
          'viewed_by_recipient': true,
          'updated_at': t1,
        },
      ];
      final deduped = InterestBadgeAggregator.dedupeInterestRows(rows);
      expect(deduped.length, 1);
      expect(
        InterestBadgeAggregator.viewedByRecipientIsTruthy(deduped.single),
        isTrue,
      );
      expect(InterestBadgeAggregator.pendingReceivedUnviewed(rows), 0);
    });

    test('pendingIncomingRequestDocCount unions unique doc ids', () {
      expect(
        InterestBadgeAggregator.pendingIncomingRequestDocCount(
          birthOwnerIds: const ['a', 'b'],
          birthOwnerAuthIds: const ['b', 'c'],
          communityOwnerIds: const <String>[],
          communityOwnerAuthIds: const <String>[],
          photoToUserIds: const ['a'],
          photoToProfileIds: const <String>[],
        ),
        4,
      );
    });

    test('birth and community with same doc id count as two', () {
      final rows = [
        {
          'id': 'R1_O1',
          'request_kind': 'birth',
          'requester_id': 'R1',
          'owner_id': 'O1',
          'status': 'pending',
        },
        {
          'id': 'R1_O1',
          'request_kind': 'community',
          'requester_id': 'R1',
          'owner_id': 'O1',
          'status': 'pending',
        },
        {
          'id': 'photo1',
          'request_kind': 'photo',
          'from_user_id': 'R2',
          'to_user_id': 'O1',
          'status': 'pending',
        },
      ];
      expect(InterestBadgeAggregator.incomingPrivacyRequestsUnviewed(rows), 3);
      expect(
        InterestBadgeAggregator.pendingIncomingRequestDocCount(
          birthOwnerIds: const ['R1_O1'],
          birthOwnerAuthIds: const <String>[],
          communityOwnerIds: const ['R1_O1'],
          communityOwnerAuthIds: const <String>[],
          photoToUserIds: const <String>[],
          photoToProfileIds: const <String>[],
        ),
        2,
      );
    });

    test('resolveInterestParticipantQueryAliasIds omits profile id', () {
      final ids = InterestBadgeAggregator.resolveInterestParticipantQueryAliasIds(
        canonicalUserDocId: 'docA',
        firebaseAuthUid: 'auth1',
        identityAuthUid: 'auth2',
      );
      expect(ids, ['docA', 'auth1', 'auth2']);
      expect(ids, isNot(contains('MG28088')));
    });

    test('resolveInterestQueryAliasIds dedupes and preserves canonical first', () {
      final ids = InterestBadgeAggregator.resolveInterestQueryAliasIds(
        canonicalUserDocId: 'doc1',
        queryUserDocIdHint: 'doc1',
        firebaseAuthUid: 'auth1',
        identityAuthUid: 'auth1',
        profileId: 'p1',
      );
      expect(ids, ['doc1', 'auth1', 'p1']);
    });

    test('resolveInterestQueryAliasIds uses hint when canonical empty', () {
      final ids = InterestBadgeAggregator.resolveInterestQueryAliasIds(
        canonicalUserDocId: '',
        queryUserDocIdHint: 'hint',
        firebaseAuthUid: 'fa',
        identityAuthUid: null,
        profileId: null,
      );
      expect(ids, ['hint', 'fa']);
    });

    test('chunksForFirestoreWhereIn splits at 10', () {
      final ids = List.generate(25, (i) => 'id$i');
      final chunks = InterestBadgeAggregator.chunksForFirestoreWhereIn(ids);
      expect(chunks.length, 3);
      expect(chunks[0].length, 10);
      expect(chunks[1].length, 10);
      expect(chunks[2].length, 5);
    });

    test('activityBellTotal is explicit sum of all inputs', () {
      expect(
        InterestBadgeAggregator.activityBellTotal(
          notificationUnreadExcludingHubMirrored: 2,
          pendingReceivedUnviewedInterests: 3,
          pendingSentInterests: 1,
          unreadMessages: 4,
          pendingPrivacyRequestDocs: 5,
        ),
        15,
      );
    });

    test('pendingSentUnviewed counts only visible unopened sent rows', () {
      final sent = [
        {'id': 's1', 'status': 'pending', 'viewed_by_sender': false},
        {'id': 's2', 'status': 'pending', 'viewed_by_sender': true},
        {'id': 's3', 'status': 'accepted', 'viewed_by_sender': false},
        {'id': 's4', 'status': 'withdrawn', 'viewed_by_sender': false},
      ];
      expect(InterestBadgeAggregator.pendingSentUnviewed(sent), 2);
    });

    test('activityBellUnreadTotal dedupes notification and interest row', () {
      final total = InterestBadgeAggregator.activityBellUnreadTotal(
        notifications: [
          {
            'id': 'n1',
            'type': 'interest_received',
            'is_read': false,
            'interest_id': 'a_b',
          },
        ],
        interestsReceived: [
          {'id': 'a_b', 'status': 'pending', 'viewed_by_recipient': false},
        ],
        interestsSent: const [],
        messagesReceived: const [],
        pendingIncomingPrivacyDocIds: const [],
      );
      expect(total, 1);
    });

    test('activityBellUnreadTotal sums distinct unread sources', () {
      final total = InterestBadgeAggregator.activityBellUnreadTotal(
        notifications: [
          {'id': 'n1', 'type': 'profile_view', 'is_read': false},
        ],
        interestsReceived: [
          {'id': 'r1', 'status': 'pending', 'viewed_by_recipient': false},
        ],
        interestsSent: [
          {'id': 's1', 'status': 'pending', 'viewed_by_sender': false},
        ],
        messagesReceived: [
          {'id': 'm1', 'is_read': false, 'status': 'pending'},
        ],
        pendingIncomingPrivacyDocIds: ['req1'],
      );
      expect(total, 5);
    });

    test('sentHubBadgeCount includes unviewed outgoing privacy requests', () {
      expect(
        InterestBadgeAggregator.sentHubBadgeCount(
          interestsSent: const [],
          outgoingPrivacyRequests: [
            {'id': 'r1', 'request_kind': 'birth', 'status': 'pending'},
            {
              'id': 'r2',
              'request_kind': 'community',
              'status': 'granted',
              'viewed_by_requester': false,
            },
            {
              'id': 'r3',
              'request_kind': 'birth',
              'status': 'granted',
              'viewed_by_requester': true,
            },
          ],
        ),
        2,
      );
    });

    test('activityBellHubAlignedTotal matches hub tabs not duplicate notifs', () {
      final total = InterestBadgeAggregator.activityBellHubAlignedTotal(
        interestsReceived: [
          {'id': 'r1', 'status': 'pending', 'viewed_by_recipient': false},
        ],
        interestsSent: [
          {'id': 's1', 'status': 'pending', 'viewed_by_sender': false},
        ],
        incomingPrivacyRequestRows: [
          {'id': 'req1', 'request_kind': 'birth', 'status': 'pending'},
        ],
        outgoingPrivacyRequestRows: const [],
        notifications: [
          {
            'id': 'n1',
            'type': 'interest_received',
            'is_read': false,
            'interest_id': 'r1',
          },
          {
            'id': 'n2',
            'type': 'birth_request',
            'is_read': false,
            'request_doc_id': 'req1',
          },
        ],
        unreadMessages: 0,
      );
      // Overview = 1 received + 1 privacy + 1 sent; notifs are hub-mirrored.
      expect(total, 3);
    });

    test('activityBellHubAlignedTotal does not double-count photo inbox rows', () {
      final total = InterestBadgeAggregator.activityBellHubAlignedTotal(
        interestsReceived: const [],
        interestsSent: const [],
        incomingPrivacyRequestRows: [
          {'id': 'photo1', 'request_kind': 'photo', 'status': 'pending'},
        ],
        outgoingPrivacyRequestRows: const [],
        notifications: const [],
        messagesReceived: [
          {
            'id': 'photo1',
            'type': 'photo_request',
            'status': 'pending',
            'is_read': false,
          },
        ],
      );
      expect(total, 1);
    });

    test('activityBellUnreadTotal drops read notification and viewed interest', () {
      final total = InterestBadgeAggregator.activityBellUnreadTotal(
        notifications: [
          {'id': 'n1', 'type': 'interest_received', 'is_read': true},
        ],
        interestsReceived: [
          {'id': 'a_b', 'status': 'pending', 'viewed_by_recipient': true},
        ],
        interestsSent: const [],
        messagesReceived: const [],
        pendingIncomingPrivacyDocIds: const [],
      );
      expect(total, 0);
    });
  });
}
