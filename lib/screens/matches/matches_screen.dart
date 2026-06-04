import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/gender.dart';
import '../../models/user.dart' as app_models;
import '../../legacy/compatibility.dart';
import '../../services/block_service.dart';
import '../../services/like_service_v2.dart';
import '../../services/astrology_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_sizes.dart';
import '../../widgets/app_header.dart';
import '../../widgets/profile_discovery_card.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/membership_badge_chip.dart';
import '../../widgets/online_status_indicator.dart';
import '../search/filter_screen.dart';
import '../../core/app_router.dart';
import '../../core/app_identity.dart';
import '../../core/app_initializer.dart';
import '../../core/contract.dart';
import '../../core/profile_completion_policy.dart';
import '../../utils/error_handler.dart';
import '../../utils/profile_display_shuffle.dart';
import 'profile_detail_screen.dart';

bool _filtersNeedUserProfile(FilterPreferences f) {
  bool ne(String? s) =>
      s != null && s.trim().isNotEmpty && s.toLowerCase() != 'any';
  return f.minAge != null ||
      f.maxAge != null ||
      ne(f.nakshatra) ||
      ne(f.sect) ||
      ne(f.subSect) ||
      ne(f.education) ||
      ne(f.occupation) ||
      ne(f.country) ||
      ne(f.state) ||
      ne(f.city) ||
      ne(f.maritalStatus) ||
      ne(f.foodHabit) ||
      ne(f.incomeRange);
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchesScreen
// ─────────────────────────────────────────────────────────────────────────────

class MatchesScreen extends StatefulWidget {
  /// When true (main [HomeScreen] tab), list bottom padding clears the floating
  /// glass nav (`extendBody`). When false (standalone route), use safe area only.
  final bool embeddedInMainShell;

  const MatchesScreen({super.key, this.embeddedInMainShell = false});

  @override
  State<MatchesScreen> createState() => MatchesScreenState();
}

// In-screen cache to prevent duplicate per-row user resolution work.
final Map<String, Future<app_models.User?>> _matchesUserLookupCache =
    <String, Future<app_models.User?>>{};
final Map<String, List<Map<String, dynamic>>> _matchesYouLikedRowsCache =
    <String, List<Map<String, dynamic>>>{};
final Map<String, List<Map<String, dynamic>>> _matchesLikedYouRowsCache =
    <String, List<Map<String, dynamic>>>{};

/// Dedupes identity/bind logs across hot restarts and parallel rebind attempts.
String? _matchesLikeBindLoggedFingerprint;
bool _matchesLikeBindInProgress = false;

void _debugLikeLog(String message) {
  if (kDebugMode) debugPrint(message);
}

String _likeRowDisplayName(Map<String, dynamic> row, {String fallback = 'User'}) {
  final name = (row['name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final fn = (row[Fields.firstName] ?? row['firstName'] ?? '')
      .toString()
      .trim();
  final ln = (row[Fields.lastName] ?? row['lastName'] ?? '')
      .toString()
      .trim();
  if (fn.isNotEmpty) return '$fn $ln'.trim();
  final pid = (row[Fields.profileId] ?? row['profile_id'] ?? '')
      .toString()
      .trim();
  if (pid.isNotEmpty) return pid;
  return fallback;
}

List<String> _likeRowDetailChips(Map<String, dynamic> row) {
  final chips = <String>[];
  final age = row[Fields.age] ?? row['age'];
  if (age is int && age > 0) chips.add('$age yrs');
  final city = (row[Fields.city] ?? row['city'] ?? '').toString().trim();
  if (city.isNotEmpty) chips.add(city);
  final occ = (row['occupation'] ?? '').toString().trim();
  if (occ.isNotEmpty) chips.add(occ);
  return chips;
}

void _prefetchLikeRowProfiles(List<Map<String, dynamic>> rows) {
  final ids = <String>{};
  for (final row in rows) {
    for (final key in [
      Fields.userId,
      Fields.docId,
      'user_id',
      'doc_id',
      'to_user_id',
      'toUserId',
      'from_user_id',
      'fromUserId',
      'uid',
      'id',
    ]) {
      final v = (row[key] ?? '').toString().trim();
      if (v.isNotEmpty) ids.add(v);
    }
  }
  if (ids.isEmpty) return;
  unawaited(LikeServiceV2().prefetchProfilesForLikes(ids));
}

void _debugLikeBindIdentityOnce(String fingerprint, String identitiesLine) {
  if (!kDebugMode) return;
  if (_matchesLikeBindLoggedFingerprint == fingerprint) return;
  _matchesLikeBindLoggedFingerprint = fingerprint;
  _debugLikeLog(identitiesLine);
  _debugLikeLog('LIKE STREAM BIND identity=$fingerprint');
}

Future<app_models.User?> _cachedResolveMatchUser({
  required AuthService auth,
  required String uid,
  String? fallbackProfileId,
}) {
  final normalizedUid = uid.trim();
  final normalizedFallback = (fallbackProfileId ?? '').trim();
  final cacheKey = '$normalizedUid|$normalizedFallback';
  return _matchesUserLookupCache.putIfAbsent(cacheKey, () async {
    if (normalizedUid.isEmpty) return null;

    app_models.User? resolved;
    try {
      resolved = await auth.getUserById(normalizedUid);
    } catch (_) {}
    if (resolved != null) return resolved;

    try {
      resolved = await auth.getUserByUidField(normalizedUid);
    } catch (_) {}
    if (resolved != null) return resolved;

    if (normalizedUid.startsWith('MB') || normalizedUid.startsWith('MG')) {
      try {
        resolved = await auth.getUserByProfileId(normalizedUid);
      } catch (_) {}
      if (resolved != null) return resolved;
    }

    if (normalizedFallback.isNotEmpty) {
      try {
        resolved = await auth.getUserByProfileId(normalizedFallback);
      } catch (_) {}
      if (resolved != null) return resolved;
    }

    scheduleMicrotask(() => _matchesUserLookupCache.remove(cacheKey));
    return null;
  });
}

class MatchesScreenState extends State<MatchesScreen>
    with
        SingleTickerProviderStateMixin,
        RouteAware,
        AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  late ScrollController _scrollController;

  // ── Search state ──────────────────────────────────────────
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // ── Pagination ────────────────────────────────────────────
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _loadingMore = false;

  AuthService get authController => _authService ?? context.read<AuthService>();

  // Mutual matches list paging (UI-level, stream provides full list).
  static const int _mutualPageSize = 30;
  int _mutualVisible = _mutualPageSize;

  final List<app_models.User> _profiles = [];
  Future<List<app_models.User>>? _future;
  bool _fetchingProfiles = false; // 🔥 Guard against duplicate fetches
  Gender? _lastDiscoveryGender;
  Timer? _discoveryRefetchDebounce;
  Stream<List<Map<String, dynamic>>>? _youLikedStream;
  Stream<List<Map<String, dynamic>>>? _likedYouStream;
  StreamSubscription<List<Map<String, dynamic>>>? _youLikedSub;
  StreamSubscription<List<Map<String, dynamic>>>? _likedYouSub;
  String? _likeStreamIdentityKey;
  List<Map<String, dynamic>> _youLikedRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _likedYouRows = <Map<String, dynamic>>[];
  bool _youLikedStreamReady = false;
  bool _likedYouStreamReady = false;
  Object? _youLikedStreamError;
  Object? _likedYouStreamError;
  Timer? _likeBindDebounce;

  // 🔥 Cached service references - initialized in didChangeDependencies()
  FilterService? _filterService;
  AuthService? _authService;
  bool _servicesInitialized = false;

  // ── Lifecycle ─────────────────────────────────────────────

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_servicesInitialized) {
      _filterService = context.read<FilterService>();
      _authService = context.read<AuthService>();
      _filterService?.addListener(_onFiltersChanged);
      IdentityProvider.addListener(_onLikeIdentityProviderTick);
      _authService?.addListener(_onAuthServiceUpdate);
      _servicesInitialized = true;
      _initAsync();
    }
    _scheduleMaybeBindLikeStreams();
  }

  void _onLikeIdentityProviderTick(AppIdentity? _) {
    _scheduleMaybeBindLikeStreams();
  }

  void _onAuthServiceUpdate() {
    _scheduleMaybeBindLikeStreams();
    _scheduleDiscoveryRefetchIfGenderJustLoaded();
  }

  void _scheduleDiscoveryRefetchIfGenderJustLoaded() {
    final auth = _authService;
    if (auth == null || !mounted) return;
    final gender = auth.currentUser?.profile?.gender;
    final hadGender = _lastDiscoveryGender != null;
    _lastDiscoveryGender = gender;
    if (gender == null || hadGender) return;
    if (_profiles.isNotEmpty || _fetchingProfiles) return;
    _discoveryRefetchDebounce?.cancel();
    _discoveryRefetchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _profiles.isNotEmpty || _fetchingProfiles) return;
      debugPrint(
        '🔥 MatchesScreen: gender loaded (${gender.name}) — refetching profiles',
      );
      unawaited(refreshProfiles());
    });
  }

  void _scheduleMaybeBindLikeStreams() {
    if (!_servicesInitialized) return;
    _likeBindDebounce?.cancel();
    _likeBindDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      unawaited(_maybeBindLikeStreams());
    });
  }

  List<Map<String, dynamic>> _validLikeMapsForDisplay(
    List<Map<String, dynamic>> raw,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in raw) {
      final f =
          (m[Fields.fromUserId] ?? m['fromUserId'] ?? '').toString().trim();
      final t = (m[Fields.toUserId] ?? m['toUserId'] ?? '').toString().trim();
      if (f.isEmpty || t.isEmpty) {
        _debugLikeLog(
          'LIKE ROW SKIP malformed like id=${m['id'] ?? m['likeId'] ?? '?'}',
        );
        continue;
      }
      out.add(m);
    }
    return out;
  }

  Future<void> _maybeBindLikeStreams() async {
    if (!mounted || _matchesLikeBindInProgress) return;
    _matchesLikeBindInProgress = true;
    try {
      await _bindLikeStreamsImpl();
    } finally {
      _matchesLikeBindInProgress = false;
    }
  }

  Future<void> _bindLikeStreamsImpl() async {
    if (!mounted) return;
    final likeService = context.read<LikeService>();

    if ((FirebaseAuth.instance.currentUser?.uid.trim() ?? '').isEmpty &&
        IdentityProvider.userDocId.trim().isEmpty) {
      _debugLikeLog(
        'LIKE STREAM BIND awaiting identity (no Firebase uid or userDocId)…',
      );
      await AppInitializer.ensureInitialized();
      if (!mounted) return;
    }

    final resolvedAuthUid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final resolvedUserDocId = IdentityProvider.userDocId.trim();

    if (resolvedAuthUid.isEmpty && resolvedUserDocId.isEmpty) {
      _debugLikeLog('LIKE STREAM BIND skipped: no identity available');
      return;
    }

    // Stable key: non-empty segments only; prefer one auth uid (IdentityProvider
    // or Firebase) so null→resolved userDocId does not churn the fingerprint.
    final authUid = IdentityProvider.authUid.trim().isNotEmpty
        ? IdentityProvider.authUid.trim()
        : resolvedAuthUid;
    final fingerprint = [
      resolvedUserDocId,
      authUid,
      IdentityProvider.profileId.trim(),
    ].where((s) => s.isNotEmpty).join('|');

    if (_likeStreamIdentityKey == fingerprint &&
        _youLikedSub != null &&
        _likedYouSub != null) {
      return;
    }

    _debugLikeBindIdentityOnce(
      fingerprint,
      'LIKE BIND identities: userDocId=${IdentityProvider.userDocId}, '
      'authUid=${IdentityProvider.authUid}, '
      'firebaseUid=${FirebaseAuth.instance.currentUser?.uid}, '
      'authServiceUserDocId=${_authService?.currentUser?.id}',
    );

    _youLikedSub?.cancel();
    _likedYouSub?.cancel();
    _youLikedSub = null;
    _likedYouSub = null;

    _likeStreamIdentityKey = fingerprint;

    if (_matchesYouLikedRowsCache.containsKey(fingerprint)) {
      _youLikedRows = List<Map<String, dynamic>>.from(
        _matchesYouLikedRowsCache[fingerprint]!,
      );
    } else {
      _youLikedRows = [];
    }
    if (_matchesLikedYouRowsCache.containsKey(fingerprint)) {
      _likedYouRows = List<Map<String, dynamic>>.from(
        _matchesLikedYouRowsCache[fingerprint]!,
      );
    } else {
      _likedYouRows = [];
    }

    _youLikedStreamReady = false;
    _likedYouStreamReady = false;
    _youLikedStreamError = null;
    _likedYouStreamError = null;

    if (mounted) setState(() {});

    // Do not wrap Firestore snapshot streams in timeout-with-empty: idle streams
    // emit nothing for long periods; injecting [] wipes valid UI state.
    _youLikedStream = likeService.getYouLiked();
    _likedYouStream = likeService.getLikedYou();

    void logMutualIfReady() {
      if (!_youLikedStreamReady || !_likedYouStreamReady) return;
      final sent = _validLikeMapsForDisplay(_youLikedRows);
      final recv = _validLikeMapsForDisplay(_likedYouRows);
      final n = LikeService.mutualLikeRows(sent: sent, received: recv).length;
      debugPrint('MUTUAL COUNT=$n');
    }

    _youLikedSub = _youLikedStream!.listen(
      (rows) {
        if (!mounted) return;
        final clean = _validLikeMapsForDisplay(rows);
        setState(() {
          _youLikedStreamError = null;
          _youLikedStreamReady = true;
          _storeYouLikedRows(clean);
        });
        _debugLikeLog('LIKE STREAM READY sent=${clean.length}');
        logMutualIfReady();
      },
      onError: (Object e, StackTrace st) {
        _debugLikeLog('LIKE STREAM ERROR youLiked subscription: $e');
        if (!mounted) return;
        setState(() {
          _youLikedStreamError = e;
          _youLikedStreamReady = true;
        });
        logMutualIfReady();
      },
    );
    _likedYouSub = _likedYouStream!.listen(
      (rows) {
        if (!mounted) return;
        final clean = _validLikeMapsForDisplay(rows);
        setState(() {
          _likedYouStreamError = null;
          _likedYouStreamReady = true;
          _storeLikedYouRows(clean);
        });
        _debugLikeLog('LIKE STREAM READY received=${clean.length}');
        logMutualIfReady();
      },
      onError: (Object e, StackTrace st) {
        _debugLikeLog('LIKE STREAM ERROR likedYou subscription: $e');
        if (!mounted) return;
        setState(() {
          _likedYouStreamError = e;
          _likedYouStreamReady = true;
        });
        logMutualIfReady();
      },
    );
  }

  void _storeYouLikedRows(List<Map<String, dynamic>> rows) {
    _youLikedRows = List<Map<String, dynamic>>.from(rows);
    final key = _likeStreamIdentityKey;
    if (key != null && key.isNotEmpty) {
      _matchesYouLikedRowsCache[key] = _youLikedRows;
    }
    _prefetchLikeRowProfiles(_youLikedRows);
  }

  void _storeLikedYouRows(List<Map<String, dynamic>> rows) {
    _likedYouRows = List<Map<String, dynamic>>.from(rows);
    final key = _likeStreamIdentityKey;
    if (key != null && key.isNotEmpty) {
      _matchesLikedYouRowsCache[key] = _likedYouRows;
    }
    _prefetchLikeRowProfiles(_likedYouRows);
  }

  Future<void> _initAsync() async {
    // 🔥 FIX: Check mounted before each async operation to prevent crashes
    if (!mounted) return;

    await _bootstrap();
    if (!mounted) return;

    // FIX 1: reset pagination state before the very first fetch.
    _currentPage = 0;
    _profiles.clear();

    await _refreshProfileInterestStatus();
    if (!mounted) return;

    final auth = _authService ?? context.read<AuthService>();
    final ready = await auth.ensureReadyForDiscovery();
    if (!mounted) return;
    if (!ready) {
      debugPrint(
        '⚠️ MatchesScreen: discovery not ready (gender/session) — will retry when auth loads',
      );
    }
    _lastDiscoveryGender = auth.currentUser?.profile?.gender;

    // 🔥 FIX: Assign _future BEFORE setState to avoid race conditions
    final future = _fetchProfiles();
    setState(() {
      _future = future;
    });

    // 🔥 FIX: Capture ModalRoute before any async gap
    final route = ModalRoute.of(context);
    if (route != null) {
      AppRouter.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _bootstrap();
    // FIX: Don't clear profiles completely - just refresh interest status
    // The InterestService already has updated data from ProfileDetailScreen
    // Only reset pagination if filters changed, not on normal back navigation
    _refreshProfileInterestStatus();
  }

  /// Refresh interest status on profiles without clearing the list
  Future<void> _refreshProfileInterestStatus() async {
    try {
      // 🔥 FIX: Use cached service references to avoid "deactivated widget ancestor" error
      final auth = _authService;
      final interestService = context.read<InterestService>();
      if (!mounted || auth == null) return;

      final uid = auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return;

      await interestService.loadInterests(uid);
      if (!mounted) return;

      setState(() {});
    } catch (e) {
      debugPrint('Error refreshing interests: $e');
    }
  }

  @override
  void didPushNext() {}
  @override
  void didPush() {}
  @override
  void didPop() {}

  /// 🔥 Auto-refresh when filters change from any screen
  void _onFiltersChanged() {
    debugPrint('🔥 MatchesScreen: Filters changed, refreshing profiles...');
    refreshProfiles();
  }

  @override
  void dispose() {
    // 🔥 CRITICAL FIX: Use stored reference, NOT context.read()
    // context is invalid during dispose() - accessing it causes Flutter errors
    try {
      _filterService?.removeListener(_onFiltersChanged);
    } catch (e) {
      debugPrint('⚠️ Error removing filter listener: $e');
    }

    try {
      IdentityProvider.removeListener(_onLikeIdentityProviderTick);
    } catch (e) {
      debugPrint('⚠️ Error removing identity listener: $e');
    }

    try {
      _authService?.removeListener(_onAuthServiceUpdate);
    } catch (e) {
      debugPrint('⚠️ Error removing auth listener: $e');
    }

    _likeBindDebounce?.cancel();
    _discoveryRefetchDebounce?.cancel();

    try {
      AppRouter.routeObserver.unsubscribe(this);
    } catch (e) {
      debugPrint('⚠️ Error unsubscribing from route observer: $e');
    }

    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _youLikedSub?.cancel();
    _likedYouSub?.cancel();
    super.dispose();
  }

  // ── Bootstrap ─────────────────────────────────────────────

  Future<void> _bootstrap() async {
    // 🔥 FIX: Use cached service reference
    final auth = _authService ?? context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    final analytics = context.read<ProfileAnalyticsService>();
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await analytics.loadAnalyticsForUser(
      authUid.isNotEmpty ? authUid : user.id,
    );
    if (!mounted) return; // 🔥 FIX: guard after await
  }

  // ── Fetch ─────────────────────────────────────────────────

  Future<List<app_models.User>> _fetchProfiles({bool refresh = false}) async {
    // 🔥 FIX: Use cached service references
    final filterService = _filterService ?? context.read<FilterService>();

    // If a fetch is already in flight, do NOT return a prematurely-completed
    // Future with an empty _profiles list — that leaves FutureBuilder stuck on
    // an empty snapshot while the real request finishes (plain / empty UI).
    if (_fetchingProfiles) {
      debugPrint('⚠️ _fetchProfiles: awaiting in-flight fetch...');
      while (_fetchingProfiles && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!mounted) {
        return List<app_models.User>.from(_profiles);
      }
      if (!refresh) {
        return List<app_models.User>.from(_profiles);
      }
      // refresh=true: fall through and run a new fetch now that the slot is free
    }
    _fetchingProfiles = true;

    try {
      if (!mounted) {
        return List<app_models.User>.from(
            _profiles); // 🔥 FIX: guard after potential await from caller
      }

      final auth = authController;
      if (auth.currentUser?.profile?.gender == null) {
        await auth.ensureReadyForDiscovery(
          timeout: const Duration(seconds: 2),
        );
        if (!mounted) {
          return List<app_models.User>.from(_profiles);
        }
      }

      final currentFilters = filterService.current;

      debugPrint(
          '🔥 MATCHES _fetchProfiles: refresh=$refresh, page=$_currentPage');
      debugPrint(
          '🔥 MATCHES filters: sect=${currentFilters?.sect}, subSect=${currentFilters?.subSect}, education=${currentFilters?.education}');

      // 🔥 Reset pagination on first load or refresh
      final bool resetFeed = refresh || _currentPage == 0;
      if (resetFeed) {
        debugPrint('🔥 MATCHES resetting pagination and clearing profiles');
        authController.resetProfilePagination();
        _profiles.clear();
      }

      final page = await authController.fetchMatchingProfilesPage(
        currentFilters ?? FilterPreferences(),
        limit: _pageSize,
      );
      if (!mounted) {
        return List<app_models.User>.from(
            _profiles); // 🔥 FIX: Guard after await
      }
      final data = page.users;

      // 🔥 REMOVED: Client-side gender filter - backend already filters by opposite gender
      // This prevents double-filtering and race conditions when user gender not loaded yet

      // Apply CLIENT-SIDE filters (age / nakshatra etc. not fully on server)
      final filteredData = data.where((user) {
        if (!ProfileCompletionPolicy.isEligibleForDiscovery(user)) return false;
        final f = currentFilters;
        final profile = user.profile;
        if (profile == null) {
          if (f != null && _filtersNeedUserProfile(f)) return false;
          return true;
        }

        // 🔥 NOTE: Gender filtering is done in backend (getMatchingProfiles)
        // Do NOT add client-side gender filter here - causes double-filter bugs

        // Age filter (client-side only - requires accurate date calculation)
        if (f != null && (f.minAge != null || f.maxAge != null)) {
          final now = DateTime.now();
          var age = now.year - profile.dateOfBirth.year;
          // Adjust if birthday hasn't occurred this year
          if (now.month < profile.dateOfBirth.month ||
              (now.month == profile.dateOfBirth.month &&
                  now.day < profile.dateOfBirth.day)) {
            age--;
          }
          if (f.minAge != null && age < f.minAge!) return false;
          if (f.maxAge != null && age > f.maxAge!) return false;
        }

        // Nakshatra filter (client-side - complex matching logic)
        if (f?.nakshatra != null && f!.nakshatra!.isNotEmpty) {
          if (profile.nakshatra == null) return false;
          if (profile.nakshatra != f.nakshatra) return false;
        }

        if (f?.sect != null && f!.sect!.isNotEmpty && profile.sect != f.sect) {
          return false;
        }

        if (f?.subSect != null &&
            f!.subSect!.isNotEmpty &&
            profile.subSect != f.subSect) {
          return false;
        }

        if (f?.education != null &&
            f!.education!.isNotEmpty &&
            profile.education != f.education) {
          return false;
        }

        if (f?.occupation != null &&
            f!.occupation!.isNotEmpty &&
            profile.occupation != f.occupation) {
          return false;
        }

        if (f?.country != null &&
            f!.country!.isNotEmpty &&
            (profile.country == null ||
                !profile.country!
                    .toLowerCase()
                    .contains(f.country!.toLowerCase()))) {
          return false;
        }

        if (f?.state != null &&
            f!.state!.isNotEmpty &&
            profile.state != f.state) {
          return false;
        }

        if (f?.city != null &&
            f!.city!.isNotEmpty &&
            (profile.city == null ||
                !profile.city!.toLowerCase().contains(f.city!.toLowerCase()))) {
          return false;
        }

        if (f?.maritalStatus != null &&
            f!.maritalStatus!.isNotEmpty &&
            profile.maritalStatus != f.maritalStatus) {
          return false;
        }

        if (f?.foodHabit != null &&
            f!.foodHabit!.isNotEmpty &&
            profile.foodHabit != f.foodHabit) {
          return false;
        }

        return true;
      }).toList();

      debugPrint(
          '🔍 FILTER DEBUG: ${filteredData.length} profiles match filters out of ${data.length} total fetched (gender filter: server-side)');

      // 🔥 FIX 3: Prevent duplicate profiles
      for (final user in filteredData) {
        if (!_profiles.any((existing) => existing.id == user.id)) {
          _profiles.add(user);
        }
      }

      if (resetFeed && _profiles.isNotEmpty) {
        final viewerId = authController.currentUser?.id;
        final shuffled = shuffleUsersForDiscovery(
          List<app_models.User>.from(_profiles),
          viewerUserId: viewerId,
          salt: 'matches_profiles_tab',
        );
        _profiles
          ..clear()
          ..addAll(shuffled);
      }

      _hasMore = page.hasMore;

      return List<app_models.User>.from(_profiles);
    } catch (e) {
      debugPrint('❌ _fetchProfiles: $e');
      return List<app_models.User>.from(_profiles);
    } finally {
      _fetchingProfiles = false;
    }
  }

  // ── Scroll / load more ────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return; // guard double-calls
    _loadingMore = true;
    _currentPage++;
    // FIX 5: reassign _future so FutureBuilder picks up the newly loaded page.
    // Previously _fetchProfiles() mutated _profiles but _future was never updated,
    // so FutureBuilder re-used the stale completed-future snapshot and never showed
    // the extra profiles.
    final next = _fetchProfiles();
    if (!mounted) {
      _loadingMore = false;
      return;
    }
    setState(() => _future = next);
    await next;
    _loadingMore = false;
    if (!mounted) return;
    setState(() {});
  }

  /// 🔥 Public method to refresh profiles with filters
  Future<void> refreshProfiles() async {
    if (!mounted) return;
    if (_fetchingProfiles) {
      // Avoid queuing a second refresh immediately after login/auth hydration.
      return;
    }
    // 🔥 FIX: Assign _future BEFORE setState to avoid race conditions
    final future = _fetchProfiles(refresh: true);
    setState(() {
      _currentPage = 0;
      _profiles.clear();
      _hasMore = true;
      _future = future;
    });
  }

  // ── Search ────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _onSearch(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = val.toLowerCase().trim());
    });
  }

  // ── Navigate ──────────────────────────────────────────────

  Future<void> _openUser(String userId) async {
    if (userId.isEmpty) return;
    final auth = _authService ?? context.read<AuthService>();
    final user = await _cachedResolveMatchUser(auth: auth, uid: userId);
    if (!mounted) return; // 🔥 FIX: Guard after await
    if (user != null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProfileDetailScreen(user: user)));
    } else {
      // Profile may have been removed/deactivated; fail silently to avoid
      // interrupting swipe/list actions with blocking error toasts.
      debugPrint('Matches: profile not found for userId=$userId');
    }
  }

  // ── Open filter screen ────────────────────────────────────

  void _openFilter() {
    // 🔥 FIX: Use cached service reference
    final filterService = _filterService ?? context.read<FilterService>();
    final filterPrefs = filterService.current;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilterScreen(
          initialFilters: filterPrefs,
          onApply: (result) {
            filterService.setFilters(result);
            setState(() {
              _currentPage = 0;
              _profiles.clear();
              _hasMore = true;
              // 🔥 FIX: Assign _future BEFORE setState
              _future = _fetchProfiles(refresh: true);
            });
          },
        ),
      ),
    );
  }

  EdgeInsets _matchesScrollListPadding() {
    final bottom = widget.embeddedInMainShell
        ? AppSizes.shellBottomContentInset(context)
        : MediaQuery.paddingOf(context).bottom + 32;
    return ProfileDiscoveryCard.listPadding(bottom: bottom);
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Narrow rebuilds: full AuthService.watch was rebuilding this whole screen on every auth tick.
    final blocked = context.select<BlockService, Set<String>>(
        (b) => b.allBlockedPeerIds);

    return Scaffold(
      backgroundColor: AC.bg(context),

      // ── AppHeader — Discover 3D lives on Home FAB only (avoid duplicate with Matches).
      appBar: AppHeader(
        title: 'Matches',
        showLogo: true,
        showNotifications: false,
        showFilter: true,
        onFilterTap: _openFilter,
        showSearch: true,
        isSearchActive: _searchOpen,
        onSearchTap: _toggleSearch,
      ),

      body: Column(children: [
        // ── Search bar slides in below header ─────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _searchOpen
              ? Container(
                  color: AC.card(context),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _toggleSearch,
                      ),
                      filled: true,
                      fillColor: AC.inputFill(context),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.primaryOrange),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Tab bar — explicit colours (avoid const TextStyle stripping label colours) ──
        Container(
          color: AC.surface(context),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.primaryOrange,
            indicatorWeight: 4,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelColor: AC.text(context),
            unselectedLabelColor: AC.textSub(context),
            labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: AC.text(context)),
            unselectedLabelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AC.textSub(context)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: const [
              Tab(text: 'Profiles'),
              Tab(text: 'You Liked'),
              Tab(text: 'Liked You'),
              Tab(text: 'Mutual'),
            ],
          ),
        ),

        // ── Tab content ────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildProfiles(blocked),
              _buildYouLiked(),
              _buildLikedYou(),
              _buildMutual(),
            ],
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TAB 1 — PROFILES  (home-screen card style)
  // ─────────────────────────────────────────────────────────

  Widget _buildProfiles(Set<String> blocked) {
    return FutureBuilder<List<app_models.User>>(
        future: _future,
        builder: (_, snap) {
          if (_future == null ||
              snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: AppTheme.primaryOrange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading profiles…',
                      style: TextStyle(
                        color: AC.textSub(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snap.hasError) {
            return _emptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: snap.error.toString(),
              onRetry: refreshProfiles,
            );
          }

          var list = (snap.data ?? [])
              .where(
                (u) =>
                    !blocked.contains(u.profileId) && !blocked.contains(u.id),
              )
              .where(ProfileCompletionPolicy.isEligibleForDiscovery)
              .toList();

          // client-side search
          if (_searchQuery.isNotEmpty) {
            list = list.where((u) {
              final p = u.profile;
              final name = p != null
                  ? '${p.firstName} ${p.lastName}'.trim().toLowerCase()
                  : '${u.firstName} ${u.lastName}'.trim().toLowerCase();
              return name.contains(_searchQuery) ||
                  u.profileId.toLowerCase().contains(_searchQuery);
            }).toList();
          }

          if (list.isEmpty) {
            return _emptyState(
              icon: Icons.person_search,
              title: _searchQuery.isNotEmpty
                  ? 'No results for "$_searchQuery"'
                  : 'No Profiles Found',
              subtitle: _searchQuery.isNotEmpty
                  ? 'Try a different name'
                  : 'Check back later or adjust filters',
              onRetry: refreshProfiles,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => refreshProfiles(),
            child: ListView.builder(
              controller: _scrollController,
              padding: _matchesScrollListPadding(),
              itemCount: list.length + (_hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == list.length && !_loadingMore) {
                  // 🔥 FIX 4: Use Future.microtask to prevent multiple simultaneous calls
                  Future.microtask(_loadMore);
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final u = list[i];
                final p = u.profileForDiscovery;
                final eduLine = p.education?.trim();
                return ProfileDiscoveryCard(
                  user: u,
                  compactPresence: true,
                  additionalWrapChildren: [
                    if (eduLine != null && eduLine.isNotEmpty)
                      profileDiscoveryChip(context, eduLine),
                    Builder(
                      builder: (ctx) {
                        final currentUser =
                            ctx.read<AuthService>().currentUser;
                        final doshaResult =
                            AstrologyService.checkDoshaWithCurrentUser(
                          u,
                          currentUser,
                        );
                        if (!doshaResult.hasDosha) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withAlpha(50)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber,
                                  size: 12, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Shashta Ashtaka',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProfileDetailScreen(user: u)),
                  ),
                )
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 60 * i.clamp(0, 8)))
                    .slideY(begin: 0.04);
              },
            ),
          );
        });
  }

  // When you like someone, they appear in your "You Liked" tab
  // and you appear in their "Liked You" tab.
  // ─────────────────────────────────────────────────────────

  Widget _buildYouLiked() {
    return ListenableBuilder(
      listenable: LikeService(),
      builder: (context, _) {
        final svcErr = LikeService().youLikedQueryError;
        if (_youLikedStream == null) {
          return _emptyState(
            icon: Icons.bookmark_border,
            title: 'No Liked Profiles',
            subtitle: 'Profiles you like will appear here',
          );
        }
        if (!_youLikedStreamReady && _youLikedRows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final errText = svcErr ?? _youLikedStreamError?.toString();
        if (errText != null && _youLikedRows.isEmpty) {
          return _emptyState(
            icon: Icons.error_outline,
            title: 'Error loading likes',
            subtitle: '$errText\nPull to refresh or reopen Matches.',
            onRetry: () => _scheduleMaybeBindLikeStreams(),
          );
        }

        final list = _youLikedRows;
        if (list.isEmpty) {
          return _emptyState(
            icon: Icons.bookmark_border,
            title: 'No Liked Profiles',
            subtitle: 'Profiles you like will appear here',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (svcErr != null && list.isNotEmpty)
              Material(
                color: AppTheme.kumkumRed.withAlpha(28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Like list warning: $svcErr',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kumkumRed.withAlpha(240),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: _matchesScrollListPadding(),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final userData = list[i];
                  final targetId = (userData['user_id'] as String?) ??
                      (userData['doc_id'] as String?) ??
                      (userData['to_user_id'] as String?) ??
                      (userData['toUserId'] as String?) ??
                      (userData['uid'] as String?) ??
                      (userData['id'] as String?) ??
                      '';
                  return UserProfileTile(
                    key: ValueKey<String>(
                        'you_liked_${targetId.trim().toLowerCase()}'),
                    userId: targetId,
                    likePreview: userData,
                    badgeText: 'Liked',
                    badgeColor: AppTheme.sacredGreen,
                    showOnline: false,
                    index: i,
                    actionLabel: 'Unlike',
                    actionIcon: Icons.heart_broken_outlined,
                    actionColor: AppTheme.kumkumRed,
                    onAction: () => _showUnlikeDialog(targetId),
                    onTap: () => _openUser(targetId),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // TAB 3 — LIKED YOU
  // Uses getLikedYou() — shows all profiles who liked YOU.
  // When someone likes you, they appear in your "Liked You" tab
  // and you appear in their "You Liked" tab.
  // ─────────────────────────────────────────────────────────

  Widget _buildLikedYou() {
    return ListenableBuilder(
      listenable: LikeService(),
      builder: (context, _) {
        final svcErr = LikeService().likedYouQueryError;
        if (_likedYouStream == null) {
          return _emptyState(
            icon: Icons.favorite_border,
            title: 'No One Yet',
            subtitle: 'Profiles that like you will appear here',
          );
        }
        if (!_likedYouStreamReady && _likedYouRows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final errText = svcErr ?? _likedYouStreamError?.toString();
        if (errText != null && _likedYouRows.isEmpty) {
          return _emptyState(
            icon: Icons.error_outline,
            title: 'Error loading likes',
            subtitle: '$errText\nPull to refresh or reopen Matches.',
            onRetry: () => _scheduleMaybeBindLikeStreams(),
          );
        }

        final list = _likedYouRows;
        if (list.isEmpty) {
          return _emptyState(
            icon: Icons.favorite_border,
            title: 'No One Yet',
            subtitle: 'Profiles that like you will appear here',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (svcErr != null && list.isNotEmpty)
              Material(
                color: AppTheme.kumkumRed.withAlpha(28),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Like list warning: $svcErr',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kumkumRed.withAlpha(240),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await refreshProfiles();
                },
                child: ListView.builder(
                  padding: _matchesScrollListPadding(),
                  itemCount: list.length,
                  itemBuilder: (_, index) {
                    final userData = list[index];
                    final userId = (userData['user_id'] as String?) ??
                        (userData['doc_id'] as String?) ??
                        (userData['from_user_id'] as String?) ??
                        (userData['fromUserId'] as String?) ??
                        (userData['uid'] as String?) ??
                        '';
                    if (userId.isEmpty) return const SizedBox.shrink();

                    return _LikedYouTile(
                      key: ValueKey<String>(
                          'liked_you_${userId.trim().toLowerCase()}'),
                      userId: userId,
                      name: _likeRowDisplayName(
                        userData,
                        fallback: (userData['name'] as String?) ?? '',
                      ),
                      profileId: (userData['profile_id'] as String?) ??
                          (userData['uid'] as String?) ??
                          '',
                      previewChips: _likeRowDetailChips(userData),
                      index: index,
                      onTap: () => _openUser(userId),
                      onDismiss: () {},
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 60 * index))
                        .slideX(begin: 0.06);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────
  // TAB 4 — MUTUAL MATCHES (both users interested)
  // ─────────────────────────────────────────────────

  Widget _buildMutual() {
    final authService = context.read<AuthService>();
    final currentUserId = authService.currentUser?.id ?? '';
    if (currentUserId.isEmpty) {
      return _emptyState(
        icon: Icons.person_outline,
        title: 'Please login',
        subtitle: 'Sign in to view matches',
      );
    }

    String idFromSent(Map<String, dynamic> m) => (m['user_id'] ??
            m['doc_id'] ??
            m['to_user_id'] ??
            m['toUserId'] ??
            m['uid'] ??
            m['id'] ??
            '')
        .toString()
        .trim();

    return ListenableBuilder(
      listenable: LikeService(),
      builder: (context, _) {
        final svc = LikeService();
        if (_youLikedStream == null || _likedYouStream == null) {
          return _emptyState(
            icon: Icons.favorite,
            title: 'No Mutual Matches Yet',
            subtitle: 'When both users like each other, matches appear here',
          );
        }

        if (!_youLikedStreamReady || !_likedYouStreamReady) {
          return const Center(child: CircularProgressIndicator());
        }

        final sent = _validLikeMapsForDisplay(_youLikedRows);
        final recv = _validLikeMapsForDisplay(_likedYouRows);
        final hasErr = _youLikedStreamError != null ||
            _likedYouStreamError != null ||
            svc.youLikedQueryError != null ||
            svc.likedYouQueryError != null;
        if (hasErr && sent.isEmpty && recv.isEmpty) {
          final parts = <String?>[
            _youLikedStreamError?.toString(),
            _likedYouStreamError?.toString(),
            svc.youLikedQueryError,
            svc.likedYouQueryError,
          ].whereType<String>().where((s) => s.isNotEmpty).toList();
          return _emptyState(
            icon: Icons.error_outline,
            title: 'Could not load mutual matches',
            subtitle: parts.join('\n'),
            onRetry: () => _scheduleMaybeBindLikeStreams(),
          );
        }

        final mutualMaps =
            LikeService.mutualLikeRows(sent: sent, received: recv);
        debugPrint('MUTUAL COUNT=${mutualMaps.length}');

        final mutualUserIds = mutualMaps
            .map(idFromSent)
            .where((id) => id.isNotEmpty)
            .toList();
        final shown = mutualUserIds.take(_mutualVisible).toList();
        final canLoadMore = shown.length < mutualUserIds.length;

        if (mutualUserIds.isEmpty) {
          return _emptyState(
            icon: Icons.favorite,
            title: 'No Mutual Matches Yet',
            subtitle: 'When both users like each other, matches appear here',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await refreshProfiles();
          },
          child: ListView.builder(
            padding: _matchesScrollListPadding(),
            itemCount: shown.length + (canLoadMore ? 1 : 0),
            itemBuilder: (_, index) {
              if (canLoadMore && index >= shown.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _mutualVisible = (_mutualVisible + _mutualPageSize)
                              .clamp(0, mutualUserIds.length);
                        });
                      },
                      child: Text(
                          'Load more (${mutualUserIds.length - shown.length})'),
                    ),
                  ),
                );
              }

              final matchedUserId = shown[index];
              return _MutualMatchTile(
                key: ValueKey<String>(
                    'mutual_${matchedUserId.trim().toLowerCase()}'),
                userId: matchedUserId,
                name: '',
                profileId: '',
                index: index,
                onTap: () => _openUser(matchedUserId),
                onDismiss: () {},
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 60 * index))
                  .slideX(begin: 0.06);
            },
          ),
        );
      },
    );
  }

  void _showUnlikeDialog(String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlike'),
        content: const Text(
          'Remove this profile from your likes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // 🔥 FIX: Use cached service reference and capture before any await
              final likeSvc = context.read<LikeService>();
              Navigator.pop(context);
              try {
                await likeSvc.unlikeUser(targetUserId: userId);
              } catch (e) {
                if (context.mounted) {
                  AppError.showError(
                    context,
                    AppError.firebaseWriteMessage(e),
                  );
                }
              }
            },
            child: const Text(
              'Unlike',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AC.textMuted(context)),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                    )),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AC.textSub(context)),
                  textAlign: TextAlign.center),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LikedYouTile
// Renders a "Liked You" card using data already enriched by
// getWhoLikedMe(). Shows the enriched name immediately (no spinner),
// then upgrades to full profile details once the user doc loads.
// ─────────────────────────────────────────────────────────────────────────────

class _LikedYouTile extends StatefulWidget {
  final String userId;
  final String? name; // pre-enriched from getWhoLikedMe
  final String profileId;
  final List<String> previewChips;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _LikedYouTile({
    super.key,
    required this.userId,
    required this.name,
    required this.profileId,
    this.previewChips = const [],
    required this.index,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_LikedYouTile> createState() => _LikedYouTileState();
}

class _LikedYouTileState extends State<_LikedYouTile> {
  Future<app_models.User?>? _userFuture;

  @override
  void initState() {
    super.initState();
    if (widget.userId.isNotEmpty) {
      _userFuture = _fetchUser(widget.userId);
    }
  }

  @override
  void didUpdateWidget(_LikedYouTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.profileId != widget.profileId) {
      _userFuture = widget.userId.isNotEmpty ? _fetchUser(widget.userId) : null;
    }
  }

  Future<app_models.User?> _fetchUser(String uid) async {
    if (uid.isEmpty) return null;
    final auth = context.read<AuthService>();
    return _cachedResolveMatchUser(
      auth: auth,
      uid: uid,
      fallbackProfileId: widget.profileId,
    ).timeout(const Duration(seconds: 12), onTimeout: () => null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<app_models.User?>(
      future: _userFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint(
              '❌ _LikedYouTile: Error loading user ${widget.userId}: ${snap.error}');
        }

        final user = snap.data;
        final profile = user?.profile;

        // Display name: prefer full profile, then enriched name, then 'User'
        String displayName;
        if (profile?.firstName != null && profile!.firstName.isNotEmpty) {
          displayName = '${profile.firstName} ${profile.lastName}'.trim();
        } else if (widget.name?.isNotEmpty == true) {
          displayName = widget.name!;
        } else if (widget.profileId.isNotEmpty) {
          displayName = widget.profileId;
        } else if (widget.userId.isNotEmpty) {
          displayName = widget.userId;
        } else {
          displayName = 'User';
        }

        final pid = (user?.profileId.isNotEmpty ?? false)
            ? user!.profileId
            : widget.profileId;

        final chips = <String>[];
        if (profile?.age != null) chips.add('${profile!.age} yrs');
        if (profile?.city != null && profile!.city!.isNotEmpty) {
          chips.add(profile.city!);
        }
        if (profile?.occupation != null && profile!.occupation!.isNotEmpty) {
          chips.add(profile.occupation!);
        } else if (chips.isEmpty && widget.previewChips.isNotEmpty) {
          chips.addAll(widget.previewChips);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AC.border(context).withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Avatar ──────────────────────────────────
                  OnlineStatusOverlay(
                    userId: widget.userId,
                    dotSize: 11,
                    alignment: Alignment.bottomRight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.sacredGreen.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AC.border(context)),
                          ),
                          child: profile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: ProfilePhoto(
                                    profile: user!.profileForDiscovery,
                                    ownerUserId: user.id,
                                    ownerUserDoc:
                                        user.discoveryPhotoFirestoreMap(),
                                    size: 64,
                                    imageAlignment: Alignment.topCenter,
                                    isPremiumViewer: context
                                            .read<AuthService>()
                                            .currentUser
                                            ?.membership
                                            .isPremium ??
                                        false,
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.sacredGreen,
                                    ),
                                  ),
                                ),
                        ),
                        if (user != null)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: MembershipBadgeChip(
                              isPremium: user.isPremium,
                              compact: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Info ────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AC.text(context),
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Profile ID badge
                        if (pid.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGold.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppTheme.primaryGold.withAlpha(60)),
                            ),
                            child: Text(pid,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.templeGold,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],

                        // Detail chips
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: chips
                                .map((c) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            AppTheme.sacredGreen.withAlpha(15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(c,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.sacredGreen,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                        ],

                        // Badge
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.sacredGreen.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Liked → You',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.sacredGreen,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),

                  // ── Actions ─────────────────────────────────
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_right,
                            color: AC.textMuted(context)),
                        onPressed: widget.onTap,
                        tooltip: 'View Profile',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 60,
                        height: 28,
                        child: Material(
                          color: AC.textMuted(context).withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.close_rounded,
                                      size: 10, color: AC.textMuted(context)),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      'Dismiss',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: AC.textMuted(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UserProfileTile
// Fetches full user data by userId and displays name, profile ID, photo,
// age/location/occupation plus an action button (Withdraw / Dismiss).
// ─────────────────────────────────────────────────────────────────────────────

class UserProfileTile extends StatefulWidget {
  final String userId;
  /// Profile fields merged by [LikeServiceV2] (name, age, city) for fast paint.
  final Map<String, dynamic>? likePreview;
  final String badgeText;
  final Color badgeColor;
  final bool showOnline;
  final int index;
  final String actionLabel;
  final IconData actionIcon;
  final Color actionColor;
  final VoidCallback onAction;
  final VoidCallback onTap;

  const UserProfileTile({
    super.key,
    required this.userId,
    this.likePreview,
    required this.badgeText,
    required this.badgeColor,
    required this.showOnline,
    required this.index,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionColor,
    required this.onAction,
    required this.onTap,
  });

  @override
  State<UserProfileTile> createState() => UserProfileTileState();
}

class UserProfileTileState extends State<UserProfileTile> {
  late Future<app_models.User?> _userFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = _fetchUser(widget.userId);
  }

  /// Try fetching by Firebase UID first; if that returns null (e.g. doc stored
  /// under profileId), fall back to getUserByProfileId so "Liked You" tiles
  /// always resolve the full profile instead of showing "Unknown".
  Future<app_models.User?> _fetchUser(String userId) async {
    if (userId.isEmpty) return null;
    final auth = context.read<AuthService>();
    return _cachedResolveMatchUser(auth: auth, uid: userId)
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
  }

  Map<String, dynamic>? get _effectivePreview {
    final fromWidget = widget.likePreview;
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    return LikeServiceV2().cachedProfilePreview(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _effectivePreview;
    return FutureBuilder<app_models.User?>(
      future: _userFuture,
      builder: (context, snap) {
        final user = snap.data;
        final profile = user?.profile;
        final loading =
            snap.connectionState == ConnectionState.waiting && user == null;

        // ── Avatar ─────────────────────────────────────────
        Widget avatar = Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: widget.badgeColor.withAlpha(20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AC.border(context), width: 1),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : (profile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: ProfilePhoto(
                        profile: user!.profileForDiscovery,
                        ownerUserId: user.id,
                        ownerUserDoc: user.discoveryPhotoFirestoreMap(),
                        size: 64,
                        imageAlignment: Alignment.topCenter,
                        isPremiumViewer: context
                                .read<AuthService>()
                                .currentUser
                                ?.membership
                                .isPremium ??
                            false,
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.person,
                        size: 28,
                        color: widget.badgeColor.withAlpha(120),
                      ),
                    )),
        );

        if (!loading && user != null) {
          avatar = Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                bottom: 2,
                left: 2,
                child: MembershipBadgeChip(
                  isPremium: user.isPremium,
                  compact: true,
                ),
              ),
            ],
          );
        }

        if (widget.showOnline) {
          avatar = OnlineStatusOverlay(
            userId: widget.userId,
            dotSize: 11,
            alignment: Alignment.bottomRight,
            child: avatar,
          );
        }

        // ── Name / details ─────────────────────────────────
        final displayName = profile != null
            ? '${profile.firstName} ${profile.lastName}'.trim()
            : (preview != null
                ? _likeRowDisplayName(preview)
                : (loading ? 'Loading…' : 'User'));

        var profileId = user?.profileId ?? '';
        if (profileId.isEmpty && preview != null) {
          profileId = (preview[Fields.profileId] ?? preview['profile_id'] ?? '')
              .toString()
              .trim();
        }

        final chips = profile != null
            ? <String>[
                if (profile.age != null) '${profile.age} yrs',
                if (profile.city != null && profile.city!.isNotEmpty)
                  profile.city!,
                if (profile.occupation != null &&
                    profile.occupation!.isNotEmpty)
                  profile.occupation!,
              ]
            : (preview != null ? _likeRowDetailChips(preview) : <String>[]);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AC.border(context).withAlpha(80)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Photo ───────────────────────────────
                  avatar,
                  const SizedBox(width: 12),

                  // ── Info ────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AC.text(context),
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Profile ID badge
                        if (profileId.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGold.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppTheme.primaryGold.withAlpha(60)),
                            ),
                            child: Text(profileId,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.templeGold,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],

                        // Age / city / occupation chips
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: chips
                                .map((c) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: widget.badgeColor.withAlpha(15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(c,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: widget.badgeColor,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                        ],

                        // Badge
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.badgeColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(widget.badgeText,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: widget.badgeColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),

                  // ── Action button ────────────────────────
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View profile arrow
                      IconButton(
                        icon: Icon(Icons.chevron_right,
                            color: AC.textMuted(context)),
                        onPressed: widget.onTap,
                        tooltip: 'View Profile',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 4),
                      // Unlike / Dismiss button
                      SizedBox(
                        width: 60,
                        height: 28,
                        child: Material(
                          color: widget.actionColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: widget.onAction,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(widget.actionIcon,
                                      size: 10, color: widget.actionColor),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      widget.actionLabel,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: widget.actionColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )
            .animate()
            .fadeIn(delay: Duration(milliseconds: 60 * widget.index))
            .slideX(begin: 0.06);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MutualMatchTile
// Renders a mutual match card where both users are interested
// ─────────────────────────────────────────────────────────────────────────────

class _MutualMatchTile extends StatefulWidget {
  final String userId;
  final String? name; // pre-enriched from mutual matches
  final String profileId;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _MutualMatchTile({
    super.key,
    required this.userId,
    required this.name,
    required this.profileId,
    required this.index,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_MutualMatchTile> createState() => _MutualMatchTileState();
}

class _MutualMatchTileState extends State<_MutualMatchTile> {
  Future<app_models.User?>? _userFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = _fetchUser(widget.userId);
  }

  @override
  void didUpdateWidget(_MutualMatchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.profileId != widget.profileId) {
      _userFuture = widget.userId.isNotEmpty ? _fetchUser(widget.userId) : null;
    }
  }

  Future<app_models.User?> _fetchUser(String uid) async {
    if (uid.isEmpty) return null;
    final auth = context.read<AuthService>();
    return _cachedResolveMatchUser(
      auth: auth,
      uid: uid,
      fallbackProfileId: widget.profileId,
    ).timeout(const Duration(seconds: 12), onTimeout: () => null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<app_models.User?>(
      future: _userFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint(
              '❌ _MutualMatchTile: Error loading user ${widget.userId}: ${snap.error}');
        }

        final user = snap.data;
        final profile = user?.profile;

        // Display name: prefer full profile, then enriched name, then 'User'
        String displayName;
        if (profile?.firstName != null && profile!.firstName.isNotEmpty) {
          displayName = '${profile.firstName} ${profile.lastName}'.trim();
        } else if (widget.name?.isNotEmpty == true) {
          displayName = widget.name!;
        } else if (widget.profileId.isNotEmpty) {
          displayName = widget.profileId;
        } else if (widget.userId.isNotEmpty) {
          displayName = widget.userId;
        } else {
          displayName = 'User';
        }

        final pid = (user?.profileId.isNotEmpty ?? false)
            ? user!.profileId
            : widget.profileId;

        final chips = <String>[];
        if (profile?.age != null) chips.add('${profile!.age} yrs');
        if (profile?.city != null && profile!.city!.isNotEmpty) {
          chips.add(profile.city!);
        }
        if (profile?.occupation != null && profile!.occupation!.isNotEmpty) {
          chips.add(profile.occupation!);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AC.border(context).withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Avatar ──────────────────────────────────
                  OnlineStatusOverlay(
                    userId: widget.userId,
                    dotSize: 11,
                    alignment: Alignment.bottomRight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.sacredGreen.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AC.border(context)),
                          ),
                          child: profile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: ProfilePhoto(
                                    profile: user!.profileForDiscovery,
                                    ownerUserId: user.id,
                                    ownerUserDoc:
                                        user.discoveryPhotoFirestoreMap(),
                                    size: 64,
                                    imageAlignment: Alignment.topCenter,
                                    isPremiumViewer: context
                                            .read<AuthService>()
                                            .currentUser
                                            ?.membership
                                            .isPremium ??
                                        false,
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.sacredGreen,
                                    ),
                                  ),
                                ),
                        ),
                        if (user != null)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: MembershipBadgeChip(
                              isPremium: user.isPremium,
                              compact: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Info ────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name with mutual badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AC.text(context),
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGold.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppTheme.primaryGold.withAlpha(40),
                                    width: 1),
                              ),
                              child: Text(
                                'MUTUAL',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AC.textSub(context),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),

                        // Profile ID badge
                        if (pid.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGold.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppTheme.primaryGold.withAlpha(50)),
                            ),
                            child: Text(pid,
                                style: const TextStyle(
                                    color: AppTheme.templeGold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],

                        // Chips
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: chips
                                .map((chip) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            AppTheme.primaryGold.withAlpha(20),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: AppTheme.primaryGold
                                                .withAlpha(40),
                                            width: 1),
                                      ),
                                      child: Text(chip,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AC.textSub(context),
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
            .animate()
            .fadeIn(delay: Duration(milliseconds: 60 * widget.index))
            .slideX(begin: 0.06);
      },
    );
  }
}
