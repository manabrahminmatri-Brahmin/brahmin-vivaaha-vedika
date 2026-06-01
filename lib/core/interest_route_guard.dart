/// Route-level dismissal for profiles opened with [routeGuardInterestDocId].
///
/// Interest rows can briefly be absent until [InterestService] streams hydrate —
/// callers must pass whether the matching row has been observed at least once
/// ([hasPreviouslySeenInterestRow]) before treating "missing" as withdrawn/deleted.
class InterestRouteGuard {
  InterestRouteGuard._();

  static String _rowDocId(Map<String, dynamic> row) {
    return (row['id'] ?? row['interest_id'] ?? row['interestId'] ?? '')
        .toString()
        .trim();
  }

  static Map<String, dynamic>? _findRowByInterestDocId(
    Iterable<Map<String, dynamic>> rows,
    String interestDocId,
  ) {
    final needle = interestDocId.trim();
    if (needle.isEmpty) return null;
    for (final m in rows) {
      if (_rowDocId(m) == needle) return m;
    }
    return null;
  }

  /// First non-null occurrence of [interestDocId] in sent / received pools.
  static Map<String, dynamic>? findInterestRowAcrossPools({
    required String interestDocId,
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> interestsReceived,
  }) {
    final id = interestDocId.trim();
    if (id.isEmpty) return null;
    return _findRowByInterestDocId(interestsSent, id) ??
        _findRowByInterestDocId(interestsReceived, id);
  }

  static bool _isTerminalStatus(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'withdrawn':
      case 'inactive':
      case 'deleted':
        return true;
      default:
        return false;
    }
  }

  /// Profile route (~ [Navigator.maybePop]) should dismiss when the interest hits
  /// a terminal status, **or** it disappears after we had observed it ([hasPreviouslySeenInterestRow]).
  static bool shouldPopProfileForInterestDoc({
    required String interestDocId,
    required Iterable<Map<String, dynamic>> interestsSent,
    required Iterable<Map<String, dynamic>> interestsReceived,
    required bool hasPreviouslySeenInterestRow,
  }) {
    final id = interestDocId.trim();
    if (id.isEmpty) return false;

    final row = findInterestRowAcrossPools(
      interestDocId: id,
      interestsSent: interestsSent,
      interestsReceived: interestsReceived,
    );

    if (row != null && _isTerminalStatus(row['status'] as String?)) {
      return true;
    }
    return row == null && hasPreviouslySeenInterestRow;
  }
}
