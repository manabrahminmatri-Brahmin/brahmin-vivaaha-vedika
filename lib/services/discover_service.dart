import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/profile_completion_policy.dart';
import '../core/contract.dart';
import '../utils/firestore_cache_read.dart';
import '../models/discover_profile_vm.dart';
import '../models/gender.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/discovery_scheduler_service.dart';
import '../services/match_ranking_service.dart';
import '../services/privacy_enforcement_service.dart';
import '../services/security/profile_photo_proxy_service.dart';
import '../services/star_compatibility_service.dart';

class DiscoverService {
  final FirebaseFirestore _db;
  final AuthService _authService;
  final BlockService _blockService;
  final MatchRankingService _rankingService;
  final DiscoverySchedulerService _schedulerService;
  final PrivacyEnforcementService _privacyService;

  /// 3D Discover: only pairs at or above this Ashtakoot % (18/36 ≈ 50% traditional minimum).
  static const double kDiscover3dMinAshtakootPercent = 50.0;

  DocumentSnapshot<Map<String, dynamic>>? _lastDiscoverDoc;
  bool _hasMore = true;
  final Set<String> _seenUserIds = <String>{};

  /// With server-side gender + is_deleted, most fetched docs are eligible — keep
  /// overfetch modest (was 4× / min 48 → 48 reads per 12 cards).
  static const int _kDiscoverOverfetchFactor = 2;
  static const int _kDiscoverFetchMin = 20;
  static const int _kDiscoverFetchMax = 80;

  int _discoverFetchSize(int pageLimit) =>
      (pageLimit * _kDiscoverOverfetchFactor)
          .clamp(_kDiscoverFetchMin, _kDiscoverFetchMax);

  /// Prefer opposite-gender + active users (requires composite index); fall back
  /// to legacy broad queries if index or rules block the optimized path.
  Future<QuerySnapshot<Map<String, dynamic>>> _discoverUsersPage({
    required Gender oppositeGender,
    required DocumentSnapshot<Map<String, dynamic>>? startAfter,
    required int fetchSize,
  }) async {
    final opposite = oppositeGender.genderName;

    Query<Map<String, dynamic>> genderedActiveQuery() {
      var q = _db
          .collection(Collections.users)
          .where('gender', isEqualTo: opposite)
          .where('is_deleted', isEqualTo: false)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      return q;
    }

    Query<Map<String, dynamic>> activeQuery() {
      var q = _db
          .collection(Collections.users)
          .where('is_deleted', isEqualTo: false)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      return q;
    }

    Query<Map<String, dynamic>> anyQuery() {
      var q = _db
          .collection(Collections.users)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      return q;
    }

    try {
      return await genderedActiveQuery().get();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' ||
          e.code == 'permission-denied') {
        debugPrint(
          '⚠️ DiscoverService gendered fetch: ${e.code} — falling back to broad active query',
        );
        try {
          return await activeQuery().get();
        } on FirebaseException catch (e2) {
          if (e2.code == 'failed-precondition' ||
              e2.code == 'permission-denied') {
            debugPrint(
              '⚠️ DiscoverService broad fetch: ${e2.code} — retry without is_deleted',
            );
            return await anyQuery().get();
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  DiscoverService({
    FirebaseFirestore? firestore,
    required AuthService authService,
    required BlockService blockService,
    MatchRankingService? rankingService,
    DiscoverySchedulerService? schedulerService,
    PrivacyEnforcementService? privacyService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _authService = authService,
        _blockService = blockService,
        _rankingService = rankingService ?? MatchRankingService(),
        _schedulerService = schedulerService ?? DiscoverySchedulerService(),
        _privacyService = privacyService ?? PrivacyEnforcementService();

  bool get hasMore => _hasMore;

  Future<bool> canManualRefresh() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return false;
    return _schedulerService.canManualRefresh(currentUser.id);
  }

  Future<void> markManualRefreshUsed() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;
    await _schedulerService.markManualRefresh(currentUser.id);
  }

  void resetPagination() {
    _lastDiscoverDoc = null;
    _hasMore = true;
    _seenUserIds.clear();
  }

  Future<List<DiscoverProfileVm>> getDiscoverProfiles({int limit = 12}) async {
    if (!_hasMore) return const <DiscoverProfileVm>[];

    final currentUser = _authService.currentUser;
    if (currentUser == null) return const <DiscoverProfileVm>[];

    final myGender = await _resolveMyGender(currentUser);
    if (myGender == null) return const <DiscoverProfileVm>[];

    final fetchSize = _discoverFetchSize(limit);
    final oppositeGender = myGender.opposite;
    final snap = await _discoverUsersPage(
      oppositeGender: oppositeGender,
      startAfter: _lastDiscoverDoc,
      fetchSize: fetchSize,
    );

    if (snap.docs.isEmpty) {
      _hasMore = false;
      return const <DiscoverProfileVm>[];
    }

    _lastDiscoverDoc = snap.docs.last;
    final serverHasMore = snap.docs.length >= fetchSize;

    final docDataById = <String, Map<String, dynamic>>{
      for (final d in snap.docs) d.id: d.data(),
    };

    final blockedPeerIds = _blockService.allBlockedPeerIds;
    final rejectedUserIds = await _loadRejectedUserIds(currentUser.id);

    final candidates = <User>[];

    for (final doc in snap.docs) {
      if (candidates.length >= limit * 3) break;
      if (_seenUserIds.contains(doc.id)) continue;

      final raw = doc.data();
      late final User user;
      try {
        user = User.fromFirestore(raw, doc.id);
      } catch (_) {
        continue;
      }

      if (!_isEligibleForDiscover(
        user: user,
        me: currentUser,
        myGender: myGender,
        candidateDoc: raw,
        blockedPeerIds: blockedPeerIds,
        rejectedUserIds: rejectedUserIds,
      )) {
        continue;
      }

      candidates.add(user);
    }

    final ranked = candidates
        .map((u) {
          final signals =
              _rankingService.buildSignals(me: currentUser, candidate: u);
          final score = _rankingService.calculateScore(signals);
          return _ScoredUser(user: u, score: score);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final ranked3d = ranked
        .where((s) => _meetsDiscover3dAshtakoot(currentUser, s.user))
        .toList();

    if (kDebugMode && ranked.isNotEmpty && ranked3d.isEmpty) {
      debugPrint(
        'DISCOVER 3D: no candidates ≥ $kDiscover3dMinAshtakootPercent% '
        'Ashtakoot (from ${ranked.length} ranked)',
      );
    }

    final curatedUsers = await _schedulerService.curateForSession(
      userId: currentUser.id,
      rankedUsers: ranked3d.map((e) => e.user).toList(),
      batchSize: limit.clamp(5, 10),
    );

    for (final u in curatedUsers) {
      _seenUserIds.add(u.id);
    }
    await _schedulerService.markServed(
      currentUser.id,
      DateTime.now(),
      curatedUsers.map((e) => e.id),
    );

    final docByUserId = <String, Map<String, dynamic>?>{
      for (final u in curatedUsers) u.id: docDataById[u.id],
    };

    final idsNeedingServerPhoto = <String>[];
    for (final u in curatedUsers) {
      final raw = docByUserId[u.id];
      final resolved = _resolveProfilePictureUrl(candidate: u, candidateDoc: raw);
      final allow = _privacyService.canIncludePhotoUrlInPremiumDiscoverCarousel(
        viewer: currentUser,
        candidate: u,
        candidateDoc: raw,
      );
      if (allow && resolved.isEmpty) {
        idsNeedingServerPhoto.add(u.id);
      }
    }

    if (idsNeedingServerPhoto.isNotEmpty) {
      await Future.wait(
        idsNeedingServerPhoto.map((id) async {
          try {
            final snap = await _db.collection(Collections.users).doc(id).get(
                  const GetOptions(source: Source.server),
                );
            if (snap.exists && snap.data() != null) {
              docByUserId[id] = snap.data();
            }
          } catch (_) {}
        }),
      );
    }

    final out = <DiscoverProfileVm>[];
    for (final u in curatedUsers) {
      final raw = docByUserId[u.id];
      User candidate = u;
      if (idsNeedingServerPhoto.contains(u.id) && raw != null) {
        try {
          candidate = User.fromFirestore(raw, u.id);
        } catch (_) {}
      }
      out.add(
        _toVm(
          me: currentUser,
          candidate: candidate,
          candidateDoc: raw,
        ),
      );
    }

    _hasMore = serverHasMore;

    if (kDebugMode && out.isEmpty && snap.docs.isNotEmpty) {
      debugPrint(
        'DISCOVERY FUNNEL getDiscoverProfiles raw=${snap.docs.length} '
        'candidates=${candidates.length} (server gender filter + Dart eligibility)',
      );
    }

    return out;
  }

  Future<void> markRejected(String currentUserId, String rejectedUserId) async {
    if (currentUserId.isEmpty || rejectedUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _rejectedKey(currentUserId);
    final current = prefs.getStringList(key)?.toSet() ?? <String>{};
    current.add(rejectedUserId);
    await prefs.setStringList(key, current.toList());
    await _recordDiscoverAction(
      actorUserId: currentUserId,
      targetUserId: rejectedUserId,
      action: 'pass',
    );
  }

  Future<void> recordSuperMatch({
    required String currentUserId,
    required String targetUserId,
  }) async {
    if (currentUserId.isEmpty || targetUserId.isEmpty) return;
    await _recordDiscoverAction(
      actorUserId: currentUserId,
      targetUserId: targetUserId,
      action: 'super_match',
      metadata: const {'source': 'discover_carousel'},
    );
  }

  String? _nakshatraForAshtakoot(User u) {
    final fromProfile = u.profile?.nakshatra?.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    final fallback = u.profileForDiscovery.nakshatra?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  /// Ashtakoot gate for 3D Discover carousel only (traditional acceptable line 18/36).
  bool _meetsDiscover3dAshtakoot(User me, User candidate) {
    final a = _nakshatraForAshtakoot(me);
    final b = _nakshatraForAshtakoot(candidate);
    if (a == null || b == null) return false;
    final r = StarCompatibilityService.calculateAshtakoot(
      {'nakshatra': a},
      {'nakshatra': b},
    );
    if (!r.success) return false;
    return r.percentage >= kDiscover3dMinAshtakootPercent;
  }

  bool _isEligibleForDiscover({
    required User user,
    required User me,
    required Gender myGender,
    required Map<String, dynamic>? candidateDoc,
    required Set<String> blockedPeerIds,
    required Set<String> rejectedUserIds,
  }) {
    if (user.id == me.id) return false;
    if (user.profileId == me.profileId) return false;
    if (user.authUid != null && user.authUid == me.authUid) return false;
    if (user.isDeleted) return false;
    if (!ProfileCompletionPolicy.isEligibleForDiscovery(user)) return false;

    final raw = candidateDoc ?? <String, dynamic>{};
    final peer = user.profile?.gender ?? genderFromUserDocumentData(raw);
    if (peer == null) return false;
    if (peer == myGender) return false;

    if (blockedPeerIds.contains(user.profileId)) return false;
    if (blockedPeerIds.contains(user.id)) return false;
    if (rejectedUserIds.contains(user.id)) return false;
    if (!_privacyService.canViewerSeeProfile(
      viewer: me,
      candidate: user,
      candidateDoc: candidateDoc,
    )) {
      return false;
    }

    return true;
  }

  /// Best-effort profile image for Discover UIs. Some members store the main
  /// picture only in [UserProfile.photos] or on the Firestore root while the
  /// parsed [User.profile] omits [profilePicture] — without this, 3D Discover
  /// showed an empty placeholder even when the member had a public photo.
  static String _resolveProfilePictureUrl({
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    String? pick(String? s) {
      final t = (s ?? '').trim();
      return t.isNotEmpty ? t : null;
    }

    /// Firestore sometimes stores URLs as non-[String] types; only accept values
    /// that still look like an http(s) URL when stringified.
    String? pickDynamic(dynamic v) {
      if (v == null) return null;
      if (v is String) return pick(v);
      final s = v.toString().trim();
      if (s.isEmpty || s == 'null') return null;
      final lower = s.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return s;
      }
      return null;
    }

    bool looksLikeHttpImageUrl(String u) {
      final lower = u.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        return false;
      }
      if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
        return false;
      }
      return true;
    }

    /// Last resort: any field whose name suggests a photo and whose value is an
    /// http(s) URL (legacy / import / partner CMS keys).
    String? firstLikelyPhotoUrlFromMap(Map<String, dynamic> m) {
      for (final e in m.entries) {
        final kl = e.key.toLowerCase();
        if (kl.contains('photo') ||
            kl.contains('picture') ||
            kl.contains('avatar') ||
            kl.contains('thumb') ||
            (kl.contains('image') && !kl.contains('message')) ||
            kl == 'media_url' ||
            kl == 'cover_photo') {
          final u = pickDynamic(e.value);
          if (u != null && looksLikeHttpImageUrl(u)) return u;
        }
      }
      return null;
    }

    /// Firestore `photos` may be `List<String>`, comma-separated string, or
    /// `List<Map>` with a `url` key (legacy / admin imports).
    Iterable<String> urlsFromPhotosField(dynamic raw) sync* {
      if (raw == null) return;
      if (raw is String) {
        for (final part in raw.split(',')) {
          final t = part.trim();
          if (t.isNotEmpty) yield t;
        }
        return;
      }
      if (raw is List) {
        for (final e in raw) {
          if (e is String) {
            final t = e.trim();
            if (t.isNotEmpty) yield t;
          } else if (e is Map) {
            for (final key in const [
              'url',
              'photo_url',
              'photoUrl',
              'src',
              'downloadUrl',
              'path',
            ]) {
              final v = e[key];
              final u = pickDynamic(v);
              if (u != null) {
                yield u;
                break;
              }
            }
          }
        }
      }
    }

    String? fromDoc(Map<String, dynamic>? doc) {
      if (doc == null) return null;
      String? fromMap(Map<String, dynamic> m) {
        for (final key in const [
          'profile_picture',
          'profilePicture',
          'photo_url',
          'photoUrl',
          'avatar',
          'photo',
          'image',
          'profile_image',
          'display_photo',
        ]) {
          final u = pickDynamic(m[key]);
          if (u != null) return u;
        }
        for (final u in urlsFromPhotosField(m['photos'])) {
          final p = pick(u);
          if (p != null) return p;
        }
        final guessed = firstLikelyPhotoUrlFromMap(m);
        if (guessed != null) return guessed;
        return null;
      }

      final root = fromMap(doc);
      if (root != null) return root;
      final nested = doc['profile'];
      if (nested is Map<String, dynamic>) {
        final inner = fromMap(nested);
        if (inner != null) return inner;
      }
      return firstLikelyPhotoUrlFromMap(doc);
    }

    final prof = candidate.profile;
    final fromPrimary = pick(prof?.profilePicture);
    if (fromPrimary != null) return fromPrimary;

    final gallery = prof?.photos;
    if (gallery != null) {
      for (final url in gallery) {
        final u = pick(url);
        if (u != null) return u;
      }
    }
    for (final u in urlsFromPhotosField(candidateDoc?['photos'])) {
      final p = pick(u);
      if (p != null) return p;
    }
    final nested = candidateDoc?['profile'];
    if (nested is Map<String, dynamic>) {
      for (final u in urlsFromPhotosField(nested['photos'])) {
        final p = pick(u);
        if (p != null) return p;
      }
    }

    final fallbackProfile = candidate.profileForDiscovery;
    final fromSynthetic = pick(fallbackProfile.profilePicture);
    if (fromSynthetic != null) return fromSynthetic;

    final fromFirestore = fromDoc(candidateDoc);
    if (fromFirestore != null) return fromFirestore;

    return '';
  }

  DiscoverProfileVm _toVm({
    required User me,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    final p = candidate.profileForDiscovery;
    final name = [p.firstName, p.lastName]
        .where((e) => e.trim().isNotEmpty)
        .join(' ')
        .trim();
    final profession = (p.occupation ?? '').trim();
    final city = (p.city ?? p.state ?? '').trim();
    final resolvedPicture = _resolveProfilePictureUrl(
      candidate: candidate,
      candidateDoc: candidateDoc,
    );
    final isPhotoHidden = PrivacyEnforcementService.isPhotoHiddenFromOthers(
      candidateDoc,
      fromParsedProfile: p.isPhotoPrivate ?? false,
    );
    var image = '';
    // Always pass a non-empty image URL into Discover UIs so widgets like
    // `ProtectedProfilePhoto` can mount. Photo access is still enforced
    // server-side by the authenticated proxy; hiding via discover privacy
    // rules only prevented the UI from attempting to load the proxied image.
    //
    // This ensures that after photo-request acceptance, the requester
    // side can immediately see the photo in all discovery/carousel screens.
    if (!isPhotoHidden && resolvedPicture.isNotEmpty) {
      image = resolvedPicture;
    } else if (ProfilePhotoProxyService.shouldUseProxyFor(
      ownerUserId: candidate.id,
    )) {
      // Include hidden profiles: UI mounts proxy; server returns bytes only
      // when the viewer has a granted photo_requests doc.
      image = ProfilePhotoProxyService.resolveNetworkUrl(
        ownerUserId: candidate.id,
        legacyDirectUrl: isPhotoHidden ? null : resolvedPicture,
        variant: me.membership.isPremium
            ? ProfilePhotoProxyVariant.full
            : ProfilePhotoProxyVariant.preview,
      );
    }

    final compatibilityLabel = _buildCompatibilityLabel(me: me, candidate: candidate);
    final heroTag = 'discover_${candidate.id}_${candidate.profileId}';

    return DiscoverProfileVm(
      userId: candidate.id,
      profileId: candidate.profileId,
      name: name.isEmpty ? 'Profile ${candidate.profileId}' : name,
      age: candidate.age,
      profession: profession.isEmpty ? 'Not Disclosed' : profession,
      city: city.isEmpty ? 'Not Disclosed' : city,
      imageUrl: image,
      isPremium: candidate.membership.isPremium,
      isPhotoHiddenFromOthers: isPhotoHidden,
      compatibilityLabel: compatibilityLabel,
      heroTag: heroTag,
    );
  }

  String _buildCompatibilityLabel({required User me, required User candidate}) {
    final myNak = me.profile?.nakshatra;
    final peerNak = candidate.profileForDiscovery.nakshatra;
    if ((myNak ?? '').isEmpty || (peerNak ?? '').isEmpty) {
      return 'Compatibility pending';
    }
    final ashtakoot = StarCompatibilityService.calculateAshtakoot(
      {'nakshatra': myNak},
      {'nakshatra': peerNak},
    );
    final pct = ashtakoot.percentage.round().clamp(0, 100);
    return '$pct% compatible';
  }

  Future<Gender?> _resolveMyGender(User me) async {
    final fromProfile = me.profile?.gender;
    if (fromProfile != null) return fromProfile;
    try {
      final doc = await getDocumentCachedFirst(_db.collection(Collections.users).doc(me.id));
      final data = doc.data();
      if (data == null) return null;
      return genderFromUserDocumentData(data);
    } catch (_) {}
    return null;
  }

  String _rejectedKey(String userId) => 'discover_rejected_$userId';

  Future<Set<String>> _loadRejectedUserIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_rejectedKey(userId))?.toSet() ?? <String>{};
  }

  Future<void> _recordDiscoverAction({
    required String actorUserId,
    required String targetUserId,
    required String action,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final docId = '${actorUserId}_${targetUserId}_$action';
      await _db.collection('discover_actions').doc(docId).set({
        'actor_user_id': actorUserId,
        'target_user_id': targetUserId,
        'action': action,
        'updated_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        if (metadata != null) ...metadata,
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal analytics persistence
    }
  }
}

class _ScoredUser {
  final User user;
  final double score;

  const _ScoredUser({required this.user, required this.score});
}
