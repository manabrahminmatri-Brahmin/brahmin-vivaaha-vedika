import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_router.dart';
import '../core/profile_completion_policy.dart';
import '../core/contract.dart';
import 'secure_storage_service.dart';

/// Smart navigation service for app-flow management.
/// Use NavHelper (in app_router.dart) for direct context-based navigation.
/// Use this service only for imperative navigation (outside widget tree).

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  // FIX B4: navigatorKey must be passed to MaterialApp.navigatorKey so that
  // all imperative navigation methods below can actually push routes.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Navigation state
  String? _currentRoute;
  final Map<String, dynamic> _navigationContext = {};

  // FIX B9: Cache validity reduced to zero — route is always freshly computed
  // after any auth state change. A 5-second stale cache caused the wrong
  // route to be returned when the user logged out and back in quickly,
  // e.g. landing on /home without MPIN verification.
  String? _cachedInitialRoute;
  DateTime? _lastRouteCheck;
  static const Duration _routeCacheValidity = Duration.zero;

  // SharedPreferences cache — avoid repeated getInstance() calls
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  /// Check if current user is an admin.
  ///
  /// FIX: This app uses anonymous Firebase Auth — Firebase UID is ephemeral
  /// and does NOT match Firestore user document ID stored under
  /// 'current_user_id' in SharedPreferences. The is_admin flag lives on the
  /// app's own user document, so we must look up by the stored user ID, not
  /// by FirebaseAuth.currentUser?.uid.
  /// Public wrapper — used by external widgets (e.g. debug tools).
  /// Delegates to the private implementation.
  Future<bool> isAdminUser() => _isAdminUser();

  Future<bool> _isAdminUser() async {
    try {
      final prefs = await _getPrefs();
      // Use the app's stored Firestore doc ID — not the anonymous Firebase Auth UID
      final storedUserId = prefs.getString('current_user_id') ?? '';
      if (storedUserId.isEmpty) return false;

      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(storedUserId)
          .get();

      return doc.data()?['is_admin'] == true;
    } catch (e) {
      debugPrint('❌ Error checking admin status: $e');
      return false;
    }
  }

  // Getters
  String? get currentRoute => _currentRoute;
  Map<String, dynamic> get navigationContext => Map.unmodifiable(_navigationContext);

  /// Determine the correct initial screen on cold start.
  ///
  /// AUTH WRAPPER already handled Layer 1 (explicit logout) and Layer 2
  /// (user loaded). By the time this runs, we know:
  ///   • user_explicitly_logged_out is FALSE (wrapper checked)
  ///   • current_user_id is present in prefs (wrapper restored it)
  ///
  /// This method only decides WHICH screen to show for a logged-in user.
  /// It reads ONLY SharedPreferences — NO Firestore calls — so it never
  /// times out and never accidentally routes to /auth-selection.
  /// Returns the correct route for a user who has just logged in or reset MPIN.
  /// Reads only SharedPreferences — no Firestore calls.
  Future<String> getInitialRoute() async {
    debugPrint('🧭 getInitialRoute: Starting...');
    try {
      if (_isRouteCacheValid()) {
        debugPrint('🧭 getInitialRoute: Using cached route: $_cachedInitialRoute');
        return _cachedInitialRoute!;
      }

      final prefs = await _getPrefs();

      // Log all relevant prefs for debugging
      debugPrint('🧭 getInitialRoute: Prefs check:');
      debugPrint('🧭   current_user_id: ${prefs.getString('current_user_id') ?? "null"}');
      debugPrint('🧭   user_logged_in: ${prefs.getBool('user_logged_in')}');
      debugPrint('🧭   mpin_setup_complete: ${prefs.getBool('mpin_setup_complete')}');
      debugPrint('🧭   is_admin_user: ${prefs.getBool('is_admin_user')}');
      debugPrint('🧭   admin_user_id: ${prefs.getString('admin_user_id') ?? "null"}');

      // No stored user → auth selection
      // Check SharedPreferences first (primary storage)
      String storedId = prefs.getString('current_user_id') ?? '';
      debugPrint('🧭 getInitialRoute: storedId = $storedId');
      
      // If SharedPreferences empty, check SecureStorage fallback
      if (storedId.isEmpty) {
        try {
          final prefs = await _getPrefs();
          final secureStorage = SecureStorageService(prefs);
          storedId = await secureStorage.getCurrentUserId() ?? '';
          debugPrint('🧭 Restored user ID from SecureStorage: $storedId');
          // Sync back to SharedPreferences for consistency
          if (storedId.isNotEmpty) {
            await prefs.setString('current_user_id', storedId);
          }
        } catch (e) {
          debugPrint('🧭 Error checking SecureStorage: $e');
        }
      }

      // Admin check: must be tied to specific user ID, not global flag
      // This prevents cross-device admin access pollution
      final isAdminGlobal = prefs.getBool('is_admin_user') ?? false;
      var adminUserId = prefs.getString('admin_user_id') ?? '';

      // Legacy installs: is_admin_user was set without admin_user_id — backfill once.
      if (isAdminGlobal && adminUserId.isEmpty && storedId.isNotEmpty) {
        await prefs.setString('admin_user_id', storedId);
        adminUserId = storedId;
        debugPrint('🧭 Backfilled admin_user_id for legacy session: $storedId');
      }

      // Only route to admin if admin flag is set AND it matches current user
      debugPrint('🧭 getInitialRoute: Admin check: isAdminGlobal=$isAdminGlobal, adminUserId=$adminUserId, storedId=$storedId');
      if (isAdminGlobal && adminUserId.isNotEmpty && adminUserId == storedId) {
        debugPrint('🧭 getInitialRoute: Routing to /admin');
        return _cacheAndReturnRoute('/admin', 'admin user: $storedId');
      } else if (isAdminGlobal &&
          adminUserId.isNotEmpty &&
          adminUserId != storedId) {
        // Clear stale admin state only when a concrete admin id disagrees
        debugPrint('🧭 Clearing stale admin state - admin_user_id: $adminUserId, current_user: $storedId');
        await prefs.setBool('is_admin_user', false);
        await prefs.remove('admin_user_id');
      }

      if (storedId.isEmpty) {
        debugPrint('🧭 getInitialRoute: storedId is empty → /auth-selection');
        return _cacheAndReturnRoute('/auth-selection', 'no user');
      }

      // MPIN not set → setup screen (only for brand-new users)
      final mpinSetupComplete = prefs.getBool('mpin_setup_complete') ?? false;
      debugPrint('🧭 getInitialRoute: mpin_setup_complete=$mpinSetupComplete');
      if (!mpinSetupComplete) {
        debugPrint('🧭 getInitialRoute: Routing to /setup-mpin (MPIN not set)');
        return _cacheAndReturnRoute('/setup-mpin', 'mpin not set');
      }

      // Profile wizard routing:
      // Prefer cached completion status on restart to avoid false regressions
      // caused by transient Firestore/session timing after app updates.
      final isLoggedIn    = prefs.getBool('user_logged_in')     ?? false;
      final currentUserId = prefs.getString('current_user_id') ?? '';
      bool profileDone = prefs.getBool('profile_complete') ?? false;

      // Only query live completion when local cache still says "incomplete".
      // This allows upgrading false -> true, but prevents true -> false
      // downgrades during startup race conditions.
      if (isLoggedIn && currentUserId.isNotEmpty && !profileDone) {
        try {
          final liveProfileDone = await ProfileCompletionPolicy.isProfileDoneForUserDoc(
            currentUserId,
          );
          profileDone = profileDone || liveProfileDone;
          debugPrint(
            '🧭 profile completion resolved: profileDone=$profileDone '
            '(threshold ${ProfileCompletionPolicy.minCompletionPercentForFullApp}%)',
          );
        } catch (e) {
          debugPrint('Error checking profile completion: $e');
        }
        await prefs.setBool('profile_complete', profileDone);
      }

      debugPrint('🧭 getInitialRoute: profileDone=$profileDone, isLoggedIn=$isLoggedIn');
      if (!profileDone) {
        debugPrint('🧭 getInitialRoute: Routing to /profile-wizard (profile incomplete)');
        return _cacheAndReturnRoute('/profile-wizard', 'profile incomplete');
      }

      debugPrint('🧭 getInitialRoute: Routing to /home');
      return _cacheAndReturnRoute('/home', 'ok');
    } catch (e) {
      debugPrint('❌ getInitialRoute error: $e');
      // SECURITY FIX: Remove fallback that bypasses proper admin validation
      return '/auth-selection';
    }
  }

  String _cacheAndReturnRoute(String route, String reason) {
    _cachedInitialRoute = route;
    _lastRouteCheck = DateTime.now();
    debugPrint('🧭 Route: $route ($reason)');
    return route;
  }

  bool _isRouteCacheValid() {
    if (_routeCacheValidity == Duration.zero) return false;
    return _cachedInitialRoute != null &&
        _lastRouteCheck != null &&
        DateTime.now().difference(_lastRouteCheck!) < _routeCacheValidity;
  }

  /// Invalidate caches when user state changes (call after login / logout).
  void invalidateCaches() {
    _cachedInitialRoute = null;
    _lastRouteCheck = null;
    debugPrint('🧭 Navigation caches invalidated');
  }

  /// Navigate to the appropriate screen based on user state.
  Future<void> navigateToAppropriateScreen(BuildContext context) async {
    try {
      final route = await getInitialRoute();
      _currentRoute = route;
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed(route);
      }
    } catch (e) {
      debugPrint('❌ Error navigating to appropriate screen: $e');
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/auth-selection');
      }
    }
  }

  // FIX B5: _isValidRoute now delegates to AppRouter so the set is always
  // in sync with the actual declared routes — old hardcoded set contained
  // stale strings ('/mobile-login', '/chat', '/like') and was missing real
  // routes ('/forgot-mpin', '/delete-profile', '/premium-upgrade', etc.).
  bool _isValidRoute(String routeName) {
    // onGenerateRoute returns a _notFound fallback for unknown routes, but
    // that fallback has a page body that shows "Page not found". We treat
    // routes as valid when AppRouter can match them to a real screen. The
    // simplest proxy: check if route name is in Routes constants.
    return Routes.allRoutes.contains(routeName);
  }

  void _handleNavigationError(String routeName, Object error) {
    debugPrint('🧭 Navigation Error: route=$routeName error=$error');
    if (navigatorKey.currentState?.mounted ?? false) {
      try {
        navigatorKey.currentState?.pushReplacementNamed('/home');
      } catch (e) {
        debugPrint('❌ Even fallback navigation failed: $e');
      }
    }
  }

  /// Imperative push — use when outside a widget tree.
  Future<dynamic> navigateTo(
    String routeName, {
    Object? arguments,
  }) async {
    try {
      if (!_isValidRoute(routeName)) {
        debugPrint('🧭 Invalid route: $routeName');
        _handleNavigationError(routeName, 'Invalid route');
        return null;
      }

      if (!(navigatorKey.currentState?.mounted ?? false)) {
        debugPrint('🧭 Navigator not mounted');
        return null;
      }

      final result = await navigatorKey.currentState?.pushNamed(
        routeName,
        arguments: arguments,
      );

      _currentRoute = routeName;
      // FIX B8: guard against non-Map arguments before casting
      if (arguments is Map<String, dynamic>) {
        _navigationContext.addAll(arguments);
      }

      debugPrint('🧭 Navigated to: $routeName');
      return result;
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
      _handleNavigationError(routeName, e.toString());
      return null;
    }
  }

  /// Imperative replace — use when outside a widget tree.
  Future<dynamic> navigateAndReplace(
    String routeName, {
    Object? arguments,
  }) async {
    try {
      if (!_isValidRoute(routeName)) {
        debugPrint('🧭 Invalid route for replacement: $routeName');
        _handleNavigationError(routeName, 'Invalid route for replacement');
        return null;
      }

      if (!(navigatorKey.currentState?.mounted ?? false)) {
        debugPrint('🧭 Navigator not mounted for replacement');
        return null;
      }

      final result = await navigatorKey.currentState?.pushReplacementNamed(
        routeName,
        arguments: arguments,
      );

      _currentRoute = routeName;
      // FIX B8: guard against non-Map arguments before casting
      if (arguments is Map<String, dynamic>) {
        _navigationContext.addAll(arguments);
      }

      debugPrint('🧭 Navigated and replaced to: $routeName');
      return result;
    } catch (e) {
      debugPrint('❌ Navigation replacement error: $e');
      _handleNavigationError(routeName, e.toString());
      return null;
    }
  }

  /// Imperative clear-stack-and-go — use when outside a widget tree.
  Future<dynamic> navigateAndClearStack(
    String routeName, {
    Object? arguments,
  }) async {
    try {
      if (!_isValidRoute(routeName)) {
        debugPrint('🧭 Invalid route for stack clear: $routeName');
        _handleNavigationError(routeName, 'Invalid route for stack clear');
        return null;
      }

      if (!(navigatorKey.currentState?.mounted ?? false)) {
        debugPrint('🧭 Navigator not mounted for stack clear');
        return null;
      }

      final result = await navigatorKey.currentState?.pushNamedAndRemoveUntil(
        routeName,
        (route) => false,
        arguments: arguments,
      );

      _currentRoute = routeName;
      // FIX B8: guard against non-Map arguments before casting
      if (arguments is Map<String, dynamic>) {
        _navigationContext.addAll(arguments);
      }

      debugPrint('🧭 Navigated and cleared stack to: $routeName');
      return result;
    } catch (e) {
      debugPrint('❌ Stack clear navigation error: $e');
      _handleNavigationError(routeName, e.toString());
      return null;
    }
  }

  /// Go back to previous screen (imperative).
  void goBack() {
    try {
      if (navigatorKey.currentState?.canPop() ?? false) {
        navigatorKey.currentState!.pop();
        debugPrint('🧭 Navigated back');
      } else {
        debugPrint('🧭 Cannot go back - no route in stack');
      }
    } catch (e) {
      debugPrint('❌ Error going back: $e');
    }
  }

  /// Context-aware smart navigate (use inside widget tree).
  Future<void> smartNavigate(
    BuildContext context,
    String route, {
    Map<String, dynamic>? arguments,
    bool replace = false,
    bool clearStack = false,
  }) async {
    try {
      _currentRoute = route;
      if (arguments != null) {
        _navigationContext.addAll(arguments);
      }

      if (clearStack) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          route,
          (route) => false,
          arguments: arguments,
        );
      } else if (replace) {
        Navigator.of(context).pushReplacementNamed(route, arguments: arguments);
      } else {
        Navigator.of(context).pushNamed(route, arguments: arguments);
      }

      debugPrint('🧭 smartNavigate: $route');
    } catch (e) {
      debugPrint('❌ smartNavigate error: $e');
    }
  }

  /// Handle back navigation with smart logic (e.g. exit confirmation on home).
  Future<bool> handleBackNavigation(BuildContext context) async {
    try {
      switch (_currentRoute) {
        case '/home':
          return await _showExitConfirmation(context);
        case '/profile-wizard':
          return await _showProfileSetupExitConfirmation(context);
        default:
          return true;
      }
    } catch (e) {
      debugPrint('❌ Back navigation error: $e');
      return true;
    }
  }

  Future<bool> _showExitConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Are you sure you want to exit mana Vivaaha Vedika?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showProfileSetupExitConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Profile Setup?'),
        content: const Text(
          'Your profile setup is incomplete. Are you sure you want to leave? '
          'You can complete it later from the profile section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue Setup'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── State helpers ──────────────────────────────────────────────────

  void resetNavigation() {
    _currentRoute = null;
    _navigationContext.clear();
    _cachedInitialRoute = null;
    _lastRouteCheck = null;
    debugPrint('🧭 Navigation state reset');
  }

  Map<String, dynamic>? getCachedRouteInfo() {
    if (_isRouteCacheValid()) {
      return {
        'route': _cachedInitialRoute,
        'timestamp': _lastRouteCheck?.toIso8601String(),
        'isValid': true,
      };
    }
    return null;
  }

  void clearCache() {
    _cachedInitialRoute = null;
    _lastRouteCheck = null;
    debugPrint('🧭 Navigation cache cleared');
  }

  Map<String, dynamic> getNavigationSummary() {
    return {
      'currentRoute': _currentRoute,
      'context': _navigationContext,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

enum PageRouteAnimation { slideRight, slideUp, fade }
