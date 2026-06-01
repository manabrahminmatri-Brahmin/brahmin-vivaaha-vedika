import '../core/interest_badge_aggregator.dart';

/// Canonical identity + field resolution for interest hub rows and access requests.
abstract final class InterestIdentityResolver {
  InterestIdentityResolver._();

  static const String unknownMember = 'Unknown Member';
  static const String locationUnavailable = 'Location unavailable';
  static const String ageUnavailable = '--';

  // ── Interest document ─────────────────────────────────────────────────────

  static String interestDocumentId(Map<String, dynamic> row) =>
      InterestBadgeAggregator.interestDocumentId(row);

  /// Repairs legacy docs missing explicit ids / snapshot keys (client-side only).
  static Map<String, dynamic> normalizeInterestRow(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    final docId = interestDocumentId(out);
    if (docId.contains('_')) {
      final parts = docId.split('_');
      if (parts.length >= 2) {
        out.putIfAbsent('from_user_id', () => parts.first.trim());
        out.putIfAbsent('to_user_id', () => parts.sublist(1).join('_').trim());
      }
    }
    out.putIfAbsent('id', () => docId.isNotEmpty ? docId : out['id']);
    out.putIfAbsent('interestId', () => out['id']);
    return out;
  }

  static bool isReceivedInterest(
    Map<String, dynamic> row,
    Iterable<String> myUserIds,
  ) {
    final to = _firstNonEmpty([
      _s(row, 'to_user_id'),
      _s(row, 'toUserId'),
    ]);
    if (to.isEmpty) return false;
    return myUserIds.any((id) => id.trim() == to);
  }

  // ── Peer fields (interest rows) ─────────────────────────────────────────

  static String peerUserId(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    if (isReceived) {
      return _firstNonEmpty([
        _s(row, 'from_user_id'),
        _s(row, 'fromUserId'),
        _s(row, 'target_user_id'),
      ]);
    }
    return _firstNonEmpty([
      _s(row, 'to_user_id'),
      _s(row, 'toUserId'),
      _s(row, 'target_user_id'),
    ]);
  }

  static String peerProfileId(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    if (isReceived) {
      return _firstNonEmpty([
        _s(row, 'from_profile_id'),
        _s(row, 'fromProfileId'),
        _s(row, 'target_profile_id'),
        _s(row, 'profile_id'),
        _s(row, 'profileId'),
      ]);
    }
    return _firstNonEmpty([
      _s(row, 'to_profile_id'),
      _s(row, 'toProfileId'),
      _s(row, 'target_profile_id'),
      _s(row, 'profile_id'),
      _s(row, 'profileId'),
    ]);
  }

  static String peerFirstName(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    if (isReceived) {
      return _firstNonEmpty([
        _s(row, 'from_first_name'),
        _s(row, 'target_first_name'),
        _s(row, 'first_name'),
        _s(row, 'firstName'),
      ]);
    }
    return _firstNonEmpty([
      _s(row, 'to_first_name'),
      _s(row, 'target_first_name'),
      _s(row, 'first_name'),
      _s(row, 'firstName'),
    ]);
  }

  static String peerLastName(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    if (isReceived) {
      return _firstNonEmpty([
        _s(row, 'from_last_name'),
        _s(row, 'target_last_name'),
        _s(row, 'last_name'),
        _s(row, 'lastName'),
      ]);
    }
    return _firstNonEmpty([
      _s(row, 'to_last_name'),
      _s(row, 'target_last_name'),
      _s(row, 'last_name'),
      _s(row, 'lastName'),
    ]);
  }

  static String peerDisplayName(
    Map<String, dynamic> row, {
    required bool isReceived,
    String? liveFullName,
  }) {
    final live = (liveFullName ?? '').trim();
    if (live.isNotEmpty) return live;
    final fn = peerFirstName(row, isReceived: isReceived);
    final ln = peerLastName(row, isReceived: isReceived);
    final both = '$fn $ln'.trim();
    if (both.isNotEmpty && both.toLowerCase() != 'member') return both;
    final pid = peerProfileId(row, isReceived: isReceived);
    if (pid.isNotEmpty) return 'Profile $pid';
    return unknownMember;
  }

  static bool hasResolvableIdentity(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    final name = peerDisplayName(row, isReceived: isReceived);
    if (name != unknownMember) return true;
    return peerProfileId(row, isReceived: isReceived).isNotEmpty ||
        peerUserId(row, isReceived: isReceived).isNotEmpty;
  }

  /// Snapshot URL stored on interest doc — must NOT bypass photo privacy in UI.
  static String? snapshotPhotoUrl(
    Map<String, dynamic> row, {
    required bool isReceived,
  }) {
    final raw = isReceived
        ? _firstNonEmpty([
            _s(row, 'from_photo_url'),
            _s(row, 'target_photo_url'),
            _s(row, 'photo_url'),
            _s(row, 'photoUrl'),
          ])
        : _firstNonEmpty([
            _s(row, 'to_photo_url'),
            _s(row, 'target_photo_url'),
            _s(row, 'photo_url'),
            _s(row, 'photoUrl'),
          ]);
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }

  static int peerAgeFromRow(
    Map<String, dynamic> row, {
    required bool isReceived,
    int liveAge = 0,
  }) {
    if (liveAge > 0) return liveAge;
    final key = isReceived ? 'from_age' : 'to_age';
    final raw = row[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  static String peerAgeText(
    Map<String, dynamic> row, {
    required bool isReceived,
    int liveAge = 0,
  }) {
    final age = peerAgeFromRow(row, isReceived: isReceived, liveAge: liveAge);
    return age > 0 ? '$age yrs' : ageUnavailable;
  }

  static String peerCity(
    Map<String, dynamic> row, {
    required bool isReceived,
    String? liveCity,
  }) {
    final live = (liveCity ?? '').trim();
    if (live.isNotEmpty) return live;
    final key = isReceived ? 'from_city' : 'to_city';
    return _s(row, key);
  }

  static String peerState(
    Map<String, dynamic> row, {
    required bool isReceived,
    String? liveState,
  }) {
    final live = (liveState ?? '').trim();
    if (live.isNotEmpty) return live;
    final key = isReceived ? 'from_state' : 'to_state';
    return _s(row, key);
  }

  static String peerLocationText(
    Map<String, dynamic> row, {
    required bool isReceived,
    String? liveCity,
    String? liveState,
  }) {
    final city = peerCity(row, isReceived: isReceived, liveCity: liveCity);
    final state = peerState(row, isReceived: isReceived, liveState: liveState);
    if (city.isNotEmpty && state.isNotEmpty) return '$city, $state';
    if (city.isNotEmpty) return city;
    if (state.isNotEmpty) return state;
    final loc = _s(row, 'location');
    return loc.isNotEmpty ? loc : locationUnavailable;
  }

  // ── Access requests (birth / community / photo) ───────────────────────────

  static String accessRequestDocumentId(Map<String, dynamic> row) =>
      _firstNonEmpty([_s(row, 'id'), _s(row, 'request_id'), _s(row, 'requestId')]);

  static String accessRequesterUserId(Map<String, dynamic> row) =>
      _firstNonEmpty([
        _s(row, 'requester_id'),
        _s(row, 'requesterId'),
        _s(row, 'from_user_id'),
        _s(row, 'fromUserId'),
      ]);

  static String accessOwnerUserId(Map<String, dynamic> row) {
    var owner = _firstNonEmpty([
      _s(row, 'owner_id'),
      _s(row, 'ownerId'),
      _s(row, 'to_user_id'),
      _s(row, 'toUserId'),
    ]);
    if (owner.isEmpty) {
      final id = accessRequestDocumentId(row);
      if (id.contains('_')) {
        final parts = id.split('_');
        if (parts.length >= 2) {
          owner = parts.sublist(1).join('_').trim();
        }
      }
    }
    return owner;
  }

  static String accessRequesterDisplayName(Map<String, dynamic> row) {
    final fn = _firstNonEmpty([
      _s(row, 'from_first_name'),
      _s(row, 'requester_first_name'),
    ]);
    final ln = _firstNonEmpty([
      _s(row, 'from_last_name'),
      _s(row, 'requester_last_name'),
    ]);
    final both = '$fn $ln'.trim();
    if (both.isNotEmpty) return both;
    final name = _firstNonEmpty([
      _s(row, 'requester_name'),
      _s(row, 'from_name'),
    ]);
    if (name.isNotEmpty) return name;
    final pid = _firstNonEmpty([
      _s(row, 'requester_profile_id'),
      _s(row, 'from_profile_id'),
    ]);
    if (pid.isNotEmpty) return 'Profile $pid';
    return accessRequesterUserId(row).isNotEmpty ? unknownMember : unknownMember;
  }

  static String _s(Map<String, dynamic> row, String key) =>
      (row[key] as String? ?? '').trim();

  static String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }
}
