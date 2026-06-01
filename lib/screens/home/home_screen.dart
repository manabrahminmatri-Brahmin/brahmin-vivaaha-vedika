import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../core/app_router.dart';
import '../../core/profile_completion_policy.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../legacy/compatibility.dart' hide AuthService;
import '../../services/block_service.dart';
import '../../services/membership_reminder_service.dart';
import '../../services/subscription_alert_service.dart';
import '../../services/network_service.dart';
import '../../services/offline_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_transitions.dart';
import '../../widgets/profile_completeness_ring.dart';
import '../matches/matches_screen.dart';
import '../matches/profile_detail_screen.dart';
import '../profile/my_profile_screen.dart';
import '../settings/settings_screen.dart';
import '../interests/interests_analytics_screen.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_header.dart';
import '../../widgets/soft_touch.dart';
import '../../widgets/home_spotlight_carousel.dart';
import '../../widgets/profile_discovery_card.dart';
import '../../utils/app_animations.dart';
import '../../utils/profile_display_shuffle.dart';
import '../../theme/app_sizes.dart';

/// Main home screen with bottom navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// LIVE STATUS FIX: HomeScreen now observes app lifecycle transitions.
class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  late final List<bool> _visitedTabs;
  final GlobalKey<MatchesScreenState> _matchesKey =
      GlobalKey<MatchesScreenState>();

  // FIX 17: Static const list — not rebuilt on every render.
  static const _navItems = [
    {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'Home'},
    {
      'icon': Icons.people_outline,
      'activeIcon': Icons.people,
      'label': 'Matches',
    },
    {
      'icon': Icons.favorite_border,
      'activeIcon': Icons.favorite,
      'label': 'Interests',
    },
    {
      'icon': Icons.settings_outlined,
      'activeIcon': Icons.settings,
      'label': 'Settings',
    },
    {'icon': Icons.person_outline, 'activeIcon': Icons.person, 'label': 'You'},
  ];

  // FIX 6: throttle home-tab refreshes so we don't hammer Firestore on every
  // tab-switch back. A refresh is allowed at most once every 60 seconds.
  DateTime? _lastHomeRefresh;

  // 🔥 FIX: Listen for connectivity restoration to reload profiles
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _navItems.length, vsync: this);
    _visitedTabs = List<bool>.filled(_navItems.length, false);
    _visitedTabs[0] = true;
    _tabController.addListener(() {
      final nextIndex = _tabController.index;
      if (_selectedIndex != nextIndex) {
        setState(() {
          _selectedIndex = nextIndex;
          _visitedTabs[nextIndex] = true;
        });
        if (nextIndex == 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final state = _interestsKey.currentState;
            if (state != null) {
              (state as dynamic).refresh();
            }
          });
        }
      }
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final now = DateTime.now();
            final last = _lastHomeRefresh;
            // Throttle: new profiles arrive slowly — avoid re-querying on every tab return.
            if (last == null || now.difference(last).inSeconds >= 900) {
              _lastHomeRefresh = now;
              _homeTabKey.currentState?._refreshFutures();
            }
          });
        }
      }
    });

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prewarmTabsAfterFirstPaint();
    });

    // 🔥 FIX: Listen for connectivity restoration to reload profiles
    _connectivitySub = NetworkService.connectionStream.listen((isOnline) {
      if (!isOnline) {
        _wasOffline = true;
        debugPrint('📱 HomeScreen: Detected offline state');
      } else if (_wasOffline && isOnline) {
        // Connection restored - reload profiles
        debugPrint('📱 HomeScreen: Connection restored - reloading profiles');
        _wasOffline = false;
        _refreshAllData();
      }
    });
  }

  void _prewarmTabsAfterFirstPaint() {
    if (kIsWeb) {
      // Single frame: avoid staggered setState + background Interests spinners while
      // on other tabs (reduces web engine "disposed EngineFlutterView" assert spam).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _visitedTabs[1] = true; // Matches
          _visitedTabs[3] = true; // Settings
          _visitedTabs[4] = true; // Profile
          // Interests (2): mount when user opens that tab — heavy Firestore hub.
        });
      });
      return;
    }
    const schedule = <int, Duration>{
      1: Duration(milliseconds: 350),
      2: Duration(milliseconds: 750),
      3: Duration(milliseconds: 1150),
      4: Duration(milliseconds: 1500),
    };
    for (final entry in schedule.entries) {
      Future<void>.delayed(entry.value, () {
        if (!mounted || _visitedTabs[entry.key]) return;
        setState(() => _visitedTabs[entry.key] = true);
      });
    }
  }

  /// 🔥 Refresh all data when connection is restored
  void _refreshAllData() {
    // Refresh home tab data
    _homeTabKey.currentState?._refreshFutures();
    // Refresh matches
    _matchesKey.currentState?.refreshProfiles();
    debugPrint('✅ HomeScreen: All data refreshed after connection restored');
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _tabController.index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lastHomeRefresh = DateTime.now();
        _homeTabKey.currentState?._refreshFutures();
      });
    }
  }

  final GlobalKey<State> _interestsKey = GlobalKey<State>();
  final GlobalKey<_HomeTabState> _homeTabKey = GlobalKey<_HomeTabState>();

  /// Bell on Home → Interests hub, Received tab (pending interests + requests).
  void _openInterestsReceivedFromBell() {
    if (!_visitedTabs[2]) {
      setState(() => _visitedTabs[2] = true);
    }
    if (_selectedIndex != 2) {
      _tabController.animateTo(2);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _interestsKey.currentState;
      if (state != null) {
        (state as dynamic).openHubTab(1);
      }
    });
  }

  void _onDestinationSelected(int index) {
    if (_tabController.index == index) {
      if (index == 2) {
        final state = _interestsKey.currentState;
        if (state != null) {
          (state as dynamic).refresh();
        }
      }
      return;
    }
    _tabController.animateTo(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  Widget _buildLazyTab(int index) {
    if (!_visitedTabs[index]) return const SizedBox.shrink();

    return switch (index) {
      0 => HomeTab(
            key: _homeTabKey,
            matchesKey: _matchesKey,
            onNotificationBellTap: _openInterestsReceivedFromBell,
          ),
      1 => MatchesScreen(key: _matchesKey, embeddedInMainShell: true),
      2 => InterestsAnalyticsScreen(
            key: _interestsKey,
            embeddedInMainShell: true,
          ),
      3 => const SettingsScreen(),
      4 => const MyProfileScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AC.bg(context),
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(_navItems.length, _buildLazyTab),
      ),
      bottomNavigationBar: _LiquidGlassNavBar(
        items: _navItems,
        selectedIndex: _selectedIndex,
        onTap: _onDestinationSelected,
      ),
    );
  }
}

/// Home Tab Content
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.matchesKey,
    this.onNotificationBellTap,
  });

  final GlobalKey<MatchesScreenState> matchesKey;
  final VoidCallback? onNotificationBellTap;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late Future<List<User>> _matchFuture;
  Future<List<User>>? _recentFuture;
  late TabController _homeTabController;
  int _homeSelectedIndex = 0;
  bool _recentTabVisited = false;
  late FilterService _filterService; // 🔥 Store reference for safe dispose()
  // _homePageController removed — FIX 3: TabBarView now driven by TabController directly.

  /// Rebuild home tab shell only when user-visible auth fields change (not every notify).
  static String _homeAuthVisualKey(User? u) {
    if (u == null) return 'n';
    final p = u.profile;
    return '${u.id}|${u.profileId}|${u.membership.isPremium}|'
        '${p?.fullName}|${p?.firstName}|${p?.age}|'
        '${p?.computedCompletionPercentage}|${p?.profilePicture}';
  }

  void _refreshFutures() {
    final authService = context.read<AuthService>();
    debugPrint('🏠 HomeTab: Refreshing futures...');
    setState(() {
      _matchFuture = _getProfilesWithOfflineSupport(authService);
      if (_recentTabVisited) {
        _recentFuture = authService.getRecentlyAddedProfiles(limit: 10);
      }
    });
    debugPrint('🏠 HomeTab: Futures refreshed');
  }

  void _ensureRecentFuture(AuthService authService) {
    _recentTabVisited = true;
    // Always refresh when entering Recently Added so newly registered users
    // appear immediately for other members.
    _recentFuture = authService.getRecentlyAddedProfiles(limit: 10);
  }

  /// Keeps loading / empty states visible inside the home sliver (not a zero-height gap).
  Widget _homeFeedLoadingShell(BuildContext context, String message) {
    final minH = (MediaQuery.sizeOf(context).height * 0.32).clamp(220.0, 480.0);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minH),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryOrange),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: AC.textSub(context),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom inset so scroll content and FABs clear the floating glass nav (extendBody).
  double _homeBottomSafeAboveNav(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).bottom;
    return pad +
        AppSizes.bottomNavMarginTop +
        AppSizes.bottomNavHeight +
        AppSizes.bottomNavMarginBottom +
        8;
  }

  void _onTapDiscover3d(BuildContext context) {
    SoftTouch.impact();
    final isPremium =
        context.read<AuthService>().currentUser?.membership.isPremium ?? false;
    if (!isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('3D Discover is a Premium feature.'),
          backgroundColor: AppTheme.primaryOrange,
        ),
      );
      NavHelper.push(context, Routes.premiumUpgrade);
      return;
    }
    NavHelper.push(context, Routes.discoverCarousel);
  }

  void _onTapPremiumUpgrade(BuildContext context) {
    SoftTouch.impact();
    NavHelper.push(context, Routes.premiumUpgrade);
  }

  /// Fixed-position actions (do not scroll with the feed); strong touch targets.
  Widget _buildHomeFloatingActions(BuildContext context, User? user) {
    if (user == null) return const SizedBox.shrink();
    final bottom = _homeBottomSafeAboveNav(context);
    final isPremium = user.membership.isPremium;
    final daysLeft = user.membership.daysRemaining;
    final showExtendPlan =
        isPremium && daysLeft > 0 && daysLeft <= 7;
    final showUpgrade = !isPremium;
    return Positioned(
      right: 12,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Tooltip(
            message: 'Discover 3D',
            child: Material(
              elevation: 6,
              shadowColor: Colors.black38,
              color: Colors.white,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                splashColor: AppTheme.primaryOrange.withValues(alpha: 0.22),
                highlightColor: AppTheme.primaryOrange.withValues(alpha: 0.08),
                onTap: () => _onTapDiscover3d(context),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(
                    Icons.auto_awesome,
                    color: AppTheme.primaryOrange,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          if (showExtendPlan || showUpgrade) ...[
            const SizedBox(height: 12),
            Tooltip(
              message: showExtendPlan
                  ? 'Extend plan ($daysLeft day${daysLeft == 1 ? '' : 's'} left)'
                  : 'Upgrade to Premium',
              child: Material(
                elevation: 8,
                shadowColor: Colors.black45,
                color: showExtendPlan ? AppTheme.primaryGold : AppTheme.kumkumRed,
                borderRadius: BorderRadius.circular(30),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  splashColor: Colors.white.withValues(alpha: 0.35),
                  highlightColor: Colors.white.withValues(alpha: 0.14),
                  onTap: () => _onTapPremiumUpgrade(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 56,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Center(
                        child: Text(
                          showExtendPlan ? 'Extend\nPlan' : 'Upgrade',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final authService = context.read<AuthService>();
    _matchFuture = _getProfilesWithOfflineSupport(authService);

    _homeTabController = TabController(length: 2, vsync: this);
    // FIX 3 & 7: Removed PageController. TabBarView is now driven directly by
    // _homeTabController. This eliminates the horizontal scroll conflict with
    // the outer CustomScrollView AND the double-animation fight where
    // addListener and onPageChanged both tried to animate simultaneously.
    _homeTabController.addListener(() {
      final nextIndex = _homeTabController.index;
      if (!mounted || _homeSelectedIndex == nextIndex) return;
      setState(() {
        _homeSelectedIndex = nextIndex;
        if (nextIndex == 1) {
          _ensureRecentFuture(context.read<AuthService>());
        }
      });
    });

    // 🔥 Listen to filter changes and auto-refresh matches
    // This ensures filters applied from Matches screen or Settings screen
    // immediately update the home screen matches
    _filterService = context.read<FilterService>();
    _filterService.addListener(_onFiltersChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkMembershipReminders();
      _checkSubscriptionExpiry();
      _loadNotifications();
      _checkProfileCompletion();
    });
  }

  Future<void> _checkProfileCompletion() async {
    final authService = context.read<AuthService>();
    final prefs = await SharedPreferences.getInstance();
    final shownThisSession = prefs.getBool('profile_nudge_shown') ?? false;
    if (shownThisSession) return;

    final profile = authService.currentUser?.profile;
    if (profile == null) return;

    final completion = profile.computedCompletionPercentage;
    if (completion >= 80) return;

    await prefs.setBool('profile_nudge_shown', true);
    if (!mounted) return;

    final missingFields = profile.getMissingFields();
    final firstIncompleteStep = profile.firstIncompleteStep;
    final stepName = _getStepName(firstIncompleteStep);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person_add_alt_1, color: AC.textSub(context)),
            const SizedBox(width: 8),
            const Text('Complete Your Profile'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your profile is $completion% complete. Profiles with more '
              'details get 3x more matches!',
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: completion / 100,
                minHeight: 10,
                backgroundColor: AC.surface2(context),
                valueColor: const AlwaysStoppedAnimation(
                  AppTheme.primaryOrange,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$completion% filled — ${100 - completion}% remaining',
              style: TextStyle(fontSize: 12, color: AC.textMuted(context)),
            ),
            if (missingFields.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.primaryOrange.withAlpha(30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next step: $stepName',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryOrange,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Missing: ${missingFields.take(3).join(', ')}${missingFields.length > 3 ? '...' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AC.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context)
                  .pushNamed(
                    '/profile-wizard',
                    arguments: {
                      'isEditMode': false,
                      'initialStep': firstIncompleteStep >= 0
                          ? firstIncompleteStep
                          : 0,
                    },
                  )
                  .then((_) {
                    if (mounted) {
                      authService.refreshUserData();
                    }
                  });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Complete $stepName'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotifications() async {
    final authService = context.read<AuthService>();
    final notificationService = context.read<NotificationService>();
    final userId = authService.currentUser?.id;
    if (userId != null) {
      await notificationService.loadNotifications(userId);
      await notificationService.refreshUnreadCount(userId);
    }
  }

  Future<void> _checkMembershipReminders() async {
    if (!mounted) return; // 🔥 FIX: guard before context use
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    await MembershipReminderService.checkAndShowReminders(context, user);
    // MembershipReminderService must also guard context.mounted before use
  }

  Future<void> _checkSubscriptionExpiry() async {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    if (user?.membership.isPremium == true) {
      final shouldShowAlert =
          await SubscriptionAlertService.shouldShowExpiryAlert(
            user!.membership,
          );
      if (shouldShowAlert && mounted) {
        SubscriptionAlertService.showExpiryAlert(context, user.membership);
      }
    }
  }

  /// 🔥 Auto-refresh when filters change (from any screen)
  void _onFiltersChanged() {
    debugPrint('🏠 HomeTab: Filters changed, refreshing matches...');
    // 🔥 FIX: Wrap setState in addPostFrameCallback to prevent "setState() called during build" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshFutures();
      }
    });
  }

  @override
  void dispose() {
    // 🔥 CRITICAL FIX: Use stored reference, NOT context.read()
    // context is invalid during dispose() - accessing it causes Flutter errors
    _filterService.removeListener(_onFiltersChanged);

    _homeTabController.dispose();
    // _homePageController removed (FIX 3 — PageView replaced by TabBarView)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AuthService, String>(
      selector: (_, auth) => _homeAuthVisualKey(auth.currentUser),
      builder: (context, _, __) {
        final authService = context.read<AuthService>();
        final user = authService.currentUser;
        final profile = user?.profile;

        return Scaffold(
          backgroundColor: AC.bg(context),
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(color: AC.card(context)),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                // Header — no action row so the title stays fully readable.
                SliverAppHeader(
                  title: 'mana Vivaaha Vedika',
                  showLogo: true,
                  showUpgradeButton: false,
                  showNotifications: true,
                  onNotificationBellTap: widget.onNotificationBellTap,
                ),

                // User Info Section
                SliverToBoxAdapter(
                  child: (user != null && profile != null)
                      ? _buildUserInfoSection(
                          context,
                          user,
                          profile,
                        ).appSlideIn(
                          baseDelay: const Duration(milliseconds: 800),
                        )
                      : const SizedBox.shrink(),
                ),

                // Profile Completeness Ring
                SliverToBoxAdapter(
                  child: Selector<AuthService, UserProfile?>(
                    selector: (_, a) => a.currentUser?.profile,
                    builder: (context, p, __) {
                      if (p == null) return const SizedBox.shrink();
                      if (p.computedCompletionPercentage >= 100 ||
                          p.getMissingFields().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return ProfileCompletenessRing(profile: p).appSlideIn(
                        baseDelay: const Duration(milliseconds: 950),
                      );
                    },
                  ),
                ),

                // Tabbed section: Today's Matches / Recently Added
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildGlobalFilterBanner(context),
                      const SizedBox(height: 8),
                      TabBar(
                        controller: _homeTabController,
                        indicatorColor: AppTheme.primaryOrange,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                        labelColor: AC.text(context),
                        unselectedLabelColor: AC.textSub(context),
                        labelStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: AC.text(context),
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AC.textSub(context),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tabs: const [
                          Tab(text: "Today's Matches"),
                          Tab(text: 'Recently Added'),
                        ],
                      ), // FIX 5: Removed .animate().fadeIn() — was blocking tab taps for 300ms
                      const SizedBox(height: 16),
                      // Intrinsic-height tab bodies (no fixed viewport) so the last card can
                      // scroll fully above the bottom nav. Horizontal insets match Matches;
                      // FABs sit in a Stack on top (same card width as Matches).
                      // Bottom clearance is only on each tab ListView — do not repeat nav
                      // inset here or the feed gains a large empty overscroll band.
                      IndexedStack(
                        index: _homeSelectedIndex,
                        children: [
                          _buildTodayMatchesPage(
                            context,
                            authService,
                            profile,
                          ),
                          _recentTabVisited
                              ? _buildRecentlyAddedPage(context, authService)
                              : const SizedBox.shrink(),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                    ],
                  ),
                ),
              ),
              _buildHomeFloatingActions(context, user),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserInfoSection(
    BuildContext context,
    User user,
    UserProfile profile,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGold.withAlpha(30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppTheme.primaryGold.withAlpha(50), width: 1),
      ),
      child: Row(
        children: [
          // User Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AC.border(context), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                profile.firstName.isNotEmpty
                    ? profile.firstName[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AC.text(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AC.textSub(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AC.textSub(context).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ID: ${user.profileId.isNotEmpty ? user.profileId : 'Loading...'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGold.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${profile.age} yrs',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryGold,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Profile completion indicator
                if (!profile.isFunctionallyComplete)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context)
                          .pushNamed(
                            '/profile-wizard',
                            arguments: {
                              'isEditMode': false,
                              'initialStep': profile.firstIncompleteStep >= 0
                                  ? profile.firstIncompleteStep
                                  : 0,
                            },
                          )
                          .then((_) {
                            if (context.mounted) {
                              context.read<AuthService>().refreshUserData();
                            }
                          });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange.withAlpha(10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryOrange.withAlpha(30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: AppTheme.primaryOrange,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Profile ${profile.computedCompletionPercentage}% complete',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryOrange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Tap to complete ${_getStepName(profile.firstIncompleteStep)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AC.textSub(context),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: AppTheme.primaryOrange,
                                size: 12,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Membership badge - compact and right-aligned
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: user.membership.isPremium
                  ? AppTheme.primaryGold.withAlpha(20)
                  : AC.surface(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: user.membership.isPremium
                    ? AppTheme.primaryGold
                    : AppTheme.primaryOrange,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user.membership.isPremium ? Icons.star : Icons.person_outline,
                  color: user.membership.isPremium
                      ? AppTheme.primaryGold
                      : AppTheme.primaryOrange,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  user.membership.isPremium ? 'Premium' : 'Free User',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: user.membership.isPremium
                        ? AppTheme.primaryGold
                        : AppTheme.primaryOrange,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStepName(int step) {
    const stepNames = [
      'Basic Info',
      'Birth Details',
      'Religious Details',
      'Education & Career',
      'Family Details',
      'Lifestyle & About',
    ];
    return step >= 0 && step < stepNames.length ? stepNames[step] : 'Profile';
  }

  Widget _buildGlobalFilterBanner(BuildContext context) {
    return Selector<FilterService, String>(
      selector: (_, f) => '${f.hasFilters}|${f.activeFilterCount}',
      builder: (context, _, __) {
        final filterService = context.read<FilterService>();
        if (!filterService.hasFilters) return const SizedBox.shrink();
        final count = filterService.activeFilterCount;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withAlpha(18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.filter_alt,
                color: AppTheme.textMedium,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count active filter${count == 1 ? '' : 's'} applied across all screens',
                  style: const TextStyle(
                    color: AppTheme.primaryOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => filterService.clearFilters(),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.kumkumRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTodayMatchesPage(
    BuildContext context,
    AuthService authService,
    UserProfile? profile,
  ) {
    final user = authService.currentUser;
    if (user == null) {
      return SizedBox(
        height: 360,
        child: _buildTabEmptyState(
          context,
          icon: Icons.people_outline,
          message: 'Sign in to see matches',
        ),
      );
    }

    final blockedIds = context.read<BlockService>().allBlockedPeerIds;
    final filterService = context.read<FilterService>();

    final listPad = ProfileDiscoveryCard.listPadding(
      bottom: _homeBottomSafeAboveNav(context) + 100,
    );

    return FutureBuilder<List<User>>(
      future: _matchFuture,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _homeFeedLoadingShell(context, 'Loading matches…');
        }
        if (snapshot.hasError) {
          // FIX 10: Removed escaped \$ — was showing literal text instead of value.
          return SizedBox(
            height: 360,
            child: _buildTabEmptyState(
              context,
              icon: Icons.error_outline,
              message: 'Error loading profiles: ${snapshot.error}',
            ),
          );
        }

        final matches = (snapshot.data ?? []).where((u) {
          if (blockedIds.contains(u.profileId) || blockedIds.contains(u.id)) {
            return false;
          }
          if (!ProfileCompletionPolicy.isEligibleForDiscovery(u)) return false;
          if (!filterService.hasFilters) return true;
          final p = u.profileForDiscovery;
          final f = filterService.current;
          if (f == null) return true; // 🔥 FIX: Guard against null
          bool m(String? pv, String? fv) {
            if (fv == null || fv.isEmpty || fv.toLowerCase() == 'any') {
              return true;
            }
            if (pv == null || pv.isEmpty) return false;
            return pv.toLowerCase().contains(fv.toLowerCase());
          }

          final age = p.age;
          if (f.minAge != null && age < f.minAge!) return false;
          if (f.maxAge != null && age > f.maxAge!) return false;
          if (!m(p.sect, f.sect)) return false;
          if (!m(p.subSect, f.subSect)) return false;
          if (!m(p.nakshatra ?? p.simpleNakshatra, f.nakshatra)) {
            return false;
          }
          if (!m(p.country, f.country)) return false;
          if (!m(p.state, f.state)) return false;
          if (!m(p.city, f.city)) return false;
          if (!m(p.maritalStatus, f.maritalStatus)) return false;
          if (!m(p.education, f.education)) return false;
          if (!m(p.occupation, f.occupation)) return false;
          if (!m(p.incomeRange, f.incomeRange)) return false;
          if (!m(p.foodHabit, f.foodHabit)) return false;
          return true;
        }).toList();

        final matchesOrdered = shuffleUsersForDiscovery(
          matches,
          viewerUserId: user.id,
          salt: 'home_today_matches',
        );

        if (matchesOrdered.isEmpty) {
          return SizedBox(
            height: 360,
            child: _buildTabEmptyState(
              context,
              icon: Icons.people_outline,
              message: NetworkService.isConnected
                  ? 'No matches found for your preferences'
                  : 'You are offline. Connect to the internet to see more profiles.',
              onRetry: _refreshFutures,
            ),
          );
        }

        final shown = matchesOrdered.take(5).toList();
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: listPad,
          children: [
            HomeSpotlightCarousel(matches: matchesOrdered),
            ...shown.map(
              (match) => ProfileDiscoveryCard(
                user: match,
                compactPresence: true,
                onTap: () => Navigator.push(
                  context,
                  AppTransitions.slide(ProfileDetailScreen(user: match)),
                ),
              ),
            ),
            if (matchesOrdered.length > 5) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // FIX 14: Animate parent _HomeScreenState tab bar via
                  // findAncestorStateOfType + TabController.animateTo.
                  // FIX 11: Removed escaped \$ — was showing literal text.
                  onPressed: () {
                    final homeState =
                        context.findAncestorStateOfType<_HomeScreenState>();
                    homeState?._tabController.animateTo(1);
                  },
                  icon: const Icon(Icons.people),
                  label: Text('View All ${matchesOrdered.length} Matches'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecentlyAddedPage(
    BuildContext context,
    AuthService authService,
  ) {
    final user = authService.currentUser;
    if (user == null) {
      return SizedBox(
        height: 360,
        child: _buildTabEmptyState(
          context,
          icon: Icons.person_search_outlined,
          message: 'Sign in to see recently added profiles',
        ),
      );
    }

    // FIX 15: Removed dead Builder(builder: (outerCtx) { return SizedBox.shrink(); })
    final recentBlockedIds = context.read<BlockService>().allBlockedPeerIds;
    final recentFuture = _recentFuture;
    if (recentFuture == null) {
      return _homeFeedLoadingShell(context, 'Loading recent profiles…');
    }

    final listPad = ProfileDiscoveryCard.listPadding(
      bottom: _homeBottomSafeAboveNav(context) + 100,
    );

    return FutureBuilder<List<User>>(
      future: recentFuture,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _homeFeedLoadingShell(context, 'Loading recent profiles…');
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 360,
            child: _buildTabEmptyState(
              context,
              icon: Icons.error_outline,
              message: 'Error loading recent profiles',
              onRetry: _refreshFutures,
            ),
          );
        }

        final recentUsers = (snapshot.data ?? [])
            .where(
              (u) =>
                  !recentBlockedIds.contains(u.profileId) &&
                      !recentBlockedIds.contains(u.id),
            )
            .toList();

        if (recentUsers.isEmpty) {
          return SizedBox(
            height: 360,
            child: _buildTabEmptyState(
              context,
              icon: Icons.person_search_outlined,
              message: 'No recently added profiles found',
              subtitle: 'Check back later for new profiles',
              onRetry: _refreshFutures,
            ),
          );
        }

        // Keep strict recency order from backend (newest registration first).
        final recentDisplay = recentUsers;

        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: listPad,
          children: [
            ...recentDisplay.map(
              (u) => ProfileDiscoveryCard(
                user: u,
                compactPresence: true,
                onTap: () => Navigator.push(
                  context,
                  AppTransitions.slide(ProfileDetailScreen(user: u)),
                ),
                showNewBadge: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabEmptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
    String? subtitle,
    VoidCallback? onRetry,
  }) {
    final bool isNetworkError =
        message.toLowerCase().contains('offline') ||
        message.toLowerCase().contains('internet') ||
        message.toLowerCase().contains('connection');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isNetworkError ? 120 : 80,
              height: isNetworkError ? 120 : 80,
              decoration: BoxDecoration(
                color: isNetworkError
                    ? AppTheme.kumkumRed.withValues(alpha: 0.1)
                    : AppTheme.primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isNetworkError ? 60 : 40),
              ),
              child: Icon(
                isNetworkError ? Icons.wifi_off : icon,
                size: isNetworkError ? 64 : 48,
                color: isNetworkError
                    ? AppTheme.kumkumRed
                    : AC.textMuted(context),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                color: isNetworkError
                    ? AppTheme.kumkumRed
                    : AC.textSub(context),
                fontSize: isNetworkError ? 18 : 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  color: AC.textMuted(context),
                  fontSize: isNetworkError ? 15 : 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: isNetworkError ? double.infinity : null,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh, size: isNetworkError ? 24 : 18),
                  label: Text(
                    isNetworkError ? 'Retry Connection' : 'Retry',
                    style: TextStyle(
                      fontSize: isNetworkError ? 16 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isNetworkError
                        ? AppTheme.sacredGreen
                        : AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isNetworkError ? 32 : 24,
                      vertical: isNetworkError ? 16 : 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<List<User>> _getProfilesWithOfflineSupport(
    AuthService authService,
  ) async {
    try {
      if (NetworkService.isConnected) {
        // 🔥 Reset pagination and fetch first page (20 profiles, server-side filtered)
        // Pass current filters so server returns only matching profiles
        final filterService = context.read<FilterService>();
        final page = await authService.getMatchingProfiles(
          limit: 20,
          filters: filterService.current,
        );
        if (page.users.isNotEmpty) {
          final usersData = page.users
              .map(
                (u) => {
                  'id': u.id,
                  'email': u.email,
                  'mobile_number': u.mobileNumber,
                  'profile_id': u.profileId,
                  'profile': u.profileForDiscovery.toJson(),
                  'created_at': u.createdAt.toIso8601String(),
                  'is_deleted': u.isDeleted,
                  'membership': u.membership.toJson(),
                },
              )
              .cast<Map<String, dynamic>>()
              .toList();
          await OfflineService().cacheMatchUsersData(usersData);
        }
        return page.users;
      } else {
        debugPrint('📱 Home Screen - Offline mode: Loading cached profiles');
        final cachedUsers = await OfflineService().getCachedMatchUsersData();
        if (cachedUsers.isEmpty) {
          debugPrint('📱 Home Screen - No cached profiles available');
          return [];
        }
        debugPrint(
          '📱 Home Screen - Loaded ${cachedUsers.length} profiles from cache',
        );
        return cachedUsers;
      }
    } catch (e) {
      debugPrint('❌ Home Screen Error in _getProfilesWithOfflineSupport: $e');
      // FIX 4: attempt the offline cache as a fallback first.
      // If the cache also has data, return it silently (graceful degradation).
      // If the cache is empty, RETHROW so the FutureBuilder sees hasError=true
      // and shows the error card with a retry button instead of a blank screen.
      try {
        final cachedUsers = await OfflineService().getCachedMatchUsersData();
        if (cachedUsers.isNotEmpty) {
          debugPrint('📱 Home Screen - Using cached users as fallback');
          return cachedUsers;
        }
      } catch (fallbackError) {
        debugPrint('❌ Home Screen - Fallback also failed: $fallbackError');
      }
      // No cache available — surface the original error to the UI.
      rethrow;
    }
  }
}

// ── _LiquidGlassNavBar — frosted glass bottom bar ─────────────────────────────
//
// Backdrop blur bar; selected tab = darker icon/label + sliding orange line.
// No per-tab highlight pill/backdrop.
class _LiquidGlassNavBar extends StatefulWidget {
  final List<Map<String, Object>> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _LiquidGlassNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  State<_LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<_LiquidGlassNavBar>
    with TickerProviderStateMixin {
  // Pill slide animation — drives Tween<double> from old index → new index.
  late AnimationController _pillCtrl;
  late Animation<double> _pillAnim;

  // Press-scale per-item controllers (same count as items).
  late List<AnimationController> _pressCtrl;

  double _fromIndex = 0;
  double _toIndex = 0;

  static const _smoothCurve = Curves.easeInOutCubicEmphasized;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex.toDouble();
    _toIndex = widget.selectedIndex.toDouble();

    _pillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _pillAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pillCtrl, curve: _smoothCurve));

    _pressCtrl = List.generate(
      widget.items.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 160),
        reverseDuration: const Duration(milliseconds: 280),
        value: 1.0,
      ),
    );
  }

  @override
  void didUpdateWidget(_LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _fromIndex = old.selectedIndex.toDouble();
      _toIndex = widget.selectedIndex.toDouble();
      _pillCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pillCtrl.dispose();
    for (final c in _pressCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  // Current interpolated pill position (in "tab units", 0..n-1).
  double get _pillPosition =>
      _fromIndex + (_toIndex - _fromIndex) * _pillAnim.value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final n = widget.items.length;

    // Frosted glass: stronger blur + layered translucency (no brand tint).
    final barTint = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.48)
        : Colors.white.withValues(alpha: 0.36);
    final barBorder = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFF3C3C43).withValues(alpha: 0.22);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.bottomNavMarginH,
        AppSizes.bottomNavMarginTop,
        AppSizes.bottomNavMarginH,
        AppSizes.bottomNavMarginBottom,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.bottomNavRadius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.50)
                : Colors.black.withValues(alpha: 0.10),
            blurRadius: isDark ? 36 : 28,
            spreadRadius: isDark ? 0 : -1,
            offset: Offset(0, isDark ? 14 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.bottomNavRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
          child: Container(
            decoration: BoxDecoration(
              color: barTint,
              borderRadius: BorderRadius.circular(AppSizes.bottomNavRadius),
              border: Border.all(color: barBorder, width: isDark ? 1 : 1.1),
            ),
            child: SizedBox(
              height: AppSizes.bottomNavHeight,
              child: AnimatedBuilder(
                animation: _pillAnim,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final totalW = constraints.maxWidth;
                      final tabW = totalW / n;
                      final pillPos = _pillPosition;
                      final indicatorW =
                          (tabW * 0.52).clamp(28.0, tabW - 12);
                      final indicatorX =
                          tabW * pillPos + (tabW - indicatorW) / 2;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: indicatorX,
                            bottom: 5,
                            child: IgnorePointer(
                              child: Container(
                                width: indicatorW,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryOrange,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryOrange
                                          .withValues(alpha: 0.35),
                                      blurRadius: 4,
                                      offset: const Offset(0, 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(n, (i) {
                              final isSelected = widget.selectedIndex == i;
                              final item = widget.items[i];
                              final pressScale =
                                  Tween<double>(begin: 0.965, end: 1.0).animate(
                                    CurvedAnimation(
                                      parent: _pressCtrl[i],
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );

                              final iconScale = isSelected ? 1.05 : 1.0;
                              final iconColor = isSelected
                                  ? AC.text(context)
                                  : AC
                                        .textSub(context)
                                        .withValues(alpha: isDark ? 0.85 : 0.9);
                              final labelColor = isSelected
                                  ? AC.text(context)
                                  : AC.textSub(context);

                              return Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (_) => _pressCtrl[i].reverse(),
                                  onTapCancel: () => _pressCtrl[i].forward(),
                                  onTap: () {
                                    _pressCtrl[i].forward();
                                    widget.onTap(i);
                                  },
                                  child: ScaleTransition(
                                    scale: pressScale,
                                    child: SizedBox(
                                      height: AppSizes.bottomNavHeight,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          AnimatedScale(
                                            scale: iconScale,
                                            duration: const Duration(
                                              milliseconds: 520,
                                            ),
                                            curve:
                                                Curves.easeInOutCubicEmphasized,
                                            child: Icon(
                                              isSelected
                                                  ? item['activeIcon']
                                                        as IconData
                                                  : item['icon'] as IconData,
                                              color: iconColor,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          AnimatedDefaultTextStyle(
                                            duration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            curve:
                                                Curves.easeInOutCubicEmphasized,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: labelColor,
                                              letterSpacing: -0.1,
                                            ),
                                            child: Text(
                                              item['label'] as String,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
