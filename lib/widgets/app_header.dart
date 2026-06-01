import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_router.dart';
import '../core/interest_badge_aggregator.dart';
import '../theme/app_theme.dart';
import 'soft_touch.dart';
import '../services/notification_service.dart';
import '../services/message_service.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../services/interest_service_v2.dart';
import '../services/access_request_broadcast.dart';
import '../services/sent_access_requests_loader.dart';
import '../core/privacy_request_notification_sync.dart';

/// Logo + primary title + "Brahmin Community" for [AppHeader] / [SliverAppHeader].
///
/// Uses **screen** width (not the title slot from [LayoutBuilder]) to pick compact
/// vs full sizes. Otherwise [AppBar] trailing actions (search, filter, bell) shrink
/// the title region and the logo looks smaller than on Home, which has fewer actions.
Widget _appHeaderLogoTitle(BuildContext context, String title) {
  final screenW = MediaQuery.sizeOf(context).width;
  final narrow = screenW < 360;
  final logoSize = narrow ? 52.0 : AppHeader.kLogoSize;
  final gap = narrow ? 8.0 : 12.0;
  final titleSize = narrow ? 16.0 : 18.0;
  final subtitleSize = narrow ? 11.0 : 12.0;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/images/app_logo.png',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.cover,
        ),
      ),
      SizedBox(width: gap),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: titleSize,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Brahmin Community',
              style: GoogleFonts.poppins(
                color: Colors.white.withAlpha(210),
                fontWeight: FontWeight.w500,
                fontSize: subtitleSize,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ],
  );
}

/// Standardised App Header — orange bar on every screen.
/// Title text + "Brahmin Community" sub-line are always white (#FFFFFF)
/// so they stay readable regardless of light / dark mode.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  static const double kToolbarHeight = 64.0;
  /// Logo is 75×75; bar must be at least that tall or layout overflows and actions (e.g. bell) break.
  static const double kToolbarHeightWithLogo = 80.0;
  static const double kLogoSize = 75.0;
  final String title;
  final bool showLogo;
  final bool showNotifications;
  final bool showUpgradeButton;
  final bool showUserInfo;
  final bool showSearch;
  final VoidCallback? onSearchTap;
  final bool showFilter;
  final VoidCallback? onFilterTap;
  final bool isSearchActive;
  final bool isFilterActive;
  final List<Widget>? additionalActions;
  final VoidCallback? onRefresh;
  /// When set (e.g. main shell Home tab), bell uses this instead of pushing a route.
  final VoidCallback? onNotificationBellTap;

  const AppHeader({
    super.key,
    required this.title,
    this.showLogo = false,
    this.showNotifications = false,
    this.showUpgradeButton = false,
    this.showUserInfo = false,
    this.showSearch = false,
    this.onSearchTap,
    this.showFilter = false,
    this.onFilterTap,
    this.isSearchActive = false,
    this.isFilterActive = false,
    this.additionalActions,
    this.onRefresh,
    this.onNotificationBellTap,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(showLogo ? kToolbarHeightWithLogo : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final barH = showLogo ? kToolbarHeightWithLogo : kToolbarHeight;
    return AppBar(
      backgroundColor: AppTheme.primaryOrange,
      foregroundColor: Colors.white,          // back-arrow & default icons = white
      elevation: 2,
      shadowColor: Colors.black26,
      centerTitle: false,
      toolbarHeight: barH,
      titleSpacing: 16,
      iconTheme: const IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
      title: _buildTitle(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildTitle(BuildContext context) {
    if (showLogo) {
      return _appHeaderLogoTitle(context, title);
    }
    // Plain title (no logo)
    return Text(title,
        style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18));
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];

    if (onRefresh != null) {
      actions.add(IconButton(
        style: SoftTouch.orangeHeaderIconStyle(),
        icon: const Icon(Icons.refresh, color: Colors.white),
        onPressed: SoftTouch.wrap(onRefresh),
      ));
    }
    if (showSearch) {
      actions.add(IconButton(
        style: isSearchActive
            ? SoftTouch.orangeHeaderIconStyle(
                merge: IconButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(40),
                  shape: const CircleBorder(),
                ),
              )
            : SoftTouch.orangeHeaderIconStyle(),
        icon: Icon(
          isSearchActive ? Icons.search_off : Icons.search,
          color: Colors.white,
          size: 26,
        ),
        onPressed: SoftTouch.wrap(onSearchTap),
        tooltip: isSearchActive ? 'Close Search' : 'Search',
      ));
    }
    if (showFilter) {
      actions.add(IconButton(
        style: SoftTouch.orangeHeaderIconStyle(),
        icon: Icon(
          Icons.tune,
          color: Colors.white,
          size: 26,
        ),
        onPressed: SoftTouch.wrap(onFilterTap),
        tooltip: 'Filter',
      ));
    }
    if (showUpgradeButton) {
      final user = context.watch<AuthService>().currentUser;
      final membership = user?.membership;
      final isPremiumActive = membership?.isPremium ?? false;
      final daysLeft = membership?.daysRemaining ?? 0;
      actions.add(Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ElevatedButton(
          onPressed: SoftTouch.wrap(
            () => NavHelper.push(context, Routes.premiumUpgrade),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPremiumActive ? AppTheme.sacredGreen : AppTheme.kumkumRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.28);
              }
              if (s.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.14);
              }
              return Colors.transparent;
            }),
          ),
          child: Text(
            isPremiumActive
                ? (daysLeft > 0 ? '$daysLeft d left' : 'Expires today')
                : 'Upgrade',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ));
    }
    if (showNotifications) {
      actions.add(NotificationBellButton(onPressed: onNotificationBellTap));
    }
    if (additionalActions != null) actions.addAll(additionalActions!);
    return actions;
  }
}

// ---------------------------------------------------------------------------
// AppScreenLayout
// ---------------------------------------------------------------------------
class AppScreenLayout extends StatelessWidget {
  final String title;
  final bool showLogo;
  final bool showNotifications;
  final bool showUpgradeButton;
  final List<Widget>? additionalActions;
  final VoidCallback? onRefresh;
  final IconData? bannerIcon;
  final String? bannerTitle;
  final String? bannerSubtitle;
  final Widget? bannerExtra;
  final Widget body;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  const AppScreenLayout({
    super.key,
    required this.title,
    required this.body,
    this.showLogo = false,
    this.showNotifications = false,
    this.showUpgradeButton = false,
    this.additionalActions,
    this.onRefresh,
    this.bannerIcon,
    this.bannerTitle,
    this.bannerSubtitle,
    this.bannerExtra,
    this.backgroundColor,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AC.bg(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppHeader(
        title: title,
        showLogo: showLogo,
        showNotifications: showNotifications,
        showUpgradeButton: showUpgradeButton,
        additionalActions: additionalActions,
        onRefresh: onRefresh,
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(children: [
        if (bannerTitle != null) _buildBanner(context),
        const SizedBox(height: 16),
        Expanded(child: body),
      ]),
    );
  }

  Widget _buildBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryOrange, AppTheme.primaryOrangeDark],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        if (bannerIcon != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(40)),
            child: Icon(bannerIcon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          if (bannerTitle != null)
            Text(bannerTitle!,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700)),
          if (bannerSubtitle != null) ...[
            const SizedBox(height: 4),
            Text(bannerSubtitle!,
                style: GoogleFonts.poppins(
                    color: Colors.white.withAlpha(200), fontSize: 13)),
          ],
          if (bannerExtra != null) ...[
            const SizedBox(height: 12),
            bannerExtra!,
          ],
        ])),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// SliverAppHeader
// ---------------------------------------------------------------------------
class SliverAppHeader extends StatelessWidget {
  final String title;
  final bool showLogo;
  final bool showNotifications;
  final bool showUpgradeButton;
  final bool showSearch;
  final VoidCallback? onSearchTap;
  final bool isSearchActive;
  final bool showFilter;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;
  final int activeFilterCount;
  final List<Widget>? additionalActions;
  final VoidCallback? onRefresh;
  final VoidCallback? onNotificationBellTap;

  static const double kToolbarHeight = AppHeader.kToolbarHeight;

  const SliverAppHeader({
    super.key,
    required this.title,
    this.showLogo = false,
    this.showNotifications = false,
    this.showUpgradeButton = false,
    this.showSearch = false,
    this.onSearchTap,
    this.isSearchActive = false,
    this.showFilter = false,
    this.onFilterTap,
    this.hasActiveFilters = false,
    this.activeFilterCount = 0,
    this.additionalActions,
    this.onRefresh,
    this.onNotificationBellTap,
  });

  @override
  Widget build(BuildContext context) {
    final barH = showLogo ? AppHeader.kToolbarHeightWithLogo : kToolbarHeight;
    return SliverAppBar(
      floating: false,
      pinned: true,
      snap: false,
      backgroundColor: AppTheme.primaryOrange,
      foregroundColor: Colors.white,
      elevation: 2,
      titleSpacing: 16,
      title: _buildTitle(context),
      actions: _buildActions(context),
      centerTitle: false,
      toolbarHeight: barH,
      iconTheme: const IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
    );
  }

  Widget _buildTitle(BuildContext context) {
    if (showLogo) {
      return _appHeaderLogoTitle(context, title);
    }
    return Text(title,
        style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 18));
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];
    if (onRefresh != null) {
      actions.add(IconButton(
        style: SoftTouch.orangeHeaderIconStyle(),
        icon: const Icon(Icons.refresh, color: Colors.white),
        onPressed: SoftTouch.wrap(onRefresh),
      ));
    }
    if (showFilter) {
      actions.add(
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              style: SoftTouch.orangeHeaderIconStyle(),
              icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 26),
              onPressed: SoftTouch.wrap(onFilterTap),
              tooltip: 'Filter',
            ),
            if (hasActiveFilters)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD700),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    activeFilterCount > 9 ? '9+' : '$activeFilterCount',
                    style: const TextStyle(
                      color: Color(0xFF7B3F00),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (showSearch) {
      actions.add(IconButton(
        style: isSearchActive
            ? SoftTouch.orangeHeaderIconStyle(
                merge: IconButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(40),
                  shape: const CircleBorder(),
                ),
              )
            : SoftTouch.orangeHeaderIconStyle(),
        icon: Icon(
          isSearchActive ? Icons.search_off : Icons.search,
          color: Colors.white,
          size: 26,
        ),
        onPressed: SoftTouch.wrap(onSearchTap),
        tooltip: isSearchActive ? 'Close Search' : 'Search',
      ));
    }
    if (showUpgradeButton) {
      actions.add(Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ElevatedButton(
          onPressed: SoftTouch.wrap(
            () => NavHelper.push(context, Routes.premiumUpgrade),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.kumkumRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.28);
              }
              if (s.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.14);
              }
              return Colors.transparent;
            }),
          ),
          child: const Text('Upgrade',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ));
    }
    if (showNotifications) {
      actions.add(NotificationBellButton(onPressed: onNotificationBellTap));
    }
    if (additionalActions != null) actions.addAll(additionalActions!);
    return actions;
  }
}
// ---------------------------------------------------------------------------
// NotificationBellButton — isolated StatefulWidget so loads are triggered
// safely in didChangeDependencies, never inside build().
// ---------------------------------------------------------------------------
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key, this.onPressed});

  /// Shell navigation (e.g. switch to Interests → Received). When null, pushes
  /// [Routes.interests] with the Received tab selected.
  final VoidCallback? onPressed;

  @override
  State<NotificationBellButton> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBellButton> {
  final ValueNotifier<int> _badgeRevision = ValueNotifier(0);
  late final Stream<int> _chatUnreadStream;
  bool _webListenersDeferred = false;
  String? _initialLoadScheduledForUserId;
  Timer? _badgeRefreshDebounce;
  Timer? _outgoingLoadDebounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _birthOwnerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _birthOwnerAuthSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _communityOwnerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _communityOwnerAuthSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _photoOwnerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _photoOwnerProfileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _birthRequesterSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _birthOwnerAllSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _communityRequesterSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _communityOwnerAllSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _photoRequesterSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _photoOwnerAllSub;
  String? _requestsListeningUserId;
  String? _privacyReconcileUserId;
  final Set<String> _birthOwnerPendingIds = <String>{};
  final Set<String> _birthOwnerAuthPendingIds = <String>{};
  final Set<String> _communityOwnerPendingIds = <String>{};
  final Set<String> _communityOwnerAuthPendingIds = <String>{};
  final Set<String> _photoOwnerPendingIds = <String>{};
  final Set<String> _photoOwnerProfilePendingIds = <String>{};
  final Map<String, Map<String, dynamic>> _birthOwnerPendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _birthOwnerAuthPendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _communityOwnerPendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _communityOwnerAuthPendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _photoOwnerPendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _photoOwnerProfilePendingRows =
      <String, Map<String, dynamic>>{};
  final Map<String, String> _privacyRequestStatuses = <String, String>{};
  List<Map<String, dynamic>> _outgoingPrivacyRows = <Map<String, dynamic>>[];
  String? _outgoingPrivacyLoadKey;

  Set<String> get _pendingIncomingPrivacyDocIds => {
        ..._birthOwnerPendingIds,
        ..._birthOwnerAuthPendingIds,
        ..._communityOwnerPendingIds,
        ..._communityOwnerAuthPendingIds,
        ..._photoOwnerPendingIds,
        ..._photoOwnerProfilePendingIds,
      };

  List<Map<String, dynamic>> get _mergedIncomingPendingRows =>
      <Map<String, dynamic>>[
        ..._birthOwnerPendingRows.values.map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'birth'),
        ),
        ..._birthOwnerAuthPendingRows.values.map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'birth'),
        ),
        ..._communityOwnerPendingRows.values.map(
          (r) =>
              InterestBadgeAggregator.tagPrivacyRequestKind(r, 'community'),
        ),
        ..._communityOwnerAuthPendingRows.values.map(
          (r) =>
              InterestBadgeAggregator.tagPrivacyRequestKind(r, 'community'),
        ),
        ..._photoOwnerPendingRows.values.map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'photo'),
        ),
        ..._photoOwnerProfilePendingRows.values.map(
          (r) => InterestBadgeAggregator.tagPrivacyRequestKind(r, 'photo'),
        ),
      ];

  void _mergePrivacyRequestStatuses(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool ownerRows,
    required String userId,
  }) {
    for (final d in snap.docs) {
      final data = d.data();
      final st = PrivacyRequestNotificationSync.normalizeStatus(data['status']);
      _privacyRequestStatuses[d.id] = st;
      if (ownerRows) {
        final ownerId = (data['owner_id'] as String? ?? '').trim();
        if (ownerId == userId && st == 'pending') {
          // pendingIncoming set maintained by pending-only listeners
        }
      }
    }
    _syncPrivacyNotificationsToService();
  }

  void _syncPrivacyNotificationsToService() {
    if (!mounted || _privacyReconcileUserId == null) return;
    context.read<NotificationService>().updatePrivacyRequestSnapshots(
          requestDocStatuses: Map<String, String>.from(_privacyRequestStatuses),
          pendingIncomingRequestDocIds: _pendingIncomingPrivacyDocIds,
        );
  }

  void _startRequestBadgeListeners(String userId, String profileId, String authUid) {
    final firebaseAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final listeningKey = '$userId|$profileId|$authUid|$firebaseAuthUid';
    if (_requestsListeningUserId == listeningKey) return;
    _stopRequestBadgeListeners();
    _requestsListeningUserId = listeningKey;
    _privacyReconcileUserId = userId;
    _privacyRequestStatuses.clear();
    final db = FirebaseFirestore.instance;

    void refresh() {
      if (!mounted) return;
      _badgeRefreshDebounce?.cancel();
      final debounceMs = kIsWeb ? 1200 : 400;
      _badgeRefreshDebounce = Timer(Duration(milliseconds: debounceMs), () {
        if (!mounted) return;
        _badgeRevision.value++;
        _syncPrivacyNotificationsToService();
      });
      _scheduleOutgoingPrivacyLoad(userId, profileId, authUid);
    }

    _scheduleOutgoingPrivacyLoad(userId, profileId, authUid);

    void replacePendingRows(
      Set<String> targetIds,
      Map<String, Map<String, dynamic>> targetRows,
      QuerySnapshot<Map<String, dynamic>> snap,
    ) {
      targetIds
        ..clear()
        ..addAll(snap.docs.map((d) => d.id));
      targetRows
        ..clear()
        ..addEntries(
          snap.docs.map(
            (d) => MapEntry(d.id, <String, dynamic>{'id': d.id, ...d.data()}),
          ),
        );
      refresh();
    }

    _birthOwnerSub = db
        .collection('birth_requests')
        .where('owner_id', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (s) => replacePendingRows(
            _birthOwnerPendingIds,
            _birthOwnerPendingRows,
            s,
          ),
          onError: (_) {},
        );

    if (authUid.isNotEmpty) {
      _birthOwnerAuthSub = db
          .collection('birth_requests')
          .where('owner_auth_uid', isEqualTo: authUid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen(
            (s) => replacePendingRows(
              _birthOwnerAuthPendingIds,
              _birthOwnerAuthPendingRows,
              s,
            ),
            onError: (_) {},
          );
    }

    _communityOwnerSub = db
        .collection('community_reference_requests')
        .where('owner_id', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (s) => replacePendingRows(
            _communityOwnerPendingIds,
            _communityOwnerPendingRows,
            s,
          ),
          onError: (_) {},
        );

    if (authUid.isNotEmpty) {
      _communityOwnerAuthSub = db
          .collection('community_reference_requests')
          .where('owner_auth_uid', isEqualTo: authUid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen(
            (s) => replacePendingRows(
              _communityOwnerAuthPendingIds,
              _communityOwnerAuthPendingRows,
              s,
            ),
            onError: (_) {},
          );
    }

    _photoOwnerSub = db
        .collection('photo_requests')
        .where('to_user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (s) => replacePendingRows(
            _photoOwnerPendingIds,
            _photoOwnerPendingRows,
            s,
          ),
          onError: (_) {},
        );

    if (profileId.isNotEmpty) {
      _photoOwnerProfileSub = db
          .collection('photo_requests')
          .where('to_profile_id', isEqualTo: profileId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen(
            (s) => replacePendingRows(
              _photoOwnerProfilePendingIds,
              _photoOwnerProfilePendingRows,
              s,
            ),
            onError: (_) {},
          );
    }

    _birthRequesterSub = db
        .collection('birth_requests')
        .where('requester_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: false, userId: userId),
          onError: (_) {},
        );

    _birthOwnerAllSub = db
        .collection('birth_requests')
        .where('owner_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: true, userId: userId),
          onError: (_) {},
        );

    _communityRequesterSub = db
        .collection('community_reference_requests')
        .where('requester_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: false, userId: userId),
          onError: (_) {},
        );

    _communityOwnerAllSub = db
        .collection('community_reference_requests')
        .where('owner_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: true, userId: userId),
          onError: (_) {},
        );

    _photoRequesterSub = db
        .collection('photo_requests')
        .where('from_user_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: false, userId: userId),
          onError: (_) {},
        );

    _photoOwnerAllSub = db
        .collection('photo_requests')
        .where('to_user_id', isEqualTo: userId)
        .snapshots()
        .listen(
          (s) => _mergePrivacyRequestStatuses(s, ownerRows: true, userId: userId),
          onError: (_) {},
        );
  }

  void _scheduleOutgoingPrivacyLoad(
    String userId,
    String profileId,
    String authUid,
  ) {
    _outgoingLoadDebounce?.cancel();
    _outgoingLoadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // ignore: discarded_futures
      _loadOutgoingPrivacyRows(userId, profileId, authUid);
    });
  }

  void _stopRequestBadgeListeners() {
    _birthOwnerSub?.cancel();
    _birthOwnerAuthSub?.cancel();
    _communityOwnerSub?.cancel();
    _communityOwnerAuthSub?.cancel();
    _photoOwnerSub?.cancel();
    _photoOwnerProfileSub?.cancel();
    _birthRequesterSub?.cancel();
    _birthOwnerAllSub?.cancel();
    _communityRequesterSub?.cancel();
    _communityOwnerAllSub?.cancel();
    _photoRequesterSub?.cancel();
    _photoOwnerAllSub?.cancel();
    _birthOwnerSub = null;
    _birthOwnerAuthSub = null;
    _communityOwnerSub = null;
    _communityOwnerAuthSub = null;
    _photoOwnerSub = null;
    _photoOwnerProfileSub = null;
    _birthRequesterSub = null;
    _birthOwnerAllSub = null;
    _communityRequesterSub = null;
    _communityOwnerAllSub = null;
    _photoRequesterSub = null;
    _photoOwnerAllSub = null;
    _requestsListeningUserId = null;
    _privacyReconcileUserId = null;
    _birthOwnerPendingIds.clear();
    _birthOwnerAuthPendingIds.clear();
    _communityOwnerPendingIds.clear();
    _communityOwnerAuthPendingIds.clear();
    _photoOwnerPendingIds.clear();
    _photoOwnerProfilePendingIds.clear();
    _birthOwnerPendingRows.clear();
    _birthOwnerAuthPendingRows.clear();
    _communityOwnerPendingRows.clear();
    _communityOwnerAuthPendingRows.clear();
    _photoOwnerPendingRows.clear();
    _photoOwnerProfilePendingRows.clear();
    _privacyRequestStatuses.clear();
    _outgoingPrivacyRows = <Map<String, dynamic>>[];
    _outgoingPrivacyLoadKey = null;
  }

  Future<void> _loadOutgoingPrivacyRows(
    String userId,
    String profileId,
    String authUid,
  ) async {
    final firebaseAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final key = '$userId|$profileId|$authUid|$firebaseAuthUid';
    _outgoingPrivacyLoadKey = key;
    final aliases = InterestBadgeAggregator.resolveSentRequestQueryAliasIds(
      canonicalUserDocId: userId,
      firebaseAuthUid: firebaseAuthUid,
      identityAuthUid: authUid,
    );
    try {
      final data = await SentAccessRequestsLoader.loadAll(
        requesterAliasIds: aliases,
      );
      if (!mounted || _outgoingPrivacyLoadKey != key) return;
      setState(() {
        _outgoingPrivacyRows = <Map<String, dynamic>>[
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
      });
    } catch (e) {
      debugPrint('NotificationBell: outgoing privacy load failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _chatUnreadStream = ChatService().watchUnreadIncomingChatCount();
    AccessRequestBroadcast.tick.addListener(_onAccessRequestBroadcast);
  }

  void _onAccessRequestBroadcast() {
    final userId = _privacyReconcileUserId;
    if (userId == null || userId.isEmpty || !mounted) return;
    final auth = context.read<AuthService>().currentUser;
    _outgoingPrivacyLoadKey = null;
    SentAccessRequestsLoader.invalidateCache();
    // ignore: discarded_futures
    context.read<NotificationService>().refreshPrivacyRequestReconcile(
          userId,
          profileId: auth?.profileId ?? '',
          authUid: auth?.authUid ?? '',
        );
    // ignore: discarded_futures
    _loadOutgoingPrivacyRows(
      userId,
      auth?.profileId ?? '',
      auth?.authUid ?? '',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AuthService>().currentUser?.id ??
        context.read<AuthController>().currentUser?.id ??
        '';
    final profileId = context.read<AuthService>().currentUser?.profileId ??
        context.read<AuthController>().currentUser?.profileId ??
        '';
    final authUid = context.read<AuthService>().currentUser?.authUid ??
        context.read<AuthController>().currentUser?.authUid ??
        '';
    if (userId.isEmpty) return;
    final ns = context.read<NotificationService>();
    final ms = context.read<MessageService>();
    ns.startListening(userId);
    // Keep message badge live (photo requests + inbox signals).
    // Previously only one-shot load was triggered, so badge could stay stale.
    // ignore: discarded_futures
    ms.startListening(userId);
    void bindBadgeListeners() {
      _startRequestBadgeListeners(userId, profileId, authUid);
    }
    if (kIsWeb) {
      if (!_webListenersDeferred) {
        _webListenersDeferred = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (!mounted) return;
            bindBadgeListeners();
          });
        });
      }
    } else {
      bindBadgeListeners();
    }
    if (_initialLoadScheduledForUserId != userId) {
      _initialLoadScheduledForUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!ns.hasFetchedForUser(userId) && !ns.isLoading) {
          // ignore: discarded_futures
          ns.loadNotifications(userId);
        }
        if (!ms.isDataLoadedForUser(userId) && !ms.isLoading) {
          // ignore: discarded_futures
          ms.loadMessages(userId);
        }
        final interestService = context.read<InterestService>();
        final notificationService = context.read<NotificationService>();
        // Always bind live Firestore listeners — not only when cache is empty.
        // ignore: discarded_futures
        interestService.ensureHubLiveSync(userId).then((_) {
          if (!mounted) return;
          final hasInterests = interestService.interestsReceived.isNotEmpty ||
              interestService.interestsSent.isNotEmpty;
          if (!hasInterests) {
            // ignore: discarded_futures
            interestService.loadInterests(userId).then((_) {
              if (!mounted) return;
              notificationService.reconcileInterestReceivedNotifications(
                interestService.interestsReceived,
              );
            });
          } else {
            notificationService.reconcileInterestReceivedNotifications(
              interestService.interestsReceived,
            );
          }
        });
      });
    }
  }

  @override
  void dispose() {
    AccessRequestBroadcast.tick.removeListener(_onAccessRequestBroadcast);
    _badgeRefreshDebounce?.cancel();
    _outgoingLoadDebounce?.cancel();
    _badgeRevision.dispose();
    _stopRequestBadgeListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.watch<NotificationService>();
    final ms = context.watch<MessageService>();
    final interestSvc = context.watch<InterestService>();
    final received =
        interestSvc.interestsReceived.cast<Map<String, dynamic>>();
    final sent = interestSvc.interestsSent.cast<Map<String, dynamic>>();
    final userId = context.read<AuthService>().currentUser?.id ??
        context.read<AuthController>().currentUser?.id ??
        '';
    final incomingPrivacyRows = _mergedIncomingPendingRows;
    return StreamBuilder<int>(
      stream: _chatUnreadStream,
      initialData: 0,
      builder: (context, unreadChatSnap) {
        final unreadChatCount = unreadChatSnap.data ?? 0;
        return ValueListenableBuilder<int>(
      valueListenable: _badgeRevision,
      builder: (context, _, __) {
        final profileViewUnreadCount = ns.notifications
            .where((n) {
              final isUnread =
                  (n['is_read'] as bool?) != true && (n['isRead'] as bool?) != true;
              if (!isUnread) return false;
              final type = (n['type'] as String? ?? '')
                  .trim()
                  .toLowerCase()
                  .replaceAll('-', '_');
              return type == 'profile_view';
            })
            .length;
        final totalBadge = InterestBadgeAggregator.interestsOverviewBadgeCount(
          interestsReceived: received,
          interestsSent: sent,
          incomingPrivacyRequestRows: incomingPrivacyRows,
          outgoingPrivacyRequestRows: _outgoingPrivacyRows,
        ) + profileViewUnreadCount + unreadChatCount;
        return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          style: SoftTouch.orangeHeaderIconStyle(),
          icon: const Icon(Icons.notifications_outlined,
              color: Colors.white, size: 26),
          tooltip:
              'Alerts: other notifications, new interests, messages, and privacy requests',
          onPressed: () {
            SoftTouch.impact();
            final notificationService =
                context.read<NotificationService>();
            final messageService = context.read<MessageService>();
            final interestService = context.read<InterestService>();
            final uid = context.read<AuthService>().currentUser?.id ??
                context.read<AuthController>().currentUser?.id ??
                '';
            if (context.mounted) {
              if (widget.onPressed != null) {
                widget.onPressed!();
              } else {
                NavHelper.push(
                  context,
                  Routes.interests,
                  args: {'initialTabIndex': 1},
                );
              }
            }
            if (uid.isEmpty) return;
            // Refresh in background so navigation feels instant, but avoid
            // heavy force-reload churn on every bell tap.
            if (!notificationService.isLoading) {
              unawaited(notificationService.loadNotifications(uid));
            }
            if (!messageService.isLoading) {
              unawaited(messageService.loadMessages(uid));
            }
            unawaited(
              interestService.loadInterests(uid).then((_) {
                notificationService.reconcileInterestReceivedNotifications(
                  interestService.interestsReceived,
                );
              }),
            );
            final auth = context.read<AuthService>().currentUser;
            unawaited(
              notificationService.refreshPrivacyRequestReconcile(
                uid,
                profileId: auth?.profileId ?? '',
                authUid: auth?.authUid ?? '',
              ),
            );
          },
        ),
        if (totalBadge > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: AppTheme.kumkumRed, shape: BoxShape.circle),
              child: Text(
                totalBadge > 99 ? '99+' : '$totalBadge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
      },
        );
      },
    );
  }
}
