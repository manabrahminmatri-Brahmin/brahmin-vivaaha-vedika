import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/access_request_status.dart';
import '../../core/safe_profile_nav.dart';
import '../../core/backend/firestore_service.dart';
import '../../core/interest_badge_aggregator.dart';
import '../../core/interest_identity_resolver.dart';
import '../../services/interests_hub_analytics.dart';
import '../../services/matrimony_gateway_service.dart';
import '../../services/interests_access_policy.dart';
import '../../core/request_ui_contract.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../legacy/compatibility.dart' hide AuthService;
import '../../services/block_service.dart';
import '../../services/chat_service.dart';
import '../../services/message_service.dart';
import '../../services/birth_details_service.dart';
import '../../services/community_reference_service.dart';
import '../../services/photo_service.dart';
import '../../services/privacy_request_view_service.dart';
import '../../services/sent_access_requests_loader.dart';
import '../../services/access_request_visibility.dart';
import '../../services/engagement_gateway_service.dart';
import 'interest_row_helpers.dart';
import '../../services/access_request_broadcast.dart';
import '../../services/privacy_enforcement_service.dart';
import '../../features/profile/profile_repository.dart';
import '../../repositories/interest_analytics_repository.dart';
import '../../widgets/request_action_bar.dart';
import '../../core/app_router.dart';
import '../chat/chat_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../theme/app_sizes.dart';
import '../../models/user.dart';
import '../../widgets/app_header.dart';
import '../profile/who_saw_your_profile_screen.dart';

// Global key for interests analytics screen
class InterestsAnalyticsScreenKey {
  static const interestsTab = ValueKey('interests_tab');
  static const receivedTab = ValueKey('received_tab');
  static const sentTab = ValueKey('sent_tab');
}

void _lightTapFeedback() {
  unawaited(HapticFeedback.selectionClick());
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-level helpers
// ─────────────────────────────────────────────────────────────────────────────

String _fmtTs(String ts) {
  if (ts.isEmpty) return '';
  try {
    final dt = DateTime.parse(ts);
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  } catch (e) {
    return '';
  }
}

String _normalizeRequestStatus(String raw) {
  final status = raw.trim().toLowerCase();
  if (status == 'sent') return 'pending';
  if (status == 'approved' || status == 'granted') return 'accepted';
  if (status == 'denied' || status == 'declined') return 'rejected';
  if (status == AccessRequestStatus.stopped) return 'stopped';
  return status;
}

bool _isVisibleRequestStatus(dynamic rawStatus) {
  final status = _normalizeRequestStatus(rawStatus as String? ?? 'pending');
  return status != 'withdrawn' &&
      status != 'inactive' &&
      status != 'deleted';
}

/// Sort interests by newest activity first (Firestore [Timestamp] or ISO [String]).
int _interestSortMillis(dynamic ts) {
  if (ts == null) return 0;
  if (ts is Timestamp) return ts.millisecondsSinceEpoch;
  if (ts is String) {
    final dt = DateTime.tryParse(ts);
    return dt?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}

/// Display label — prefers [updated_at] when set (status changes).
String _interestTimeLabel(Map<String, dynamic> data) {
  final ts = data['updated_at'] ?? data['created_at'];
  return _formatInterestTimestamp(ts);
}

/// Incoming birth/community/photo cards: show when the request was **received**
/// ([created_at]), not [updated_at] (viewed/reminder merges must not reset "0m ago").
String _receivedAccessRequestTimeLabel(Map<String, dynamic> data) {
  final status = _normalizeRequestStatus(data['status'] as String? ?? 'pending');
  final dynamic ts;
  if (status == 'pending' || status == 'sent') {
    ts = data['created_at'] ??
        data['requested_at'] ??
        data['sent_at'] ??
        data['updated_at'];
  } else {
    ts = data['updated_at'] ?? data['created_at'];
  }
  final ago = _formatInterestTimestamp(ts);
  if (ago.isEmpty) return '';
  if (status == 'pending' || status == 'sent') {
    return 'Received $ago';
  }
  return ago;
}

String _formatInterestTimestamp(dynamic ts) {
  if (ts is Timestamp) return _fmtTs(ts.toDate().toIso8601String());
  if (ts is DateTime) return _fmtTs(ts.toIso8601String());
  if (ts is String && ts.trim().isNotEmpty) return _fmtTs(ts);
  if (ts is int) {
    return _fmtTs(
      DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toIso8601String(),
    );
  }
  return '';
}

/// One broadcast stream per profile id — avoids resubscribe/log spam on rebuild.
class _ProfileViewersStreamCache {
  static String? _key;
  static Stream<List<Map<String, dynamic>>>? _stream;

  static Stream<List<Map<String, dynamic>>> forProfile(String profileId) {
    final k = profileId.trim();
    if (k.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }
    if (_key == k && _stream != null) return _stream!;
    _key = k;
    _stream =
        FirebaseService().profileViewersStream(k).asBroadcastStream();
    return _stream!;
  }
}

String _statusLbl(String status) {
  switch (_normalizeRequestStatus(status)) {
    case 'pending':
      return 'Pending';
    case 'sent':
      return 'Pending';
    case 'accepted':
      return 'Accepted';
    case 'rejected':
      return 'Rejected';
    case 'revoked':
      return 'Revoked';
    case 'stopped':
      return 'Stopped';
    case 'withdrawn':
      return 'Withdrawn';
    default:
      return status;
  }
}

Color _statusClr(String status) {
  switch (_normalizeRequestStatus(status)) {
    case 'pending':
      return AppTheme.primaryOrange;
    case 'sent':
      return AppTheme.primaryOrange;
    case 'accepted':
      return AppTheme.sacredGreen;
    case 'rejected':
      return AppTheme.kumkumRed;
    case 'revoked':
      return AppTheme.kumkumRed;
    case 'stopped':
      return AppTheme.primaryOrange;
    case 'withdrawn':
      return AppTheme.textMedium;
    default:
      return AppTheme.textMedium;
  }
}

/// Badge text for hub tabs; hides zero unless [showZero].
String? _tabBadge(int n, {bool showZero = false}) {
  if (!showZero && n <= 0) return null;
  if (n > 99) return '99+';
  return '$n';
}

class _PrivacyRowAccess {
  final bool canViewProfile;
  final bool canViewIdentity;
  final bool canViewPhoto;
  final bool requiresPremium;
  final bool requiresApproval;

  const _PrivacyRowAccess({
    required this.canViewProfile,
    required this.canViewIdentity,
    required this.canViewPhoto,
    this.requiresPremium = false,
    this.requiresApproval = false,
  });
}

// Lightweight in-memory caches for high-frequency list rows.
final Map<String, Future<User?>> _userByAnyIdCache = <String, Future<User?>>{};
final Map<String, Future<Map<String, dynamic>?>> _userDocCache =
    <String, Future<Map<String, dynamic>?>>{};
final Map<String, Future<_PrivacyRowAccess>> _privacyRowAccessCache =
    <String, Future<_PrivacyRowAccess>>{};
final Map<String, Future<({User? user, _PrivacyRowAccess access})>>
    _peerViewDataCache =
    <String, Future<({User? user, _PrivacyRowAccess access})>>{};
const int _kUserByAnyIdCacheMax = 250;
const int _kUserDocCacheMax = 250;
const int _kPrivacyAccessCacheMax = 500;
const int _kPeerViewCacheMax = 500;

T _lruGetOrPut<T>({
  required Map<String, T> cache,
  required String key,
  required int maxEntries,
  required T Function() ifAbsent,
}) {
  final existing = cache[key];
  if (existing != null) {
    // Touch key: remove/reinsert to preserve insertion-order LRU.
    cache.remove(key);
    cache[key] = existing;
    return existing;
  }
  final value = ifAbsent();
  cache[key] = value;
  while (cache.length > maxEntries) {
    cache.remove(cache.keys.first);
  }
  return value;
}

Future<_PrivacyRowAccess> _cachedPrivacyRowAccess({
  required User? viewer,
  required User? candidate,
  required String fallbackUserId,
  bool requiresAccepted = false,
  bool isAccepted = false,
}) {
  final viewerKey = (viewer?.id ?? '').trim();
  final targetKey = (candidate?.id ?? '').trim();
  final fallback = fallbackUserId.trim();
  final key =
      '$viewerKey|$targetKey|$fallback|$requiresAccepted|$isAccepted';
  return _lruGetOrPut(
    cache: _privacyRowAccessCache,
    key: key,
    maxEntries: _kPrivacyAccessCacheMax,
    ifAbsent: () => _resolvePrivacyAccessForViewer(
      viewer: viewer,
      candidate: candidate,
      fallbackUserId: fallback,
      requiresAccepted: requiresAccepted,
      isAccepted: isAccepted,
    ),
  );
}

Future<({User? user, _PrivacyRowAccess access})> _cachedPeerViewData({
  required User? viewer,
  required String otherUserId,
}) {
  final viewerId = (viewer?.id ?? '').trim();
  final key = '$viewerId|${otherUserId.trim()}|accepted:true';
  return _lruGetOrPut(
    cache: _peerViewDataCache,
    key: key,
    maxEntries: _kPeerViewCacheMax,
    ifAbsent: () async {
      final user = await _cachedUserByAnyId(otherUserId);
      final access = await _cachedPrivacyRowAccess(
        viewer: viewer,
        candidate: user,
        fallbackUserId: otherUserId,
        requiresAccepted: true,
        isAccepted: true,
      );
      return (user: user, access: access);
    },
  );
}

Future<User?> _cachedUserByAnyId(String id) {
  final key = id.trim();
  if (key.isEmpty) return Future<User?>.value(null);
  return _lruGetOrPut(
    cache: _userByAnyIdCache,
    key: key,
    maxEntries: _kUserByAnyIdCacheMax,
    ifAbsent: () => ProfileRepository().lookupUserByAnyId(key),
  );
}

Future<Map<String, dynamic>?> _cachedUserDoc(String userId) {
  final key = userId.trim();
  if (key.isEmpty) return Future<Map<String, dynamic>?>.value(null);
  return _lruGetOrPut(
    cache: _userDocCache,
    key: key,
    maxEntries: _kUserDocCacheMax,
    ifAbsent: () async {
      return ProfileRepository().getUserDocumentDataCacheFirst(key);
    },
  );
}

Future<_PrivacyRowAccess> _resolvePrivacyAccess({
  required BuildContext context,
  required User? candidate,
  required String fallbackUserId,
  bool requiresAccepted = false,
  bool isAccepted = false,
}) async {
  final viewer = context.read<AuthService>().currentUser;
  return _resolvePrivacyAccessForViewer(
    viewer: viewer,
    candidate: candidate,
    fallbackUserId: fallbackUserId,
    requiresAccepted: requiresAccepted,
    isAccepted: isAccepted,
  );
}

Future<_PrivacyRowAccess> _resolvePrivacyAccessForViewer({
  required User? viewer,
  required User? candidate,
  required String fallbackUserId,
  bool requiresAccepted = false,
  bool isAccepted = false,
}) async {
  if (viewer == null) {
    return const _PrivacyRowAccess(
      canViewProfile: false,
      canViewIdentity: false,
      canViewPhoto: false,
    );
  }

  User? target = candidate;
  if (target == null && fallbackUserId.trim().isNotEmpty) {
    try {
      target = await _cachedUserByAnyId(fallbackUserId.trim());
    } catch (_) {}
  }
  if (target == null) {
    return const _PrivacyRowAccess(
      canViewProfile: false,
      canViewIdentity: false,
      canViewPhoto: false,
    );
  }

  Map<String, dynamic>? doc;
  try {
    doc = await _cachedUserDoc(target.id);
  } catch (_) {}

  final privacy = PrivacyEnforcementService();
  final canViewProfile = privacy.canViewerSeeProfile(
    viewer: viewer,
    candidate: target,
    candidateDoc: doc,
  );
  final requiresPremium =
      PrivacyEnforcementService.isPremiumOnlyVisibility(doc) &&
          !viewer.membership.isPremium;
  final isPhotoHidden = PrivacyEnforcementService.isPhotoHiddenFromOthers(
    doc,
    fromParsedProfile: target.profile?.isPhotoPrivate ??
        target.profileForDiscovery.isPhotoPrivate ??
        false,
  );
  final requiresApproval =
      (PrivacyEnforcementService.hidePhotosUntilAccepted(doc) ||
              PrivacyEnforcementService.blurPhotosForStrangers(doc)) &&
          !(requiresAccepted && isAccepted);

  if (!canViewProfile) {
    return _PrivacyRowAccess(
      canViewProfile: false,
      canViewIdentity: false,
      canViewPhoto: false,
      requiresPremium: requiresPremium,
      requiresApproval: requiresApproval,
    );
  }

  // Hidden/private photos need an explicit photo-request grant (not just interest).
  if (isPhotoHidden) {
    var hasPhotoGrant = false;
    try {
      hasPhotoGrant = await FirestoreService().canViewPhoto(viewer.id, target.id);
    } catch (_) {}
    return _PrivacyRowAccess(
      canViewProfile: true,
      canViewIdentity: true,
      canViewPhoto: hasPhotoGrant,
      requiresPremium: requiresPremium,
      requiresApproval: !hasPhotoGrant,
    );
  }

  return _PrivacyRowAccess(
    canViewProfile: true,
    canViewIdentity: true,
    canViewPhoto: !requiresApproval,
    requiresPremium: requiresPremium,
    requiresApproval: requiresApproval,
  );
}

String _protectedSubtitle(_PrivacyRowAccess access) {
  if (access.requiresPremium) return 'Details available for premium viewers';
  if (access.requiresApproval) return 'Details available after approval';
  return 'Protected profile';
}

/// Prime notification/message stores, then push the app-wide notifications route.
Future<void> openAppNotificationsScreen(BuildContext context) async {
  final uid = (context.read<AuthService>().currentUser?.id ?? '').trim();
  if (uid.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to view notifications.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
    return;
  }
  final ns = context.read<NotificationService>();
  final ms = context.read<MessageService>();
  ns.startListening(uid);
  try {
    await Future.wait([
      ns.loadNotifications(uid, limit: 100),
      ms.loadMessages(uid),
    ]);
  } catch (e) {
    debugPrint('openAppNotificationsScreen preload failed: $e');
  }
  if (!context.mounted) return;
  await NavHelper.push(context, Routes.notifications);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// When true, omits [Center] so the widget is safe inside [ListView] children.
  final bool inline;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: EdgeInsets.all(inline ? 16 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: inline ? 48 : 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: inline ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
    if (inline) return body;
    return Center(child: body);
  }
}

/// Stable profile id for interest rows — never null during build.
String _resolvedPeerProfileId({
  required Map<String, dynamic> data,
  required bool isReceived,
  User? liveUser,
}) {
  final snapshot = InterestRowHelpers.peerProfileId(
    data,
    isReceived: isReceived,
  );
  if (snapshot.isNotEmpty) return snapshot;
  return (liveUser?.profileId ?? '').trim();
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Matches [SettingsScreen] TabBar: label uses the tab row’s [DefaultTextStyle]
/// (15 / w700 selected, 15 / w500 unselected) — do not hardcode a smaller font.
class _TabLabel extends StatelessWidget {
  final String label;
  final String? badge;
  final Color badgeColor;
  const _TabLabel(this.label, this.badge, this.badgeColor);

  @override
  Widget build(BuildContext context) {
    final labelStyle = DefaultTextStyle.of(context).style;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: labelStyle),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERESTS ANALYTICS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class InterestsAnalyticsScreen extends StatefulWidget {
  final int initialTabIndex;

  /// When true (main [HomeScreen] tab), scroll padding clears the floating
  /// glass bottom nav. When false (pushed route / [MessagesScreen]), use safe
  /// area only.
  final bool embeddedInMainShell;

  const InterestsAnalyticsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.embeddedInMainShell = false,
  });

  @override
  State<InterestsAnalyticsScreen> createState() =>
      _InterestsAnalyticsScreenState();
}

enum _IncomingRequestBucket {
  birthOwner,
  birthOwnerAuth,
  communityOwner,
  communityOwnerAuth,
  photoOwner,
  photoOwnerProfile,
}

class _InterestsAnalyticsScreenState extends State<InterestsAnalyticsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isLoading = false;
  _SentInterestFilter _sentFilterHint = _SentInterestFilter.all;
  String? _requestListeningKey;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _birthOwnerSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _birthOwnerAuthSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _communityOwnerSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>?
      _communityOwnerAuthSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _photoOwnerSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>?
      _photoOwnerProfileSub;
  Map<String, Map<String, dynamic>> _birthOwnerRows =
      <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _birthOwnerAuthRows =
      <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _communityOwnerRows =
      <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _communityOwnerAuthRows =
      <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _photoOwnerRows =
      <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> _photoOwnerProfileRows =
      <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _sentOutgoingPrivacyRows =
      <Map<String, dynamic>>[];
  String? _lastSentPrivacyAliasKey;
  bool _engagementPruneStarted = false;
  Timer? _incomingRowsDebounce;
  final Map<_IncomingRequestBucket, Map<String, Map<String, dynamic>>>
      _pendingIncomingRaw = <_IncomingRequestBucket,
          Map<String, Map<String, dynamic>>>{};
  int _incomingFilterSerial = 0;
  bool _incomingListenersPrimed = false;
  String? _boundMessageUserId;
  final ValueNotifier<int> _incomingRequestsRevision =
      ValueNotifier<int>(0);

  void _queueIncomingRowUpdate(
    _IncomingRequestBucket bucket,
    Map<String, Map<String, dynamic>> raw,
  ) {
    _pendingIncomingRaw[bucket] = raw;
    _incomingRowsDebounce?.cancel();
    _incomingRowsDebounce = Timer(const Duration(milliseconds: 120), () {
      // ignore: discarded_futures
      _flushPendingIncomingRows();
    });
  }

  static bool _incomingRowMapsEqual(
    Map<String, Map<String, dynamic>> a,
    Map<String, Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key]?['id'] != b[key]?['id']) return false;
      if (a[key]?['status'] != b[key]?['status']) return false;
      if (a[key]?['updated_at'] != b[key]?['updated_at']) return false;
    }
    return true;
  }

  static String _privacyKindForBucket(_IncomingRequestBucket bucket) {
    switch (bucket) {
      case _IncomingRequestBucket.birthOwner:
      case _IncomingRequestBucket.birthOwnerAuth:
        return 'birth';
      case _IncomingRequestBucket.communityOwner:
      case _IncomingRequestBucket.communityOwnerAuth:
        return 'community';
      case _IncomingRequestBucket.photoOwner:
      case _IncomingRequestBucket.photoOwnerProfile:
        return 'photo';
    }
  }

  Map<String, Map<String, dynamic>> _tagIncomingBucket(
    _IncomingRequestBucket bucket,
    Map<String, Map<String, dynamic>> rows,
  ) {
    final kind = _privacyKindForBucket(bucket);
    return {
      for (final e in rows.entries)
        e.key: InterestBadgeAggregator.tagPrivacyRequestKind(e.value, kind),
    };
  }

  bool _applyIncomingBucket(
    _IncomingRequestBucket bucket,
    Map<String, Map<String, dynamic>> filtered,
  ) {
    switch (bucket) {
      case _IncomingRequestBucket.birthOwner:
        if (_incomingRowMapsEqual(_birthOwnerRows, filtered)) return false;
        _birthOwnerRows = filtered;
        return true;
      case _IncomingRequestBucket.birthOwnerAuth:
        if (_incomingRowMapsEqual(_birthOwnerAuthRows, filtered)) return false;
        _birthOwnerAuthRows = filtered;
        return true;
      case _IncomingRequestBucket.communityOwner:
        if (_incomingRowMapsEqual(_communityOwnerRows, filtered)) return false;
        _communityOwnerRows = filtered;
        return true;
      case _IncomingRequestBucket.communityOwnerAuth:
        if (_incomingRowMapsEqual(_communityOwnerAuthRows, filtered)) {
          return false;
        }
        _communityOwnerAuthRows = filtered;
        return true;
      case _IncomingRequestBucket.photoOwner:
        if (_incomingRowMapsEqual(_photoOwnerRows, filtered)) return false;
        _photoOwnerRows = filtered;
        return true;
      case _IncomingRequestBucket.photoOwnerProfile:
        if (_incomingRowMapsEqual(_photoOwnerProfileRows, filtered)) {
          return false;
        }
        _photoOwnerProfileRows = filtered;
        return true;
    }
  }

  Future<void> _flushPendingIncomingRows() async {
    if (_pendingIncomingRaw.isEmpty) return;
    final serial = ++_incomingFilterSerial;
    final pending = Map<_IncomingRequestBucket,
        Map<String, Map<String, dynamic>>>.from(_pendingIncomingRaw);
    _pendingIncomingRaw.clear();

    final filteredEntries = await Future.wait(
      pending.entries.map((e) async {
        final tagged = _tagIncomingBucket(e.key, e.value);
        final filtered =
            await AccessRequestVisibility.filterIncomingOwnerRows(tagged);
        return MapEntry(e.key, filtered);
      }),
    );

    if (!mounted || serial != _incomingFilterSerial) return;

    var changed = false;
    for (final entry in filteredEntries) {
      changed |= _applyIncomingBucket(entry.key, entry.value);
    }
    _incomingListenersPrimed = true;
    if (changed && mounted) _incomingRequestsRevision.value++;
  }

  void _pruneStaleEngagementOnce() {
    if (_engagementPruneStarted) return;
    _engagementPruneStarted = true;
    unawaited(
      EngagementGatewayService.pruneStaleEngagementForMe().then((_) {
        AccessRequestVisibility.invalidateCache();
        SentAccessRequestsLoader.invalidateCache();
        if (!mounted) return;
        // ignore: discarded_futures
        _refreshSentOutgoingPrivacyRows();
      }),
    );
  }

  void _onTabChanged() {
    // 🔥 FIX: Don't call setState here - TabController already notifies listeners
    // Only rebuild if we need to update UI based on tab index
  }

  void _openTab(int index) {
    if (!mounted) return;
    final safeIndex = index.clamp(0, 5);
    if (_tabController.index == safeIndex) return;
    _tabController.animateTo(safeIndex);
  }

  void _openSentTab({_SentInterestFilter filter = _SentInterestFilter.all}) {
    if (!mounted) return;
    setState(() => _sentFilterHint = filter);
    _openTab(2);
  }

  /// Called from shell when user re-taps Interests bottom nav.
  void refresh() {
    // ignore: discarded_futures
    _refreshData();
  }

  /// Open a hub sub-tab (0=Overview … 1=Received … 5=Blocked).
  void openHubTab(int index) {
    _openTab(index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
    // Same pattern as [SettingsScreen] so tab indicator/labels repaint while dragging.
    _tabController.addListener(_onTabChanged);
    AccessRequestBroadcast.tick.addListener(_onHubAccessRequestPulse);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pruneStaleEngagementOnce();
        _refreshData();
      }
    });
  }

  void _onHubAccessRequestPulse() {
    if (!mounted) return;
    SentAccessRequestsLoader.invalidateCache();
    // ignore: discarded_futures
    _refreshSentOutgoingPrivacyRows();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Web: lifecycle resume can fire before the engine window is ready (window.dart assert).
    if (kIsWeb || state != AppLifecycleState.resumed || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SentAccessRequestsLoader.invalidateCache();
      // ignore: discarded_futures
      _refreshData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccessRequestBroadcast.tick.removeListener(_onHubAccessRequestPulse);
    _incomingRowsDebounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _stopIncomingRequestListeners();
    _incomingRequestsRevision.dispose();
    super.dispose();
  }

  void _stopIncomingRequestListeners({bool clearRows = true}) {
    _incomingRowsDebounce?.cancel();
    _incomingRowsDebounce = null;
    _pendingIncomingRaw.clear();
    _incomingFilterSerial++;
    _birthOwnerSub?.cancel();
    _birthOwnerAuthSub?.cancel();
    _communityOwnerSub?.cancel();
    _communityOwnerAuthSub?.cancel();
    _photoOwnerSub?.cancel();
    _photoOwnerProfileSub?.cancel();
    _birthOwnerSub = null;
    _birthOwnerAuthSub = null;
    _communityOwnerSub = null;
    _communityOwnerAuthSub = null;
    _photoOwnerSub = null;
    _photoOwnerProfileSub = null;
    _requestListeningKey = null;
    if (clearRows) {
      _incomingListenersPrimed = false;
      _birthOwnerRows = <String, Map<String, dynamic>>{};
      _birthOwnerAuthRows = <String, Map<String, dynamic>>{};
      _communityOwnerRows = <String, Map<String, dynamic>>{};
      _communityOwnerAuthRows = <String, Map<String, dynamic>>{};
      _photoOwnerRows = <String, Map<String, dynamic>>{};
      _photoOwnerProfileRows = <String, Map<String, dynamic>>{};
    }
  }

  void _ensureIncomingRequestListeners(
    String userDocId,
    String profileId,
    String authUid,
  ) {
    final firebaseAuthUid =
        firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
    final listeningKey = '$userDocId|$profileId|$authUid|$firebaseAuthUid';
    if (userDocId.isEmpty || _requestListeningKey == listeningKey) return;

    final prevUserDocId = _requestListeningKey?.split('|').first;
    final userChanged = prevUserDocId != null &&
        prevUserDocId.isNotEmpty &&
        prevUserDocId != userDocId;

    // Keep visible rows when profileId/authUid hydrate — only clear on account switch.
    _stopIncomingRequestListeners(clearRows: userChanged);
    _requestListeningKey = listeningKey;

    final repo = InterestAnalyticsRepository();

    _birthOwnerSub = repo.listenBirthRequestsPendingOwnerDocId(
      ownerDocId: userDocId,
      onData: (rows) => _queueIncomingRowUpdate(
        _IncomingRequestBucket.birthOwner,
        rows,
      ),
      onError: (_) {},
    );

    if (authUid.isNotEmpty) {
      _birthOwnerAuthSub = repo.listenBirthRequestsPendingOwnerAuthUid(
        authUid: authUid,
        onData: (rows) => _queueIncomingRowUpdate(
          _IncomingRequestBucket.birthOwnerAuth,
          rows,
        ),
        onError: (_) {},
      );
    }

    _communityOwnerSub = repo.listenCommunityReferencePendingOwnerDocId(
      ownerDocId: userDocId,
      onData: (rows) => _queueIncomingRowUpdate(
        _IncomingRequestBucket.communityOwner,
        rows,
      ),
      onError: (_) {},
    );

    if (authUid.isNotEmpty) {
      _communityOwnerAuthSub = repo.listenCommunityReferencePendingOwnerAuthUid(
        authUid: authUid,
        onData: (rows) => _queueIncomingRowUpdate(
          _IncomingRequestBucket.communityOwnerAuth,
          rows,
        ),
        onError: (_) {},
      );
    }

    _photoOwnerSub = repo.listenPhotoRequestsPendingToUserId(
      userDocId: userDocId,
      onData: (rows) => _queueIncomingRowUpdate(
        _IncomingRequestBucket.photoOwner,
        rows,
      ),
      onError: (_) {},
    );

    if (profileId.isNotEmpty) {
      _photoOwnerProfileSub =
          repo.listenPhotoRequestsPendingToProfileId(
        profileId: profileId,
        onData: (rows) => _queueIncomingRowUpdate(
          _IncomingRequestBucket.photoOwnerProfile,
          rows,
        ),
        onError: (_) {},
      );
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    SentAccessRequestsLoader.invalidateCache();
    final auth = context.read<AuthService>();
    final interestSvc = context.read<InterestService>();
    final messageSvc = context.read<MessageService>();
    final analyticsSvc = context.read<ProfileAnalyticsService>();
    final userId = auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    final queryUid = userId;
    final showBlockingLoader = interestSvc.interestsSent.isEmpty &&
        interestSvc.interestsReceived.isEmpty;
    if (showBlockingLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final notifSvc = context.read<NotificationService>();
      await Future.wait([
        interestSvc.loadInterests(queryUid),
        analyticsSvc.loadAnalyticsForUser(queryUid),
        messageSvc.loadMessages(queryUid),
        notifSvc.loadNotifications(queryUid),
        _refreshSentOutgoingPrivacyRows(),
      ]);
    } catch (e) {
      debugPrint('Interests hub refresh: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshSentOutgoingPrivacyRows() async {
    final me = context.read<AuthService>().currentUser;
    final userId = (me?.id ?? '').trim();
    if (userId.isEmpty) return;
    final aliases = InterestBadgeAggregator.resolveSentRequestQueryAliasIds(
      canonicalUserDocId: userId,
      firebaseAuthUid: firebase_auth.FirebaseAuth.instance.currentUser?.uid,
      identityAuthUid: (me?.authUid ?? '').trim(),
    );
    if (aliases.isEmpty) return;
    final aliasKey = aliases.join('\u0001');
    try {
      final data = await SentAccessRequestsLoader.loadAll(
        requesterAliasIds: aliases,
        force: false,
      );
      if (!mounted) return;
      _lastSentPrivacyAliasKey = aliasKey;
      final tagged = <Map<String, dynamic>>[
        ...(data['birth'] ?? const <Map<String, dynamic>>[]).map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'birth'),
        ),
        ...(data['community'] ?? const <Map<String, dynamic>>[]).map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'community'),
        ),
        ...(data['photo'] ?? const <Map<String, dynamic>>[]).map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'photo'),
        ),
      ];
      final visible =
          await AccessRequestVisibility.filterOutgoingRows(tagged);
      if (!mounted) return;
      if (_outgoingRowsEqual(_sentOutgoingPrivacyRows, visible)) return;
      setState(() => _sentOutgoingPrivacyRows = visible);
    } catch (e) {
      debugPrint('Interests hub: sent privacy reload failed: $e');
    }
  }

  static bool _outgoingRowsEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ai = a[i];
      final bi = b[i];
      if ((ai['id'] ?? '') != (bi['id'] ?? '')) return false;
      if ((ai['status'] ?? '') != (bi['status'] ?? '')) return false;
      if ((ai['updated_at'] ?? '') != (bi['updated_at'] ?? '')) return false;
      if ((ai['privacy_request_kind'] ?? '') !=
          (bi['privacy_request_kind'] ?? '')) {
        return false;
      }
    }
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final me = context.read<AuthService>().currentUser;
    final userId = (me?.id ?? '').trim();
    final profileId = (me?.profileId ?? '').trim();
    final authUid = (me?.authUid ?? '').trim();
    if (userId.isNotEmpty) {
      _ensureIncomingRequestListeners(userId, profileId, authUid);
      // Keep Firestore interest streams bound whenever hub is in the tree.
      // ignore: discarded_futures
      context.read<InterestService>().ensureHubLiveSync(userId);
      if (_boundMessageUserId != userId) {
        _boundMessageUserId = userId;
        // Keep message stream live while hub remains mounted.
        // ignore: discarded_futures
        context.read<MessageService>().startListening(userId);
      }
      final aliases = InterestBadgeAggregator.resolveSentRequestQueryAliasIds(
        canonicalUserDocId: userId,
        firebaseAuthUid: firebase_auth.FirebaseAuth.instance.currentUser?.uid,
        identityAuthUid: authUid,
      );
      final aliasKey = aliases.join('\u0001');
      if (aliasKey.isNotEmpty && aliasKey != _lastSentPrivacyAliasKey) {
        // ignore: discarded_futures
        _refreshSentOutgoingPrivacyRows();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthService, String?>(
      (a) => a.currentUser?.id,
    );
    final profileId = context.select<AuthService, String>(
      (a) => (a.currentUser?.profileId ?? '').trim(),
    );
    final authUid = context.select<AuthService, String>(
      (a) => (a.currentUser?.authUid ?? '').trim(),
    );
    if (userId == null) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Interests',
        showLogo: true,
        showNotifications: !widget.embeddedInMainShell,
        showUpgradeButton: false,
        onRefresh: _isLoading ? null : _refreshData,
      ),
      body: Consumer2<ProfileAnalyticsService, InterestService>(
        builder: (context, analytics, interests, _) {
          // Rebuild all hub tabs when live cache revision changes.
          final _ = interests.hubRevision;
          final received = interests.visibleInterestsReceived;
          final sent = interests.visibleInterestsSent;
          final birthPending = {
            ..._birthOwnerRows,
            ..._birthOwnerAuthRows,
          }.values.toList();
          final communityPending = {
            ..._communityOwnerRows,
            ..._communityOwnerAuthRows,
          }.values.toList();
          final photoPending = {
            ..._photoOwnerRows,
            ..._photoOwnerProfileRows,
          }.values.toList();
          final incomingPrivacyRows = <Map<String, dynamic>>[
            ...birthPending.map(
              (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'birth'),
            ),
            ...communityPending.map(
              (r) => InterestBadgeAggregator.tagPrivacyRequestKind(
                r,
                'community',
              ),
            ),
            ...photoPending.map(
              (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'photo'),
            ),
          ];
          final pendingRx =
              InterestBadgeAggregator.receivedInterestUnviewed(received);
          final requestPendingDocCount =
              InterestBadgeAggregator.incomingPrivacyRequestsUnviewed(
            incomingPrivacyRows,
          );
          final pendingReceivedAll = InterestBadgeAggregator.receivedHubBadgeCount(
            interestsReceived: received,
            incomingPrivacyRequests: incomingPrivacyRows,
          );
          final pendingTx = InterestBadgeAggregator.sentHubBadgeCount(
            interestsSent: sent,
            outgoingPrivacyRequests: _sentOutgoingPrivacyRows,
          );
          final viewsKey = profileId.isNotEmpty ? profileId : userId;
          final effectiveUid = userId;
          final currentUserIds = <String>[
            userId,
            if (profileId.isNotEmpty) profileId,
            if (authUid.isNotEmpty) authUid,
          ];
          final overviewBottomPad = widget.embeddedInMainShell
              ? AppSizes.shellBottomContentInset(context)
              : MediaQuery.paddingOf(context).bottom + 24;
          Widget hubColumn(int unreadChatCount) {
            return Column(
              children: [
                Container(
                  color: AC.surface(context),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: AppTheme.primaryOrange,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    labelColor: AC.text(context),
                    unselectedLabelColor: AC.textSub(context),
                    // Keep in sync with settings_screen.dart TabBar
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: [
                      Tab(
                        child: _TabLabel(
                          'Overview',
                          _tabBadge(pendingReceivedAll + pendingTx),
                          AppTheme.primaryOrange,
                        ),
                      ),
                      Tab(
                        child: _TabLabel(
                          'Received',
                          _tabBadge(pendingReceivedAll),
                          AppTheme.primaryOrange,
                        ),
                      ),
                      Tab(
                        child: _TabLabel(
                          'Sent',
                          _tabBadge(pendingTx),
                          AppTheme.primaryOrange,
                        ),
                      ),
                      Tab(
                        child: _TabLabel(
                          'Messages',
                          _tabBadge(unreadChatCount),
                          AppTheme.primaryOrange,
                        ),
                      ),
                      Tab(
                        child: _TabLabel(
                          'Views',
                          null,
                          AppTheme.primaryOrange,
                        ),
                      ),
                      Tab(
                        child: _TabLabel(
                          'Blocked',
                          null,
                          AppTheme.kumkumRed,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      TabBarView(
                          controller: _tabController,
                          children: [
                            _OverviewTab(
                              userId: userId,
                              matchUserId: effectiveUid,
                              received: received,
                              sent: sent,
                              pendingReceivedAll: pendingReceivedAll,
                              pendingRx: pendingRx,
                              requestPendingDocCount: requestPendingDocCount,
                              pendingTx: pendingTx,
                              unreadChatCount: unreadChatCount,
                              bottomScrollPadding: overviewBottomPad,
                              onOpenViews: () => _openTab(4),
                              onOpenReceived: () => _openTab(1),
                              onOpenReceivedPending: () => _openTab(1),
                              onOpenSent: () => _openSentTab(),
                              onOpenMessages: () => _openTab(3),
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable: _incomingRequestsRevision,
                              builder: (context, _, __) {
                                final birthPending = {
                                  ..._birthOwnerRows,
                                  ..._birthOwnerAuthRows,
                                }.values.toList();
                                final communityPending = {
                                  ..._communityOwnerRows,
                                  ..._communityOwnerAuthRows,
                                }.values.toList();
                                final photoPending = {
                                  ..._photoOwnerRows,
                                  ..._photoOwnerProfileRows,
                                }.values.toList();

                                return _ReceivedTab(
                                  userId: userId,
                                  birthPending: birthPending,
                                  communityPending: communityPending,
                                  photoPending: photoPending,
                                  accessRequestsPrimed:
                                      _incomingListenersPrimed,
                                );
                              },
                            ),
                            _SentTab(
                              userId: effectiveUid,
                              firestoreUserId: userId,
                              initialFilter: _sentFilterHint,
                            ),
                            const _MessagesTab(),
                            _ViewsTab(
                              analytics: analytics,
                              viewedProfileId: viewsKey,
                              fallbackViewedUserId: userId,
                              onOpenInterestStats: () => _openTab(0),
                              currentUserId: effectiveUid,
                              currentUserIds: currentUserIds,
                              received: (received as List<dynamic>? ?? [])
                                  .cast<Map<String, dynamic>>(),
                              sent: (sent as List<dynamic>? ?? [])
                                  .cast<Map<String, dynamic>>(),
                              onRefresh: () async {
                                setState(() => _isLoading = true);
                                try {
                                  await analytics.loadAnalyticsForUser(
                                    effectiveUid,
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _isLoading = false);
                                  }
                                }
                              },
                            ),
                            const _BlockedTab(),
                          ],
                        ),
                      if (_isLoading)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            color: AppTheme.primaryOrange,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }

          return StreamBuilder<int>(
            stream: ChatService().watchUnreadIncomingChatCount(),
            initialData: 0,
            builder: (context, unreadSnap) {
              return hubColumn(unreadSnap.data ?? 0);
            },
          );
        },
      ),
    );
  }
}

// ─── OVERVIEW TAB ─────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final String userId;

  /// Id used in interest docs (`to_user_id` / `from_user_id`) = Firestore profile doc id.
  final String matchUserId;
  final List<Map<String, dynamic>> received;
  final List<Map<String, dynamic>> sent;
  final int pendingReceivedAll;
  final int pendingRx;
  final int requestPendingDocCount;
  final int pendingTx;
  final int unreadChatCount;
  final double bottomScrollPadding;
  final VoidCallback onOpenViews;
  final VoidCallback onOpenReceived;
  final VoidCallback onOpenReceivedPending;
  final VoidCallback onOpenSent;
  final VoidCallback onOpenMessages;

  const _OverviewTab({
    required this.userId,
    required this.matchUserId,
    required this.received,
    required this.sent,
    required this.pendingReceivedAll,
    required this.pendingRx,
    required this.requestPendingDocCount,
    required this.pendingTx,
    required this.unreadChatCount,
    required this.bottomScrollPadding,
    required this.onOpenViews,
    required this.onOpenReceived,
    required this.onOpenReceivedPending,
    required this.onOpenSent,
    required this.onOpenMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileAnalyticsService>(
      builder: (context, analytics, _) {
        final uidForCompare = matchUserId.isNotEmpty ? matchUserId : userId;
        final totalSent = sent.length;
        final pendingSubtitle = requestPendingDocCount == 0
            ? 'Same as Received tab badge (interests only)'
            : '$pendingRx new interests · $requestPendingDocCount privacy requests';

        final merged = <Map<String, dynamic>>[
          ...received.map((e) => Map<String, dynamic>.from(e)),
          ...sent.map((e) => Map<String, dynamic>.from(e)),
        ];
        merged.sort((a, b) {
          final ub = _interestSortMillis(b['updated_at']) > 0
              ? _interestSortMillis(b['updated_at'])
              : _interestSortMillis(b['created_at']);
          final ua = _interestSortMillis(a['updated_at']) > 0
              ? _interestSortMillis(a['updated_at'])
              : _interestSortMillis(a['created_at']);
          return ub.compareTo(ua);
        });
        final monthStart = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          1,
        );
        final viewsProfileId = uidForCompare;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + bottomScrollPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Statistics'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Overview and tab badges use the same unread rules. '
                  'The Messages tab badge counts unread chat messages only. '
                  'Photo requests appear on Received, not Messages.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AC.textSub(context),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      // Still [FirebaseService.profileViewersStream]: compat stream differs
                      // from [FirestoreService.profileViewersStream] (dedup cap: no 50-row limit).
                      // Switching would change Overview "Profile Views" counts.
                      stream:
                          _ProfileViewersStreamCache.forProfile(viewsProfileId),
                      initialData: const <Map<String, dynamic>>[],
                      builder: (context, snap) {
                        final liveCount = snap.hasError
                            ? null
                            : snap.data?.length;
                        return _MetricCard(
                          title: 'Profile Views',
                          value: '${liveCount ?? analytics.totalProfileViews}',
                          icon: Icons.visibility,
                          color: AppTheme.peacockBlue,
                          onTap: onOpenViews,
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _MetricCard(
                      title: 'Interests Received',
                      value: '${received.length}',
                      icon: Icons.favorite,
                      color: AppTheme.kumkumRed,
                      onTap: onOpenReceived,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Pending (Received)',
                      value: '$pendingReceivedAll',
                      subtitle: pendingSubtitle,
                      icon: Icons.pending,
                      color: AppTheme.primaryOrange,
                      onTap: onOpenReceivedPending,
                    ),
                  ),
                  Expanded(
                    child: _MetricCard(
                      title: 'Interests Sent',
                      value: '$totalSent',
                      subtitle: pendingTx > 0
                          ? '$pendingTx awaiting response'
                          : null,
                      icon: Icons.send,
                      color: AppTheme.sacredGreen,
                      onTap: onOpenSent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Messages',
                      value: '$unreadChatCount',
                      subtitle: 'Unread chats (Messages tab)',
                      icon: Icons.chat_bubble_outline,
                      color: AppTheme.peacockBlue,
                      onTap: onOpenMessages,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<Map<String, dynamic>>>(
                // See profile views StreamBuilder note above (_StatisticsTabContent).
                stream:
                    _ProfileViewersStreamCache.forProfile(viewsProfileId),
                initialData: const <Map<String, dynamic>>[],
                builder: (context, snap) {
                  final liveViews = snap.hasError
                      ? const <Map<String, dynamic>>[]
                      : (snap.data ?? const <Map<String, dynamic>>[]);
                  bool isOnOrAfter(dynamic raw, DateTime start) {
                    if (raw is Timestamp) {
                      return !raw.toDate().isBefore(start);
                    }
                    if (raw is String) {
                      final dt = DateTime.tryParse(raw);
                      return dt != null && !dt.isBefore(start);
                    }
                    return false;
                  }

                  final todayStart = DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                  );
                  final monthCount = liveViews.where((d) {
                    final raw = d['viewed_at'];
                    return isOnOrAfter(raw, monthStart);
                  }).length;
                  final todayCount = liveViews.where((d) {
                    final raw = d['viewed_at'];
                    return isOnOrAfter(raw, todayStart);
                  }).length;
                  return Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Views Today',
                          value: '$todayCount',
                          icon: Icons.today,
                          color: AppTheme.sacredGreen,
                          onTap: onOpenViews,
                        ),
                      ),
                      Expanded(
                        child: _MetricCard(
                          title: 'This Month',
                          value: '$monthCount',
                          icon: Icons.date_range,
                          color: AC.textSub(context),
                          onTap: onOpenViews,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ─── RECEIVED TAB ─────────────────────────────────────────────────────────────

class _ReceivedTab extends StatefulWidget {
  final String userId;
  final List<Map<String, dynamic>> birthPending;
  final List<Map<String, dynamic>> communityPending;
  final List<Map<String, dynamic>> photoPending;
  final bool accessRequestsPrimed;
  const _ReceivedTab({
    required this.userId,
    required this.birthPending,
    required this.communityPending,
    required this.photoPending,
    this.accessRequestsPrimed = true,
  });

  @override
  State<_ReceivedTab> createState() => _ReceivedTabState();
}

class _ReceivedTabState extends State<_ReceivedTab>
    with AutomaticKeepAliveClientMixin<_ReceivedTab> {
  final Set<String> _hiddenBirthIncoming = <String>{};
  final Set<String> _hiddenCommunityIncoming = <String>{};
  final Set<String> _hiddenPhotoIncoming = <String>{};
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _accessRequestsSectionKey = GlobalKey();
  String _receivedSignature = '';
  List<Map<String, dynamic>> _receivedSortedCache = const <Map<String, dynamic>>[];
  String _birthSignature = '';
  List<Map<String, dynamic>> _birthSortedCache = const <Map<String, dynamic>>[];
  String _communitySignature = '';
  List<Map<String, dynamic>> _communitySortedCache = const <Map<String, dynamic>>[];
  String _photoSignature = '';
  List<Map<String, dynamic>> _photoSortedCache = const <Map<String, dynamic>>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToAccessRequests() {
    final ctx = _accessRequestsSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      alignment: 0.05,
    );
  }

  static List<Map<String, dynamic>> _newestFirst(
    List<Map<String, dynamic>> raw,
  ) {
    final list = List<Map<String, dynamic>>.from(raw);
    list.sort((a, b) {
      final ua = _interestSortMillis(a['updated_at']) > 0
          ? _interestSortMillis(a['updated_at'])
          : _interestSortMillis(a['created_at']);
      final ub = _interestSortMillis(b['updated_at']) > 0
          ? _interestSortMillis(b['updated_at'])
          : _interestSortMillis(b['created_at']);
      return ub.compareTo(ua);
    });
    return list;
  }

  static String _rowId(Map<String, dynamic> row) =>
      (row['id'] ?? '').toString().trim();

  static String _rowsSignature(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    final b = StringBuffer('${rows.length}|');
    for (final r in rows) {
      b
        ..write(_rowId(r))
        ..write(':')
        ..write((r['status'] ?? '').toString())
        ..write(':')
        ..write(_interestSortMillis(r['updated_at']))
        ..write(':')
        ..write(_interestSortMillis(r['created_at']))
        ..write('|');
    }
    return b.toString();
  }

  List<Map<String, dynamic>> _memoizedNewestFirst(
    List<Map<String, dynamic>> rows, {
    required String cacheKey,
  }) {
    final signature = _rowsSignature(rows);
    if (cacheKey == 'received') {
      if (_receivedSignature == signature) return _receivedSortedCache;
      _receivedSignature = signature;
      _receivedSortedCache = _newestFirst(rows);
      return _receivedSortedCache;
    }
    if (cacheKey == 'birth') {
      if (_birthSignature == signature) return _birthSortedCache;
      _birthSignature = signature;
      _birthSortedCache = _newestFirst(rows);
      return _birthSortedCache;
    }
    if (cacheKey == 'community') {
      if (_communitySignature == signature) return _communitySortedCache;
      _communitySignature = signature;
      _communitySortedCache = _newestFirst(rows);
      return _communitySortedCache;
    }
    if (_photoSignature == signature) return _photoSortedCache;
    _photoSignature = signature;
    _photoSortedCache = _newestFirst(rows);
    return _photoSortedCache;
  }

  void _trimAccessoryHiddenSets() {
    final b =
        widget.birthPending.map((r) => _rowId(r)).where((k) => k.isNotEmpty);
    final c = widget.communityPending
        .map((r) => _rowId(r))
        .where((k) => k.isNotEmpty);
    final p =
        widget.photoPending.map((r) => _rowId(r)).where((k) => k.isNotEmpty);
    if (_hiddenBirthIncoming.isNotEmpty) {
      _hiddenBirthIncoming.removeWhere((id) => !b.contains(id));
    }
    if (_hiddenCommunityIncoming.isNotEmpty) {
      _hiddenCommunityIncoming.removeWhere((id) => !c.contains(id));
    }
    if (_hiddenPhotoIncoming.isNotEmpty) {
      _hiddenPhotoIncoming.removeWhere((id) => !p.contains(id));
    }
    // Legacy optimistic hides after decline must not block Grant Again / Revoke.
    for (final row in widget.birthPending) {
      final id = _rowId(row);
      if (id.isEmpty) continue;
      if (AccessRequestStatus.normalize(row['status']) !=
          AccessRequestStatus.pending) {
        _hiddenBirthIncoming.remove(id);
      }
    }
    for (final row in widget.communityPending) {
      final id = _rowId(row);
      if (id.isEmpty) continue;
      if (AccessRequestStatus.normalize(row['status']) !=
          AccessRequestStatus.pending) {
        _hiddenCommunityIncoming.remove(id);
      }
    }
    for (final row in widget.photoPending) {
      final id = _rowId(row);
      if (id.isEmpty) continue;
      if (AccessRequestStatus.normalize(row['status']) !=
          AccessRequestStatus.pending) {
        _hiddenPhotoIncoming.remove(id);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ReceivedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _trimAccessoryHiddenSets();
  }

  Future<void> _respondBirthRequest(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool accept,
  }) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    final requesterId =
        (row['requester_id'] ?? row['requesterId'] ?? row['requester_auth_uid'] ?? '')
            .toString()
            .trim();
    final requesterProfileId =
        (row['requester_profile_id'] ?? row['requesterProfileId'] ?? '')
            .toString()
            .trim();
    final me = context.read<AuthService>().currentUser;
    final ownerName =
        '${(me?.firstName ?? '').toString().trim()} ${(me?.lastName ?? '').toString().trim()}'
                .trim()
                .isNotEmpty
            ? '${(me?.firstName ?? '').toString().trim()} ${(me?.lastName ?? '').toString().trim()}'
                .trim()
            : (me?.firstName ?? 'Profile Owner').toString().trim();
    try {
      await BirthDetailsService().respondToRequest(
        docId: requestId,
        status: accept ? 'granted' : 'denied',
        requesterId: requesterId,
        requesterProfileId: requesterProfileId,
        ownerName: ownerName,
      );
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      if (accept) {
        unawaited(
          InterestsHubAnalytics.birthRequestApproved(requestId: requestId),
        );
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Birth details request accepted'
                : 'Birth details request declined',
          ),
          backgroundColor: accept ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Failed to update request: $e')));
    }
  }

  Future<void> _respondCommunityRequest(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool accept,
  }) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    try {
      await CommunityReferenceService().respondToCommunityRequest(
        requestId: requestId,
        isAccepted: accept,
      );
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      if (accept) {
        unawaited(
          InterestsHubAnalytics.communityRequestApproved(requestId: requestId),
        );
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Community reference request accepted'
                : 'Community reference request declined',
          ),
          backgroundColor: accept ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Failed to update request: $e')));
    }
  }

  Future<void> _respondPhotoRequest(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool accept,
  }) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    try {
      await InterestAnalyticsRepository()
          .mergePhotoRequestResponse(requestId: requestId, accept: accept);
      // Notify all requester-side photo widgets to refresh cached/proxied
      // private-photo access state after accept/decline.
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      if (accept) {
        unawaited(
          InterestsHubAnalytics.photoRequestApproved(requestId: requestId),
        );
      } else {
        unawaited(
          InterestsHubAnalytics.photoRequestRejected(requestId: requestId),
        );
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Photo access accepted'
                : 'Photo request declined',
          ),
          backgroundColor: accept ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Failed to update request: $e')));
    }
  }

  Future<void> _stopBirthRequest(
    BuildContext context,
    Map<String, dynamic> row,
  ) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    try {
      await BirthDetailsService().stopRequest(docId: requestId);
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Birth details access paused'),
          backgroundColor: AppTheme.primaryOrange,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to stop birth access: $e')),
      );
    }
  }

  Future<void> _stopCommunityRequest(
    BuildContext context,
    Map<String, dynamic> row,
  ) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    try {
      await CommunityReferenceService().stopCommunityRequest(
        requestId: requestId,
      );
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Community reference access paused'),
          backgroundColor: AppTheme.primaryOrange,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to stop community access: $e')),
      );
    }
  }

  Future<void> _stopPhotoRequest(
    BuildContext context,
    Map<String, dynamic> row,
  ) async {
    final requestId = _rowId(row);
    if (requestId.isEmpty) return;
    try {
      await InterestAnalyticsRepository().mergePhotoRequestStop(requestId);
      AccessRequestBroadcast.notifyChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Photo access paused'),
          backgroundColor: AppTheme.primaryOrange,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to stop photo access: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _trimAccessoryHiddenSets();
    final interests = context.select<InterestService, List<Map<String, dynamic>>>(
      (s) => s.visibleInterestsReceived,
    );
    final hasAccessRequests =
        widget.birthPending.isNotEmpty ||
            widget.communityPending.isNotEmpty ||
            widget.photoPending.isNotEmpty;
    if (interests.isEmpty && !hasAccessRequests) {
      if (!widget.accessRequestsPrimed) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          ),
        );
      }
      return const _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No Interests Received',
        subtitle:
            'All incoming interest requests appear in this tab. When someone sends interest, you can accept or decline here.',
      );
    }

    final sorted = _memoizedNewestFirst(interests, cacheKey: 'received');
    final birthRows = _memoizedNewestFirst(widget.birthPending, cacheKey: 'birth')
        .where((r) => !_hiddenBirthIncoming.contains(_rowId(r)))
        .toList();
    final communityRows = _memoizedNewestFirst(
      widget.communityPending,
      cacheKey: 'community',
    )
        .where((r) => !_hiddenCommunityIncoming.contains(_rowId(r)))
        .toList();
    final photoRows = _memoizedNewestFirst(widget.photoPending, cacheKey: 'photo')
        .where((r) => !_hiddenPhotoIncoming.contains(_rowId(r)))
        .toList();
    final accessCount = InterestBadgeAggregator.incomingAccessRequestsVisibleCount(
      birthRows: birthRows,
      communityRows: communityRows,
      photoRows: photoRows,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCard = math.min(constraints.maxWidth, 680.0);
        final sidePad = math
            .max(12.0, (constraints.maxWidth - maxCard) / 2)
            .clamp(12.0, 48.0);

        return ListView(
          controller: _scrollCtrl,
          padding: EdgeInsets.fromLTRB(sidePad, 16, sidePad, 100),
          children: [
            if (accessCount > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryOrange.withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_outlined,
                      color: AppTheme.primaryOrange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        accessCount == 1
                            ? '1 access request'
                            : '$accessCount access requests',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (accessCount > 0) {
                          _scrollToAccessRequests();
                        } else {
                          openAppNotificationsScreen(context);
                        }
                      },
                      child: Text(accessCount > 0 ? 'Show' : 'Open'),
                    ),
                  ],
                ),
              ),
            if (birthRows.isNotEmpty)
              KeyedSubtree(
                key: _accessRequestsSectionKey,
                child: _SentAccessRequestsTopic(
                title: 'Birth details',
                subtitle:
                    'Reminders and withdrawals in this section apply only to birth-detail access requests.',
                icon: Icons.calendar_month_outlined,
                accentColor: AppTheme.primaryOrange,
                children: birthRows
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReceivedAccessRequestCard(
                          key: ValueKey(_rowId(r)),
                          typeLabel: 'Birth details access request',
                          icon: Icons.cake_outlined,
                          accentColor: AppTheme.primaryOrange,
                          data: r,
                          onAccept: () =>
                              _respondBirthRequest(context, r, accept: true),
                          onDecline: () =>
                              _respondBirthRequest(context, r, accept: false),
                          onStop: () => _stopBirthRequest(context, r),
                          onGrantAgain: () =>
                              _respondBirthRequest(context, r, accept: true),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ),
            if (birthRows.isNotEmpty && communityRows.isNotEmpty)
              const SizedBox(height: 20),
            if (communityRows.isNotEmpty)
              KeyedSubtree(
                key: birthRows.isEmpty ? _accessRequestsSectionKey : null,
                child: _SentAccessRequestsTopic(
                title: 'Community references',
                subtitle:
                    'Reminders and withdrawals in this section apply only to community-reference requests.',
                icon: Icons.group_outlined,
                accentColor: AppTheme.peacockBlue,
                children: communityRows
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReceivedAccessRequestCard(
                          key: ValueKey(_rowId(r)),
                          typeLabel: 'Community reference access request',
                          icon: Icons.groups_outlined,
                          accentColor: AppTheme.peacockBlue,
                          data: r,
                          onAccept: () => _respondCommunityRequest(
                            context,
                            r,
                            accept: true,
                          ),
                          onDecline: () => _respondCommunityRequest(
                            context,
                            r,
                            accept: false,
                          ),
                          onStop: () => _stopCommunityRequest(context, r),
                          onGrantAgain: () => _respondCommunityRequest(
                            context,
                            r,
                            accept: true,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ),
            if ((birthRows.isNotEmpty || communityRows.isNotEmpty) &&
                photoRows.isNotEmpty)
              const SizedBox(height: 20),
            if (photoRows.isNotEmpty)
              KeyedSubtree(
                key: birthRows.isEmpty && communityRows.isEmpty
                    ? _accessRequestsSectionKey
                    : null,
                child: _SentAccessRequestsTopic(
                title: 'Photo requests received',
                subtitle:
                    'Photo access requests sent by members. Use Accept or Decline below.',
                icon: Icons.photo_camera_outlined,
                accentColor: AppTheme.primaryOrange,
                children: photoRows
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReceivedAccessRequestCard(
                          key: ValueKey(_rowId(r)),
                          typeLabel: 'Photo request',
                          icon: Icons.photo_camera_outlined,
                          accentColor: AppTheme.primaryOrange,
                          data: {
                            ...r,
                            'requester_name':
                                InterestRowHelpers.incomingRequesterLabel(r),
                          },
                          onAccept: () =>
                              _respondPhotoRequest(context, r, accept: true),
                          onDecline: () =>
                              _respondPhotoRequest(context, r, accept: false),
                          onStop: () => _stopPhotoRequest(context, r),
                          onGrantAgain: () =>
                              _respondPhotoRequest(context, r, accept: true),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ),
            if (sorted.isNotEmpty) ...[
              if (accessCount > 0 ||
                  widget.birthPending.isNotEmpty ||
                  widget.communityPending.isNotEmpty)
                const SizedBox(height: 20),
              _SentAccessRequestsTopic(
                title: 'Interests received',
                subtitle:
                    'Members who sent you an interest appear here. Use Accept or Decline to respond.',
                icon: Icons.favorite_outline,
                accentColor: AppTheme.primaryOrange,
                children: sorted
                    .map(
                      (interest) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _InterestTile(
                          data: interest,
                          docId: InterestBadgeAggregator.interestDocumentId(
                            interest,
                          ),
                          isReceived: true,
                          currentUserId: widget.userId,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReceivedAccessRequestCard extends StatefulWidget {
  final String typeLabel;
  final IconData icon;
  final Color accentColor;
  final Map<String, dynamic> data;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final Future<void> Function()? onStop;
  final Future<void> Function()? onGrantAgain;

  const _ReceivedAccessRequestCard({
    super.key,
    required this.typeLabel,
    required this.icon,
    required this.accentColor,
    required this.data,
    required this.onAccept,
    required this.onDecline,
    this.onStop,
    this.onGrantAgain,
  });

  @override
  State<_ReceivedAccessRequestCard> createState() =>
      _ReceivedAccessRequestCardState();
}

class _ReceivedAccessRequestCardState
    extends State<_ReceivedAccessRequestCard> {
  bool _accepting = false;
  bool _declining = false;
  bool _stopping = false;
  bool _grantingAgain = false;
  late String _receivedTimeLabel;
  late Future<User?> _requesterFuture;

  @override
  void initState() {
    super.initState();
    _receivedTimeLabel = _receivedAccessRequestTimeLabel(widget.data);
    _requesterFuture = _loadRequesterUser();
    final id = (widget.data['id'] as String? ?? '').trim();
    if (id.isEmpty) return;
    final label = widget.typeLabel.toLowerCase();
    if (label.contains('birth')) {
      unawaited(PrivacyRequestViewService.markViewedByOwner(id));
    } else if (label.contains('community')) {
      unawaited(PrivacyRequestViewService.markCommunityViewedByOwner(id));
    } else if (label.contains('photo')) {
      unawaited(PrivacyRequestViewService.markPhotoViewedByOwner(id));
    }
  }

  @override
  void didUpdateWidget(covariant _ReceivedAccessRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCreated = oldWidget.data['created_at'];
    final newCreated = widget.data['created_at'];
    if (oldCreated != newCreated) {
      _receivedTimeLabel = _receivedAccessRequestTimeLabel(widget.data);
    }
    final oldPeer = AccessRequestVisibility.incomingPeerId(oldWidget.data);
    final newPeer = AccessRequestVisibility.incomingPeerId(widget.data);
    if (oldPeer != newPeer) {
      _requesterFuture = _loadRequesterUser();
    }
  }

  Future<User?> _loadRequesterUser() async {
    final peerId = AccessRequestVisibility.incomingPeerId(widget.data);
    if (peerId.isEmpty) return null;
    return _cachedUserByAnyId(peerId);
  }

  @override
  Widget build(BuildContext context) {
    // Rows are already filtered in the hub listeners; a second async visibility
    // lookup here caused spinner → empty section flicker under the topic header.
    final peerId = AccessRequestVisibility.incomingPeerId(widget.data);
    if (AccessRequestVisibility.peekPeerVisible(peerId) == false) {
      return const SizedBox.shrink();
    }
    return _buildReceivedAccessRequestBody(context);
  }

  Widget _buildReceivedAccessRequestBody(BuildContext context) {
    final requesterName =
        InterestRowHelpers.incomingRequesterLabel(widget.data);
    final time = _receivedTimeLabel;
    final normalizedStatus =
        AccessRequestStatus.normalize(widget.data['status']);
    final isGranted = normalizedStatus == AccessRequestStatus.granted;
    final isRevoked = normalizedStatus == AccessRequestStatus.revoked;
    final isStopped = normalizedStatus == AccessRequestStatus.stopped;
    final isDenied = normalizedStatus == AccessRequestStatus.denied;
    final isPhotoRequest = widget.typeLabel.toLowerCase().contains('photo');

    final chipBg = isGranted
        ? AppTheme.sacredGreen.withAlpha(22)
        : (isDenied || isRevoked)
            ? AppTheme.kumkumRed.withAlpha(22)
            : isStopped
                ? AppTheme.primaryOrange.withAlpha(22)
                : AppTheme.primaryOrange.withAlpha(22);
    final chipBorder = isGranted
        ? AppTheme.sacredGreen.withAlpha(90)
        : (isDenied || isRevoked)
            ? AppTheme.kumkumRed.withAlpha(90)
            : isStopped
                ? AppTheme.primaryOrange.withAlpha(90)
                : AppTheme.primaryOrange.withAlpha(90);
    final chipTextColor = isGranted
        ? AppTheme.sacredGreen
        : (isDenied || isRevoked)
            ? AppTheme.kumkumRed
            : isStopped
                ? AppTheme.primaryOrange
                : AppTheme.primaryOrange;
    final chipLabel = isGranted
        ? 'Accepted'
        : isRevoked
            ? 'Revoked'
            : isStopped
                ? 'Stopped'
                : isDenied
                    ? 'Declined'
                    : 'Pending';

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: widget.accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.typeLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AC.text(context),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: chipBorder,
                    ),
                  ),
                  child: Text(
                    chipLabel,
                    style: TextStyle(
                      color: chipTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<User?>(
              future: _requesterFuture,
              builder: (context, requesterSnap) {
                final requester = requesterSnap.data;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPeerPhotoAvatar(
                      context,
                      canViewPhoto: requester != null &&
                          !requester.photoHiddenFromOthers,
                      peer: requester,
                      size: 56,
                      lockedAccent: widget.accentColor,
                      showPrivateLabel: isPhotoRequest,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requesterName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AC.text(context),
                            ),
                          ),
                          if (time.isNotEmpty)
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 12,
                                color: AC.textSub(context),
                              ),
                            ),
                          if (isPhotoRequest && !isGranted)
                            Text(
                              'Private photo — accept to preview for this member',
                              style: TextStyle(
                                fontSize: 11,
                                color: AC.textMuted(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            if (normalizedStatus == AccessRequestStatus.pending)
              RequestActionBar(
                first: RequestActionItem(
                  label: 'Accept',
                  icon: Icons.check_circle_outline,
                  color: AppTheme.sacredGreen,
                  isLoading: _accepting,
                  onPressed: (_accepting || _declining)
                      ? null
                      : () async {
                          _lightTapFeedback();
                          setState(() => _accepting = true);
                          try {
                            await widget.onAccept();
                          } finally {
                            if (mounted) setState(() => _accepting = false);
                          }
                        },
                ),
                second: RequestActionItem(
                  label: 'Decline',
                  icon: Icons.cancel_outlined,
                  color: AppTheme.kumkumRed,
                  isLoading: _declining,
                  onPressed: (_accepting || _declining)
                      ? null
                      : () async {
                          _lightTapFeedback();
                          setState(() => _declining = true);
                          try {
                            await widget.onDecline();
                          } finally {
                            if (mounted) setState(() => _declining = false);
                          }
                        },
                ),
              )
            else if (normalizedStatus == AccessRequestStatus.granted)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Status: Accepted',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.sacredGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onStop == null || _stopping
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _stopping = true);
                                  try {
                                    await widget.onStop!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _stopping = false);
                                    }
                                  }
                                },
                          icon: _stopping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onGrantAgain == null || _grantingAgain
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _grantingAgain = true);
                                  try {
                                    await widget.onGrantAgain!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _grantingAgain = false);
                                    }
                                  }
                                },
                          icon: _grantingAgain
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: const Text('Grant Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else if (normalizedStatus == AccessRequestStatus.stopped)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Status: Stopped',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onStop == null || _stopping
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _stopping = true);
                                  try {
                                    await widget.onStop!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _stopping = false);
                                    }
                                  }
                                },
                          icon: _stopping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onGrantAgain == null || _grantingAgain
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _grantingAgain = true);
                                  try {
                                    await widget.onGrantAgain!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _grantingAgain = false);
                                    }
                                  }
                                },
                          icon: _grantingAgain
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: const Text('Grant Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else if (normalizedStatus == AccessRequestStatus.denied)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Status: Declined',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kumkumRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onStop == null || _stopping
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _stopping = true);
                                  try {
                                    await widget.onStop!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _stopping = false);
                                    }
                                  }
                                },
                          icon: _stopping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onGrantAgain == null || _grantingAgain
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _grantingAgain = true);
                                  try {
                                    await widget.onGrantAgain!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _grantingAgain = false);
                                    }
                                  }
                                },
                          icon: _grantingAgain
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: const Text('Grant Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(color: AppTheme.primaryOrange),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else if (normalizedStatus == AccessRequestStatus.revoked)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Status: Revoked',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kumkumRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onStop == null || _stopping
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _stopping = true);
                                  try {
                                    await widget.onStop!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _stopping = false);
                                    }
                                  }
                                },
                          icon: _stopping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(
                              color: AppTheme.primaryOrange,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onGrantAgain == null || _grantingAgain
                              ? null
                              : () async {
                                  _lightTapFeedback();
                                  setState(() => _grantingAgain = true);
                                  try {
                                    await widget.onGrantAgain!();
                                  } finally {
                                    if (mounted) {
                                      setState(() => _grantingAgain = false);
                                    }
                                  }
                                },
                          icon: _grantingAgain
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: const Text('Grant Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(color: AppTheme.primaryOrange),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => openAppNotificationsScreen(context),
                child: const Text('Open Notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SENT TAB ─────────────────────────────────────────────────────────────

enum _SentInterestFilter { all, pending, accepted, rejected }

class _SentTab extends StatefulWidget {
  /// Firestore profile doc id used in interest rows.
  final String userId;

  /// Firestore user document id for related modules (birth/community).
  final String firestoreUserId;
  final _SentInterestFilter initialFilter;

  const _SentTab({
    required this.userId,
    required this.firestoreUserId,
    this.initialFilter = _SentInterestFilter.all,
  });

  @override
  State<_SentTab> createState() => _SentTabState();
}

class _SentTabState extends State<_SentTab>
    with AutomaticKeepAliveClientMixin<_SentTab> {
  late _SentInterestFilter _filter;
  late Future<Map<String, List<Map<String, dynamic>>>> _otherRequestsFuture;
  String? _lastSentAccessoryAliasKey;
  Timer? _sentAccessReloadDebounce;
  final Set<String> _hiddenSentBirthIds = <String>{};
  final Set<String> _hiddenSentCommunityIds = <String>{};
  final Set<String> _hiddenSentPhotoIds = <String>{};
  String _sentSignature = '';
  List<Map<String, dynamic>> _sentSortedCache = const <Map<String, dynamic>>[];
  String _sentFilteredSignature = '';
  List<Map<String, dynamic>> _sentFilteredCache = const <Map<String, dynamic>>[];
  String _sentInterestCardsSignature = '';
  List<Widget> _sentInterestCardsCache = const <Widget>[];
  String _sentAccessorySignature = '';
  ({
    List<Map<String, dynamic>> birth,
    List<Map<String, dynamic>> community,
    List<Map<String, dynamic>> photo
  }) _sentAccessoryVisibleCache = (
    birth: const <Map<String, dynamic>>[],
    community: const <Map<String, dynamic>>[],
    photo: const <Map<String, dynamic>>[],
  );

  @override
  bool get wantKeepAlive => true;

  String _sentAccessoryId(Map<String, dynamic> m) =>
      (m['id'] as String? ?? '').trim();

  /// Firestore user doc id for queries — never throws during build.
  String get _safeUserDocId {
    try {
      final fs = widget.firestoreUserId.trim();
      if (fs.isNotEmpty) return fs;
      return widget.userId.trim();
    } catch (_) {
      return '';
    }
  }

  void _trimSentAccessoryHidden(Map<String, List<Map<String, dynamic>>> data) {
    final bs = data['birth'] ?? const <Map<String, dynamic>>[];
    final cs = data['community'] ?? const <Map<String, dynamic>>[];
    final ps = data['photo'] ?? const <Map<String, dynamic>>[];
    final b = bs.map((m) => _sentAccessoryId(m)).where((k) => k.isNotEmpty);
    final c = cs.map((m) => _sentAccessoryId(m)).where((k) => k.isNotEmpty);
    final p = ps.map((m) => _sentAccessoryId(m)).where((k) => k.isNotEmpty);
    if (_hiddenSentBirthIds.isNotEmpty) {
      _hiddenSentBirthIds.removeWhere((id) => !b.contains(id));
    }
    if (_hiddenSentCommunityIds.isNotEmpty) {
      _hiddenSentCommunityIds.removeWhere((id) => !c.contains(id));
    }
    if (_hiddenSentPhotoIds.isNotEmpty) {
      _hiddenSentPhotoIds.removeWhere((id) => !p.contains(id));
    }
  }

  Future<({String requesterId, String ownerId})> _resolveSentRequestParties(
    Map<String, dynamic> item,
    String requestId,
  ) async {
    var requesterId = (item['requester_id'] as String? ??
            item['requesterId'] as String? ??
            '')
        .trim();
    var ownerId =
        (item['owner_id'] as String? ?? item['ownerId'] as String? ?? '').trim();
    if (requestId.contains('_')) {
      final parts = requestId.split('_');
      if (parts.length >= 2) {
        if (requesterId.isEmpty) requesterId = parts.first.trim();
        if (ownerId.isEmpty) ownerId = parts.sublist(1).join('_').trim();
      }
    }
    if (requesterId.isEmpty) {
      requesterId = widget.firestoreUserId.isEmpty
          ? widget.userId.trim()
          : widget.firestoreUserId.trim();
    }
    if (ownerId.isEmpty) {
      final ownerHints = <String>{
        (item['owner_profile_id'] as String? ?? '').trim(),
        (item['ownerProfileId'] as String? ?? '').trim(),
        (item['to_profile_id'] as String? ?? '').trim(),
        (item['toProfileId'] as String? ?? '').trim(),
        (item['target_profile_id'] as String? ?? '').trim(),
        (item['targetProfileId'] as String? ?? '').trim(),
        (item['to_user_id'] as String? ?? '').trim(),
        (item['toUserId'] as String? ?? '').trim(),
        (item['user_id'] as String? ?? '').trim(),
        (item['doc_id'] as String? ?? '').trim(),
      }..removeWhere((v) => v.isEmpty);
      for (final hint in ownerHints) {
        try {
          final u = await ProfileRepository().lookupUserByAnyId(hint);
          final resolved = (u?.id ?? '').trim();
          if (resolved.isNotEmpty) {
            ownerId = resolved;
            break;
          }
        } catch (_) {}
      }
    }
    return (requesterId: requesterId, ownerId: ownerId);
  }

  Future<void> _withdrawSentBirth(
    BuildContext outerContext,
    Map<String, dynamic> item,
  ) async {
    final requestId = _sentAccessoryId(item);
    if (requestId.isEmpty) return;
    setState(() => _hiddenSentBirthIds.add(requestId));
    final parties = await _resolveSentRequestParties(item, requestId);
    final requesterId = parties.requesterId;
    final ownerId = parties.ownerId;
    if (ownerId.isEmpty) {
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(const SnackBar(
        content: Text('Withdraw failed: request looks stale. Refresh and try again.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      setState(() => _hiddenSentBirthIds.remove(requestId));
      return;
    }
    try {
      await BirthDetailsService().withdrawRequest(
        requesterId: requesterId,
        ownerId: ownerId,
        requestId: requestId,
      );
      AccessRequestBroadcast.notifyChanged();
      final fresh = await _loadOtherRequests();
      if (!mounted) return;
      setState(() {
        _hiddenSentBirthIds.remove(requestId);
        _otherRequestsFuture = Future.value(fresh);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hiddenSentBirthIds.remove(requestId));
      }
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(
        SnackBar(
          content: Text('Withdraw failed: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _withdrawSentCommunity(
    BuildContext outerContext,
    Map<String, dynamic> item,
  ) async {
    final requestId = _sentAccessoryId(item);
    if (requestId.isEmpty) return;
    setState(() => _hiddenSentCommunityIds.add(requestId));
    final parties = await _resolveSentRequestParties(item, requestId);
    final requesterId = parties.requesterId;
    final ownerId = parties.ownerId;
    if (ownerId.isEmpty) {
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(const SnackBar(
        content: Text('Withdraw failed: request looks stale. Refresh and try again.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      setState(() => _hiddenSentCommunityIds.remove(requestId));
      return;
    }
    try {
      await CommunityReferenceService().withdrawRequest(
        requesterId: requesterId,
        ownerId: ownerId,
        requestId: requestId,
      );
      AccessRequestBroadcast.notifyChanged();
      final fresh = await _loadOtherRequests();
      if (!mounted) return;
      setState(() {
        _hiddenSentCommunityIds.remove(requestId);
        _otherRequestsFuture = Future.value(fresh);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hiddenSentCommunityIds.remove(requestId));
      }
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(
        SnackBar(
          content: Text('Withdraw failed: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _withdrawSentPhoto(
    BuildContext outerContext,
    Map<String, dynamic> item,
  ) async {
    final requestId = _sentAccessoryId(item);
    if (requestId.isEmpty) return;
    setState(() => _hiddenSentPhotoIds.add(requestId));
    try {
      await InterestAnalyticsRepository().mergePhotoRequestWithdrawn(requestId);
      AccessRequestBroadcast.notifyChanged();
      final fresh = await _loadOtherRequests();
      if (!mounted) return;
      setState(() {
        _hiddenSentPhotoIds.remove(requestId);
        _otherRequestsFuture = Future.value(fresh);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hiddenSentPhotoIds.remove(requestId));
      }
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(
        SnackBar(
          content: Text('Withdraw failed: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  void _onAccessRequestPulse() {
    if (!mounted) return;
    SentAccessRequestsLoader.invalidateCache();
    _sentAccessReloadDebounce?.cancel();
    _sentAccessReloadDebounce = Timer(const Duration(milliseconds: 120), () {
      _sentAccessReloadDebounce = null;
      if (!mounted) return;
      setState(() {
        _otherRequestsFuture = _loadOtherRequests();
      });
    });
  }

  void _reloadSentAccessoriesIfNeeded({bool force = false}) {
    final aliases = _sentRequestAliasIds();
    final aliasKey = aliases.join('\u0001');
    if (aliasKey.isEmpty) return;
    if (!force && aliasKey == _lastSentAccessoryAliasKey) return;
    _lastSentAccessoryAliasKey = aliasKey;
    setState(() {
      _otherRequestsFuture = _loadOtherRequests(force: force);
    });
  }

  static Map<String, List<Map<String, dynamic>>> _emptySentAccessoryData() =>
      const {
        'birth': <Map<String, dynamic>>[],
        'community': <Map<String, dynamic>>[],
        'photo': <Map<String, dynamic>>[],
      };

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    // Load once in [didChangeDependencies] when [AuthService] is available.
    _otherRequestsFuture = Future.value(_emptySentAccessoryData());
    AccessRequestBroadcast.tick.addListener(_onAccessRequestPulse);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadSentAccessoriesIfNeeded();
  }

  @override
  void dispose() {
    AccessRequestBroadcast.tick.removeListener(_onAccessRequestPulse);
    _sentAccessReloadDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter &&
        _filter != widget.initialFilter) {
      setState(() => _filter = widget.initialFilter);
    }
    // Reload when interest user id / profile doc id changes.
    if (oldWidget.userId != widget.userId ||
        oldWidget.firestoreUserId != widget.firestoreUserId) {
      _lastSentAccessoryAliasKey = null;
      _reloadSentAccessoriesIfNeeded(force: true);
    }
  }

  List<String> _sentRequestAliasIds() {
    final me = context.read<AuthService>().currentUser;
    final canonical = widget.firestoreUserId.trim().isNotEmpty
        ? widget.firestoreUserId.trim()
        : widget.userId.trim();
    return InterestBadgeAggregator.resolveSentRequestQueryAliasIds(
      canonicalUserDocId: canonical,
      firebaseAuthUid: firebase_auth.FirebaseAuth.instance.currentUser?.uid,
      identityAuthUid: (me?.authUid ?? '').trim(),
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadOtherRequests({
    bool force = false,
  }) async {
    final aliases = _sentRequestAliasIds();
    if (aliases.isEmpty) {
      debugPrint(
        '❌ SentTab: no alias ids for birth/community/photo sent requests',
      );
      return const {
        'birth': <Map<String, dynamic>>[],
        'community': <Map<String, dynamic>>[],
        'photo': <Map<String, dynamic>>[],
      };
    }
    try {
      final data = await SentAccessRequestsLoader.loadAll(
        requesterAliasIds: aliases,
        force: force,
      );
      debugPrint(
        '📤 SentTab loaded: birth=${data['birth']?.length ?? 0} '
        'community=${data['community']?.length ?? 0} '
        'photo=${data['photo']?.length ?? 0}',
      );
      if (mounted) _trimSentAccessoryHidden(data);
      return data;
    } catch (e) {
      debugPrint('❌ SentTab: loadOtherRequests failed: $e');
      rethrow;
    }
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> raw) {
    final list = List<Map<String, dynamic>>.from(raw);
    list.sort((a, b) {
      final ua = _interestSortMillis(a['updated_at']) > 0
          ? _interestSortMillis(a['updated_at'])
          : _interestSortMillis(a['created_at']);
      final ub = _interestSortMillis(b['updated_at']) > 0
          ? _interestSortMillis(b['updated_at'])
          : _interestSortMillis(b['created_at']);
      return ub.compareTo(ua);
    });
    return list;
  }

  static String _interestRowsSignature(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    final b = StringBuffer('${rows.length}|');
    for (final r in rows) {
      b
        ..write((r['id'] ?? '').toString())
        ..write(':')
        ..write((r['status'] ?? '').toString())
        ..write(':')
        ..write(_interestSortMillis(r['updated_at']))
        ..write(':')
        ..write(_interestSortMillis(r['created_at']))
        ..write('|');
    }
    return b.toString();
  }

  List<Map<String, dynamic>> _memoizedSortedSent(
    List<Map<String, dynamic>> rows,
  ) {
    final signature = _interestRowsSignature(rows);
    if (_sentSignature == signature) return _sentSortedCache;
    _sentSignature = signature;
    _sentSortedCache = _sorted(rows);
    return _sentSortedCache;
  }

  List<Map<String, dynamic>> _memoizedFilteredSent(
    List<Map<String, dynamic>> sorted,
  ) {
    final signature = '${_interestRowsSignature(sorted)}|${_filter.name}';
    if (_sentFilteredSignature == signature) return _sentFilteredCache;
    _sentFilteredSignature = signature;
    _sentFilteredCache = _applyFilter(sorted);
    return _sentFilteredCache;
  }

  String _hiddenIdsSignature(Set<String> ids) {
    if (ids.isEmpty) return '0';
    final sorted = ids.toList()..sort();
    return sorted.join('\u0001');
  }

  String _accessoryRowsSignature(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    final b = StringBuffer('${rows.length}|');
    for (final r in rows) {
      b
        ..write(_sentAccessoryId(r))
        ..write(':')
        ..write((r['status'] ?? '').toString())
        ..write(':')
        ..write(_interestSortMillis(r['updated_at']))
        ..write(':')
        ..write(_interestSortMillis(r['created_at']))
        ..write('|');
    }
    return b.toString();
  }

  List<Map<String, dynamic>> _visibleAccessoryRows(
    List<Map<String, dynamic>> rows,
    Set<String> hidden,
  ) {
    return rows
        .where((m) => _isVisibleRequestStatus(m['status']))
        .where((m) => !hidden.contains(_sentAccessoryId(m)))
        .toList();
  }

  ({
    List<Map<String, dynamic>> birth,
    List<Map<String, dynamic>> community,
    List<Map<String, dynamic>> photo
  }) _memoizedAccessoryVisibleRows(Map<String, List<Map<String, dynamic>>> data) {
    final birthRaw =
        (data['birth'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    final communityRaw =
        (data['community'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    final photoRaw =
        (data['photo'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    final signature = [
      _accessoryRowsSignature(birthRaw),
      _accessoryRowsSignature(communityRaw),
      _accessoryRowsSignature(photoRaw),
      _hiddenIdsSignature(_hiddenSentBirthIds),
      _hiddenIdsSignature(_hiddenSentCommunityIds),
      _hiddenIdsSignature(_hiddenSentPhotoIds),
    ].join('||');
    if (_sentAccessorySignature == signature) {
      return _sentAccessoryVisibleCache;
    }
    _sentAccessorySignature = signature;
    _sentAccessoryVisibleCache = (
      birth: _visibleAccessoryRows(birthRaw, _hiddenSentBirthIds),
      community: _visibleAccessoryRows(communityRaw, _hiddenSentCommunityIds),
      photo: _visibleAccessoryRows(photoRaw, _hiddenSentPhotoIds),
    );
    return _sentAccessoryVisibleCache;
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> sorted) {
    bool ok(String s, _SentInterestFilter f) {
      switch (f) {
        case _SentInterestFilter.all:
          return true;
        case _SentInterestFilter.pending:
          return s == 'pending';
        case _SentInterestFilter.accepted:
          return s == 'accepted';
        case _SentInterestFilter.rejected:
          return s == 'rejected';
      }
    }

    return sorted.where((m) {
      final s = _normalizeRequestStatus(m['status'] as String? ?? 'pending');
      return ok(s, _filter);
    }).toList();
  }

  int _count(String status, List<Map<String, dynamic>> raw) {
    return raw.where((m) {
      final normalized = _normalizeRequestStatus(
        m['status'] as String? ?? 'pending',
      );
      return normalized == status;
    }).length;
  }

  List<Widget> _sentInterestCards(
    List<Map<String, dynamic>> visible,
    String reloadUserId,
  ) {
    final signature =
        '${_interestRowsSignature(visible)}|$reloadUserId|${widget.userId}|${widget.firestoreUserId}';
    if (_sentInterestCardsSignature == signature) {
      return _sentInterestCardsCache;
    }
    _sentInterestCardsSignature = signature;
    final built = visible
        .map(
          (item) {
            final docId = InterestBadgeAggregator.interestDocumentId(item);
            return SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SentInterestCard(
                  data: item,
                  docId:
                      docId.isNotEmpty ? docId : (item['id'] as String? ?? ''),
                  currentUserId: reloadUserId,
                ),
              ),
            );
          },
        )
        .toList(growable: false);
    _sentInterestCardsCache = built;
    return _sentInterestCardsCache;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Reactive: rebuild whenever [InterestService] hub cache changes.
    final interests = context.select<InterestService, List<Map<String, dynamic>>>(
      (s) => s.visibleInterestsSent,
    );

    // 🔥 FIX: Guard against empty user ID - prevents RenderErrorBox crash
    if (widget.firestoreUserId.trim().isEmpty && widget.userId.trim().isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading user data...'),
          ],
        ),
      );
    }

    final sorted = _memoizedSortedSent(interests);
    final visible = _memoizedFilteredSent(sorted);
    final countable = sorted;
    final reloadUserId = _safeUserDocId;

    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _otherRequestsFuture,
      builder: (context, snapshot) {
        // 🔥 FIX: Handle error state to prevent RenderErrorBox crash
        if (snapshot.hasError) {
          debugPrint('❌ _SentTab: FutureBuilder error: ${snapshot.error}');
          return _EmptyState(
            icon: Icons.error_outline,
            title: 'Failed to load requests',
            subtitle: 'Pull down to retry: ${snapshot.error}',
          );
        }

        final data = snapshot.data ??
            {
              'birth': <Map<String, dynamic>>[],
              'community': <Map<String, dynamic>>[],
              'photo': <Map<String, dynamic>>[],
            };
        final accessoryVisible = _memoizedAccessoryVisibleRows(data);
        final birth = accessoryVisible.birth;
        final community = accessoryVisible.community;
        final photo = accessoryVisible.photo;
        final hasAccessories =
            birth.isNotEmpty || community.isNotEmpty || photo.isNotEmpty;
        final hasInterestRows = countable.isNotEmpty;
        final hasAny = hasInterestRows || hasAccessories;

        if (!hasAny && snapshot.connectionState == ConnectionState.done) {
          return const _EmptyState(
            icon: Icons.send_outlined,
            title: 'No Requests Sent',
            subtitle:
                'Everything you send appears here with response status. Pending requests can be withdrawn or reminded.',
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryOrange,
          onRefresh: () async {
            final queryUid = reloadUserId.trim();
            if (queryUid.isEmpty) {
              debugPrint('❌ SentTab refresh blocked: empty firestoreUserId');
              return;
            }
            SentAccessRequestsLoader.invalidateCache();
            await context
                .read<InterestService>()
                .loadInterests(queryUid);
            if (!mounted) return;
            AccessRequestBroadcast.notifyChanged();
            _lastSentAccessoryAliasKey = null;
            _reloadSentAccessoriesIfNeeded();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxCard = math.min(constraints.maxWidth, 680.0);
              final sidePad = math
                  .max(12.0, (constraints.maxWidth - maxCard) / 2)
                  .clamp(12.0, 48.0);
              final interestCards = _sentInterestCards(visible, reloadUserId);

              final listChildren = <Widget>[
                _SentFilterChips(
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                  total: countable.length,
                  pending: _count('pending', sorted),
                  accepted: _count('accepted', sorted),
                  rejected: _count('rejected', sorted),
                ),
                const SizedBox(height: 8),
              ];

              if (hasInterestRows) {
                if (visible.isEmpty &&
                    snapshot.connectionState == ConnectionState.done) {
                  listChildren.add(
                    const _EmptyState(
                      inline: true,
                      icon: Icons.filter_alt_off_outlined,
                      title: 'Nothing in this filter',
                      subtitle: 'Try another filter or clear filters',
                    ),
                  );
                } else if (interestCards.isNotEmpty) {
                  listChildren.add(
                    _SentAccessRequestsTopic(
                      title: 'Interests sent',
                      subtitle:
                          'Interests you have sent and their current status. Pending items can be withdrawn or reminded.',
                      icon: Icons.send_outlined,
                      accentColor: AppTheme.primaryOrange,
                      children: interestCards,
                    ),
                  );
                }
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 100),
                children: [
                  ...listChildren,
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ),
                  if (hasAccessories &&
                      snapshot.connectionState == ConnectionState.done) ...[
                    if (hasInterestRows && interestCards.isNotEmpty)
                      const SizedBox(height: 20),
                    _OtherSentRequestsSection(
                      userId: reloadUserId,
                      birth: birth,
                      community: community,
                      photo: photo,
                      onWithdrawBirth: _withdrawSentBirth,
                      onWithdrawCommunity: _withdrawSentCommunity,
                      onWithdrawPhoto: _withdrawSentPhoto,
                      onChanged: () {
                        if (!mounted) return;
                        setState(() {
                          _otherRequestsFuture = _loadOtherRequests();
                        });
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Visually separates Birth vs Community on the Sent tab (no merged “one topic” look).
class _SentAccessRequestsTopic extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<Widget> children;

  const _SentAccessRequestsTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderA = isDark ? 130 : 110;
    final fillA = isDark ? 28 : 16;
    final divA = isDark ? 90 : 55;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withAlpha(borderA), width: 1.5),
        color: accentColor.withAlpha(fillA),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AC.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AC.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: accentColor.withAlpha(divA)),
            const SizedBox(height: 10),
            ...children,
          ],
        ],
      ),
    );
  }
}

class _OtherSentRequestsSection extends StatelessWidget {
  final String userId;
  final List<Map<String, dynamic>> birth;
  final List<Map<String, dynamic>> community;
  final List<Map<String, dynamic>> photo;
  final Future<void> Function(BuildContext ctx, Map<String, dynamic> item)
      onWithdrawBirth;
  final Future<void> Function(BuildContext ctx, Map<String, dynamic> item)
      onWithdrawCommunity;
  final Future<void> Function(BuildContext ctx, Map<String, dynamic> item)
      onWithdrawPhoto;
  final VoidCallback onChanged;

  // Cannot be const — withdraw callbacks capture tab state.
  // ignore: prefer_const_constructors_in_immutables
  _OtherSentRequestsSection({
    required this.userId,
    required this.birth,
    required this.community,
    required this.photo,
    required this.onWithdrawBirth,
    required this.onWithdrawCommunity,
    required this.onWithdrawPhoto,
    required this.onChanged,
  });

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> items) {
    final list = List<Map<String, dynamic>>.from(items);
    list.sort((a, b) {
      final ta = _interestSortMillis(a['updated_at']) > 0
          ? _interestSortMillis(a['updated_at'])
          : _interestSortMillis(a['created_at']);
      final tb = _interestSortMillis(b['updated_at']) > 0
          ? _interestSortMillis(b['updated_at'])
          : _interestSortMillis(b['created_at']);
      return tb.compareTo(ta);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final birthSorted = _sorted(birth);
    final communitySorted = _sorted(community);
    final photoSorted = _sorted(photo);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        if (birthSorted.isNotEmpty)
          _SentAccessRequestsTopic(
            title: 'Birth details',
            subtitle:
                'Reminders and withdrawals in this section apply only to birth-detail access requests.',
            icon: Icons.calendar_month_outlined,
            accentColor: AppTheme.primaryOrange,
            children: birthSorted
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AccessRequestCard(
                      typeLabel: 'Birth Details',
                      hideTypeSubtitle: true,
                      data: item,
                      onWithdraw: () => onWithdrawBirth(context, item),
                      onReminder: () async {
                        var ownerId =
                            (item['owner_id'] as String? ?? item['ownerId'] as String? ?? '')
                                .trim();
                        var requesterId = (item['requester_id'] as String? ??
                                item['requesterId'] as String? ??
                                '')
                            .trim();
                        final requestId = (item['id'] as String? ?? '').trim();
                        if (requestId.contains('_')) {
                          final parts = requestId.split('_');
                          if (parts.length >= 2) {
                            if (requesterId.isEmpty) {
                              requesterId = parts.first.trim();
                            }
                            if (ownerId.isEmpty) {
                              ownerId = parts.sublist(1).join('_').trim();
                            }
                          }
                        }
                        if (requesterId.isEmpty) requesterId = userId;
                        await BirthDetailsService().sendReminder(
                          requesterId: requesterId,
                          requesterProfileId:
                              (item['requester_profile_id'] as String? ?? '')
                                  .trim(),
                          requesterName:
                              (item['requester_name'] as String? ?? 'Member')
                                  .trim(),
                          ownerId: ownerId,
                          ownerProfileId:
                              (item['owner_profile_id'] as String? ?? '')
                                  .trim(),
                          ownerName: (item['owner_name'] as String? ?? 'Member')
                              .trim(),
                        );
                        onChanged();
                      },
                      onRequestAgain: () async {
                        var ownerId =
                            (item['owner_id'] as String? ?? item['ownerId'] as String? ?? '')
                                .trim();
                        var requesterId = (item['requester_id'] as String? ??
                                item['requesterId'] as String? ??
                                '')
                            .trim();
                        final requestId = (item['id'] as String? ?? '').trim();
                        if (requestId.contains('_')) {
                          final parts = requestId.split('_');
                          if (parts.length >= 2) {
                            if (requesterId.isEmpty) {
                              requesterId = parts.first.trim();
                            }
                            if (ownerId.isEmpty) {
                              ownerId = parts.sublist(1).join('_').trim();
                            }
                          }
                        }
                        if (requesterId.isEmpty) requesterId = userId;

                        await BirthDetailsService().sendRequest(
                          requesterId: requesterId,
                          requesterProfileId:
                              (item['requester_profile_id'] as String? ?? '')
                                  .trim(),
                          requesterName:
                              (item['requester_name'] as String? ?? 'Member')
                                  .trim(),
                          ownerId: ownerId,
                          ownerProfileId:
                              (item['owner_profile_id'] as String? ?? '')
                                  .trim(),
                          ownerName: (item['owner_name'] as String? ?? 'Member')
                              .trim(),
                          forceResend: true,
                        );
                        onChanged();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        if (birthSorted.isNotEmpty && communitySorted.isNotEmpty)
          const SizedBox(height: 20),
        if (communitySorted.isNotEmpty)
          _SentAccessRequestsTopic(
            title: 'Community references',
            subtitle:
                'Reminders and withdrawals in this section apply only to community-reference requests.',
            icon: Icons.group_outlined,
            accentColor: AppTheme.peacockBlue,
            children: communitySorted
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AccessRequestCard(
                      typeLabel: 'Community References',
                      hideTypeSubtitle: true,
                      data: item,
                      onWithdraw: () => onWithdrawCommunity(context, item),
                      onReminder: () async {
                        var ownerId =
                            (item['owner_id'] as String? ?? item['ownerId'] as String? ?? '')
                                .trim();
                        var requesterId = (item['requester_id'] as String? ??
                                item['requesterId'] as String? ??
                                '')
                            .trim();
                        final requestId = (item['id'] as String? ?? '').trim();
                        if (requestId.contains('_')) {
                          final parts = requestId.split('_');
                          if (parts.length >= 2) {
                            if (requesterId.isEmpty) {
                              requesterId = parts.first.trim();
                            }
                            if (ownerId.isEmpty) {
                              ownerId = parts.sublist(1).join('_').trim();
                            }
                          }
                        }
                        if (requesterId.isEmpty) requesterId = userId;
                        await CommunityReferenceService().sendReminder(
                          requesterId: requesterId,
                          requesterProfileId:
                              (item['requester_profile_id'] as String? ?? '')
                                  .trim(),
                          requesterName:
                              (item['requester_name'] as String? ?? 'Member')
                                  .trim(),
                          ownerId: ownerId,
                          ownerProfileId:
                              (item['owner_profile_id'] as String? ?? '')
                                  .trim(),
                          ownerName: (item['owner_name'] as String? ?? 'Member')
                              .trim(),
                        );
                        onChanged();
                      },
                      onRequestAgain: () async {
                        var ownerId =
                            (item['owner_id'] as String? ?? item['ownerId'] as String? ?? '')
                                .trim();
                        var requesterId = (item['requester_id'] as String? ??
                                item['requesterId'] as String? ??
                                '')
                            .trim();
                        final requestId = (item['id'] as String? ?? '').trim();
                        if (requestId.contains('_')) {
                          final parts = requestId.split('_');
                          if (parts.length >= 2) {
                            if (requesterId.isEmpty) {
                              requesterId = parts.first.trim();
                            }
                            if (ownerId.isEmpty) {
                              ownerId = parts.sublist(1).join('_').trim();
                            }
                          }
                        }
                        if (requesterId.isEmpty) requesterId = userId;

                        await CommunityReferenceService().sendRequest(
                          requesterId: requesterId,
                          requesterProfileId:
                              (item['requester_profile_id'] as String? ?? '')
                                  .trim(),
                          requesterName:
                              (item['requester_name'] as String? ?? 'Member')
                                  .trim(),
                          ownerId: ownerId,
                          ownerProfileId:
                              (item['owner_profile_id'] as String? ?? '')
                                  .trim(),
                          ownerName: (item['owner_name'] as String? ?? 'Member')
                              .trim(),
                          forceResend: true,
                        );
                        onChanged();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        if ((birthSorted.isNotEmpty || communitySorted.isNotEmpty) &&
            photoSorted.isNotEmpty)
          const SizedBox(height: 20),
        if (photoSorted.isNotEmpty)
          _SentAccessRequestsTopic(
            title: 'Photo requests sent',
            subtitle:
                'Photo access requests you sent. Pending requests can be withdrawn or reminded.',
            icon: Icons.photo_camera_outlined,
            accentColor: AppTheme.primaryOrange,
            children: photoSorted
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AccessRequestCard(
                      typeLabel: 'Photo request',
                      hideTypeSubtitle: true,
                      data: {
                        ...item,
                        'owner_id':
                            (item['to_user_id'] as String? ?? '').trim(),
                        'owner_profile_id':
                            (item['to_profile_id'] as String? ?? '').trim(),
                        'owner_name':
                            ('${(item['to_first_name'] as String? ?? '')} ${(item['to_last_name'] as String? ?? '')}'
                                    .trim()
                                    .isEmpty)
                                ? 'Member'
                                : '${(item['to_first_name'] as String? ?? '')} ${(item['to_last_name'] as String? ?? '')}'
                                    .trim(),
                      },
                      onWithdraw: () => onWithdrawPhoto(context, item),
                      onReminder: () async {
                        final requestId = (item['id'] as String? ?? '').trim();
                        if (requestId.isEmpty) return;
                        await InterestAnalyticsRepository()
                            .mergePhotoRequestReminder(requestId);
                        onChanged();
                      },
                      onRequestAgain: () async {
                        final ownerId = (item['to_user_id'] as String? ??
                                item['toUserId'] as String? ??
                                item['owner_id'] as String? ??
                                item['ownerId'] as String? ??
                                '')
                            .toString()
                            .trim();
                        if (ownerId.isEmpty) return;

                        final ok = await PhotoService().requestPhotoAccess(ownerId);
                        if (!ok) {
                          throw Exception('Could not send photo request again');
                        }
                        onChanged();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _AccessRequestCard extends StatefulWidget {
  final String typeLabel;

  /// When true, omit repeating the request type on the card (topic header already shows it).
  final bool hideTypeSubtitle;
  final Map<String, dynamic> data;
  final Future<void> Function() onWithdraw;
  final Future<void> Function() onReminder;
  final Future<void> Function()? onRequestAgain;

  const _AccessRequestCard({
    required this.typeLabel,
    this.hideTypeSubtitle = false,
    required this.data,
    required this.onWithdraw,
    required this.onReminder,
    this.onRequestAgain,
  });

  @override
  State<_AccessRequestCard> createState() => _AccessRequestCardState();
}

class _AccessRequestCardState extends State<_AccessRequestCard> {
  bool _withdrawing = false;
  bool _reminding = false;
  bool _requestingAgain = false;
  late Future<User?> _ownerFuture;

  @override
  void initState() {
    super.initState();
    _ownerFuture = _loadOwnerUser();
    final id = (widget.data['id'] as String? ?? '').trim();
    if (id.isNotEmpty) {
      final label = widget.typeLabel.toLowerCase();
      if (label.contains('birth')) {
        unawaited(PrivacyRequestViewService.markBirthViewedByRequester(id));
      } else if (label.contains('community')) {
        unawaited(
          PrivacyRequestViewService.markCommunityViewedByRequester(id),
        );
      } else if (label.contains('photo')) {
        unawaited(PrivacyRequestViewService.markPhotoViewedByRequester(id));
      }
    }
  }

  @override
  void didUpdateWidget(covariant _AccessRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prevOwnerId = (oldWidget.data['owner_id'] as String? ?? '').trim();
    final nextOwnerId = (widget.data['owner_id'] as String? ?? '').trim();
    if (prevOwnerId != nextOwnerId) {
      _ownerFuture = _loadOwnerUser();
    }
  }

  Future<User?> _loadOwnerUser() async {
    final ownerId = (widget.data['owner_id'] as String? ?? '').trim();
    if (ownerId.isEmpty) return null;
    return ProfileRepository().lookupUserByAnyId(ownerId);
  }

  String _fallbackOwnerName() {
    final ownerName = (widget.data['owner_name'] as String? ?? '').trim();
    return ownerName.isNotEmpty ? ownerName : 'Member';
  }

  String _locationText(User? u) {
    final p = u?.profile;
    final city = (p?.city ?? '').trim();
    final state = (p?.state ?? '').trim();
    if (city.isNotEmpty && state.isNotEmpty) return '$city, $state';
    if (city.isNotEmpty) return city;
    if (state.isNotEmpty) return state;
    return 'Location not available';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _ownerFuture,
      builder: (context, ownerSnap) {
        if (ownerSnap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 72,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (ownerSnap.hasError ||
            (ownerSnap.connectionState == ConnectionState.done &&
                ownerSnap.data == null)) {
          return const SizedBox.shrink();
        }
        return _buildAccessRequestCardBody(context, ownerSnap.data);
      },
    );
  }

  Widget _buildAccessRequestCardBody(BuildContext context, User? owner) {
    final status = _normalizeRequestStatus(
      widget.data['status'] as String? ?? 'pending',
    );
    final time = _interestTimeLabel(widget.data);
    final u = owner;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final ownerName =
                    (u?.profile?.fullName ?? _fallbackOwnerName()).trim();
                final ownerProfile = (u?.profileId ?? '').trim();
                final age = (u?.profile?.age ?? 0);
                final ageText = age > 0 ? '$age yrs' : 'Age N/A';
                final locationText = _locationText(u);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ownerName.isNotEmpty ? ownerName : 'Member',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AC.text(context),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _statusClr(status).withAlpha(22),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _statusClr(status).withAlpha(90),
                            ),
                          ),
                          child: Text(
                            _statusLbl(status),
                            style: TextStyle(
                              color: _statusClr(status),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.hideTypeSubtitle
                          ? '${ownerProfile.isNotEmpty ? 'ID: $ownerProfile · ' : ''}$ageText'
                          : '${widget.typeLabel}'
                              '${ownerProfile.isNotEmpty ? ' · ID: $ownerProfile' : ''}'
                              ' · $ageText',
                      style: TextStyle(
                        fontSize: 12,
                        color: AC.textSub(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationText,
                      style: TextStyle(
                        fontSize: 12,
                        color: AC.textMuted(context),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                status == 'pending' ? 'Sent · $time' : 'Updated · $time',
                style: TextStyle(fontSize: 12, color: AC.textSub(context)),
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              RequestActionBar(
                first: RequestActionItem(
                  label: RequestUiContract.withdraw,
                  icon: Icons.undo,
                  isLoading: _withdrawing,
                  onPressed: _withdrawing || _reminding
                      ? null
                      : () async {
                          _lightTapFeedback();
                          setState(() => _withdrawing = true);
                          try {
                            await widget.onWithdraw();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${widget.typeLabel} withdrawn'),
                                backgroundColor: AppTheme.textMedium,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${RequestUiContract.withdrawFailed}: $e',
                                ),
                                backgroundColor: AppTheme.kumkumRed,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _withdrawing = false);
                          }
                        },
                ),
                second: RequestActionItem(
                  label: RequestUiContract.reminder,
                  icon: Icons.notifications_active_outlined,
                  isLoading: _reminding,
                  color: AppTheme.primaryOrange,
                  onPressed: _withdrawing || _reminding
                      ? null
                      : () async {
                          _lightTapFeedback();
                          setState(() => _reminding = true);
                          try {
                            await widget.onReminder();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Reminder sent · ${widget.typeLabel}',
                                ),
                                backgroundColor: AppTheme.sacredGreen,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not send reminder: $e'),
                                backgroundColor: AppTheme.kumkumRed,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _reminding = false);
                          }
                        },
                ),
              ),
            ],
            if (status == 'rejected' ||
                status == 'revoked' ||
                status == 'stopped') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _requestingAgain || widget.onRequestAgain == null
                      ? null
                      : () async {
                          setState(() => _requestingAgain = true);
                          try {
                            await widget.onRequestAgain!();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${widget.typeLabel} request sent again',
                                ),
                                backgroundColor: AppTheme.sacredGreen,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Request again failed: $e',
                                ),
                                backgroundColor: AppTheme.kumkumRed,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _requestingAgain = false);
                          }
                        },
                  icon: _requestingAgain
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  label: const Text(RequestUiContract.sendAgain),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryOrange,
                    side: const BorderSide(color: AppTheme.primaryOrange),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SentFilterChips extends StatelessWidget {
  final _SentInterestFilter selected;
  final ValueChanged<_SentInterestFilter> onChanged;
  final int total;
  final int pending;
  final int accepted;
  final int rejected;

  const _SentFilterChips({
    required this.selected,
    required this.onChanged,
    required this.total,
    required this.pending,
    required this.accepted,
    required this.rejected,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(_SentInterestFilter f, String label, int count) {
      final isSel = selected == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: FilterChip(
          selected: isSel,
          label: Text('$label${count >= 0 ? ' ($count)' : ''}'),
          onSelected: (_) => onChanged(f),
          selectedColor: AppTheme.primaryOrange.withAlpha(48),
          checkmarkColor: AppTheme.primaryOrange,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? AppTheme.primaryOrange : AC.textSub(context),
          ),
          side: BorderSide(
            color: isSel ? AppTheme.primaryOrange : AC.border(context),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(
        children: [
          chip(_SentInterestFilter.all, 'All', total),
          chip(_SentInterestFilter.pending, 'Pending', pending),
          chip(
            _SentInterestFilter.accepted,
            RequestUiContract.accepted,
            accepted,
          ),
          chip(
            _SentInterestFilter.rejected,
            RequestUiContract.declined,
            rejected,
          ),
        ],
      ),
    );
  }
}

/// Sent-interest row: open profile; pending → withdraw + reminder (with cooldown).
class _SentInterestCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String currentUserId;

  const _SentInterestCard({
    required this.data,
    required this.docId,
    required this.currentUserId,
  });

  @override
  State<_SentInterestCard> createState() => _SentInterestCardState();
}

class _SentInterestCardState extends State<_SentInterestCard> {
  bool _withdrawing = false;
  bool _reminding = false;
  DateTime? _reminderSentAt;
  late Future<User?> _targetFuture;

  Map<String, dynamic> get data => widget.data;
  String get docId => widget.docId;
  String get currentUserId => widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _targetFuture = _loadTargetUser();
  }

  @override
  void didUpdateWidget(covariant _SentInterestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prevTo = (oldWidget.data['to_user_id'] as String? ?? '').trim();
    final nextTo = (widget.data['to_user_id'] as String? ?? '').trim();
    final prevPid = (oldWidget.data['to_profile_id'] as String? ?? '').trim();
    final nextPid = (widget.data['to_profile_id'] as String? ?? '').trim();
    if (prevTo != nextTo || prevPid != nextPid) {
      _targetFuture = _loadTargetUser();
    }
  }

  Future<User?> _loadTargetUser() =>
      InterestRowHelpers.loadPeerUser(data, isReceived: false);

  String get _targetUserId =>
      InterestRowHelpers.peerUserId(data, isReceived: false);

  String get _targetProfileId =>
      InterestRowHelpers.peerProfileId(data, isReceived: false);

  bool _hasSnapshotIdentity() =>
      InterestRowHelpers.hasSnapshotIdentity(data, isReceived: false);

  String _locationText(User? u) => InterestRowHelpers.peerLocation(
        data,
        u,
        isReceived: false,
      );

  Future<void> _openProfile(BuildContext context) async {
    final pid = _targetProfileId;
    if (pid.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByProfileId(
        context,
        profileId: pid,
        routeGuardInterestDocId: docId,
      );
      return;
    }
    final uid = _targetUserId;
    if (uid.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: uid,
        routeGuardInterestDocId: docId,
      );
    }
  }

  Future<void> _withdraw(BuildContext context) async {
    if (_withdrawing) return;
    _lightTapFeedback();
    setState(() => _withdrawing = true);
    final interestService = context.read<InterestService>();
    final result = await interestService.withdrawInterestWithResult(
      interestId: docId,
    );
    if (!mounted) return;
    setState(() => _withdrawing = false);
    if (!context.mounted) return;
    if (result['success'] == true) {
      unawaited(() async {
        try {
          await interestService.loadInterests(currentUserId);
        } catch (e) {
          debugPrint('⚠️ Interest refresh after sent withdraw failed: $e');
        }
      }());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interest withdrawn'),
          backgroundColor: AppTheme.textMedium,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] as String? ?? RequestUiContract.withdrawFailed,
          ),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _sendReminder(BuildContext context) async {
    if (_reminding) return;
    final status = (data['status'] as String? ?? '').toLowerCase();
    if (!(status == 'pending' || status == 'sent')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(RequestUiContract.reminderPendingOnly),
          backgroundColor: AppTheme.textMedium,
        ),
      );
      return;
    }
    _lightTapFeedback();
    setState(() => _reminding = true);
    final interestService = context.read<InterestService>();
    final interestId =
        (data['interestId'] ?? data['id'] ?? data['interest_id'] ?? docId)
            .toString();
    bool sent = false;
    String error = RequestUiContract.reminderFailed;
    try {
      await interestService.sendInterestReminderForSentRow(interestId);
      sent = true;
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() => _reminding = false);
    if (!context.mounted) return;
    if (sent) {
      setState(() => _reminderSentAt = DateTime.now());
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sent ? RequestUiContract.reminderSent : error),
        backgroundColor: sent ? AppTheme.sacredGreen : AppTheme.kumkumRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _normalizeRequestStatus(
      data['status'] as String? ?? 'pending',
    );
    final st = _statusLbl(status);
    final time = _interestTimeLabel(data);
    final optimistic = data['_pendingFirestoreSync'] == true;

    final fallbackUserId = InterestRowHelpers.peerUserId(
      data,
      isReceived: false,
    );
    final viewer = context.read<AuthService>().currentUser;
    return FutureBuilder<User?>(
      future: _targetFuture,
      builder: (context, userSnap) {
        final target = userSnap.data;
        final privacyFuture = _cachedPrivacyRowAccess(
          viewer: viewer,
          candidate: target,
          fallbackUserId: fallbackUserId,
        );
        return FutureBuilder<_PrivacyRowAccess>(
          future: privacyFuture,
          builder: (context, accessSnap) {
            final access = accessSnap.data ??
                const _PrivacyRowAccess(
                  canViewProfile: false,
                  canViewIdentity: false,
                  canViewPhoto: false,
                );
            final canOpenProfile =
                access.canViewProfile || _hasSnapshotIdentity();
            final showIdentity =
                access.canViewIdentity || _hasSnapshotIdentity();
            final resolvedProfileId = _resolvedPeerProfileId(
              data: data,
              isReceived: false,
              liveUser: target,
            );
            final displayName = InterestIdentityResolver.peerDisplayName(
              data,
              isReceived: false,
              liveFullName: target?.profile?.fullName ?? '',
            );
            final ageText = InterestIdentityResolver.peerAgeText(
              data,
              isReceived: false,
              liveAge: target?.profile?.age ?? 0,
            );
            final locationText = _locationText(target);
            return SizedBox(
              width: double.infinity,
              child: Material(
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canOpenProfile
                      ? () => _openProfile(context)
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_protectedSubtitle(access)),
                            ),
                          ),
                  child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _photoAvatar(
                            context,
                            canViewPhoto: access.canViewPhoto,
                            target: target,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  showIdentity
                                      ? (displayName !=
                                              InterestIdentityResolver
                                                  .unknownMember
                                          ? displayName
                                          : (resolvedProfileId.isNotEmpty
                                              ? 'Profile $resolvedProfileId'
                                              : 'Member'))
                                      : 'Protected Profile',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AC.text(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  showIdentity
                                      ? '${resolvedProfileId.isNotEmpty ? 'ID: $resolvedProfileId · ' : ''}$ageText'
                                      : 'Age hidden',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AC.textMuted(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  showIdentity
                                      ? locationText
                                      : _protectedSubtitle(access),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AC.textMuted(context),
                                  ),
                                ),
                                if (time.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    optimistic
                                        ? 'Just now · sending…'
                                        : (status != 'pending'
                                            ? 'Updated · $time'
                                            : 'Sent · $time'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AC.textSub(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusClr(status).withAlpha(22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _statusClr(status).withAlpha(90),
                              ),
                            ),
                            child: Text(
                              st,
                              style: TextStyle(
                                color: _statusClr(status),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (status == 'pending' || status == 'accepted') ...[
                        const SizedBox(height: 12),
                        RequestActionBar(
                          first: RequestActionItem(
                            label: status == 'accepted'
                                ? 'Withdraw Interest'
                                : RequestUiContract.withdraw,
                            icon: Icons.undo,
                            isLoading: _withdrawing,
                            onPressed: _withdrawing || _reminding
                                ? null
                                : () => _withdraw(context),
                          ),
                          second: status == 'pending'
                              ? RequestActionItem(
                                  label: RequestUiContract.reminder,
                                  icon: Icons.notifications_active_outlined,
                                  isLoading: _reminding,
                                  color: AppTheme.primaryOrange,
                                  onPressed: _withdrawing || _reminding
                                      ? null
                                      : () => _sendReminder(context),
                                )
                              : RequestActionItem(
                                  label: 'View Profile',
                                  icon: Icons.person_outline,
                                  color: AppTheme.textMedium,
                                  onPressed: canOpenProfile
                                      ? () => _openProfile(context)
                                      : null,
                                ),
                        ),
                        if (_reminderSentAt != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.sacredGreen.withAlpha(22),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppTheme.sacredGreen.withAlpha(90),
                                ),
                              ),
                              child: const Text(
                                'Reminder sent just now',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.sacredGreen,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

  Widget _photoAvatar(
    BuildContext context, {
    required bool canViewPhoto,
    User? target,
  }) {
    return _buildPeerPhotoAvatar(
      context,
      canViewPhoto: canViewPhoto,
      peer: target,
      fallbackUserId: _targetUserId,
      size: 56,
      lockedAccent: AppTheme.primaryOrange,
    );
  }
}

// ─── MESSAGES TAB ───────────────────────────────────────────────────────────────

class _MessagesTab extends StatefulWidget {
  const _MessagesTab();

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab>
    with AutomaticKeepAliveClientMixin<_MessagesTab> {
  Stream<List<Map<String, dynamic>>>? _chatsStream;
  String? _boundUserId;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final userId = (auth.currentUser?.id ?? '').trim();
    if (userId.isEmpty || _boundUserId == userId) return;
    _boundUserId = userId;
    _chatsStream = ChatService().getUserChats().asBroadcastStream();
    final accepted = context.read<InterestService>().interestsReceived
        .cast<Map<String, dynamic>>()
        .where((r) {
      final s = (r['status'] as String? ?? '').toLowerCase();
      return s == 'accepted' || s == 'granted';
    });
    final sentAccepted = context.read<InterestService>().interestsSent
        .cast<Map<String, dynamic>>()
        .where((r) {
      final s = (r['status'] as String? ?? '').toLowerCase();
      return s == 'accepted' || s == 'granted';
    });
    unawaited(
      ChatService().repairChatsForAcceptedInterests([
        ...accepted,
        ...sentAccepted,
      ]),
    );
  }

  static String _sanitizeChatPreview(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty || t.toLowerCase() == 'null') return '';
    return t;
  }

  static String? _otherParticipant(
    Map<String, dynamic> chat,
    Set<String> myIds,
  ) {
    final parts = (chat['participants'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    for (final p in parts) {
      if (!myIds.contains(p)) return p;
    }
    return parts.isNotEmpty ? parts.first : null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.read<AuthService>();
    final userId = (auth.currentUser?.id ?? '').trim();
    final myIds = <String>{
      (auth.currentUser?.authUid ?? '').trim(),
      userId,
      (auth.getCurrentUid() ?? '').trim(),
    }..removeWhere((v) => v.isEmpty);

    return RefreshIndicator(
      color: AppTheme.primaryOrange,
      onRefresh: () async {
        if (mounted) {
          setState(() {
            _chatsStream =
                ChatService().getUserChats().asBroadcastStream();
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          final chatsLoading = snapshot.connectionState ==
                  ConnectionState.waiting &&
              !snapshot.hasData;
          if (chatsLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryOrange),
            );
          }

          final chats = snapshot.hasError
              ? const <Map<String, dynamic>>[]
              : (snapshot.data ?? const <Map<String, dynamic>>[]);
          final visibleChats = <Map<String, dynamic>>[];
          for (final chat in chats) {
            final otherId = _otherParticipant(chat, myIds);
            if (otherId == null || otherId.isEmpty) continue;
            visibleChats.add(chat);
          }

          final streamError = snapshot.hasError ? snapshot.error : null;
          final showChatWarning =
              streamError != null && visibleChats.isEmpty;

          if (visibleChats.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.only(top: 48, left: 16, right: 16),
              children: [
                if (showChatWarning)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Chats could not be loaded right now. Pull down to retry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AC.textSub(context),
                      ),
                    ),
                  ),
                const _EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No messages yet',
                  subtitle:
                      'When you and a match both accept, your conversation appears here. '
                      'Photo requests are on the Received tab.',
                ),
              ],
            );
          }

          final children = <Widget>[];
          if (showChatWarning) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Some chats could not be loaded. Pull down to retry.',
                  style: TextStyle(fontSize: 13, color: AC.textSub(context)),
                ),
              ),
            );
          }
          for (final chat in visibleChats) {
            final chatId = (chat['id'] as String? ?? '').trim();
            final otherId = _otherParticipant(chat, myIds)!;
            final last = _sanitizeChatPreview(chat['lastMessage'] as String?);
            final updated = chat['updated_at'];
            var timeStr = '';
            if (updated is Timestamp) {
              timeStr = _fmtTs(updated.toDate().toIso8601String());
            }
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChatPreviewTile(
                  chatId: chatId,
                  otherUserId: otherId,
                  lastMessage: last,
                  trailingTime: timeStr,
                ),
              ),
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: children,
          );
        },
      ),
    );
  }
}

class _ChatPreviewTile extends StatelessWidget {
  final String chatId;
  final String otherUserId;
  final String lastMessage;
  final String trailingTime;

  const _ChatPreviewTile({
    required this.chatId,
    required this.otherUserId,
    required this.lastMessage,
    required this.trailingTime,
  });

  @override
  Widget build(BuildContext context) {
    final viewer = context.read<AuthService>().currentUser;
    final isPremium =
        context.read<AuthService>().currentUser?.membership.isPremium ?? false;
    final peerViewFuture = _cachedPeerViewData(
      viewer: viewer,
      otherUserId: otherUserId,
    );
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final data = await peerViewFuture;
          final access = data.access;
          if (!context.mounted) return;
          if (!access.canViewProfile) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_protectedSubtitle(access))));
            return;
          }
          final blockReason = await InterestsAccessPolicy.chatBlockReason(
            me: viewer,
            peerUserId: otherUserId,
            interestStatus: 'accepted',
            blockService: context.read<BlockService>(),
          );
          if (!context.mounted) return;
          if (blockReason != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(blockReason),
                backgroundColor: blockReason.contains('Premium')
                    ? AppTheme.primaryOrange
                    : AppTheme.kumkumRed,
              ),
            );
            if (blockReason.contains('Premium')) {
              Navigator.pushNamed(context, Routes.premiumUpgrade);
            }
            return;
          }
          var resolvedChatId = chatId.trim();
          if (resolvedChatId.isEmpty) {
            resolvedChatId =
                await ChatService().getOrCreateChatRoom(otherUserId);
          }
          if (!context.mounted) return;
          if (resolvedChatId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open chat. Check your connection and try again.',
                ),
                backgroundColor: AppTheme.kumkumRed,
              ),
            );
            return;
          }
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(
                chatId: resolvedChatId,
                otherUserId: otherUserId,
              ),
            ),
          );
          if (!context.mounted) return;
          await ChatService().markMessagesAsRead(resolvedChatId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: FutureBuilder<({User? user, _PrivacyRowAccess access})>(
            future: peerViewFuture,
            builder: (context, snapshot) {
                  final data = snapshot.data;
                  final access = data?.access ??
                      const _PrivacyRowAccess(
                        canViewProfile: false,
                        canViewIdentity: false,
                        canViewPhoto: false,
                      );
                  final u = data?.user;
                  final protected = !access.canViewIdentity;
                  final first = (u?.profile?.firstName ?? '').trim();
                  final name = protected
                      ? 'Protected Profile'
                      : first.isNotEmpty
                          ? first
                          : (u != null && u.profileId.isNotEmpty
                              ? u.profileId
                              : 'Member');
                  final subtitle = protected
                      ? _protectedSubtitle(access)
                      : !isPremium
                          ? 'Message hidden. Upgrade to Premium to view.'
                          : (lastMessage.isEmpty
                              ? 'Tap to open chat'
                              : lastMessage);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primaryOrange.withAlpha(40),
                    child: Icon(
                      protected
                          ? Icons.lock_outline_rounded
                          : Icons.person_rounded,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AC.text(context),
                                ),
                              ),
                            ),
                            if (trailingTime.isNotEmpty)
                              Text(
                                trailingTime,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AC.textMuted(context),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AC.textSub(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isPremium
                        ? Icons.chevron_right_rounded
                        : Icons.lock_outline_rounded,
                    color: AC.textMuted(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── VIEWS TAB ────────────────────────────────────────────────────────────────

class _ViewsTab extends StatelessWidget {
  final ProfileAnalyticsService analytics;
  final String viewedProfileId;
  final String fallbackViewedUserId;
  final VoidCallback onOpenInterestStats;
  final String currentUserId;
  final List<String> currentUserIds;
  final List<Map<String, dynamic>> received;
  final List<Map<String, dynamic>> sent;
  final Future<void> Function() onRefresh;

  const _ViewsTab({
    required this.analytics,
    required this.viewedProfileId,
    required this.fallbackViewedUserId,
    required this.onOpenInterestStats,
    required this.currentUserId,
    required this.currentUserIds,
    required this.received,
    required this.sent,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    void openViewerHistory() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WhoSawYourProfileScreen(
            viewedProfileId: viewedProfileId,
            fallbackViewedUserId: fallbackViewedUserId,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primaryOrange,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        // Rebuild-only subscription; compat stream avoids 50-row cap (see Overview tab).
        stream: _ProfileViewersStreamCache.forProfile(viewedProfileId),
        initialData: const <Map<String, dynamic>>[],
        builder: (context, snap) {
          final merged = <Map<String, dynamic>>[
            ...received.map((e) => Map<String, dynamic>.from(e)),
            ...sent.map((e) => Map<String, dynamic>.from(e)),
          ];
          merged.sort((a, b) {
            final ub = _interestSortMillis(b['updated_at']) > 0
                ? _interestSortMillis(b['updated_at'])
                : _interestSortMillis(b['created_at']);
            final ua = _interestSortMillis(a['updated_at']) > 0
                ? _interestSortMillis(a['updated_at'])
                : _interestSortMillis(a['created_at']);
            return ub.compareTo(ua);
          });
          final top = merged.take(5).toList();

          return SingleChildScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader(title: 'View History'),
                const SizedBox(height: 10),
                _NavTile(
                  title: 'See All Viewers',
                  sub: 'Full viewer list with profile details',
                  icon: Icons.people_outline_rounded,
                  color: AppTheme.peacockBlue,
                  onTap: openViewerHistory,
                ),
                const SizedBox(height: 22),
                const _SectionHeader(title: 'Recent Activity'),
                const SizedBox(height: 8),
                if (top.isEmpty)
                  _NavTile(
                    title: 'No Recent Activity',
                    sub: 'Interest updates will appear here',
                    icon: Icons.inbox_outlined,
                    color: AC.textSub(context),
                    onTap: onOpenInterestStats,
                  )
                else
                  ...top.map(
                    (data) {
                      final docId =
                          InterestBadgeAggregator.interestDocumentId(data);
                      return _ActivityTile(
                        data: data,
                        docId: docId.isNotEmpty
                            ? docId
                            : (data['id'] as String? ?? ''),
                        currentUserId: currentUserId,
                        currentUserIds: currentUserIds,
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NavTile({
    required this.title,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(36),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AC.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 13,
                        color: AC.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AC.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MetricCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.25,
                color: AC.textSub(context),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String currentUserId;
  final List<String> currentUserIds;
  const _ActivityTile({
    required this.data,
    required this.docId,
    required this.currentUserId,
    required this.currentUserIds,
  });

  String _field(String key) => (data[key] as String? ?? '').trim();

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  bool _isCurrentUserId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    return currentUserIds.any((current) => current.trim() == trimmed);
  }

  bool get _isReceived {
    final fromUserId = _field('from_user_id');
    final toUserId = _field('to_user_id');
    if (_isCurrentUserId(toUserId)) return true;
    if (_isCurrentUserId(fromUserId)) return false;
    return toUserId == currentUserId;
  }

  String get _peerUserId =>
      _isReceived ? _field('from_user_id') : _field('to_user_id');

  String get _peerProfileId => _firstNonEmpty([
        _isReceived ? _field('from_profile_id') : _field('to_profile_id'),
        _field('profile_id'),
        _field('profileId'),
      ]);

  String get _peerName => _firstNonEmpty([
        _isReceived
            ? '${_field('from_first_name')} ${_field('from_last_name')}'
            : '${_field('to_first_name')} ${_field('to_last_name')}',
        _field('name'),
        '${_field('first_name')} ${_field('last_name')}',
      ]);

  String get _peerPhotoUrl => _firstNonEmpty([
        _isReceived ? _field('from_photo_url') : _field('to_photo_url'),
        _field('photo_url'),
        _field('photoUrl'),
        _field('profile_picture'),
        _field('profilePicture'),
      ]);

  Future<User?> _loadPeerUser() async {
    final peerId = _peerUserId;
    final peerProfileId = _peerProfileId;
    if (peerId.isEmpty && peerProfileId.isEmpty) return null;
    try {
      final user = peerId.isNotEmpty
          ? await ProfileRepository().lookupUserByAnyId(peerId)
          : null;
      if (user != null) return user;
      if (peerProfileId.isNotEmpty) {
        return await ProfileRepository().lookupUserByAnyId(peerProfileId);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openProfile(BuildContext context) async {
    final profileId = _peerProfileId;
    if (profileId.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByProfileId(
        context,
        profileId: profileId,
        routeGuardInterestDocId: docId,
      );
      return;
    }
    final userId = _peerUserId;
    if (userId.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: userId,
        routeGuardInterestDocId: docId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = _isReceived;
    final status =
        (data['status'] as String? ?? 'pending').trim().toLowerCase();
    final timeLabel = _interestTimeLabel(data);
    final fallbackName = _peerName;
    final fallbackProfileId = _peerProfileId;
    final fallbackPhotoUrl = _peerPhotoUrl;
    final fallbackUserId = _peerUserId;
    final hasSnapshot = InterestRowHelpers.hasSnapshotIdentity(
      data,
      isReceived: isReceived,
    );
    return FutureBuilder<User?>(
      future: _loadPeerUser(),
      builder: (context, userSnap) {
        final u = userSnap.data;
        return FutureBuilder<_PrivacyRowAccess>(
          future: _resolvePrivacyAccess(
            context: context,
            candidate: u,
            fallbackUserId: fallbackUserId,
          ),
          builder: (context, accessSnap) {
            final access = accessSnap.data ??
                const _PrivacyRowAccess(
                  canViewProfile: false,
                  canViewIdentity: false,
                  canViewPhoto: false,
                );
            final showIdentity = access.canViewIdentity || hasSnapshot;
            final canOpenProfile = access.canViewProfile || hasSnapshot;
            final photoUrl =
                (u?.profile?.profilePicture ?? fallbackPhotoUrl).trim();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                tileColor: Theme.of(context).cardColor,
                splashColor: AppTheme.primaryOrange.withAlpha(40),
                hoverColor: AppTheme.primaryOrange.withAlpha(20),
                onTap: canOpenProfile
                    ? () => _openProfile(context)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_protectedSubtitle(access))),
                        ),
                leading: SizedBox(
                  width: 40,
                  height: 40,
                  child: ProfilePhoto(
                    profile: u?.profileForDiscovery ??
                        UserProfile.fallbackForDiscovery(
                          User(
                            id: fallbackUserId.isNotEmpty
                                ? fallbackUserId
                                : fallbackProfileId,
                            email: '',
                            password: '',
                            mobileNumber: '',
                          ),
                        ),
                    ownerUserId: u?.id ?? (fallbackUserId.isNotEmpty ? fallbackUserId : null),
                    ownerUserDoc: u?.discoveryPhotoFirestoreMap() ??
                        <String, dynamic>{
                          if (photoUrl.isNotEmpty) ...{
                            'profile_picture': photoUrl,
                            'photo_url': photoUrl,
                          },
                        },
                    size: 40,
                    circle: true,
                    isPremiumViewer:
                        context.read<AuthService>().currentUser?.membership.isPremium ?? false,
                    photoAccessGranted: access.canViewPhoto,
                  ),
                ),
                title: Builder(
                  builder: (context) {
                    final liveName = (u?.profile?.fullName ?? '').trim();
                    final snapName = fallbackName.trim();
                    final displayName = liveName.isNotEmpty
                        ? liveName
                        : (snapName.isNotEmpty && snapName != 'Member'
                            ? snapName
                            : '');
                    final profileId =
                        (u?.profileId ?? fallbackProfileId).trim();
                    final subtitle = showIdentity
                        ? (profileId.isNotEmpty
                            ? 'ID: $profileId  •  ${_statusLbl(status)}'
                            : _statusLbl(status))
                        : _protectedSubtitle(access);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showIdentity
                              ? (displayName.isNotEmpty
                                  ? displayName
                                  : (profileId.isNotEmpty
                                      ? 'Profile $profileId'
                                      : 'Member'))
                              : 'Protected Profile',
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                subtitle: const SizedBox.shrink(),
                trailing: Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Shared peer photo for interests / access-request rows.
Widget _buildPeerPhotoAvatar(
  BuildContext context, {
  required bool canViewPhoto,
  User? peer,
  String fallbackUserId = '',
  double size = 56,
  bool circle = false,
  Color? lockedAccent,
  bool showPrivateLabel = false,
}) {
  final radius = circle ? size / 2 : 12.0;
  final accent = lockedAccent ?? AppTheme.primaryOrange;

  if (!canViewPhoto || peer == null) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withAlpha(36),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withAlpha(72)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            color: AC.textMuted(context),
            size: size * 0.32,
          ),
          if (showPrivateLabel && size >= 48) ...[
            const SizedBox(height: 2),
            Text(
              'Photo\nprivate',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: AC.textMuted(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  final premium =
      context.read<AuthService>().currentUser?.membership.isPremium ?? false;
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: ProfilePhoto(
      profile: peer.profileForDiscovery,
      ownerUserId: peer.id,
      ownerUserDoc: peer.discoveryPhotoFirestoreMap(),
      size: size,
      circle: circle,
      isPremiumViewer: premium,
      photoAccessGranted: canViewPhoto,
    ),
  );
}

Widget _interestPeerAvatar(
  BuildContext context, {
  required bool canViewPhoto,
  required User? peer,
  required bool isReceived,
  required Color statusColor,
}) {
  return _buildPeerPhotoAvatar(
    context,
    canViewPhoto: canViewPhoto,
    peer: peer,
    size: 48,
    circle: true,
    lockedAccent: statusColor,
    showPrivateLabel: true,
  );
}

class _InterestTile extends StatelessWidget {
  static final Set<String> _autoViewedKeys = <String>{};

  final Map<String, dynamic> data;
  final String docId;
  final bool isReceived;
  final String currentUserId;
  const _InterestTile({
    required this.data,
    required this.docId,
    required this.isReceived,
    required this.currentUserId,
  });

  Future<User?> _loadPeerUser() =>
      InterestRowHelpers.loadPeerUser(data, isReceived: isReceived);

  Future<void> _markSeenForBell(BuildContext context) async {
    final id = docId.trim();
    if (id.isEmpty) return;
    final key = '${isReceived ? 'received' : 'sent'}:$id';
    if (_autoViewedKeys.contains(key)) return;
    _autoViewedKeys.add(key);
    try {
      final interestService = context.read<InterestService>();
      if (isReceived) {
        await interestService.markInterestViewedByRecipient(id);
      } else {
        await interestService.markInterestViewedBySender(id);
      }
      await context
          .read<NotificationService>()
          .markInterestNotificationsReadForInterest(id);
    } catch (e) {
      // Retry on next rebuild if marking fails (network / permission race).
      _autoViewedKeys.remove(key);
      debugPrint('⚠️ auto mark interest viewed failed: $e');
    }
  }

  Future<void> _openProfile(BuildContext context) async {
    final interestService = context.read<InterestService>();
    if (docId.isNotEmpty) {
      try {
        if (isReceived) {
          await interestService.markInterestViewedByRecipient(docId);
        } else {
          await interestService.markInterestViewedBySender(docId);
        }
        try {
          if (!context.mounted) return;
          await context
              .read<NotificationService>()
              .markInterestNotificationsReadForInterest(docId);
        } catch (e) {
          debugPrint('⚠️ mark interest notifications read failed: $e');
        }
        try {
          await interestService.loadInterests(currentUserId);
        } catch (e) {
          debugPrint('⚠️ refresh after mark viewed failed: $e');
        }
      } catch (e) {
        debugPrint('⚠️ mark interest viewed failed: $e');
      }
    }
    if (!context.mounted) return;
    // Try profile_id first
    final profileId = InterestRowHelpers.peerProfileId(
      data,
      isReceived: isReceived,
    );
    if (profileId.isNotEmpty) {
      if (!context.mounted) return;
      unawaited(InterestsHubAnalytics.profileViewOpened(profileId: profileId));
      await SafeProfileNav.safeOpenProfileByProfileId(
        context,
        profileId: profileId,
        routeGuardInterestDocId: docId,
      );
      return;
    }
    // Fall back to user_id
    final userId = InterestRowHelpers.peerUserId(
      data,
      isReceived: isReceived,
    );
    if (userId.isNotEmpty) {
      if (!context.mounted) return;
      unawaited(InterestsHubAnalytics.profileViewOpened(profileId: profileId));
      await SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: userId,
        routeGuardInterestDocId: docId,
      );
    }
  }

  Future<void> _openChatForAccepted(BuildContext context) async {
    final auth = context.read<AuthService>();
    final me = auth.currentUser;
    final status = _normalizeRequestStatus(data['status'] as String? ?? 'pending');
    final peerId = InterestRowHelpers.peerUserId(data, isReceived: isReceived);
    final blockReason = await InterestsAccessPolicy.chatBlockReason(
      me: me,
      peerUserId: peerId,
      peerProfileId: InterestRowHelpers.peerProfileId(
        data,
        isReceived: isReceived,
      ),
      interestStatus: status,
      blockService: context.read<BlockService>(),
    );
    if (!context.mounted) return;
    if (blockReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blockReason),
          backgroundColor: blockReason.contains('Premium')
              ? AppTheme.primaryOrange
              : AppTheme.kumkumRed,
        ),
      );
      if (blockReason.contains('Premium')) {
        Navigator.pushNamed(context, Routes.premiumUpgrade);
      }
      return;
    }

    final peer = await _loadPeerUser();
    if (peerId.isEmpty) return;

    final chatId = await ChatService().getOrCreateChatRoom(peerId);
    if (!context.mounted) return;
    if (chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open chat right now.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chatId: chatId,
          otherUserId: peerId,
          otherUserName: peer?.profile?.firstName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(_markSeenForBell(context));
    });
    final status = _normalizeRequestStatus(
      data['status'] as String? ?? 'pending',
    );
    final timeLabel = _interestTimeLabel(data);
    final fallbackName =
        InterestRowHelpers.peerName(data, isReceived: isReceived);
    final fallbackUserId =
        InterestRowHelpers.peerUserId(data, isReceived: isReceived);
    final hasSnapshot =
        InterestRowHelpers.hasSnapshotIdentity(data, isReceived: isReceived);
    return FutureBuilder<User?>(
      future: _loadPeerUser(),
      builder: (context, userSnap) {
        final peerUser = userSnap.data;
        return FutureBuilder<_PrivacyRowAccess>(
          future: _resolvePrivacyAccess(
            context: context,
            candidate: peerUser,
            fallbackUserId: fallbackUserId,
            requiresAccepted: true,
            isAccepted: status == 'accepted',
          ),
          builder: (context, accessSnap) {
            final access = accessSnap.data ??
                const _PrivacyRowAccess(
                  canViewProfile: false,
                  canViewIdentity: false,
                  canViewPhoto: false,
                );
            final showIdentity =
                access.canViewIdentity || hasSnapshot;
            final canOpenProfile =
                access.canViewProfile || hasSnapshot;
            return Material(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: canOpenProfile
                    ? () => _openProfile(context)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_protectedSubtitle(access))),
                        ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AC.border(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _interestPeerAvatar(
                              context,
                              canViewPhoto: access.canViewPhoto,
                              peer: peerUser,
                              isReceived: isReceived,
                              statusColor: _statusClr(status),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final u = peerUser;
                                  final snapName = fallbackName.trim();
                                  final fullName = (u?.profile?.fullName ?? '')
                                      .trim();
                                  final displayName = fullName.isNotEmpty
                                      ? fullName
                                      : (snapName.isNotEmpty &&
                                              snapName != 'Member'
                                          ? snapName
                                          : '');
                                  final profileId = (u?.profileId ??
                                          InterestRowHelpers.peerProfileId(
                                            data,
                                            isReceived: isReceived,
                                          ))
                                      .trim();
                                  final age = InterestRowHelpers.peerAge(
                                    data,
                                    u,
                                    isReceived: isReceived,
                                  );
                                  final ageText = InterestIdentityResolver
                                      .peerAgeText(
                                    data,
                                    isReceived: isReceived,
                                    liveAge: age,
                                  );
                                  final locationText =
                                      InterestRowHelpers.peerLocation(
                                    data,
                                    u,
                                    isReceived: isReceived,
                                  );

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        showIdentity
                                            ? (displayName.isNotEmpty
                                                ? displayName
                                                : (profileId.isNotEmpty
                                                    ? 'Profile $profileId'
                                                    : 'Member'))
                                            : 'Protected Profile',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.titleLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        showIdentity
                                            ? '${profileId.isNotEmpty ? 'ID: $profileId · ' : ''}$ageText'
                                            : 'Age hidden',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AC.textMuted(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        showIdentity
                                            ? locationText
                                            : _protectedSubtitle(access),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AC.textMuted(context),
                                        ),
                                      ),
                                      if (timeLabel.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            timeLabel,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AC.textSub(context),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _statusClr(status).withAlpha(15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _statusClr(status).withAlpha(60),
                                ),
                              ),
                              child: Text(
                                _statusLbl(status),
                                style: TextStyle(
                                  color: _statusClr(status),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isReceived && status == 'pending') ...[
                          const SizedBox(height: 12),
                          RequestActionBar(
                            first: RequestActionItem(
                              label: RequestUiContract.accept,
                              icon: Icons.check_circle_outline,
                              isPrimary: true,
                              color: AppTheme.sacredGreen,
                              onPressed: () => _respondToInterest(
                                context,
                                docId,
                                'accepted',
                              ),
                            ),
                            second: RequestActionItem(
                              label: RequestUiContract.decline,
                              icon: Icons.cancel_outlined,
                              color: AppTheme.kumkumRed,
                              onPressed: () => _respondToInterest(
                                context,
                                docId,
                                'rejected',
                              ),
                            ),
                          ),
                        ],
                        if (!isReceived && status == 'pending') ...[
                          const SizedBox(height: 12),
                          RequestActionBar(
                            first: RequestActionItem(
                              label: RequestUiContract.withdraw,
                              icon: Icons.undo,
                              onPressed: () => _withdrawInterest(
                                context,
                                docId,
                                currentUserId,
                              ),
                            ),
                            second: RequestActionItem(
                              label: RequestUiContract.reminder,
                              icon: Icons.notifications_active_outlined,
                              color: AppTheme.primaryOrange,
                              onPressed: () =>
                                  _sendReminderInterest(context, docId),
                            ),
                          ),
                        ],
                        if (status != 'pending' &&
                            status != 'sent' &&
                            status != 'accepted') ...[
                          const SizedBox(height: 12),
                          RequestActionBar(
                            first: RequestActionItem(
                              label: 'Delete',
                              icon: Icons.delete_outline,
                              color: AppTheme.kumkumRed,
                              onPressed: () =>
                                  _hideInterest(context, docId, currentUserId),
                            ),
                            second: RequestActionItem(
                              label: 'View Profile',
                              icon: Icons.person_outline,
                              color: AppTheme.textMedium,
                              onPressed: access.canViewProfile
                                  ? () => _openProfile(context)
                                  : null,
                            ),
                          ),
                        ],
                        if (status == 'accepted') ...[
                          const SizedBox(height: 12),
                          RequestActionBar(
                            first: RequestActionItem(
                              label: 'Chat',
                              icon: Icons.chat_bubble_outline,
                              isPrimary: true,
                              color: AppTheme.primaryOrange,
                              onPressed: () => _openChatForAccepted(context),
                            ),
                            second: RequestActionItem(
                              label: 'View Profile',
                              icon: Icons.person_outline,
                              color: AppTheme.textMedium,
                              onPressed: access.canViewProfile
                                  ? () => _openProfile(context)
                                  : null,
                            ),
                          ),
                          if (!isReceived) ...[
                            const SizedBox(height: 12),
                            RequestActionBar(
                              first: RequestActionItem(
                                label: 'Withdraw Interest',
                                icon: Icons.undo,
                                color: AppTheme.kumkumRed,
                                onPressed: () => _withdrawInterest(
                                  context,
                                  docId,
                                  currentUserId,
                                ),
                              ),
                              second: RequestActionItem(
                                label: 'View Profile',
                                icon: Icons.person_outline,
                                color: AppTheme.textMedium,
                                onPressed: access.canViewProfile
                                    ? () => _openProfile(context)
                                    : null,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _respondToInterest(
    BuildContext context,
    String interestId,
    String status,
  ) async {
    final svc = context.read<InterestService>();
    final result = await svc.respondToInterestWithResult(
      interestId: interestId,
      response: status == 'accepted' ? 'accepted' : 'rejected',
    );
    // Force immediate repaint of Received/Sent/Overview tabs after write.
    // This avoids waiting for stream propagation in mixed-network conditions.
    try {
      await svc.loadInterests(currentUserId);
    } catch (e) {
      debugPrint('⚠️ Interest refresh after respond failed: $e');
    }
    if (context.mounted && result['success'] == true) {
      await context
          .read<NotificationService>()
          .markInterestNotificationsReadForInterest(interestId);
      await context.read<NotificationService>().reconcileInterestReceivedNotifications(
        svc.interestsReceived,
      );
    }
    if (!context.mounted) return;
    if (result['success'] == true) {
      final peerId = InterestRowHelpers.peerUserId(data, isReceived: isReceived);
      if (status == 'accepted') {
        unawaited(
          InterestsHubAnalytics.interestAccepted(interestId: interestId),
        );
        unawaited(
          MatrimonyGatewayService.unlockContact(
            interestId: interestId,
            peerUserId: peerId.isNotEmpty ? peerId : null,
          ),
        );
        if (peerId.isNotEmpty) {
          try {
            await ChatService().getOrCreateChatRoom(peerId);
          } catch (e) {
            debugPrint('⚠️ Could not pre-create chat room after accept: $e');
          }
        }
      } else {
        unawaited(
          InterestsHubAnalytics.interestRejected(interestId: interestId),
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] as String? ??
                (status == 'accepted'
                    ? 'Interest accepted!'
                    : 'Interest declined'),
          ),
          backgroundColor:
              status == 'accepted' ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] as String? ?? RequestUiContract.respondFailed,
          ),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _withdrawInterest(
    BuildContext context,
    String interestId,
    String currentUserId,
  ) async {
    final interestService = context.read<InterestService>();

    final result = await interestService.withdrawInterestWithResult(
      interestId: interestId,
    );
    if (result['success'] == true) {
      unawaited(() async {
        try {
          await interestService.loadInterests(currentUserId);
        } catch (e) {
          debugPrint('⚠️ Interest refresh after withdraw failed: $e');
        }
      }());
    }

    if (context.mounted) {
      if (result['success'] == true) {
        unawaited(
          InterestsHubAnalytics.interestWithdrawn(interestId: interestId),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Interest withdrawn'),
            backgroundColor: AppTheme.textMedium,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? RequestUiContract.withdrawFailed,
            ),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    }
  }

  Future<void> _sendReminderInterest(
    BuildContext context,
    String interestId,
  ) async {
    final service = context.read<InterestService>();
    try {
      await service.sendInterestReminderForSentRow(interestId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(RequestUiContract.reminderSent),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${RequestUiContract.reminderFailed}: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _hideInterest(
    BuildContext context,
    String interestId,
    String currentUserId,
  ) async {
    final service = context.read<InterestService>();
    final result = await service.hideInterestWithResult(interestId: interestId);
    unawaited(() async {
      try {
        await service.loadInterests(currentUserId);
      } catch (_) {}
    }());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Request removed'
              : 'Could not remove request',
        ),
        backgroundColor: result['success'] == true
            ? AppTheme.sacredGreen
            : AppTheme.kumkumRed,
      ),
    );
  }
}

// ─── MATCHES TAB (MUTUAL INTERESTS) ─────────────────────────────────────────────

class _MatchesTab extends StatefulWidget {
  final String userId;
  const _MatchesTab({required this.userId});

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Get all accepted interests where current user is involved
      final userId = widget.userId;

      final matches = await InterestAnalyticsRepository()
          .loadAcceptedInterestsForMatches(userId);

      if (mounted) {
        setState(() {
          _matches = matches;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openProfile(String partnerId) async {
    if (!mounted) return;
    await SafeProfileNav.safeOpenProfileByUserId(context, userId: partnerId);
  }

  Future<void> _startChat(Map<String, dynamic> match) async {
    final partnerId = match['_partner_id'] as String? ?? '';
    final partnerName = match['_partner_name'] as String? ?? 'Match';

    if (partnerId.isEmpty) return;

    // Navigate to chat screen
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: {'user_id': partnerId, 'name': partnerName},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryOrange),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.kumkumRed,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading matches',
              style: TextStyle(color: AC.text(context)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadMatches,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.favorite,
                  size: 64,
                  color: AppTheme.sacredGreen,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Matches Yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AC.text(context),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'When you and another member accept each other\'s interest, they\'ll appear here.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AC.textMuted(context)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/matches'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('Find Matches'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMatches,
      color: AppTheme.primaryOrange,
      child: ListView.builder(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        itemCount: _matches.length,
        itemBuilder: (context, index) {
          final match = _matches[index];
          final partnerName = match['_partner_name'] as String? ?? 'Unknown';
          final partnerPid = match['_partner_pid'] as String? ?? '';
          final partnerPhoto = match['_partner_photo'] as String? ?? '';
          final partnerId = match['_partner_id'] as String? ?? '';
          final acceptedAt = match['updated_at'] as String? ??
              match['created_at'] as String? ??
              '';

          final initial = partnerName.isNotEmpty && partnerName != 'Unknown'
              ? partnerName[0].toUpperCase()
              : '?';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AC.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.sacredGreen.withAlpha(40)),
              boxShadow: [
                BoxShadow(
                  color: AC.shadow(context).withAlpha(20),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final partner = await ProfileRepository().lookupUserByAnyId(
                    partnerId,
                  );
                  if (!context.mounted) return;
                  final access = await _resolvePrivacyAccess(
                    context: context,
                    candidate: partner,
                    fallbackUserId: partnerId,
                    requiresAccepted: true,
                    isAccepted: true,
                  );
                  if (!context.mounted) return;
                  if (!access.canViewProfile) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_protectedSubtitle(access))),
                    );
                    return;
                  }
                  _openProfile(partnerId);
                },
                child: FutureBuilder<User?>(
                  future: ProfileRepository().lookupUserByAnyId(partnerId),
                  builder: (context, snap) {
                    final partnerUser = snap.data;
                    return FutureBuilder<_PrivacyRowAccess>(
                      future: _resolvePrivacyAccess(
                        context: context,
                        candidate: partnerUser,
                        fallbackUserId: partnerId,
                        requiresAccepted: true,
                        isAccepted: true,
                      ),
                      builder: (context, accessSnap) {
                        final access = accessSnap.data ??
                            const _PrivacyRowAccess(
                              canViewProfile: false,
                              canViewIdentity: false,
                              canViewPhoto: false,
                            );
                        return Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // Profile photo
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.goldGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: partnerUser != null
                                      ? ProfilePhoto(
                                          profile: partnerUser.profileForDiscovery,
                                          ownerUserId: partnerUser.id,
                                          ownerUserDoc:
                                              partnerUser.discoveryPhotoFirestoreMap(),
                                          size: 56,
                                          isPremiumViewer: context
                                                  .read<AuthService>()
                                                  .currentUser
                                                  ?.membership
                                                  .isPremium ??
                                              false,
                                          photoAccessGranted: access.canViewPhoto,
                                        )
                                      : (!access.canViewPhoto || partnerPhoto.isEmpty)
                                          ? Center(
                                              child: Text(
                                                access.canViewIdentity ? initial : '•',
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            )
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            access.canViewIdentity
                                                ? partnerName
                                                : 'Protected Profile',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: AC.text(context),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.sacredGreen
                                                .withAlpha(18),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: AppTheme.sacredGreen
                                                  .withAlpha(60),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                size: 12,
                                                color: AppTheme.sacredGreen,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Matched',
                                                style: TextStyle(
                                                  color: AppTheme.sacredGreen,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (access.canViewIdentity &&
                                        partnerPid.isNotEmpty)
                                      Text(
                                        'ID: $partnerPid',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AC.textSub(context),
                                        ),
                                      ),
                                    if (!access.canViewIdentity)
                                      Text(
                                        _protectedSubtitle(access),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AC.textSub(context),
                                        ),
                                      ),
                                    if (acceptedAt.isNotEmpty)
                                      Text(
                                        'Matched ${_fmtTs(acceptedAt)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AC.textMuted(context),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Chat button
                              if (!(context
                                      .read<AuthService>()
                                      .currentUser
                                      ?.membership
                                      .isPremium ??
                                  false))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFD700),
                                        Color(0xFFFFA500),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.workspace_premium,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Chat',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                IconButton(
                                  onPressed: access.canViewProfile
                                      ? () => _startChat(match)
                                      : null,
                                  icon: const Icon(
                                    Icons.chat_bubble_outline,
                                    color: AppTheme.primaryOrange,
                                  ),
                                  tooltip: 'Start Chat',
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(delay: Duration(milliseconds: 50 * index))
              .slideY(begin: 0.05);
        },
      ),
    );
  }
}

// ─── BLOCKED PROFILES TAB ───────────────────────────────────────────────────────────

String _blockedTabSignature(BlockService b) {
  if (b.isLoading) return 'L';
  final ids = b.blockedUsers.map((u) => u.profileId).toList()..sort();
  return '${ids.length}:${ids.join('|')}';
}

class _BlockedTab extends StatelessWidget {
  const _BlockedTab();

  @override
  Widget build(BuildContext context) {
    return Selector<BlockService, String>(
      selector: (_, b) => _blockedTabSignature(b),
      builder: (context, _, __) {
        final blockService = context.read<BlockService>();
        final blockedUsers = blockService.blockedUsers;

        if (blockService.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }

        if (blockedUsers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.sacredGreen.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppTheme.sacredGreen,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Blocked Profiles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AC.text(context),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You haven\'t blocked anyone yet.\nBlocked profiles cannot see your profile.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AC.textMuted(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ).animate().fadeIn(),
            ),
          );
        }

        return ListView.builder(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          itemCount: blockedUsers.length,
          itemBuilder: (context, index) {
            final user = blockedUsers[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AC.card(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                tileColor: AC.card(context),
                splashColor: AppTheme.primaryOrange.withAlpha(40),
                hoverColor: AppTheme.primaryOrange.withAlpha(20),
                contentPadding: const EdgeInsets.all(12),
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: ProfilePhoto(
                    profile: UserProfile.fallbackForDiscovery(
                      User(
                        id: user.userDocId.isNotEmpty ? user.userDocId : user.profileId,
                        profileId: user.profileId,
                        email: '',
                        password: '',
                        mobileNumber: '',
                      ),
                    ),
                    ownerUserId: user.userDocId.isNotEmpty ? user.userDocId : null,
                    ownerUserDoc: <String, dynamic>{
                      if ((user.photo ?? '').trim().isNotEmpty) ...{
                        'profile_picture': user.photo,
                        'photo_url': user.photo,
                      },
                    },
                    size: 56,
                    circle: true,
                    isPremiumViewer:
                        context.read<AuthService>().currentUser?.membership.isPremium ?? false,
                  ),
                ),
                title: Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AC.text(context),
                      ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${user.profileId}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AC.textMuted(context)),
                    ),
                    Text(
                      'Blocked on ${user.blockedAt.day}/${user.blockedAt.month}/${user.blockedAt.year}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AC.textMuted(context)),
                    ),
                    if (user.reason != null && user.reason!.isNotEmpty)
                      Text(
                        'Reason: ${user.reason}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.kumkumRed),
                      ),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: () =>
                      _showUnblockDialog(context, user, blockService),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.sacredGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Unblock',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: Duration(milliseconds: 50 * index))
                .slideX(begin: 0.1);
          },
        );
      },
    );
  }

  void _showUnblockDialog(
    BuildContext context,
    BlockedUser user,
    BlockService blockService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unblock Profile'),
        content: Text(
          'Are you sure you want to unblock ${user.name}?\n\nThey will be able to see your profile again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              blockService.unblockUser(user.profileId);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${user.name} has been unblocked'),
                  backgroundColor: AppTheme.sacredGreen,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.sacredGreen,
            ),
            child: const Text('Unblock', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
