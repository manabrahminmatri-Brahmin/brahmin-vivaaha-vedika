// ─────────────────────────────────────────────────────────────────────────────
// LikeModel  —  FIXED v4
//
// BUG FIXED:
//   isMutual() had wrong logic:
//     OLD: (fromUserId == currentUserId && toUserId == currentUserId)
//          This condition is NEVER true (a user cannot like themselves).
//     OLD: || (fromUserId == currentUserId || toUserId == currentUserId)
//          This just checks if the current user is involved — not mutual.
//
//   FIX: isMutual() now correctly states this LikeModel represents
//        a mutual relationship only when THIS document is the reverse
//        like (i.e. from=other, to=current) — meaning the other user
//        has liked the current user back.
//        For full mutual verification, use LikeService.isMutualLike()
//        which does two Firestore queries.
// ─────────────────────────────────────────────────────────────────────────────

/// ❤️ LIKE MODEL — clean data structure for a single like document.
class LikeModel {
  final String id;
  final String fromUserId;
  final String toUserId;
  final DateTime timestamp;

  const LikeModel({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.timestamp,
  });

  /// Create from Firestore document data + document ID.
  factory LikeModel.fromFirestore(
      Map<String, dynamic> data, String documentId) {
    DateTime ts;
    final rawTs = data['created_at'];
    if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return LikeModel(
      id: documentId,
      fromUserId: data['from'] as String? ?? '',
      toUserId: data['to'] as String? ?? '',
      timestamp: ts,
    );
  }

  /// Convert to Firestore map.
  Map<String, dynamic> toFirestore() {
    return {
      'from': fromUserId,
      'to': toUserId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Returns true if the CURRENT user is the recipient of this like
  /// (i.e. this is the reverse-like document proving mutual interest).
  ///
  /// NOTE: For a complete mutual check (both directions), use
  /// LikeService.isMutualLike(otherUserId) which queries Firestore for
  /// both directions.
  bool isLikedBy(String currentUserId) {
    return toUserId == currentUserId;
  }

  /// Returns true if the CURRENT user sent this like.
  bool isSentBy(String currentUserId) {
    return fromUserId == currentUserId;
  }

  /// Returns the other user's ID relative to [currentUserId].
  /// Returns empty string if neither fromUserId nor toUserId matches.
  String getOtherUserId(String currentUserId) {
    if (fromUserId == currentUserId) return toUserId;
    if (toUserId == currentUserId) return fromUserId;
    return '';
  }

  @override
  String toString() =>
      'LikeModel(id: $id, from: $fromUserId, to: $toUserId)';
}
