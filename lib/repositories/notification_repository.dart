import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/firestore_client.dart';
import '../core/firestore_page.dart';
import '../utils/safe_data_extractor.dart';

class NotificationRepository {
  NotificationRepository({FirestoreClient? client})
      : _client = client ?? FirestoreClient();

  final FirestoreClient _client;

  CollectionReference<Map<String, dynamic>> get _col =>
      _client.db.collection('notifications');

  static Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? <String, dynamic>{};
    return <String, dynamic>{...data, 'id': d.id};
  }

  static String _notifSortKey(Map<String, dynamic> n) {
    final v = n['created_at'] ?? n['timestamp'];
    final parsed = SafeDataExtractor.parseFirestoreDate(v);
    if (parsed != null) return parsed.toIso8601String();
    return v?.toString() ?? '';
  }

  static int _notifSortDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _notifSortKey(b).compareTo(_notifSortKey(a));

  /// Unread unless explicitly marked read (legacy docs may omit [is_read]).
  static bool isUnread(Map<String, dynamic> n) {
    if (n['is_read'] == true || n['isRead'] == true) return false;
    return true;
  }

  static bool isVisibleForUser(Map<String, dynamic> n, String userId) {
    final deletedFor = n['deletedFor'] as List<dynamic>? ?? const [];
    return !deletedFor.contains(userId);
  }

  static void _mergeDocs(
    Map<String, Map<String, dynamic>> byId,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final d in docs) {
      byId[d.id] = _withId(d);
    }
  }

  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    bool unreadOnly = false,
    int limit = 200,
  }) async {
    await _client.ensureAuth();

    final snap = await _client.withTimeout(
      _col.where('user_id', isEqualTo: userId).limit(limit).get(),
      timeout: const Duration(seconds: 10),
    );
    final snapLegacyToUserId = await _client.withTimeout(
      _col.where('to_user_id', isEqualTo: userId).limit(limit).get(),
      timeout: const Duration(seconds: 10),
    );
    final snapLegacyToUser = await _client.withTimeout(
      _col.where('to_user', isEqualTo: userId).limit(limit).get(),
      timeout: const Duration(seconds: 10),
    );
    final snapLegacyReceiver = await _client.withTimeout(
      _col.where('receiver_user_id', isEqualTo: userId).limit(limit).get(),
      timeout: const Duration(seconds: 10),
    );

    final byId = <String, Map<String, dynamic>>{};
    _mergeDocs(byId, snap.docs);
    _mergeDocs(byId, snapLegacyToUserId.docs);
    _mergeDocs(byId, snapLegacyToUser.docs);
    _mergeDocs(byId, snapLegacyReceiver.docs);

    var items = byId.values
        .where((n) => isVisibleForUser(n, userId))
        .toList()
      ..sort(_notifSortDesc);

    if (unreadOnly) {
      items = items.where(isUnread).toList();
    }

    if (items.length > limit) {
      return items.sublist(0, limit);
    }
    return items;
  }

  Future<FirestorePage<Map<String, dynamic>>> pageForUser(
    String userId, {
    bool unreadOnly = false,
    int limit = 30,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    await _client.ensureAuth();
    // Index-safe query: avoid orderBy() to prevent runtime failures on devices
    // where composite indexes are missing. We sort in Dart below.
    Query<Map<String, dynamic>> q =
        _col.where('user_id', isEqualTo: userId).limit(limit);
    if (unreadOnly) {
      q = q.where('is_read', isEqualTo: false);
    }
    Query<Map<String, dynamic>> qLegacy =
        _col.where('user_id', isEqualTo: userId).limit(limit);
    if (unreadOnly) {
      qLegacy = qLegacy.where('is_read', isEqualTo: false);
    }
    // Pagination cursor with no orderBy is not deterministic, so we intentionally
    // keep this as first-page only for stability on all devices.

    final snap = await _client.withTimeout(
      q.get(),
      timeout: const Duration(seconds: 10),
    );
    final snapLegacy = await _client.withTimeout(
      qLegacy.get(),
      timeout: const Duration(seconds: 10),
    );

    final byId = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in snap.docs) {
      byId[d.id] = d;
    }
    for (final d in snapLegacy.docs) {
      byId[d.id] = d;
    }

    final filtered = byId.values
        .where((d) =>
            !((d.data() ?? <String, dynamic>{})['deletedFor'] as List<dynamic>? ??
                    const [])
                .contains(userId))
        .toList();

    final items = filtered.map(_withId).toList()..sort(_notifSortDesc);
    final last = filtered.isNotEmpty ? filtered.last : startAfter;
    final hasMore = false;
    return FirestorePage(items: items, lastDoc: last, hasMore: hasMore);
  }

  Stream<List<Map<String, dynamic>>> watchForUser(String userId) {
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    late final StreamController<List<Map<String, dynamic>>> controller;

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        scheduleMicrotask(() async {
          await _client.ensureAuth();
          final bySource = <String, Map<String, Map<String, dynamic>>>{};

          void emit() {
            final byId = <String, Map<String, dynamic>>{};
            for (final source in bySource.values) {
              byId.addAll(source);
            }
            final items = byId.values.toList()
              ..removeWhere((n) {
                final deletedFor = n['deletedFor'] as List<dynamic>? ?? const [];
                return deletedFor.contains(userId);
              })
              ..sort(_notifSortDesc);
            if (!controller.isClosed) controller.add(items);
          }

          void absorb(String sourceKey, QuerySnapshot<Map<String, dynamic>> snap) {
            final source = bySource.putIfAbsent(
              sourceKey,
              () => <String, Map<String, dynamic>>{},
            );
            for (final change in snap.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                source.remove(change.doc.id);
              } else {
                source[change.doc.id] = _withId(change.doc);
              }
            }
            emit();
          }

          subs.add(_col
              .where('user_id', isEqualTo: userId)
              .snapshots(includeMetadataChanges: false)
              .listen((snap) => absorb('user_id', snap)));
          subs.add(_col
              .where('to_user_id', isEqualTo: userId)
              .snapshots(includeMetadataChanges: false)
              .listen((snap) => absorb('to_user_id', snap)));
          subs.add(_col
              .where('to_user', isEqualTo: userId)
              .snapshots(includeMetadataChanges: false)
              .listen((snap) => absorb('to_user', snap)));
          subs.add(_col
              .where('receiver_user_id', isEqualTo: userId)
              .snapshots(includeMetadataChanges: false)
              .listen((snap) => absorb('receiver_user_id', snap)));
        });
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  Future<void> markRead(String notificationId) async {
    if (notificationId.isEmpty) return;
    await _client.ensureAuth();
    await _client.withTimeout(
      _col.doc(notificationId).update({'is_read': true}),
      timeout: const Duration(seconds: 10),
    );
  }

  Future<void> markAllRead(String userId) async {
    if (userId.isEmpty) return;
    await _client.ensureAuth();
    final snap = await _client.withTimeout(
      _col.where('user_id', isEqualTo: userId).get(),
      timeout: const Duration(seconds: 12),
    );
    final snapLegacyToUserId = await _client.withTimeout(
      _col.where('to_user_id', isEqualTo: userId).get(),
      timeout: const Duration(seconds: 12),
    );
    final snapLegacyToUser = await _client.withTimeout(
      _col.where('to_user', isEqualTo: userId).get(),
      timeout: const Duration(seconds: 12),
    );
    final snapLegacyReceiver = await _client.withTimeout(
      _col.where('receiver_user_id', isEqualTo: userId).get(),
      timeout: const Duration(seconds: 12),
    );
    final seenPaths = <String>{};
    final docRefs = <DocumentReference<Map<String, dynamic>>>[];
    void addRef(DocumentReference<Map<String, dynamic>> r) {
      if (seenPaths.add(r.path)) docRefs.add(r);
    }
    for (final d in snap.docs) {
      addRef(d.reference);
    }
    for (final d in snapLegacyToUserId.docs) {
      addRef(d.reference);
    }
    for (final d in snapLegacyToUser.docs) {
      addRef(d.reference);
    }
    for (final d in snapLegacyReceiver.docs) {
      addRef(d.reference);
    }
    if (docRefs.isEmpty) return;

    // Batch size safety (<= 500 ops). Stay well under.
    for (var i = 0; i < docRefs.length; i += 400) {
      final end = (i + 400) > docRefs.length ? docRefs.length : i + 400;
      final chunk = docRefs.sublist(i, end);
      final batch = _client.db.batch();
      for (final ref in chunk) {
        batch.update(ref, {'is_read': true});
      }
      await _client.withTimeout(batch.commit(), timeout: const Duration(seconds: 12));
    }
  }

  Future<void> delete(String notificationId) async {
    if (notificationId.isEmpty) return;
    await _client.ensureAuth();
    await _client.withTimeout(
      _col.doc(notificationId).delete(),
      timeout: const Duration(seconds: 10),
    );
  }
}

