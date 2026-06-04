import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import '../utils/firebase_session_policy.dart';
import 'network_service.dart';

/// Heartbeat only refreshes [lastSeen] while foreground (onDisconnect handles offline).
const Duration kPresenceHeartbeatInterval = Duration(minutes: 3);

/// If [online] is true but [lastSeen] is older than this, show offline in UI.
const Duration kPresenceStaleThreshold = Duration(seconds: 90);

/// @deprecated Use [kPresenceStaleThreshold].
const int kPresenceStaleAfterMinutes = 2;

const String _rtdbPresenceRoot = 'presence';

const Duration _rtdbWriteTimeout = Duration(seconds: 6);

// ─────────────────────────────────────────────────────────────────────────────
// PresenceService — singleton; one session owner (AppInitializer.startTracking).
//
// Source of truth: Firebase Realtime Database `presence/{authUid}` with
// onDisconnect so crash / network loss marks the user offline.
// Firestore `users/{docId}.is_online` is mirrored best-effort for legacy readers.
// ─────────────────────────────────────────────────────────────────────────────

class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Timer? _heartbeatTimer;
  Timer? _stalenessPumpTimer;
  StreamSubscription<bool>? _connectivitySub;
  String? _ownUserId; // Firestore users/{docId}
  String? _authUid;
  bool _isTracking = false;
  bool _networkConnected = true;
  bool _foregroundActive = true;

  DateTime? _lastBackgroundCall;
  static const _backgroundDebounceMs = 500;

  DateTime? _lastFirestoreMirrorAt;
  static const _firestoreMirrorDebounceMs = 2000;

  DateTime? _lastFirestoreActivityMirrorAt;
  static const _firestoreActivityMirrorInterval = Duration(seconds: 45);

  Timer? _firestoreActivityTimer;

  static final Map<String, String> _authUidToDocIdCache = {};
  static final Map<String, String> _docIdToAuthUidCache = {};

  static final Map<String, Stream<PresenceData>> _presenceStreams = {};
  static final Map<String, PresenceData> _presenceLast = {};

  /// Shared UI tick so list tiles don't each run a 20s [Timer.periodic].
  final ValueNotifier<int> uiStalenessTick = ValueNotifier(0);

  /// True when this device is actively tracking presence for a logged-in user.
  bool get isSessionActive => _isTracking && _authUid != null;

  DatabaseReference _rtdbPresenceRef(String authUid) =>
      FirebaseDatabase.instance.ref('$_rtdbPresenceRoot/$authUid');

  /// Call once after login from [AppInitializer] only.
  Future<void> startTracking(String authUid) async {
    if (authUid.isEmpty) return;

    if (_isTracking && _authUid != null && _authUid != authUid) {
      await stopTracking();
    }

    if (_isTracking && _authUid == authUid) {
      debugPrint(
        '⚠️ PresenceService: duplicate startTracking ignored (authUid=$authUid)',
      );
      return;
    }

    _authUid = authUid;
    _isTracking = true;
    _foregroundActive = true;

    final docId = await _resolveDocIdFromAuthUid(authUid);
    if (docId == null) {
      debugPrint(
        '❌ PresenceService: Could not resolve Firestore doc for authUid=$authUid',
      );
      _isTracking = false;
      _authUid = null;
      return;
    }
    _ownUserId = docId;
    _docIdToAuthUidCache[docId] = authUid;

    _networkConnected = NetworkService.isConnected;
    _startConnectivityListener();
    _ensureStalenessPump();

    try {
      await _markOnline().timeout(_rtdbWriteTimeout);
    } catch (e) {
      debugPrint('⚠️ PresenceService: initial online write timed out/failed: $e');
    }
    _startHeartbeat();
    _startFirestoreActivityMirror();

    debugPrint(
      '✅ PresenceService: RTDB tracking started authUid=$authUid docId=$docId',
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(kPresenceHeartbeatInterval, (_) {
      if (!_isTracking ||
          !_foregroundActive ||
          _authUid == null ||
          !_networkConnected) {
        return;
      }
      unawaited(_touchLastSeen());
      unawaited(_mirrorFirestoreActivity());
    });
  }

  void _startFirestoreActivityMirror() {
    _firestoreActivityTimer?.cancel();
    _firestoreActivityTimer = Timer.periodic(
      _firestoreActivityMirrorInterval,
      (_) {
        if (!_isTracking ||
            !_foregroundActive ||
            _authUid == null ||
            !_networkConnected) {
          return;
        }
        unawaited(_mirrorFirestoreActivity());
      },
    );
  }

  void _startConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = NetworkService.connectionStream.listen((connected) {
      final wasConnected = _networkConnected;
      _networkConnected = connected;
      if (!connected && wasConnected && _isTracking) {
        debugPrint('📡 PresenceService: network lost');
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        unawaited(goBackground());
        _recomputeCachedPresenceStale();
      } else if (connected && !wasConnected && _isTracking) {
        debugPrint('📡 PresenceService: network restored');
        if (_foregroundActive) {
          unawaited(goForeground());
          _startHeartbeat();
        }
      }
    });
  }

  void _recomputeCachedPresenceStale() {
    for (final key in _presenceLast.keys.toList()) {
      final prev = _presenceLast[key];
      if (prev == null) continue;
      _presenceLast[key] = prev.applyStaleness();
    }
    uiStalenessTick.value++;
  }

  void _ensureStalenessPump() {
    if (_stalenessPumpTimer != null) return;
    _stalenessPumpTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _recomputeCachedPresenceStale();
    });
  }

  Future<String?> _resolveDocIdFromAuthUid(String authUid) async {
    if (_authUidToDocIdCache.containsKey(authUid)) {
      return _authUidToDocIdCache[authUid];
    }

    try {
      final snap = await _db
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: authUid)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final docId = snap.docs.first.id;
        _authUidToDocIdCache[authUid] = docId;
        _docIdToAuthUidCache[docId] = authUid;
        return docId;
      }

      final directSnap = await _db.collection(Collections.users).doc(authUid).get();
      if (directSnap.exists) {
        _authUidToDocIdCache[authUid] = authUid;
        _docIdToAuthUidCache[authUid] = authUid;
        return authUid;
      }

      return null;
    } catch (e) {
      debugPrint('❌ PresenceService: resolve docId failed: $e');
      return null;
    }
  }

  Future<String?> _resolveAuthUidFromAnyUserKey(String userKey) async {
    final key = userKey.trim();
    if (key.isEmpty) return null;

    if (_docIdToAuthUidCache.containsKey(key)) {
      return _docIdToAuthUidCache[key];
    }
    if (_authUidToDocIdCache.containsKey(key)) {
      return key;
    }

    try {
      final directSnap = await _db.collection(Collections.users).doc(key).get();
      if (directSnap.exists) {
        final data = directSnap.data() ?? {};
        final authUid = (data['auth_uid'] as String? ?? '').trim();
        if (authUid.isNotEmpty) {
          _docIdToAuthUidCache[key] = authUid;
          _authUidToDocIdCache[authUid] = key;
          return authUid;
        }
        _docIdToAuthUidCache[key] = key;
        _authUidToDocIdCache[key] = key;
        return key;
      }

      for (final field in const ['auth_uid', 'profile_id']) {
        final snap = await _db
            .collection(Collections.users)
            .where(field, isEqualTo: key)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final docId = snap.docs.first.id;
          final data = snap.docs.first.data();
          final authUid = (data['auth_uid'] as String? ?? '').trim();
          final resolved = authUid.isNotEmpty ? authUid : docId;
          _docIdToAuthUidCache[docId] = resolved;
          _authUidToDocIdCache[resolved] = docId;
          if (key != docId) {
            _docIdToAuthUidCache[key] = resolved;
          }
          return resolved;
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ PresenceService: resolve authUid failed: $e');
      return null;
    }
  }

  Future<String?> _resolveDocIdFromAnyUserKey(String userKey) async {
    final key = userKey.trim();
    if (key.isEmpty) return null;
    if (_authUidToDocIdCache.containsKey(key)) {
      return _authUidToDocIdCache[key];
    }
    final authUid = await _resolveAuthUidFromAnyUserKey(key);
    if (authUid == null) return null;
    return _authUidToDocIdCache[authUid];
  }

  Future<bool> _isPresenceVisibleForDoc(String docId) async {
    try {
      final snap = await _db.collection(Collections.users).doc(docId).get();
      if (!snap.exists) return true;
      final data = snap.data() ?? {};
      return _isPresenceVisible(data);
    } catch (_) {
      return true;
    }
  }

  bool _isPresenceVisible(Map<String, dynamic> data) {
    final profile = data['profile'];
    final nested = profile is Map<String, dynamic> ? profile : const {};
    return data['privacy_show_online_status'] as bool? ??
        data['privacy_online_status'] as bool? ??
        data['show_online_status'] as bool? ??
        nested['show_online_status'] as bool? ??
        true;
  }

  Future<void> _configureOnDisconnect(DatabaseReference ref) async {
    try {
      await ref
          .onDisconnect()
          .update({
            'online': false,
            'lastSeen': ServerValue.timestamp,
          })
          .timeout(_rtdbWriteTimeout);
    } catch (e) {
      debugPrint('⚠️ PresenceService.onDisconnect setup failed: $e');
    }
  }

  Future<void> _cancelOnDisconnect(DatabaseReference ref) async {
    try {
      await ref.onDisconnect().cancel();
    } catch (_) {}
  }

  Future<void> _markOnline() async {
    if (_authUid == null || !_isTracking) return;

    await _ensureFirebaseSession();
    // Firestore is what the UI reads — always mirror first.
    await _mirrorFirestoreOnline(true);
    await _mirrorFirestoreActivity();

    try {
      final ref = _rtdbPresenceRef(_authUid!);
      await ref
          .set({
            'online': true,
            'lastSeen': ServerValue.timestamp,
          })
          .timeout(_rtdbWriteTimeout);
      await _configureOnDisconnect(ref);
      debugPrint('✅ PresenceService._markOnline RTDB ok authUid=$_authUid');
    } catch (e) {
      debugPrint('⚠️ PresenceService._markOnline RTDB skipped: $e');
    }
  }

  Future<void> _touchLastSeen() async {
    if (_authUid == null || !_isTracking || !_foregroundActive) return;
    try {
      await _rtdbPresenceRef(_authUid!).update({
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('⚠️ PresenceService._touchLastSeen: $e');
    }
  }

  Future<void> _markOffline({required bool cancelOnDisconnect}) async {
    if (_authUid == null) return;

    await _ensureFirebaseSession();
    await _mirrorFirestoreOnline(false);

    try {
      final ref = _rtdbPresenceRef(_authUid!);
      if (cancelOnDisconnect) {
        await _cancelOnDisconnect(ref);
      }
      await ref
          .update({
            'online': false,
            'lastSeen': ServerValue.timestamp,
          })
          .timeout(_rtdbWriteTimeout);
    } catch (e) {
      debugPrint('⚠️ PresenceService._markOffline RTDB skipped: $e');
    }
  }

  /// Keeps `users/{docId}.last_active` fresh so [PresenceData.applyStaleness]
  /// does not clear "Live now" while the user is still in the app.
  Future<void> _mirrorFirestoreActivity() async {
    if (_ownUserId == null || !_isTracking) return;
    final now = DateTime.now();
    if (_lastFirestoreActivityMirrorAt != null) {
      final elapsed = now.difference(_lastFirestoreActivityMirrorAt!);
      if (elapsed < _firestoreActivityMirrorInterval) return;
    }
    _lastFirestoreActivityMirrorAt = now;

    try {
      await _db.collection(Collections.users).doc(_ownUserId!).set({
        'is_online': true,
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ PresenceService Firestore activity mirror failed: $e');
    }
  }

  Future<void> _mirrorFirestoreOnline(bool online) async {
    if (_ownUserId == null) return;
    final now = DateTime.now();
    if (_lastFirestoreMirrorAt != null) {
      final diff = now.difference(_lastFirestoreMirrorAt!).inMilliseconds;
      if (diff < _firestoreMirrorDebounceMs) return;
    }
    _lastFirestoreMirrorAt = now;

    try {
      await _db.collection(Collections.users).doc(_ownUserId!).set({
        'is_online': online,
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ PresenceService Firestore mirror failed: $e');
    }
  }

  Future<void> goBackground() async {
    if (!_isTracking || _authUid == null) return;

    final now = DateTime.now();
    if (_lastBackgroundCall != null) {
      final diff = now.difference(_lastBackgroundCall!).inMilliseconds;
      if (diff < _backgroundDebounceMs) return;
    }
    _lastBackgroundCall = now;
    _foregroundActive = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _markOffline(cancelOnDisconnect: true);
  }

  Future<void> goForeground() async {
    if (!_isTracking || _authUid == null) return;
    _foregroundActive = true;
    _lastBackgroundCall = null;
    await _markOnline();
    _startHeartbeat();
  }

  Future<void> stopTracking() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _firestoreActivityTimer?.cancel();
    _firestoreActivityTimer = null;
    _stalenessPumpTimer?.cancel();
    _stalenessPumpTimer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    final authUid = _authUid;
    final docId = _ownUserId;

    _isTracking = false;
    _foregroundActive = false;
    _networkConnected = true;
    _authUid = null;
    _ownUserId = null;

    if (authUid != null) {
      try {
        await _ensureFirebaseSession();
        final ref = _rtdbPresenceRef(authUid);
        await _cancelOnDisconnect(ref);
        await ref
            .update({
              'online': false,
              'lastSeen': ServerValue.timestamp,
            })
            .timeout(_rtdbWriteTimeout);
      } catch (e) {
        debugPrint('⚠️ PresenceService.stopTracking RTDB: $e');
      }
    }

    if (docId != null) {
      try {
        await _db.collection(Collections.users).doc(docId).set({
          'is_online': false,
          'last_active': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    _presenceStreams.clear();
    _presenceLast.clear();
    debugPrint('✅ PresenceService: tracking stopped');
  }

  PresenceData? lastPresenceFor(String userId) {
    final key = userId.trim();
    if (key.isEmpty) return null;
    return _presenceLast[key]?.applyStaleness();
  }

  Stream<PresenceData> watchUser(String userId) {
    if (userId.isEmpty) {
      return Stream.value(PresenceData.unknown());
    }

    final streamKey = userId.trim();
    final base = _presenceStreams.putIfAbsent(
      streamKey,
      () => _buildUserPresenceStream(streamKey)
          .map((data) {
            _presenceLast[streamKey] = data;
            return data;
          })
          .asBroadcastStream(),
    );
    return _seededPresenceStream(streamKey, base);
  }

  Stream<PresenceData> _seededPresenceStream(
    String streamKey,
    Stream<PresenceData> source,
  ) {
    _ensureStalenessPump();
    return Stream.multi((controller) {
      PresenceData? lastEmitted;

      void emitFresh() {
        final raw = _presenceLast[streamKey];
        if (raw == null) return;
        final fresh = raw.applyStaleness();
        if (lastEmitted != null &&
            lastEmitted!.isOnline == fresh.isOnline &&
            lastEmitted!.lastActive == fresh.lastActive) {
          return;
        }
        lastEmitted = fresh;
        _presenceLast[streamKey] = fresh;
        controller.add(fresh);
      }

      emitFresh();

      late StreamSubscription<PresenceData> sub;
      sub = source.listen(
        (data) {
          _presenceLast[streamKey] = data;
          emitFresh();
        },
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );

      final stalenessSub = Timer.periodic(const Duration(seconds: 30), (_) {
        emitFresh();
      });

      controller.onCancel = () {
        sub.cancel();
        stalenessSub.cancel();
      };
    });
  }

  PresenceData _presenceFromUserDoc(DocumentSnapshot snap) {
    if (!snap.exists) return PresenceData.unknown();
    final raw = snap.data();
    if (raw is! Map) return PresenceData.unknown();
    final data = Map<String, dynamic>.from(raw);
    if (!_isPresenceVisible(data)) {
      return PresenceData(
        isOnline: false,
        lastActive: PresenceData.parseLastActive(data['last_active']),
      ).applyStaleness();
    }
    return PresenceData.fromMap(data);
  }

  Stream<PresenceData> _buildUserPresenceStream(String streamKey) async* {
    await _ensureFirebaseSession();

    final resolvedUserId = await _resolveDocIdFromAnyUserKey(streamKey);
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      final unknown = PresenceData.unknown();
      _presenceLast[streamKey] = unknown;
      yield unknown;
      return;
    }

    if (!await _isPresenceVisibleForDoc(resolvedUserId)) {
      final hidden = const PresenceData(isOnline: false, lastActive: null);
      _presenceLast[streamKey] = hidden;
      yield hidden;
      return;
    }

    try {
      final initialSnap = await _db
          .collection(Collections.users)
          .doc(resolvedUserId)
          .get()
          .timeout(const Duration(seconds: 5));
      final initial = _presenceFromUserDoc(initialSnap);
      _presenceLast[streamKey] = initial;
      yield initial;
    } catch (e) {
      debugPrint('⚠️ PresenceService Firestore initial($resolvedUserId): $e');
    }

    yield* _db
        .collection(Collections.users)
        .doc(resolvedUserId)
        .snapshots()
        .map(_presenceFromUserDoc)
        .transform(
      StreamTransformer<PresenceData, PresenceData>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          debugPrint(
            '⚠️ PresenceService Firestore watch($resolvedUserId): $error',
          );
          sink.add(PresenceData.unknown());
        },
      ),
    );
  }

  Future<void> _ensureFirebaseSession() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      try {
        await current.getIdToken(false);
        return;
      } catch (_) {
        try {
          await current.getIdToken(true);
          return;
        } catch (_) {}
      }
    }

    if (!await FirebaseSessionPolicy.mayUseAnonymousFirebaseSession()) {
      return;
    }

    await FirebaseAuth.instance.signInAnonymously();
  }

  Future<PresenceData> fetchUser(String userId) async {
    if (userId.isEmpty) return PresenceData.unknown();
    try {
      await _ensureFirebaseSession();
      final resolved = await _resolveDocIdFromAnyUserKey(userId.trim());
      if (resolved == null || resolved.isEmpty) {
        return PresenceData.unknown();
      }
      if (!await _isPresenceVisibleForDoc(resolved)) {
        return const PresenceData(isOnline: false, lastActive: null);
      }

      final snap = await _db
          .collection(Collections.users)
          .doc(resolved)
          .get()
          .timeout(const Duration(seconds: 5));
      return _presenceFromUserDoc(snap);
    } catch (e) {
      debugPrint('⚠️ PresenceService.fetchUser($userId): $e');
      return PresenceData.unknown();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PresenceData
// ─────────────────────────────────────────────────────────────────────────────

class PresenceData {
  final bool isOnline;
  final DateTime? lastActive;

  const PresenceData({required this.isOnline, this.lastActive});

  factory PresenceData.unknown() =>
      const PresenceData(isOnline: false, lastActive: null);

  factory PresenceData.fromMap(Map<String, dynamic> data) {
    final isOnlineRaw = data['is_online'] as bool? ??
        data['online'] as bool? ??
        false;
    final lastActive = parseLastActive(
      data['last_active'] ?? data['lastSeen'] ?? data['last_seen'],
    );
    return PresenceData(
      isOnline: isOnlineRaw,
      lastActive: lastActive,
    ).applyStaleness();
  }

  factory PresenceData.fromRtdbMap(Map<dynamic, dynamic> data) {
    final isOnlineRaw = data['online'] == true;
    final lastActive = parseLastActive(data['lastSeen'] ?? data['last_seen']);
    return PresenceData(
      isOnline: isOnlineRaw,
      lastActive: lastActive,
    ).applyStaleness();
  }

  PresenceData applyStaleness() {
    if (!isOnline) return this;
    // Trust Firestore `is_online` when `last_active` is missing (mirror in progress).
    if (lastActive == null) return this;
    final age = DateTime.now().toUtc().difference(lastActive!.toUtc());
    if (age > kPresenceStaleThreshold) {
      return PresenceData(isOnline: false, lastActive: lastActive);
    }
    return this;
  }

  static DateTime? parseLastActive(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toUtc();
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    return null;
  }

  String get lastSeenText {
    if (isOnline) return 'Live now';
    if (lastActive == null) return 'Offline';

    final now = DateTime.now().toUtc();
    final diff = now.difference(lastActive!.toUtc());
    return 'Last seen ${_formatAgo(diff)}';
  }

  static String _formatAgo(Duration diff) {
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }

  @override
  String toString() =>
      'PresenceData(isOnline: $isOnline, lastActive: $lastActive)';
}
