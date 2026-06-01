import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_identity.dart';
import '../core/contract.dart';

/// Block list backed by Firestore `blocks` collection (single source of truth).
/// SharedPreferences holds a read-only cache for fast UI checks.
class BlockService extends ChangeNotifier {
  BlockService(this._prefs) {
    _instance = this;
    _loadCacheSync();
  }

  static BlockService? _instance;
  static BlockService? get instance => _instance;

  static const String _legacyPrefsKey = 'blocked_users';
  static const String _cacheKey = 'blocks_cache_v2';
  static const String _cacheBlockerKey = 'blocks_cache_blocker_doc_id';

  final SharedPreferences _prefs;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  List<BlockedUser> _blockedUsers = [];
  final Set<String> _blockedProfileIds = {};
  final Set<String> _blockedUserDocIds = {};
  final Set<String> _blockedByOthersDocIds = {};

  String? _blockerDocId;
  bool _isLoading = false;
  bool _isDataLoaded = false;
  DateTime? _lastSyncedAt;
  DateTime? _lastReportTime;

  /// After sync, cache is considered fresh for UI filtering for this duration.
  static const Duration cacheFreshTtl = Duration(minutes: 5);

  /// Injected in tests to simulate live Firestore without Firebase.init.
  @visibleForTesting
  static Future<bool> Function({
    required String actorUserDocId,
    required String peerUserDocId,
  })? liveQueryOverride;

  List<BlockedUser> get blockedUsers => List.unmodifiable(_blockedUsers);
  bool get isLoading => _isLoading;
  bool get isDataLoaded => _isDataLoaded;
  bool get isCacheFresh {
    if (!_isDataLoaded || _lastSyncedAt == null) return false;
    return DateTime.now().difference(_lastSyncedAt!) < cacheFreshTtl;
  }
  int get blockedCount => _blockedUsers.length;

  String? get blockerDocId => _blockerDocId;

  // ── Cache (performance only) ──────────────────────────────────────────────

  void _loadCacheSync() {
    try {
      _blockerDocId = _prefs.getString(_cacheBlockerKey);
      final raw = _prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _applyBlockedUsers(
        decoded
            .whereType<Map>()
            .map((e) => BlockedUser.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        loadedFromNetwork: false,
      );
      _isDataLoaded = _blockerDocId != null && _blockerDocId!.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ BlockService cache read failed: $e');
      _blockedUsers = [];
      _rebuildIdSets();
    }
  }

  Future<void> _persistCache() async {
    try {
      if (_blockerDocId != null) {
        await _prefs.setString(_cacheBlockerKey, _blockerDocId!);
      }
      await _prefs.setString(
        _cacheKey,
        jsonEncode(_blockedUsers.map((u) => u.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ BlockService cache write failed: $e');
    }
  }

  void _applyBlockedUsers(
    List<BlockedUser> users, {
    required bool loadedFromNetwork,
  }) {
    _blockedUsers = users;
    _rebuildIdSets();
    if (loadedFromNetwork) _isDataLoaded = true;
  }

  void _rebuildIdSets() {
    _blockedProfileIds
      ..clear()
      ..addAll(
        _blockedUsers.map((u) => u.profileId.trim()).where((id) => id.isNotEmpty),
      );
    _blockedUserDocIds
      ..clear()
      ..addAll(
        _blockedUsers.map((u) => u.userDocId.trim()).where((id) => id.isNotEmpty),
      );
  }

  // ── Firestore sync ────────────────────────────────────────────────────────

  /// Loads blocks from Firestore for [blockerDocId] and refreshes local cache.
  Future<void> syncFromFirestore({String? blockerDocId}) async {
    final id = (blockerDocId ?? _blockerDocId ?? IdentityProvider.userDocId).trim();
    if (id.isEmpty) {
      debugPrint('⚠️ BlockService.syncFromFirestore: empty blocker id');
      return;
    }

    _isLoading = true;
    _blockerDocId = id;
    notifyListeners();

    try {
      await _migrateLegacyPrefsToFirestore(blockerDocId: id);

      final iBlocked = await _db
          .collection('blocks')
          .where('blockerId', isEqualTo: id)
          .get();

      final blockedMe = await _db
          .collection('blocks')
          .where('blockedId', isEqualTo: id)
          .get();

      _blockedByOthersDocIds
        ..clear()
        ..addAll(
          blockedMe.docs
              .map((d) => (d.data()['blockerId'] as String? ?? '').trim())
              .where((v) => v.isNotEmpty),
        );

      final users = iBlocked.docs.map(_blockedUserFromDoc).toList();
      _applyBlockedUsers(users, loadedFromNetwork: true);
      _lastSyncedAt = DateTime.now();
      await _persistCache();
      debugPrint(
        '✅ BlockService synced: ${_blockedUsers.length} blocked, '
        '${_blockedByOthersDocIds.length} blocked-me',
      );
    } catch (e) {
      debugPrint('❌ BlockService.syncFromFirestore failed: $e');
      // Keep last cache if network fails.
      if (_blockedUsers.isNotEmpty) _isDataLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  BlockedUser _blockedUserFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final blockedDocId = (data['blockedId'] as String? ?? '').trim();
    final profileId = (data['blocked_profile_id'] as String? ??
            data['blockedProfileId'] as String? ??
            '')
        .trim();
    final name = (data['blocked_name'] as String? ??
            data['name'] as String? ??
            'Member')
        .trim();
    final photo = (data['blocked_photo'] as String? ?? data['photo'] as String?)
        ?.trim();
    final reason = (data['reason'] as String?)?.trim();
    final blockedAt = data['blockedAt'];
    final at = blockedAt is Timestamp
        ? blockedAt.toDate()
        : DateTime.tryParse('$blockedAt') ?? DateTime.now();

    return BlockedUser(
      firestoreDocId: doc.id,
      userDocId: blockedDocId.isNotEmpty ? blockedDocId : profileId,
      profileId: profileId.isNotEmpty ? profileId : blockedDocId,
      name: name.isEmpty ? 'Member' : name,
      photo: photo?.isEmpty == true ? null : photo,
      reason: reason?.isEmpty == true ? null : reason,
      blockedAt: at,
    );
  }

  Future<void> _migrateLegacyPrefsToFirestore({required String blockerDocId}) async {
    final legacyRaw = _prefs.getString(_legacyPrefsKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return;

    try {
      final decoded = jsonDecode(legacyRaw);
      if (decoded is! List) return;

      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final profileId =
            (map['profile_id'] as String? ?? map['profileId'] as String? ?? '')
                .trim();
        if (profileId.isEmpty) continue;

        var blockedDocId = await _resolveDocIdFromProfileId(profileId);
        if (blockedDocId.isEmpty) blockedDocId = profileId;

        await _writeBlockDoc(
          blockerDocId: blockerDocId,
          blockedDocId: blockedDocId,
          profileId: profileId,
          name: (map['name'] as String? ?? 'Member').trim(),
          photo: map['photo'] as String?,
          reason: map['reason'] as String?,
        );
      }

      await _prefs.remove(_legacyPrefsKey);
      debugPrint('✅ BlockService: migrated legacy prefs blocks to Firestore');
    } catch (e) {
      debugPrint('⚠️ BlockService legacy migration failed: $e');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  bool isBlocked(String profileOrUserId) {
    final id = profileOrUserId.trim();
    if (id.isEmpty) return false;
    return _blockedProfileIds.contains(id) || _blockedUserDocIds.contains(id);
  }

  /// Cache-only. Use for discover/matches filtering and UI — not for writes.
  bool isEitherBlocked({
    required String peerUserDocId,
    String? peerProfileId,
  }) {
    final uid = peerUserDocId.trim();
    final pid = (peerProfileId ?? '').trim();
    if (isBlocked(uid) || (pid.isNotEmpty && isBlocked(pid))) return true;
    if (uid.isNotEmpty && _blockedByOthersDocIds.contains(uid)) return true;
    return false;
  }

  /// Always queries Firestore (never cache-only). Refreshes cache on block hit.
  static Future<bool> verifyEitherBlockedLive({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) async {
    final blocked = await _queryFirestoreEitherBlocked(
      actorUserDocId: actorUserDocId,
      peerUserDocId: peerUserDocId,
    );
    if (blocked && liveQueryOverride == null) {
      final svc = instance;
      final actor = actorUserDocId.trim();
      if (svc != null && actor.isNotEmpty) {
        // Refresh cache so UI filtering catches up after a live block hit.
        // ignore: discarded_futures
        svc.syncFromFirestore(blockerDocId: actor);
      }
    }
    return blocked;
  }

  /// Prefer [verifyEitherBlockedLive] for security-sensitive paths.
  @Deprecated('Use verifyEitherBlockedLive for sends/chat/profile open')
  static Future<bool> queryEitherBlocked({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      verifyEitherBlockedLive(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  static Future<bool> _queryFirestoreEitherBlocked({
    required String actorUserDocId,
    required String peerUserDocId,
  }) async {
    final actor = actorUserDocId.trim();
    final peer = peerUserDocId.trim();
    if (actor.isEmpty || peer.isEmpty) return false;
    if (liveQueryOverride != null) {
      return liveQueryOverride!(
        actorUserDocId: actor,
        peerUserDocId: peer,
      );
    }
    try {
      final db = FirebaseFirestore.instance;
      final a = await db
          .collection('blocks')
          .where('blockerId', isEqualTo: actor)
          .where('blockedId', isEqualTo: peer)
          .limit(1)
          .get();
      if (a.docs.isNotEmpty) return true;
      final b = await db
          .collection('blocks')
          .where('blockerId', isEqualTo: peer)
          .where('blockedId', isEqualTo: actor)
          .limit(1)
          .get();
      return b.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<String> getBlockedProfileIds() =>
      _blockedProfileIds.toList(growable: false);

  List<String> getBlockedUserDocIds() =>
      _blockedUserDocIds.toList(growable: false);

  Set<String> get allBlockedPeerIds => {
        ..._blockedProfileIds,
        ..._blockedUserDocIds,
        ..._blockedByOthersDocIds,
      };

  Future<void> blockUser({
    required String profileId,
    required String name,
    String? photo,
    String? reason,
    String? userDocId,
  }) async {
    final blockerId = (_blockerDocId ?? IdentityProvider.userDocId).trim();
    if (blockerId.isEmpty) {
      throw Exception('Sign in required to block a member');
    }

    var blockedDocId = (userDocId ?? '').trim();
    final pid = profileId.trim();
    if (blockedDocId.isEmpty && pid.isNotEmpty) {
      blockedDocId = await _resolveDocIdFromProfileId(pid);
    }
    if (blockedDocId.isEmpty) blockedDocId = pid;
    if (blockedDocId.isEmpty) {
      throw Exception('Invalid member id for block');
    }

    if (await verifyEitherBlockedLive(
      actorUserDocId: blockerId,
      peerUserDocId: blockedDocId,
      peerProfileId: pid,
    )) {
      return;
    }

    final docId = await _writeBlockDoc(
      blockerDocId: blockerId,
      blockedDocId: blockedDocId,
      profileId: pid.isNotEmpty ? pid : blockedDocId,
      name: name,
      photo: photo,
      reason: reason,
    );

    final entry = BlockedUser(
      firestoreDocId: docId,
      userDocId: blockedDocId,
      profileId: pid.isNotEmpty ? pid : blockedDocId,
      name: name,
      photo: photo,
      reason: reason,
      blockedAt: DateTime.now(),
    );

    _blockedUsers.removeWhere(
      (u) =>
          u.profileId == entry.profileId ||
          u.userDocId == entry.userDocId,
    );
    _blockedUsers.add(entry);
    _rebuildIdSets();
    await _persistCache();
    notifyListeners();

    await _cleanupInterestsBetween(blockerId, blockedDocId);
  }

  Future<void> unblockUser(String profileOrUserId) async {
    final blockerId = (_blockerDocId ?? IdentityProvider.userDocId).trim();
    if (blockerId.isEmpty) return;

    final target = profileOrUserId.trim();
    if (target.isEmpty) return;

    final snap = await _db
        .collection('blocks')
        .where('blockerId', isEqualTo: blockerId)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final blockedId = (data['blockedId'] as String? ?? '').trim();
      final blockedProfile = (data['blocked_profile_id'] as String? ?? '').trim();
      if (blockedId == target ||
          blockedProfile == target ||
          _blockedUsers.any(
            (u) =>
                (u.profileId == target || u.userDocId == target) &&
                (u.firestoreDocId == doc.id ||
                    u.userDocId == blockedId ||
                    u.profileId == blockedProfile),
          )) {
        await doc.reference.delete();
      }
    }

    _blockedUsers.removeWhere(
      (u) => u.profileId == target || u.userDocId == target,
    );
    _rebuildIdSets();
    await _persistCache();
    notifyListeners();
  }

  Future<void> clearAllBlocked() async {
    final blockerId = (_blockerDocId ?? IdentityProvider.userDocId).trim();
    if (blockerId.isEmpty) return;

    final snap = await _db
        .collection('blocks')
        .where('blockerId', isEqualTo: blockerId)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }

    _blockedUsers.clear();
    _rebuildIdSets();
    await _persistCache();
    notifyListeners();
  }

  /// Clears cache on logout (Firestore remains source of truth).
  Future<void> clearOnLogout() async {
    _blockerDocId = null;
    _blockedUsers.clear();
    _blockedProfileIds.clear();
    _blockedUserDocIds.clear();
    _blockedByOthersDocIds.clear();
    _isDataLoaded = false;
    await _prefs.remove(_cacheKey);
    await _prefs.remove(_cacheBlockerKey);
    notifyListeners();
  }

  // ── Firestore writes ──────────────────────────────────────────────────────

  Future<String> _writeBlockDoc({
    required String blockerDocId,
    required String blockedDocId,
    required String profileId,
    required String name,
    String? photo,
    String? reason,
  }) async {
    final docId = '${blockerDocId}_$blockedDocId';
    await _db.collection('blocks').doc(docId).set({
      'blockerId': blockerDocId,
      'blockedId': blockedDocId,
      'blocked_profile_id': profileId,
      'blocked_name': name,
      if (photo != null && photo.isNotEmpty) 'blocked_photo': photo,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'blockedAt': FieldValue.serverTimestamp(),
    });
    return docId;
  }

  Future<String> _resolveDocIdFromProfileId(String profileId) async {
    final pid = profileId.trim();
    if (pid.isEmpty) return '';
    try {
      final byProfile = await _db
          .collection(Collections.users)
          .where('profile_id', isEqualTo: pid)
          .limit(1)
          .get();
      if (byProfile.docs.isNotEmpty) return byProfile.docs.first.id;
      final direct = await _db.collection(Collections.users).doc(pid).get();
      if (direct.exists) return direct.id;
    } catch (e) {
      debugPrint('⚠️ BlockService resolve doc id: $e');
    }
    return '';
  }

  Future<void> _cleanupInterestsBetween(String userA, String userB) async {
    final pair = <String>{userA, userB};
    try {
      for (final id in [userA, userB]) {
        final sent = await _db
            .collection(Collections.interests)
            .where(Fields.fromUserId, isEqualTo: id)
            .get();
        for (final doc in sent.docs) {
          final to = (doc.data()[Fields.toUserId] as String? ?? '').trim();
          if (pair.contains(to)) await doc.reference.delete();
        }
        final received = await _db
            .collection(Collections.interests)
            .where(Fields.toUserId, isEqualTo: id)
            .get();
        for (final doc in received.docs) {
          final from =
              (doc.data()[Fields.fromUserId] as String? ?? '').trim();
          if (pair.contains(from)) await doc.reference.delete();
        }
      }
    } catch (e) {
      debugPrint('⚠️ BlockService interest cleanup: $e');
    }
  }

  // ── Reports (unchanged) ───────────────────────────────────────────────────

  bool _canSubmitReport() {
    if (_lastReportTime == null) return true;
    return DateTime.now().difference(_lastReportTime!) >=
        const Duration(seconds: 30);
  }

  Future<void> reportUser({
    required String reportedId,
    required String reason,
    String? details,
    String? reporterId,
  }) async {
    if (!_canSubmitReport()) {
      throw Exception('Please wait 30 seconds between reports');
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final actualReporterId = reporterId ?? currentUser?.uid ?? 'anonymous';
    if (actualReporterId == 'anonymous') {
      throw Exception('You must be logged in to submit a report');
    }

    _lastReportTime = DateTime.now();

    await _db.collection('reports').add({
      'reportedId': reportedId,
      'reporterId': actualReporterId,
      'reason': reason,
      'details': details,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
      'isAdminReport': actualReporterId.startsWith('admin_'),
    });
  }

  // ── Testing ───────────────────────────────────────────────────────────────

  @visibleForTesting
  Future<void> seedForTests({
    required String blockerDocId,
    required List<BlockedUser> users,
    Set<String> blockedByOthers = const {},
  }) async {
    _blockerDocId = blockerDocId;
    _blockedByOthersDocIds
      ..clear()
      ..addAll(blockedByOthers);
    _applyBlockedUsers(users, loadedFromNetwork: true);
    await _persistCache();
  }
}

/// Model for a blocked member (cache + UI).
class BlockedUser {
  final String firestoreDocId;
  final String userDocId;
  final String profileId;
  final String name;
  final String? photo;
  final String? reason;
  final DateTime blockedAt;

  BlockedUser({
    this.firestoreDocId = '',
    required this.userDocId,
    required this.profileId,
    required this.name,
    this.photo,
    this.reason,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      firestoreDocId: json['firestore_doc_id'] as String? ?? '',
      userDocId: (json['user_doc_id'] as String? ??
              json['profile_id'] as String? ??
              '')
          .trim(),
      profileId: (json['profile_id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? 'Member').trim(),
      photo: json['photo'] as String?,
      reason: json['reason'] as String?,
      blockedAt:
          DateTime.tryParse(json['blockedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (firestoreDocId.isNotEmpty) 'firestore_doc_id': firestoreDocId,
      'user_doc_id': userDocId,
      'profile_id': profileId,
      'name': name,
      'photo': photo,
      'reason': reason,
      'blockedAt': blockedAt.toIso8601String(),
    };
  }
}
