/// Canonical privacy access request statuses (photo, birth, community).
class AccessRequestStatus {
  AccessRequestStatus._();

  static const pending = 'pending';
  static const granted = 'granted';
  static const denied = 'denied';
  static const revoked = 'revoked';
  static const stopped = 'stopped';
  static const withdrawn = 'withdrawn';

  /// Normalize legacy server/client values to canonical statuses.
  static String normalize(dynamic raw) {
    final s = (raw as String? ?? pending).trim().toLowerCase();
    if (s.isEmpty) return pending;
    if (s == 'approved' || s == 'accepted') return granted;
    if (s == 'rejected' || s == 'declined') return denied;
    return s;
  }

  static bool isGranted(String normalized) => normalized == granted;

  static bool isSettled(String normalized) =>
      normalized != pending && normalized != withdrawn;

  /// Owner-side incoming listeners (birth / community).
  static const List<String> ownerIncomingWhereIn = [
    pending,
    granted,
    revoked,
    stopped,
    denied,
    'accepted',
    'approved',
  ];

  /// Owner-side incoming photo listeners (includes legacy aliases).
  static const List<String> photoOwnerIncomingWhereIn = [
    pending,
    granted,
    revoked,
    stopped,
    denied,
    'accepted',
    'approved',
    'rejected',
    'declined',
  ];
}
