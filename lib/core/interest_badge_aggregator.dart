import 'package:cloud_firestore/cloud_firestore.dart';

import 'privacy_request_notification_sync.dart';

/// Single source of truth for interest-row semantics used by:
/// - header notification bell
/// - Interests hub badges
/// - Activity / profile style counters (when "visible" totals are needed)
///
/// All predicates stay aligned with [interests_analytics_screen.dart] list rules.
class InterestBadgeAggregator {
  InterestBadgeAggregator._();

  /// Firestore `whereIn` maximum elements (SDK limit).
  static const int firestoreWhereInMax = 10;

  // ── Status ───────────────────────────────────────────────────────────────

  /// Legacy / malformed normalization — trim + lowercase; mirrors hub helpers.
  static String normalizeInterestStatus(dynamic raw) {
    final s = (raw as String? ?? 'pending').trim().toLowerCase();
    if (s.isEmpty) return 'pending';
    if (s == 'sent') return 'pending';
    if (s == 'approved' || s == 'granted') return 'accepted';
    if (s == 'denied' || s == 'declined') return 'rejected';
    return s;
  }

  /// Rows the hub must not surface and badges must not count.
  static bool isInterestRowHidden(dynamic rawStatus) {
    final n = normalizeInterestStatus(rawStatus);
    return n == 'withdrawn' || n == 'inactive' || n == 'deleted';
  }

  static bool isInterestRowVisible(dynamic rawStatus) =>
      !isInterestRowHidden(rawStatus);

  static bool isPendingInterestStatus(dynamic rawStatus) =>
      normalizeInterestStatus(rawStatus) == 'pending';

  // ── viewed_by_recipient ───────────────────────────────────────────────────

  /// Interest no longer needs a Received-tab / notification alert.
  static bool interestRowClearsReceivedNotification(Map<String, dynamic> row) {
    if (!isInterestRowVisible(row['status'])) return true;
    if (!isPendingInterestStatus(row['status'])) return true;
    return viewedByRecipientIsTruthy(row);
  }

  static bool _truthyField(dynamic v) {
    if (v == true) return true;
    if (v == 1 || v == 1.0) return true;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  static bool viewedByRecipientIsTruthy(Map<String, dynamic> row) {
    return _truthyField(row['viewed_by_recipient']) ||
        _truthyField(row['viewedByRecipient']);
  }

  static bool viewedBySenderIsTruthy(Map<String, dynamic> row) {
    return _truthyField(row['viewed_by_sender']) ||
        _truthyField(row['viewedBySender']);
  }

  static bool viewedByOwnerIsTruthy(Map<String, dynamic> row) {
    return _truthyField(row['viewed_by_owner']) ||
        _truthyField(row['viewedByOwner']);
  }

  static bool viewedByRequesterIsTruthy(Map<String, dynamic> row) {
    return _truthyField(row['viewed_by_requester']) ||
        _truthyField(row['viewedByRequester']);
  }

  /// Received-tab / bell: any visible interest you have not opened yet.
  static bool receivedInterestNeedsBellCount(Map<String, dynamic> row) {
    if (!isInterestRowVisible(row['status'])) return false;
    return isPendingInterestStatus(row['status']);
  }

  /// Sent-tab / bell: visible interest the sender has not opened yet.
  static bool sentInterestNeedsBellCount(Map<String, dynamic> row) {
    if (!isInterestRowVisible(row['status'])) return false;
    return isPendingInterestStatus(row['status']);
  }

  /// Matches hub accessory list visibility (birth / community / photo rows).
  static bool isPrivacyRequestRowVisible(dynamic rawStatus) {
    final n = PrivacyRequestNotificationSync.normalizeStatus(rawStatus);
    return n != 'withdrawn' && n != 'inactive' && n != 'deleted';
  }

  static String privacyRequestDocumentId(Map<String, dynamic> row) {
    return (row['id'] as String? ?? '').trim();
  }

  /// Unique badge key: birth and community may share the same Firestore doc id
  /// (`requester_owner`) but must always count as separate requests.
  static String privacyRequestBadgeKey(Map<String, dynamic> row) {
    final id = privacyRequestDocumentId(row);
    if (id.isEmpty) return '';
    final kind =
        (row['request_kind'] as String? ?? row['kind'] as String? ?? '')
            .trim()
            .toLowerCase();
    if (kind == 'birth' || kind == 'community' || kind == 'photo') {
      return '$kind:$id';
    }
    if (isPhotoPrivacyRow(row)) return 'photo:$id';
    return '';
  }

  static bool isPhotoPrivacyRow(Map<String, dynamic> row) {
    final kind =
        (row['request_kind'] as String? ?? row['kind'] as String? ?? '')
            .trim()
            .toLowerCase();
    if (kind == 'photo') return true;
    if (kind == 'birth' || kind == 'community') return false;
    final hasFrom = (row['from_user_id'] as String? ??
            row['fromUserId'] as String? ??
            '')
        .trim()
        .isNotEmpty;
    final hasTo = (row['to_user_id'] as String? ??
            row['toUserId'] as String? ??
            row['to_profile_id'] as String? ??
            row['toProfileId'] as String? ??
            '')
        .trim()
        .isNotEmpty;
    final hasRequesterOwner = (row['requester_id'] as String? ??
            row['requesterId'] as String? ??
            '')
        .trim()
        .isNotEmpty &&
        (row['owner_id'] as String? ?? row['ownerId'] as String? ?? '')
            .trim()
            .isNotEmpty;
    return hasFrom && hasTo && !hasRequesterOwner;
  }

  static Map<String, dynamic> tagPrivacyRequestKind(
    Map<String, dynamic> row,
    String kind,
  ) {
    return <String, dynamic>{...row, 'request_kind': kind};
  }

  static String _notificationPrivacyBadgeKey(String type, String requestDocId) {
    final id = requestDocId.trim();
    if (id.isEmpty) return '';
    if (type.contains('photo')) return 'photo:$id';
    if (type.contains('community')) return 'community:$id';
    if (type.contains('birth')) return 'birth:$id';
    return '';
  }

  /// Incoming access/photo requests shown on Received (pending until you act).
  static bool incomingPrivacyRequestNeedsBellCount(Map<String, dynamic> row) {
    if (!isPrivacyRequestRowVisible(row['status'])) return false;
    return PrivacyRequestNotificationSync.normalizeStatus(row['status']) ==
        'pending';
  }

  /// Outgoing requests on Sent: pending always counts; outcomes until opened.
  static bool outgoingPrivacyRequestNeedsBellCount(Map<String, dynamic> row) {
    if (!isPrivacyRequestRowVisible(row['status'])) return false;
    return PrivacyRequestNotificationSync.normalizeStatus(row['status']) ==
        'pending';
  }

  static bool notificationIsUnread(Map<String, dynamic> n) {
    if (n['is_read'] == true || n['isRead'] == true) return false;
    return true;
  }

  static String? interestIdFromNotification(Map<String, dynamic> n) {
    final data = n['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final id = (map['interest_id'] as String? ??
            n['interest_id'] as String? ??
            '')
        .trim();
    return id.isEmpty ? null : id;
  }

  static String? requestDocIdFromNotification(Map<String, dynamic> n) {
    final data = n['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final id = (n['request_doc_id'] as String? ??
            n['requestDocId'] as String? ??
            map['request_doc_id'] as String? ??
            map['requestDocId'] as String? ??
            '')
        .trim();
    return id.isEmpty ? null : id;
  }

  static String? messageDocIdFromNotification(Map<String, dynamic> n) {
    final data = n['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final id = (map['message_id'] as String? ??
            n['message_id'] as String? ??
            map['messageId'] as String? ??
            n['messageId'] as String? ??
            '')
        .trim();
    return id.isEmpty ? null : id;
  }

  static String messageDocumentId(Map<String, dynamic> msg) {
    return (msg['id'] as String? ?? '').trim();
  }

  // ── Document id ───────────────────────────────────────────────────────────

  static String interestDocumentId(Map<String, dynamic> row) {
    final a = (row['id'] ??
            row['interestId'] ??
            row['interest_id'] ??
            '')
        .toString()
        .trim();
    if (a.isNotEmpty) return a;
    final from = (row['from_user_id'] ?? row['fromUserId'] ?? '')
        .toString()
        .trim();
    final to =
        (row['to_user_id'] ?? row['toUserId'] ?? '').toString().trim();
    if (from.isNotEmpty && to.isNotEmpty) return '${from}_$to';
    return '';
  }

  /// Every id that may refer to the same interest doc (withdraw / optimistic hide).
  static Set<String> interestDocumentIdAliases(Map<String, dynamic> row) {
    final ids = <String>{};
    void add(String? raw) {
      final t = raw?.trim() ?? '';
      if (t.isNotEmpty) ids.add(t);
    }

    add(row['id'] as String?);
    add(row['interestId'] as String?);
    add(row['interest_id'] as String?);
    final from = (row['from_user_id'] ?? row['fromUserId'] ?? '')
        .toString()
        .trim();
    final to =
        (row['to_user_id'] ?? row['toUserId'] ?? '').toString().trim();
    if (from.isNotEmpty && to.isNotEmpty) ids.add('${from}_$to');
    final primary = interestDocumentId(row);
    if (primary.isNotEmpty) ids.add(primary);
    return ids;
  }

  static Set<String> resolveOptimisticHideIds(
    String docId, {
    Map<String, dynamic>? rowHint,
  }) {
    final ids = <String>{...interestDocumentIdAliases(rowHint ?? const {})};
    final trimmed = docId.trim();
    if (trimmed.isNotEmpty) ids.add(trimmed);
    ids.removeWhere((e) => e.isEmpty);
    return ids;
  }

  static bool interestRowMatchesDocId(
    Map<String, dynamic> row,
    String docId,
  ) {
    final t = docId.trim();
    if (t.isEmpty) return false;
    return interestDocumentIdAliases(row).contains(t);
  }

  static bool interestRowMatchesAnyHiddenId(
    Map<String, dynamic> row,
    Set<String> hiddenIds,
  ) {
    if (hiddenIds.isEmpty) return false;
    for (final alias in interestDocumentIdAliases(row)) {
      if (hiddenIds.contains(alias)) return true;
    }
    return false;
  }

  /// Hub list rows: deduped + withdrawn/inactive/deleted removed.
  static List<Map<String, dynamic>> hubVisibleInterestRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    return dedupeInterestRows(rows)
        .where((r) => isInterestRowVisible(r['status']))
        .toList();
  }

  static int _updatedMillis(Map<String, dynamic> row) {
    var ts = row['updated_at'] ?? row['updatedAt'];
    ts ??= row['created_at'] ?? row['createdAt'];
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is String) {
      return DateTime.tryParse(ts)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  /// Same logical doc via aliases must count once; keep newest snapshot by
  /// [updated_at] / [created_at].
  static List<Map<String, dynamic>> dedupeInterestRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = interestDocumentId(r);
      if (id.isEmpty) continue;
      final prev = byId[id];
      if (prev == null || _updatedMillis(r) >= _updatedMillis(prev)) {
        byId[id] = r;
      }
    }
    return byId.values.toList();
  }

  /// Cheap revision token for hub tab [ValueKey]s (list identity + order).
  static String sentListRevision(Iterable<Map<String, dynamic>> rows) {
    final deduped = dedupeInterestRows(rows);
    if (deduped.isEmpty) return '0';
    final buf = StringBuffer();
    for (final row in deduped.take(12)) {
      final id = interestDocumentId(row);
      final status = normalizeInterestStatus(row['status']);
      buf
        ..write(id)
        ..write(':')
        ..write(status)
        ..write('|');
    }
    return '${deduped.length}:${buf.toString()}';
  }

  // ── Badge counts ───────────────────────────────────────────────────────────

  /// Interests received that you have not opened yet (any visible status).
  static int receivedInterestUnviewed(
    Iterable<Map<String, dynamic>> received,
  ) {
    final rows = dedupeInterestRows(received);
    return rows.where(receivedInterestNeedsBellCount).length;
  }

  /// Pending interests to you that you have not opened yet.
  static int pendingReceivedUnviewed(
    Iterable<Map<String, dynamic>> received,
  ) =>
      receivedInterestUnviewed(received);

  /// Interests you sent still awaiting a response.
  static int pendingSent(Iterable<Map<String, dynamic>> sent) {
    final rows = dedupeInterestRows(sent);
    return rows
        .where(
          (i) =>
              isInterestRowVisible(i['status']) &&
              isPendingInterestStatus(i['status']),
        )
        .length;
  }

  /// Sent interests you have not opened (read clears the count).
  static int sentInterestUnviewed(Iterable<Map<String, dynamic>> sent) {
    final rows = dedupeInterestRows(sent);
    return rows.where(sentInterestNeedsBellCount).length;
  }

  /// Alias — same as [sentInterestUnviewed].
  static int pendingSentUnviewed(Iterable<Map<String, dynamic>> sent) =>
      sentInterestUnviewed(sent);

  static int _dedupedPrivacyRequestCount(
    Iterable<Map<String, dynamic>> rows,
    bool Function(Map<String, dynamic>) include,
  ) {
    final countedKeys = <String>{};
    var total = 0;

    for (final r in rows) {
      if (!include(r)) continue;
      final key = privacyRequestBadgeKey(r);
      if (key.isEmpty) continue;
      if (!countedKeys.add(key)) continue;
      total++;
    }
    return total;
  }

  /// Visible pending access rows on Received (birth + community + photo each separate).
  static int incomingAccessRequestsVisibleCount({
    required Iterable<Map<String, dynamic>> birthRows,
    required Iterable<Map<String, dynamic>> communityRows,
    required Iterable<Map<String, dynamic>> photoRows,
  }) {
    return _dedupedPrivacyRequestCount(
      [
        ...birthRows.map((r) => tagPrivacyRequestKind(r, 'birth')),
        ...communityRows.map((r) => tagPrivacyRequestKind(r, 'community')),
        ...photoRows.map((r) => tagPrivacyRequestKind(r, 'photo')),
      ],
      (_) => true,
    );
  }

  /// Pending birth/community/photo requests waiting on you (Received tab).
  static int incomingPrivacyRequestsUnviewed(
    Iterable<Map<String, dynamic>> rows,
  ) =>
      _dedupedPrivacyRequestCount(rows, incomingPrivacyRequestNeedsBellCount);

  /// Birth/community/photo requests you sent (Sent tab; outcomes until opened).
  static int outgoingPrivacyRequestsUnviewed(
    Iterable<Map<String, dynamic>> rows,
  ) =>
      _dedupedPrivacyRequestCount(rows, outgoingPrivacyRequestNeedsBellCount);

  /// Received tab badge: every unopened interest + every pending access request.
  static int receivedHubBadgeCount({
    required Iterable<Map<String, dynamic>> interestsReceived,
    required Iterable<Map<String, dynamic>> incomingPrivacyRequests,
  }) {
    return receivedInterestUnviewed(interestsReceived) +
        incomingPrivacyRequestsUnviewed(incomingPrivacyRequests);
  }

  /// Sent tab badge: every unopened interest + every sent access request row.
  static int sentHubBadgeCount({
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> outgoingPrivacyRequests,
  }) {
    return sentInterestUnviewed(interestsSent) +
        outgoingPrivacyRequestsUnviewed(outgoingPrivacyRequests);
  }

  /// All visible received rows (deduped) — for profile/activity totals that
  /// must match hub visibility, not raw Firestore list length.
  static int visibleReceivedTotal(Iterable<Map<String, dynamic>> received) {
    final rows = dedupeInterestRows(received);
    return rows.where((i) => isInterestRowVisible(i['status'])).length;
  }

  /// All visible sent rows (deduped).
  static int visibleSentTotal(Iterable<Map<String, dynamic>> sent) {
    final rows = dedupeInterestRows(sent);
    return rows.where((i) => isInterestRowVisible(i['status'])).length;
  }

  // ── Privacy request doc union (birth / community / photo pending ids) ─────

  static int pendingIncomingRequestDocCount({
    required Iterable<String> birthOwnerIds,
    required Iterable<String> birthOwnerAuthIds,
    required Iterable<String> communityOwnerIds,
    required Iterable<String> communityOwnerAuthIds,
    required Iterable<String> photoToUserIds,
    required Iterable<String> photoToProfileIds,
    Iterable<Map<String, dynamic>> birthRows = const [],
    Iterable<Map<String, dynamic>> communityRows = const [],
    Iterable<Map<String, dynamic>> photoRows = const [],
  }) {
    if (birthRows.isNotEmpty ||
        communityRows.isNotEmpty ||
        photoRows.isNotEmpty) {
      return incomingPrivacyRequestsUnviewed([
        ...birthRows.map((r) => tagPrivacyRequestKind(r, 'birth')),
        ...communityRows.map((r) => tagPrivacyRequestKind(r, 'community')),
        ...photoRows.map((r) => tagPrivacyRequestKind(r, 'photo')),
      ]);
    }
    // Doc-id fallback: prefix by kind so shared `requester_owner` ids stay distinct.
    return <String>{
      ...birthOwnerIds.map((id) => 'birth:$id'),
      ...birthOwnerAuthIds.map((id) => 'birth:$id'),
      ...communityOwnerIds.map((id) => 'community:$id'),
      ...communityOwnerAuthIds.map((id) => 'community:$id'),
      ...photoToUserIds.map((id) => 'photo:$id'),
      ...photoToProfileIds.map((id) => 'photo:$id'),
    }.length;
  }

  // ── Interest `whereIn` aliases (Firestore 10-cap) ────────────────────────

  /// Firestore `users/{docId}` + auth uids for interest list queries.
  ///
  /// Omits public [profileId] — interests store doc ids in `from_user_id` /
  /// `to_user_id`; querying by profile id returns nothing and can race with
  /// optimistic sends.
  static List<String> resolveInterestParticipantQueryAliasIds({
    required String canonicalUserDocId,
    String? queryUserDocIdHint,
    String? firebaseAuthUid,
    String? identityAuthUid,
  }) {
    final out = <String>[];
    void add(String? v) {
      final t = (v ?? '').trim();
      if (t.isEmpty || out.contains(t)) return;
      out.add(t);
    }

    final c = canonicalUserDocId.trim();
    final h = (queryUserDocIdHint ?? '').trim();

    if (c.isNotEmpty) {
      add(c);
    } else if (h.isNotEmpty) {
      add(h);
    }
    if (c.isNotEmpty && h.isNotEmpty && h != c) add(h);

    add(firebaseAuthUid);
    add(identityAuthUid);
    return out;
  }

  /// Canonical Firestore user doc id first, then other aliases, deduped,
  /// capped at [firestoreWhereInMax]. Never returns empty if any input non-empty.
  static List<String> resolveInterestQueryAliasIds({
    required String canonicalUserDocId,
    String? queryUserDocIdHint,
    String? firebaseAuthUid,
    String? identityAuthUid,
    String? profileId,
  }) {
    final out = resolveInterestParticipantQueryAliasIds(
      canonicalUserDocId: canonicalUserDocId,
      queryUserDocIdHint: queryUserDocIdHint,
      firebaseAuthUid: firebaseAuthUid,
      identityAuthUid: identityAuthUid,
    );
    final profile = (profileId ?? '').trim();
    if (profile.isNotEmpty && !out.contains(profile)) {
      out.add(profile);
    }
    return out;
  }

  /// Firestore user doc id + auth uids only (not public profile_id) for sent
  /// birth/community/photo request queries — avoids permission-denied list reads.
  static List<String> resolveSentRequestQueryAliasIds({
    required String canonicalUserDocId,
    String? firebaseAuthUid,
    String? identityAuthUid,
  }) {
    final out = <String>[];
    void add(String? v) {
      final t = (v ?? '').trim();
      if (t.isEmpty || out.contains(t)) return;
      out.add(t);
    }

    add(canonicalUserDocId);
    add(firebaseAuthUid);
    add(identityAuthUid);
    return out;
  }

  /// Splits [ids] into chunks of at most [firestoreWhereInMax] for `whereIn` queries.
  static List<List<String>> chunksForFirestoreWhereIn(List<String> ids) {
    if (ids.isEmpty) return const [];
    final out = <List<String>>[];
    for (var i = 0; i < ids.length; i += firestoreWhereInMax) {
      final end = i + firestoreWhereInMax > ids.length
          ? ids.length
          : i + firestoreWhereInMax;
      out.add(ids.sublist(i, end));
    }
    return out;
  }

  /// Notification types already counted via Interests hub rows (not bell).
  static const Set<String> hubMirroredNotificationTypes = {
    'interest_received',
    'interest_reminder',
    'interest',
    'interest_accepted',
    'interest_rejected',
    'interest_declined',
    ...PrivacyRequestNotificationSync.hubMirroredBellTypes,
  };

  static String normalizeNotificationType(dynamic raw) {
    return (raw as String? ?? '').trim().toLowerCase().replaceAll('-', '_');
  }

  /// Overview tab badge: Received hub + Sent hub (matches Interests hub UI).
  static int interestsOverviewBadgeCount({
    required Iterable<Map<String, dynamic>> interestsReceived,
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> incomingPrivacyRequestRows,
    required Iterable<Map<String, dynamic>> outgoingPrivacyRequestRows,
  }) {
    return receivedHubBadgeCount(
          interestsReceived: interestsReceived,
          incomingPrivacyRequests: incomingPrivacyRequestRows,
        ) +
        sentHubBadgeCount(
          interestsSent: interestsSent,
          outgoingPrivacyRequests: outgoingPrivacyRequestRows,
        );
  }

  /// Inbox unread rows for the bell, excluding photo requests already in hub badges.
  static int unreadInboxCountForBell({
    required Iterable<Map<String, dynamic>> messagesReceived,
    required Iterable<Map<String, dynamic>> incomingPrivacyRequestRows,
    required Iterable<Map<String, dynamic>> outgoingPrivacyRequestRows,
  }) {
    final hubPhotoDocIds = <String>{
      for (final r in incomingPrivacyRequestRows)
        if (isPhotoPrivacyRow(r)) privacyRequestDocumentId(r),
      for (final r in outgoingPrivacyRequestRows)
        if (isPhotoPrivacyRow(r)) privacyRequestDocumentId(r),
    }..removeWhere((id) => id.isEmpty);

    var total = 0;
    for (final msg in messagesReceived) {
      final msgType = normalizeNotificationType(
        msg['type'] ?? msg['message_type'],
      );
      if (msgType == 'photo_request') {
        final id = messageDocumentId(msg);
        if (id.isNotEmpty && hubPhotoDocIds.contains(id)) continue;
      }
      final status = (msg['status'] as String? ?? 'pending').toLowerCase();
      if (status == 'approved' ||
          status == 'accepted' ||
          status == 'granted' ||
          status == 'rejected' ||
          status == 'declined' ||
          status == 'denied') {
        continue;
      }
      final isRead =
          (msg['is_read'] as bool?) ?? (msg['isRead'] as bool?) ?? false;
      if (!isRead) total++;
    }
    return total;
  }

  // ── Header bell aggregate ─────────────────────────────────────────────────

  /// Full consolidated activity bell: each argument is an independent source;
  /// callers recompute all pieces on every build.
  static int activityBellTotal({
    required int notificationUnreadExcludingHubMirrored,
    required int pendingReceivedUnviewedInterests,
    required int pendingSentInterests,
    required int unreadMessages,
    required int pendingPrivacyRequestDocs,
  }) {
    return notificationUnreadExcludingHubMirrored +
        pendingReceivedUnviewedInterests +
        pendingSentInterests +
        unreadMessages +
        pendingPrivacyRequestDocs;
  }

  /// Single bell count: every unread notification, plus live rows/messages/requests
  /// not already represented by an unread notification. Marking read or viewed
  /// lowers the total (no double-count across notification + hub mirrors).
  static int activityBellUnreadTotal({
    required Iterable<Map<String, dynamic>> notifications,
    required Iterable<Map<String, dynamic>> interestsReceived,
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> messagesReceived,
    required Iterable<String> pendingIncomingPrivacyDocIds,
    Iterable<Map<String, dynamic>> incomingPrivacyRequestRows = const [],
    Iterable<Map<String, dynamic>> outgoingPrivacyRequestRows = const [],
  }) {
    var total = 0;
    final claimed = <String>{};

    bool claim(String key) {
      if (key.isEmpty) return false;
      return claimed.add(key);
    }

    void reserveInterest(String? id) {
      if (id == null || id.isEmpty) return;
      claimed.add('interest:$id');
    }

    void reserveRequest(String? id, {String? notificationType}) {
      if (id == null || id.isEmpty) return;
      final key = notificationType == null
          ? ''
          : _notificationPrivacyBadgeKey(
              normalizeNotificationType(notificationType),
              id,
            );
      claimed.add(key.isNotEmpty ? 'req:$key' : 'req:$id');
    }

    void reserveMessage(String? id) {
      if (id == null || id.isEmpty) return;
      claimed.add('msg:$id');
    }

    for (final n in notifications) {
      if (!notificationIsUnread(n)) continue;
      final notifId = (n['id'] as String? ?? '').trim();
      if (notifId.isEmpty) continue;
      if (!claim('notif:$notifId')) continue;
      total++;
      reserveInterest(interestIdFromNotification(n));
      reserveRequest(
        requestDocIdFromNotification(n),
        notificationType: n['type'] as String?,
      );
      reserveMessage(messageDocIdFromNotification(n));
    }

    for (final row in dedupeInterestRows(interestsReceived)) {
      if (!receivedInterestNeedsBellCount(row)) continue;
      final id = interestDocumentId(row);
      if (id.isEmpty || claimed.contains('interest:$id')) continue;
      if (!claim('interest:$id')) continue;
      total++;
    }

    for (final row in dedupeInterestRows(interestsSent)) {
      if (!sentInterestNeedsBellCount(row)) continue;
      final id = interestDocumentId(row);
      if (id.isEmpty || claimed.contains('interest:$id')) continue;
      if (!claim('interest:$id')) continue;
      total++;
    }

    for (final msg in messagesReceived) {
      final id = messageDocumentId(msg);
      if (id.isEmpty) continue;
      final status = (msg['status'] as String? ?? 'pending').toLowerCase();
      if (status == 'approved' ||
          status == 'accepted' ||
          status == 'granted' ||
          status == 'rejected' ||
          status == 'declined' ||
          status == 'denied') {
        continue;
      }
      final isRead =
          (msg['is_read'] as bool?) ?? (msg['isRead'] as bool?) ?? false;
      if (isRead || claimed.contains('msg:$id')) continue;
      if (!claim('msg:$id')) continue;
      total++;
    }

    final incomingRows = <Map<String, dynamic>>[
      ...incomingPrivacyRequestRows,
    ];
    if (incomingRows.isEmpty) {
      for (final docId in pendingIncomingPrivacyDocIds) {
        final id = docId.trim();
        if (id.isEmpty || claimed.contains('req:$id')) continue;
        if (!claim('req:$id')) continue;
        total++;
      }
    } else {
      for (final row in incomingRows) {
        if (!incomingPrivacyRequestNeedsBellCount(row)) continue;
        final key = privacyRequestBadgeKey(row);
        if (key.isEmpty) continue;
        final claimKey = 'req:$key';
        if (claimed.contains(claimKey)) continue;
        if (!claim(claimKey)) continue;
        total++;
      }
    }

    for (final row in outgoingPrivacyRequestRows) {
      if (!outgoingPrivacyRequestNeedsBellCount(row)) continue;
      final key = privacyRequestBadgeKey(row);
      if (key.isEmpty) continue;
      final claimKey = 'req:$key';
      if (claimed.contains(claimKey)) continue;
      if (!claim(claimKey)) continue;
      total++;
    }

    return total;
  }

  /// Bell count aligned with Interests hub tab badges (Overview = Received + Sent
  /// + Messages). Does not add hub-mirrored notification rows on top of live data.
  static int activityBellHubAlignedTotal({
    required Iterable<Map<String, dynamic>> interestsReceived,
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> incomingPrivacyRequestRows,
    required Iterable<Map<String, dynamic>> outgoingPrivacyRequestRows,
    required Iterable<Map<String, dynamic>> notifications,
    Iterable<Map<String, dynamic>> messagesReceived = const [],
    int unreadMessages = 0,
  }) {
    final hub = interestsOverviewBadgeCount(
      interestsReceived: interestsReceived,
      interestsSent: interestsSent,
      incomingPrivacyRequestRows: incomingPrivacyRequestRows,
      outgoingPrivacyRequestRows: outgoingPrivacyRequestRows,
    );

    final hubInterestIds = <String>{};
    for (final row in dedupeInterestRows(interestsReceived)) {
      if (receivedInterestNeedsBellCount(row)) {
        hubInterestIds.add(interestDocumentId(row));
      }
    }
    for (final row in dedupeInterestRows(interestsSent)) {
      if (sentInterestNeedsBellCount(row)) {
        hubInterestIds.add(interestDocumentId(row));
      }
    }

    final hubRequestKeys = <String>{};
    for (final row in incomingPrivacyRequestRows) {
      if (incomingPrivacyRequestNeedsBellCount(row)) {
        final key = privacyRequestBadgeKey(row);
        if (key.isNotEmpty) hubRequestKeys.add(key);
      }
    }
    for (final row in outgoingPrivacyRequestRows) {
      if (outgoingPrivacyRequestNeedsBellCount(row)) {
        final key = privacyRequestBadgeKey(row);
        if (key.isNotEmpty) hubRequestKeys.add(key);
      }
    }

    var otherUnreadNotifications = 0;
    for (final n in notifications) {
      if (!notificationIsUnread(n)) continue;
      final type = normalizeNotificationType(n['type']);
      if (hubMirroredNotificationTypes.contains(type)) continue;
      final interestId = interestIdFromNotification(n);
      if (interestId != null &&
          interestId.isNotEmpty &&
          hubInterestIds.contains(interestId)) {
        continue;
      }
      final requestId = requestDocIdFromNotification(n);
      if (requestId != null && requestId.isNotEmpty) {
        final notifRequestKey = _notificationPrivacyBadgeKey(type, requestId);
        if (notifRequestKey.isNotEmpty &&
            hubRequestKeys.contains(notifRequestKey)) {
          continue;
        }
      }
      otherUnreadNotifications++;
    }

    final inbox = messagesReceived.isEmpty
        ? unreadMessages
        : unreadInboxCountForBell(
            messagesReceived: messagesReceived,
            incomingPrivacyRequestRows: incomingPrivacyRequestRows,
            outgoingPrivacyRequestRows: outgoingPrivacyRequestRows,
          );

    return hub + inbox + otherUnreadNotifications;
  }
}
