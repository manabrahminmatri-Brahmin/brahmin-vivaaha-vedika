import 'interest_badge_aggregator.dart';

/// In-memory hub cache: Firestore stream snapshots + optimistic UI overlay.
///
/// Firestore snapshots are stored **unfiltered** in [_sent] / [_received].
/// Optimistic hides apply only when reading [sent], [received], [visibleSent],
/// or [visibleReceived] so failed withdraw/decline can restore instantly.
class InterestHubCache {
  List<Map<String, dynamic>> _sent = const [];
  List<Map<String, dynamic>> _received = const [];
  final Set<String> _optimisticHiddenIds = <String>{};
  int _revision = 0;

  int get revision => _revision;
  List<Map<String, dynamic>> get sent => _applyOptimisticHiddenFilter(_sent);
  List<Map<String, dynamic>> get received =>
      _applyOptimisticHiddenFilter(_received);

  /// Rows for Sent tab / sent badges (deduped, visible status, not optimistically hidden).
  List<Map<String, dynamic>> get visibleSent =>
      InterestBadgeAggregator.hubVisibleInterestRows(_sent).where(_isNotHidden).toList();

  /// Rows for Received tab / received badges.
  List<Map<String, dynamic>> get visibleReceived =>
      InterestBadgeAggregator.hubVisibleInterestRows(_received)
          .where(_isNotHidden)
          .toList();

  void clear() {
    _sent = const [];
    _received = const [];
    _optimisticHiddenIds.clear();
    _revision++;
  }

  Map<String, dynamic>? findRow(String docId) {
    final id = docId.trim();
    if (id.isEmpty) return null;
    for (final row in [..._sent, ..._received]) {
      if (InterestBadgeAggregator.interestRowMatchesDocId(row, id)) {
        return row;
      }
    }
    return null;
  }

  void applySentSnapshot(List<Map<String, dynamic>> rows) {
    _sent = _mergeSnapshotWithPendingLocal(
      previous: _sent,
      incoming: rows,
    );
    _revision++;
  }

  void applyReceivedSnapshot(List<Map<String, dynamic>> rows) {
    _received = _mergeSnapshotWithPendingLocal(
      previous: _received,
      incoming: rows,
    );
    _revision++;
  }

  /// Keeps freshly sent rows visible until Firestore streams include them.
  List<Map<String, dynamic>> _mergeSnapshotWithPendingLocal({
    required List<Map<String, dynamic>> previous,
    required List<Map<String, dynamic>> incoming,
  }) {
    final mergedIncoming = InterestBadgeAggregator.dedupeInterestRows(incoming);
    final incomingIds = mergedIncoming
        .map(InterestBadgeAggregator.interestDocumentId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final preserved = <Map<String, dynamic>>[];
    for (final row in previous) {
      if (!_isPendingFirestoreSync(row)) continue;
      final id = InterestBadgeAggregator.interestDocumentId(row);
      if (id.isEmpty || incomingIds.contains(id)) continue;
      if (_pendingSyncExpired(row)) continue;
      preserved.add(row);
    }

    if (preserved.isEmpty) return mergedIncoming;
    return InterestBadgeAggregator.dedupeInterestRows([
      ...preserved,
      ...mergedIncoming,
    ]);
  }

  static bool _isPendingFirestoreSync(Map<String, dynamic> row) =>
      row['_pendingFirestoreSync'] == true;

  static bool _pendingSyncExpired(Map<String, dynamic> row) {
    final raw = row['_pendingUntil'];
    if (raw is! String || raw.trim().isEmpty) return false;
    final until = DateTime.tryParse(raw.trim());
    if (until == null) return false;
    return DateTime.now().isAfter(until);
  }

  void upsertSentLocal({
    required String interestId,
    required String fromUserId,
    required String toUserId,
    String status = 'pending',
    Map<String, dynamic>? extra,
  }) {
    final id = interestId.trim();
    final from = fromUserId.trim();
    final to = toUserId.trim();
    if (id.isEmpty || from.isEmpty || to.isEmpty) return;

    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final pendingUntil =
        now.add(const Duration(minutes: 3)).toIso8601String();
    final row = <String, dynamic>{
      'id': id,
      'interestId': id,
      'interest_id': id,
      'from_user_id': from,
      'to_user_id': to,
      'status': status,
      'created_at': nowIso,
      'updated_at': nowIso,
      '_pendingFirestoreSync': true,
      '_pendingUntil': pendingUntil,
      if (extra != null) ...extra,
    };

    final list = List<Map<String, dynamic>>.from(_sent);
    final idx = list.indexWhere(
      (r) => InterestBadgeAggregator.interestRowMatchesDocId(r, id),
    );
    if (idx >= 0) {
      list[idx] = {...list[idx], ...row};
    } else {
      list.insert(0, row);
    }
    applySentSnapshot(list);
    pruneOptimisticHidden();
  }

  void optimisticHide(String docId, {Map<String, dynamic>? rowHint}) {
    final ids = InterestBadgeAggregator.resolveOptimisticHideIds(
      docId,
      rowHint: rowHint,
    );
    if (ids.isEmpty) return;
    var changed = false;
    for (final id in ids) {
      if (_optimisticHiddenIds.add(id)) changed = true;
    }
    if (changed) _revision++;
  }

  void restoreHide(String docId, {Map<String, dynamic>? rowHint}) {
    final ids = InterestBadgeAggregator.resolveOptimisticHideIds(
      docId,
      rowHint: rowHint,
    );
    if (ids.isEmpty) return;
    var changed = false;
    for (final id in ids) {
      if (_optimisticHiddenIds.remove(id)) changed = true;
    }
    if (changed) _revision++;
  }

  /// Drop optimistic hides once Firestore confirms withdrawal or row is gone.
  void pruneOptimisticHidden() {
    if (_optimisticHiddenIds.isEmpty) return;
    final toRemove = <String>[];
    for (final hid in _optimisticHiddenIds) {
      final row = findRow(hid);
      if (row == null) {
        toRemove.add(hid);
        continue;
      }
      if (!InterestBadgeAggregator.isInterestRowVisible(row['status'])) {
        toRemove.add(hid);
      }
    }
    if (toRemove.isEmpty) return;
    for (final id in toRemove) {
      _optimisticHiddenIds.remove(id);
    }
    _revision++;
  }

  bool _isNotHidden(Map<String, dynamic> row) =>
      !InterestBadgeAggregator.interestRowMatchesAnyHiddenId(
        row,
        _optimisticHiddenIds,
      );

  List<Map<String, dynamic>> _applyOptimisticHiddenFilter(
    List<Map<String, dynamic>> rows,
  ) {
    if (_optimisticHiddenIds.isEmpty) return rows;
    return rows.where(_isNotHidden).toList();
  }
}
