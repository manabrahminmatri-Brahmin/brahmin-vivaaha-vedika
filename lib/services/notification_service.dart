import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/interest_badge_aggregator.dart';
import '../core/privacy_request_notification_sync.dart';
import '../repositories/notification_repository.dart';
import '../core/app_identity.dart';
import '../models/notification.dart';
import '../services/notification_sound_service.dart';
import '../utils/log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService  —  FIXED v4
//
// BUGS FIXED:
//  1. startListening() was querying .where('user_id', ...) but all documents
//     are stored with field name 'user_id'. The listener returned 0 results
//     every time, making the notification badge always show 0 and the
//     notifications screen always appear empty.
//     FIX: Changed to .where('user_id', ...) to match firebase_service.dart.
//
//  2. startListening() used .orderBy('timestamp', ...) which requires a
//     Firestore composite index. If the index doesn't exist, the listener
//     throws and notifications never load.
//     FIX: Removed orderBy from the listener — sort is done in Dart.
//
//  3. Removed the unused internal setter/getter pairs (notificationsInternal,
//     unreadCountInternal) that exposed mutable state incorrectly.
//
//  4. _toSortedList() was defined but never called — removed dead code.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService extends ChangeNotifier {
  List<Map<String, dynamic>> _notifications = [];
  final Set<String> _deletedIds = {};

  int _unreadCount = 0;
  int _lastLoggedNotificationTotal = -1;
  int _lastLoggedUnreadCount = -1;
  bool _isLoading = false;
  /// True after at least one successful fetch or realtime payload for this user.
  String? _fetchedForUserId;
  final _db = FirebaseFirestore.instance;
  final NotificationRepository _repo;

  // 🔥 CRITICAL FIX: Prevent notifyListeners() after dispose
  bool _disposed = false;
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
  @override
  void dispose() {
    _disposed = true;
    stopListening();
    super.dispose();
  }

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSubscription;
  String? _listenedUserId;
  final Set<String> _seenNotificationIds = <String>{};
  String? _soundPrimedUserId;
  int _lastEligibleUnreadForSound = 0;
  bool _isFirstSoundSnapshot = true;

  NotificationService({NotificationRepository? repository})
      : _repo = repository ?? NotificationRepository();

  bool get isLoading => _isLoading;
  int get unreadCount => _unreadCount;

  /// Notification types that are already represented by live Interests hub data
  /// (interest rows, incoming request listeners, inbox) when computing a single
  /// consolidated header badge — avoids double-counting next to [unreadCount].
  static const Set<String> _hubMirroredInActivityBadge = {
    NotificationType.interestReceived,
    ...PrivacyRequestNotificationSync.hubMirroredBellTypes,
  };

  Map<String, String> _privacyRequestStatuses = {};
  Set<String> _pendingIncomingPrivacyDocIds = {};

  /// Unread notifications excluding types mirrored by in-app queues in the bell.
  int get unreadCountForConsolidatedActivityBadge => _notifications
      .where((n) {
        if (!NotificationRepository.isUnread(n)) return false;
        final t = (n['type'] as String? ?? '').trim();
        return !_hubMirroredInActivityBadge.contains(t);
      })
      .length;

  List<Map<String, dynamic>> get notifications =>
      List.unmodifiable(_notifications);

  /// Bell + list use the same store; this avoids showing empty while the first fetch is pending.
  bool hasFetchedForUser(String userId) =>
      userId.isNotEmpty && _fetchedForUserId == userId;

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _countUnread(List<Map<String, dynamic>> list) =>
      list.where(NotificationRepository.isUnread).length;

  List<Map<String, dynamic>> _filterVisibleForUser(
    List<Map<String, dynamic>> list,
    String userId,
  ) =>
      list
          .where((n) => !_deletedIds.contains(n['id'] as String? ?? ''))
          .where((n) => NotificationRepository.isVisibleForUser(n, userId))
          .toList();

  /// Prefer Firestore profile doc id for `from_user` (matches `user_id` / CF writes).
  /// 🔥 CONTRACT FIX: Always use userDocId (Firestore doc ID), never authUid for relations
  Future<String?> _notificationFromUserId() async {
    // Primary: Use IdentityProvider.userDocId (this is the Firestore document ID)
    final userDocId = IdentityProvider.userDocId;
    if (userDocId.isNotEmpty) return userDocId;
    
    // Fallback: Try shared preferences (legacy compatibility)
    final prefs = await SharedPreferences.getInstance();
    final doc = (prefs.getString('current_user_id') ?? '').trim();
    if (doc.isNotEmpty) return doc;
    
    // 🔥 WARNING: authUid must NEVER be stored in notification.user_id
    // This would cause permission-denied errors
    debugPrint('⚠️ _notificationFromUserId: No userDocId available');
    return null;
  }

  // ── Real-time listener ────────────────────────────────────────────────────

  void startListening(String userId) {
    if (userId.isEmpty) {
      stopListening();
      return;
    }
    if (_listenedUserId == userId && _realtimeSubscription != null) return;
    stopListening();
    _listenedUserId = userId;

    try {
      _realtimeSubscription = _repo.watchForUser(userId).listen((list) {
        _notifications = _filterVisibleForUser(list, userId);
        _maybePlayIncomingRequestSound(_notifications, userId);

        _fetchedForUserId = userId;
        _unreadCount = _countUnread(_notifications);
        _safeNotify();  // 🔥 FIX: Use safe notify
        unawaited(reconcilePrivacyRequestNotifications());

        if (_notifications.length != _lastLoggedNotificationTotal ||
            _unreadCount != _lastLoggedUnreadCount) {
          _lastLoggedNotificationTotal = _notifications.length;
          _lastLoggedUnreadCount = _unreadCount;
          Log.d(
            '🔔 Notifications: ${_notifications.length} total, $_unreadCount unread',
          );
        }
      }, onError: (e) {
        Log.w('❌ Notification listener error: $e');
        // 🔥 FIX: Gracefully handle permission denied - don't crash UI
        if (e.toString().contains('permission-denied')) {
          debugPrint('🔒 Notifications: permission denied, returning empty list');
          _notifications = [];
          _unreadCount = 0;
          _fetchedForUserId = userId;
          _safeNotify();
          return;
        }
        // 🔥 FIX: Don't call loadNotifications from error handler - causes cascade failures
        if (!_disposed && !e.toString().contains('permission')) {
          loadNotifications(userId, force: true);
        }
      }, cancelOnError: false);

      Log.d('🔔 Notification listener started for $userId');
    } catch (e) {
      Log.w('❌ Failed to start notification listener: $e');
    }
  }

  void stopListening() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _listenedUserId = null;
    _fetchedForUserId = null;
    _soundPrimedUserId = null;
    _lastEligibleUnreadForSound = 0;
    _isFirstSoundSnapshot = true;
    _seenNotificationIds.clear();
  }

  static const Set<String> _requestReceivedSoundTypes = {
    NotificationType.interestReceived,
    'interest',
    'request',
    'new_request',
    'match_request',
    ...PrivacyRequestNotificationSync.incomingTypes,
  };

  static String _normalizeSoundType(String raw) =>
      raw.trim().toLowerCase().replaceAll('-', '_');

  void _maybePlayIncomingRequestSound(
    List<Map<String, dynamic>> notifications,
    String userId,
  ) {
    if (userId.isEmpty) return;
    final debugNewEligibleTypes = <String>[];
    final eligibleUnreadCount = notifications.where((n) {
      final type = _normalizeSoundType(n['type'] as String? ?? '');
      return NotificationRepository.isUnread(n) &&
          _requestReceivedSoundTypes.contains(type);
    }).length;

    // Ignore first listener snapshot (often cached/initial state).
    if (_soundPrimedUserId != userId || _isFirstSoundSnapshot) {
      _soundPrimedUserId = userId;
      _isFirstSoundSnapshot = false;
      _lastEligibleUnreadForSound = eligibleUnreadCount;
      if (kDebugMode) {
        debugPrint(
          '🔔 BellDebug primed user=$userId eligibleUnread=$eligibleUnreadCount total=${notifications.length}',
        );
      }
      _seenNotificationIds
        ..clear()
        ..addAll(
          notifications
              .map((n) => (n['id'] as String? ?? '').trim())
              .where((id) => id.isNotEmpty),
        );
      return;
    }

    // Primary trigger: if unread request-like notifications increase, play once.
    // This also covers updates where the same notification doc is mutated instead
    // of inserting a brand-new document id.
    if (eligibleUnreadCount > _lastEligibleUnreadForSound) {
      final delta = eligibleUnreadCount - _lastEligibleUnreadForSound;
      if (kDebugMode) {
        debugPrint(
          '🔔 BellDebug trigger=unread_delta user=$userId '
          'prev=$_lastEligibleUnreadForSound now=$eligibleUnreadCount delta=$delta',
        );
      }
      _lastEligibleUnreadForSound = eligibleUnreadCount;
      unawaited(NotificationSoundService.playRequestReceivedSound());
      // Keep ids updated so we don't double-trigger in the fallback path below.
      _seenNotificationIds
        ..clear()
        ..addAll(
          notifications
              .map((n) => (n['id'] as String? ?? '').trim())
              .where((id) => id.isNotEmpty),
        );
      return;
    }
    _lastEligibleUnreadForSound = eligibleUnreadCount;

    bool shouldPlayBell = false;
    for (final n in notifications) {
      final id = (n['id'] as String? ?? '').trim();
      if (id.isEmpty || _seenNotificationIds.contains(id)) continue;
      _seenNotificationIds.add(id);

      final type = _normalizeSoundType(n['type'] as String? ?? '');
      final unread = NotificationRepository.isUnread(n);
      if (unread && _requestReceivedSoundTypes.contains(type)) {
        shouldPlayBell = true;
        debugNewEligibleTypes.add(type);
      }
    }

    if (shouldPlayBell) {
      if (kDebugMode) {
        debugPrint(
          '🔔 BellDebug trigger=new_id user=$userId '
          'types=${debugNewEligibleTypes.join(",")} '
          'eligibleUnread=$eligibleUnreadCount',
        );
      }
      unawaited(NotificationSoundService.playRequestReceivedSound());
    } else if (kDebugMode) {
      debugPrint(
        '🔔 BellDebug no-trigger user=$userId '
        'prev=$_lastEligibleUnreadForSound now=$eligibleUnreadCount',
      );
    }
  }

  // ── One-shot load ─────────────────────────────────────────────────────────

  Future<void> loadNotifications(
    String userId, {
    bool unreadOnly = false,
    bool force = false,
    int limit = 200,
  }) async {
    if (userId.isEmpty) return;
    if (_isLoading && !force) return;
    if (_listenedUserId != userId) startListening(userId);

    _isLoading = true;

    try {
      final list = await _repo.listForUser(
        userId,
        unreadOnly: unreadOnly,
        limit: limit,
      );
      _notifications = _filterVisibleForUser(list, userId);
      _fetchedForUserId = userId;
      _unreadCount = _countUnread(_notifications);
    } catch (e) {
      Log.w('❌ [Notif] loadNotifications: $e');
      // 🔥 FIX: Gracefully handle permission denied - return empty list
      if (e.toString().contains('permission-denied')) {
        debugPrint('🔒 Notifications load: permission denied, returning empty list');
        _notifications = [];
        _unreadCount = 0;
      }
      // Still mark fetch "done" so UIs don't spin forever on permission/network errors.
      _fetchedForUserId = userId;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<void> refreshUnreadCount(String userId) async {
    if (userId.isEmpty) return;
    try {
      final list = await _repo.listForUser(userId, limit: 200);
      _notifications = _filterVisibleForUser(list, userId);
      _unreadCount = _countUnread(_notifications);
      _fetchedForUserId = userId;
      _safeNotify();
    } catch (e) {
      Log.w('❌ [Notif] refreshUnreadCount: $e');
    }
  }

  static const Set<String> _interestHubNotificationTypes = {
    NotificationType.interestReceived,
    'interest_reminder',
    'interest',
  };

  String? _interestIdFromNotification(Map<String, dynamic> n) {
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

  /// Marks hub-mirrored interest notifications read for one interest doc
  /// (e.g. after accept/decline from Interests tab).
  Future<void> markInterestNotificationsReadForInterest(
    String interestDocumentId,
  ) async {
    final interestId = interestDocumentId.trim();
    if (interestId.isEmpty) return;

    for (final n in _notifications) {
      if (!NotificationRepository.isUnread(n)) continue;
      final type = (n['type'] as String? ?? '').trim();
      if (!_interestHubNotificationTypes.contains(type)) continue;
      if (_interestIdFromNotification(n) != interestId) continue;
      final id = n['id'] as String? ?? '';
      if (id.isEmpty) continue;
      await markAsRead(id);
    }
  }

  /// Marks [interest_received] (and related) notifications read when the
  /// interest row is viewed, responded to, or no longer pending — keeps
  /// notification unread counts aligned with the Interests hub.
  Future<void> reconcileInterestReceivedNotifications(
    Iterable<dynamic> receivedInterests,
  ) async {
    final settledIds = <String>{};
    for (final raw in receivedInterests) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (!InterestBadgeAggregator.interestRowClearsReceivedNotification(row)) {
        continue;
      }
      final id = InterestBadgeAggregator.interestDocumentId(row);
      if (id.isNotEmpty) settledIds.add(id);
    }
    if (settledIds.isEmpty) return;

    for (final n in _notifications) {
      if (!NotificationRepository.isUnread(n)) continue;
      final type = (n['type'] as String? ?? '').trim();
      if (!_interestHubNotificationTypes.contains(type)) continue;
      final interestId = _interestIdFromNotification(n);
      if (interestId == null || !settledIds.contains(interestId)) continue;
      final id = n['id'] as String? ?? '';
      if (id.isEmpty) continue;
      await markAsRead(id);
    }
  }

  /// Live privacy-request snapshots (from header listeners).
  void updatePrivacyRequestSnapshots({
    required Map<String, String> requestDocStatuses,
    required Set<String> pendingIncomingRequestDocIds,
  }) {
    _privacyRequestStatuses = Map<String, String>.from(requestDocStatuses);
    _pendingIncomingPrivacyDocIds =
        Set<String>.from(pendingIncomingRequestDocIds);
    unawaited(reconcilePrivacyRequestNotifications());
  }

  /// Clears unread rows tied to one request doc (after grant/deny/send outcome).
  Future<void> markPrivacyNotificationsReadForRequestDoc(
    String requestDocId, {
    String? settledStatus,
  }) async {
    final docId = requestDocId.trim();
    if (docId.isEmpty) return;
    if (settledStatus != null && settledStatus.trim().isNotEmpty) {
      _privacyRequestStatuses[docId] =
          PrivacyRequestNotificationSync.normalizeStatus(settledStatus);
      _pendingIncomingPrivacyDocIds.remove(docId);
    }

    for (final n in _notifications) {
      if (!NotificationRepository.isUnread(n)) continue;
      if (PrivacyRequestNotificationSync.requestDocIdFromNotification(n) !=
          docId) {
        continue;
      }
      final type = (n['type'] as String? ?? '').trim();
      final isPrivacy = PrivacyRequestNotificationSync.incomingTypes
              .contains(type) ||
          PrivacyRequestNotificationSync.outcomeTypes.contains(type);
      if (!isPrivacy) continue;
      final id = n['id'] as String? ?? '';
      if (id.isEmpty) continue;
      await markAsRead(id);
    }
  }

  /// Marks privacy-request notifications read when Firestore request docs
  /// are no longer pending (owner) or have a final status (requester).
  Future<void> reconcilePrivacyRequestNotifications() async {
    if (_privacyRequestStatuses.isEmpty &&
        _pendingIncomingPrivacyDocIds.isEmpty) {
      return;
    }

    for (final n in _notifications) {
      if (!NotificationRepository.isUnread(n)) continue;
      final type = (n['type'] as String? ?? '').trim();
      final docId = PrivacyRequestNotificationSync.requestDocIdFromNotification(n);
      if (docId == null) continue;

      final shouldRead = PrivacyRequestNotificationSync.shouldMarkNotificationRead(
        type: type,
        requestDocId: docId,
        pendingIncomingRequestDocIds: _pendingIncomingPrivacyDocIds,
        requestDocStatuses: _privacyRequestStatuses,
      );
      if (!shouldRead) continue;
      final id = n['id'] as String? ?? '';
      if (id.isEmpty) continue;
      await markAsRead(id);
    }
  }

  /// One-shot fetch of request docs for reconcile (Notifications screen, etc.).
  Future<void> refreshPrivacyRequestReconcile(
    String userId, {
    String profileId = '',
    String authUid = '',
  }) async {
    if (userId.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final statuses = <String, String>{};
    final pendingIncoming = <String>{};

    void absorbDoc(String docId, Map<String, dynamic> data, {required bool ownerRow}) {
      final st = PrivacyRequestNotificationSync.normalizeStatus(data['status']);
      statuses[docId] = st;
      if (ownerRow && st == 'pending') {
        pendingIncoming.add(docId);
      }
    }

    Future<void> runQuery(
      Future<QuerySnapshot<Map<String, dynamic>>> query, {
      required bool Function(Map<String, dynamic> data) isOwnerRow,
    }) async {
      try {
        final snap = await query;
        for (final d in snap.docs) {
          final data = d.data();
          absorbDoc(d.id, data, ownerRow: isOwnerRow(data));
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') return;
        rethrow;
      }
    }

    Future<void> loadBirth() async {
      await runQuery(
        db.collection('birth_requests').where('owner_id', isEqualTo: userId).get(),
        isOwnerRow: (data) =>
            (data['owner_id'] as String? ?? '').trim() == userId,
      );
      await runQuery(
        db
            .collection('birth_requests')
            .where('requester_id', isEqualTo: userId)
            .get(),
        isOwnerRow: (_) => false,
      );
      if (authUid.isNotEmpty) {
        await runQuery(
          db
              .collection('birth_requests')
              .where('owner_auth_uid', isEqualTo: authUid)
              .get(),
          isOwnerRow: (data) {
            final ownerAuth =
                (data['owner_auth_uid'] as String? ?? '').trim();
            final ownerId = (data['owner_id'] as String? ?? '').trim();
            return ownerAuth == authUid || ownerId == userId;
          },
        );
      }
    }

    Future<void> loadCommunity() async {
      await runQuery(
        db
            .collection('community_reference_requests')
            .where('owner_id', isEqualTo: userId)
            .get(),
        isOwnerRow: (data) =>
            (data['owner_id'] as String? ?? '').trim() == userId,
      );
      await runQuery(
        db
            .collection('community_reference_requests')
            .where('requester_id', isEqualTo: userId)
            .get(),
        isOwnerRow: (_) => false,
      );
      if (authUid.isNotEmpty) {
        await runQuery(
          db
              .collection('community_reference_requests')
              .where('owner_auth_uid', isEqualTo: authUid)
              .get(),
          isOwnerRow: (data) {
            final ownerAuth =
                (data['owner_auth_uid'] as String? ?? '').trim();
            final ownerId = (data['owner_id'] as String? ?? '').trim();
            return ownerAuth == authUid || ownerId == userId;
          },
        );
      }
    }

    Future<void> loadPhoto() async {
      await runQuery(
        db
            .collection('photo_requests')
            .where('to_user_id', isEqualTo: userId)
            .get(),
        isOwnerRow: (data) =>
            (data['to_user_id'] as String? ?? '').trim() == userId,
      );
      await runQuery(
        db
            .collection('photo_requests')
            .where('from_user_id', isEqualTo: userId)
            .get(),
        isOwnerRow: (_) => false,
      );
      if (profileId.isNotEmpty) {
        await runQuery(
          db
              .collection('photo_requests')
              .where('to_profile_id', isEqualTo: profileId)
              .get(),
          isOwnerRow: (data) {
            final toUser = (data['to_user_id'] as String? ?? '').trim();
            final toProfile =
                (data['to_profile_id'] as String? ?? '').trim();
            return toUser == userId || toProfile == profileId;
          },
        );
      }
    }

    try {
      await Future.wait([loadBirth(), loadCommunity(), loadPhoto()]);
      updatePrivacyRequestSnapshots(
        requestDocStatuses: statuses,
        pendingIncomingRequestDocIds: pendingIncoming,
      );
    } catch (e) {
      Log.w('❌ [Notif] refreshPrivacyRequestReconcile: $e');
    }
  }

  // ── Mark read ─────────────────────────────────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    final idx =
        _notifications.indexWhere((n) => n['id'] == notificationId);
    if (idx != -1) {
      _notifications[idx] = {
        ..._notifications[idx],
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      };
      _unreadCount = _countUnread(_notifications);
      _safeNotify();  // 🔥 FIX: Use safe notify
    }
    try {
      await _repo.markRead(notificationId);
    } catch (e) {
      Log.w('❌ [Notif] markAsRead: $e');
    }
  }

  Future<void> markAllAsRead(String userId) async {
    _notifications = _notifications
        .map((n) => {
              ...n,
              'is_read': true,
              'read_at': DateTime.now().toIso8601String(),
            })
        .toList();
    _unreadCount = 0;
    _safeNotify();  // 🔥 FIX: Use safe notify
    try {
      await _repo.markAllRead(userId);
    } catch (e) {
      Log.w('❌ [Notif] markAllAsRead: $e');
    }
  }

  Future<void> markProfileViewNotificationsRead() async {
    String normalizeType(dynamic raw) =>
        (raw as String? ?? '').trim().toLowerCase().replaceAll('-', '_');

    final unreadProfileViewIds = _notifications
        .where(NotificationRepository.isUnread)
        .where((n) => normalizeType(n['type']) == NotificationType.profileView)
        .map((n) => (n['id'] as String? ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (unreadProfileViewIds.isEmpty) return;
    await Future.wait(unreadProfileViewIds.map(markAsRead));
  }

  Future<void> markSingleProfileViewNotificationRead({
    String? viewerUserId,
    String? viewerProfileId,
  }) async {
    String normalizeType(dynamic raw) =>
        (raw as String? ?? '').trim().toLowerCase().replaceAll('-', '_');
    String norm(dynamic raw) => (raw as String? ?? '').trim().toLowerCase();

    final unreadProfileView = _notifications
        .where(NotificationRepository.isUnread)
        .where((n) => normalizeType(n['type']) == NotificationType.profileView)
        .toList(growable: false);
    if (unreadProfileView.isEmpty) return;

    final viewerId = norm(viewerUserId);
    final profileId = norm(viewerProfileId);

    bool matchesViewer(Map<String, dynamic> n) {
      final dataRaw = n['data'];
      final data = dataRaw is Map
          ? Map<String, dynamic>.from(dataRaw as Map<dynamic, dynamic>)
          : const <String, dynamic>{};
      final probes = <String>{
        norm(n['from_user']),
        norm(n['from_user_id']),
        norm(n['viewer_user_id']),
        norm(n['viewer_id']),
        norm(n['viewer_profile_id']),
        norm(data['from_user']),
        norm(data['from_user_id']),
        norm(data['viewer_user_id']),
        norm(data['viewer_id']),
        norm(data['viewer_profile_id']),
      }..remove('');
      if (viewerId.isNotEmpty && probes.contains(viewerId)) return true;
      if (profileId.isNotEmpty && probes.contains(profileId)) return true;
      return false;
    }

    final target = unreadProfileView.cast<Map<String, dynamic>?>().firstWhere(
          (n) => n != null && matchesViewer(n),
          orElse: () => unreadProfileView.first,
        );
    final id = (target?['id'] as String? ?? '').trim();
    if (id.isEmpty) return;
    await markAsRead(id);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteNotification(String id) async {
    if (id.isEmpty) return;

    // Check ownership before deleting using stored user ID
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('current_user_id') ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      _deletedIds.add(id);
      _notifications.removeWhere((n) => n['id'] == id);
      _unreadCount = _countUnread(_notifications);
      _safeNotify();  // 🔥 FIX: Use safe notify

      // Rules enforce ownership; keep UI optimistic.
      await _repo.delete(id);
      Log.d('✅ [Notif] Deleted notification: $id');
    } catch (e) {
      _deletedIds.remove(id);
      Log.w('❌ [Notif] Failed to delete notification: $e');
      rethrow;
    }
  }

  Future<void> clearAllNotifications(String userId) async {
    if (userId.isEmpty) return;

    final idsToGuard = _notifications
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    try {
      _deletedIds.addAll(idsToGuard);
      _notifications.clear();
      _unreadCount = 0;
      _safeNotify();  // 🔥 FIX: Use safe notify

      await FirebaseFirestore.instance
          .collection('notifications')
          .where('user_id', isEqualTo: userId)  // 🔥 FIX: snake_case
          .get()
          .then((snapshot) {
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in snapshot.docs) {
              batch.delete(doc.reference);
            }
            return batch.commit();
          });
      Log.d('✅ [Notif] Cleared all notifications for $userId');
    } catch (e) {
      Log.w('❌ [Notif] clearAllNotifications failed: $e');
      _deletedIds.removeAll(idsToGuard);
      await loadNotifications(userId, force: true);
      rethrow;
    }
  }

  // ── Send notification helper ───────────────────────────────────────────────

  Future<void> sendMatchNotification(String targetUserId) async {
    if (targetUserId.isEmpty) return;
    final from = await _notificationFromUserId();
    if (from == null || from.isEmpty) return;
    try {
      await _db.collection('notifications').add({
        'user_id': targetUserId,
        'to_user': targetUserId,
        'from_user': from,
        'type': 'match',
        'title': 'New Match!',
        'body': 'You have a new mutual match.',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      Log.w('❌ [Notif] sendMatchNotification: $e');
    }
  }

  /// Add a new notification to Firestore
  Future<void> addNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (userId.isEmpty) return;

    try {
      final from = await _notificationFromUserId() ?? '';
      if (from.isEmpty) return;
      await _db.collection('notifications').add({
        'user_id': userId,
        // Cross-user creates must satisfy firestore.rules (to_user + from_user + notificationFromUserIsCaller).
        'to_user': userId,
        'from_user': from,
        'type': type,
        'title': title,
        'body': body,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
        if (data != null) 'data': data,
      });
      Log.d('✅ [Notif] Notification sent to $userId: $type');
    } catch (e) {
      Log.w('❌ [Notif] Failed to add notification: $e');
    }
  }

  // ── Interest Notifications ───────────────────────────────────────────────

  /// Notify receiver that someone sent them interest
  Future<void> sendInterestReceivedNotification({
    required String toUserId,
    required String fromUserId,
    String? fromFirstName,
    String? fromLastName,
  }) async {
    final senderName = [fromFirstName, fromLastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final displayName = senderName.isNotEmpty ? senderName : 'Someone';

    await addNotification(
      userId: toUserId,
      type: 'interest_received',
      title: 'New Interest Received!',
      body: '$displayName is interested in your profile',
      data: {
        'from_user_id': fromUserId,
        'from_first_name': fromFirstName,
        'from_last_name': fromLastName,
      },
    );
  }

  /// Notify sender that their interest was accepted
  Future<void> sendInterestAcceptedNotification({
    required String toUserId, // The original sender
    required String fromUserId, // The receiver who accepted
    String? fromFirstName,
    String? fromLastName,
  }) async {
    final receiverName = [fromFirstName, fromLastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final displayName = receiverName.isNotEmpty ? receiverName : 'Someone';

    await addNotification(
      userId: toUserId,
      type: 'interest_accepted',
      title: 'Interest Accepted! 🎉',
      body: '$displayName accepted your interest. You can now chat!',
      data: {
        'from_user_id': fromUserId,
        'from_first_name': fromFirstName,
        'from_last_name': fromLastName,
      },
    );
  }

  /// Notify sender that their interest was rejected
  Future<void> sendInterestRejectedNotification({
    required String toUserId,
    required String fromUserId,
    String? fromFirstName,
    String? fromLastName,
  }) async {
    final receiverName = [fromFirstName, fromLastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final displayName = receiverName.isNotEmpty ? receiverName : 'Someone';

    await addNotification(
      userId: toUserId,
      type: 'interest_rejected',
      title: 'Interest Response',
      body: '$displayName is not interested at this time',
      data: {
        'from_user_id': fromUserId,
        'from_first_name': fromFirstName,
        'from_last_name': fromLastName,
      },
    );
  }
}
