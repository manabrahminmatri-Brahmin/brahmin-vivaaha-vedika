import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/auth_selection_screen.dart';
import '../screens/auth/disclaimer_screen.dart';
import '../screens/auth/existing_user_login_screen.dart';
import '../screens/auth/forgot_mpin_screen.dart';
import '../screens/auth/mpin_setup_screen.dart';
import '../screens/discover/discover_carousel_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/interests/interests_analytics_screen.dart';
import '../screens/matches/matches_screen.dart';
import '../screens/matches/liked_screen_v2.dart';
import '../screens/matches/success_stories_screen.dart';
import '../screens/payment/premium_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/profile/my_profile_screen.dart';
import '../screens/analytics/profile_analytics_screen.dart';
import '../screens/profile/profile_incomplete_screen.dart';
import '../screens/profile/profile_wizard_screen.dart';
import '../screens/profile/who_saw_your_profile_screen.dart';
import '../screens/settings/about_screen.dart';
import '../screens/settings/blocked_profiles_screen.dart';
import '../screens/settings/change_mpin_screen.dart';
import '../screens/settings/delete_profile_screen.dart';
import '../screens/settings/font_settings_screen.dart';
import '../screens/settings/help_support_screen.dart';
import '../screens/support/support_chat_screen.dart';
import '../screens/settings/matching_preferences_screen.dart';
import '../screens/settings/notification_settings_screen.dart';
import '../screens/settings/privacy_policy_screen.dart';
import '../screens/settings/privacy_settings_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/search/filter_screen.dart';
import '../screens/settings/terms_screen.dart';
import '../screens/settings/payment_refund_policy_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_gate.dart';
import '../services/admin_service.dart';
import '../widgets/auth_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route names — one canonical string per destination, used everywhere.
// Never write a raw '/string' anywhere else in the app.
// ─────────────────────────────────────────────────────────────────────────────
abstract class Routes {
  Routes._();

  static const String splash = '/';
  static const String home = '/home';
  static const String authSelection = '/auth-selection';
  static const String login = '/login';
  static const String register = '/register';
  static const String mpinSetup = '/mpin-setup';
  static const String forgotMpin = '/forgot-mpin';
  static const String disclaimer = '/disclaimer';
  static const String onboarding = '/onboarding';

  static const String profileWizard = '/profile-wizard';
  static const String profileIncomplete = '/profile-incomplete';
  static const String myProfile = '/my-profile';
  static const String profileAnalytics = '/profile-analytics';
  static const String whoSawProfile = '/who-saw-profile';

  static const String matches = '/matches';
  static const String liked = '/liked';
  static const String successStories = '/success-stories';
  static const String interests = '/interests';
  static const String messages = '/messages';
  static const String notifications = '/notifications';

  static const String settings = '/settings';
  // BUG 7 FIX: Add About route so it's reachable via named navigation.
  static const String about = '/about';
  static const String deleteProfile = '/delete-profile';
  static const String changeMpin = '/change-mpin';
  static const String privacySettings = '/privacy-settings';
  static const String privacyPolicy = '/privacy-policy';
  static const String terms = '/terms';

  /// In-app purchases / manual UPI — refund & billing (Play policy).
  static const String paymentRefundPolicy = '/payment-refund-policy';
  static const String helpSupport = '/help-support';
  static const String supportChat = '/support-chat';
  static const String notificationSettings = '/notification-settings';
  static const String blockedProfiles = '/blocked-profiles';
  static const String matchingPreferences = '/matching-preferences';
  static const String filterSettings = '/filter-settings';
  static const String fontSettings = '/font-settings';

  static const String premiumUpgrade = '/premium-upgrade';
  static const String discoverCarousel = '/discover-carousel';
  static const String adminDashboard = '/admin';
  static const String adminDebug = '/admin-debug';
  static const String apiKeyDebug = '/api-key-debug';

  // FIX B5: Canonical set of all valid named routes including legacy aliases.
  // NavigationService._isValidRoute() uses this to validate route names.
  // Keep in sync whenever a new route is added above.
  static const Set<String> allRoutes = {
    splash, home,
    authSelection, '/auth', // '/auth' is legacy alias
    login, '/mpin-login', // '/mpin-login' is legacy alias
    register,
    mpinSetup, '/setup-mpin', // '/setup-mpin' is legacy alias
    forgotMpin,
    disclaimer,
    onboarding, '/welcome', // '/welcome' is legacy alias
    profileWizard,
    profileIncomplete,
    myProfile, '/profile', // '/profile' is legacy alias
    profileAnalytics,
    whoSawProfile,
    matches, liked, successStories,
    interests, messages, notifications,
    settings, about,
    deleteProfile, changeMpin,
    privacySettings, privacyPolicy, terms, paymentRefundPolicy,
    helpSupport, supportChat, notificationSettings,
    blockedProfiles, matchingPreferences, filterSettings, fontSettings,
    premiumUpgrade,
    discoverCarousel,
    adminDashboard,
    adminDebug,
    apiKeyDebug,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Transition types — what animation each route group uses
// ─────────────────────────────────────────────────────────────────────────────
enum TransitionType { slide, slideUp, fade, fadeScale }

// ─────────────────────────────────────────────────────────────────────────────
// AppRouter — call AppRouter.onGenerateRoute from MaterialApp
// ─────────────────────────────────────────────────────────────────────────────
class AppRouter {
  AppRouter._();

  /// Global RouteObserver — subscribe in any State using RouteAware to get
  /// notified when a pushed route is popped back to this screen (didPopNext).
  /// Register it in MaterialApp.navigatorObservers (done in main.dart).
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  // Transition timing — one place to tune the whole app
  static const Duration _duration = Duration(milliseconds: 300);
  static const Duration _reverseDuration = Duration(milliseconds: 250);
  static const Curve _curve = Curves.easeInOutCubic;

  // Which transition does each route use?
  static const Map<String, TransitionType> _transitionMap = {
    // Auth flow — slide right (forward journey)
    Routes.authSelection: TransitionType.fade,
    Routes.disclaimer: TransitionType.slide,
    Routes.login: TransitionType.slide,
    Routes.register: TransitionType.slide,
    Routes.mpinSetup: TransitionType.slide,
    Routes.forgotMpin: TransitionType.slide,
    Routes.onboarding: TransitionType.fade,

    // Core screens — fade (tab-like, no directional feel)
    Routes.home: TransitionType.fade,
    Routes.matches: TransitionType.fade,
    Routes.interests: TransitionType.fade,
    Routes.messages: TransitionType.fade,
    Routes.notifications: TransitionType.fade,

    // Profile — slide (detail drill-down)
    Routes.profileWizard: TransitionType.slide,
    Routes.myProfile: TransitionType.slide,
    Routes.profileAnalytics: TransitionType.slide,
    Routes.whoSawProfile: TransitionType.slide,
    Routes.profileIncomplete: TransitionType.fade,

    // Matches / social
    Routes.liked: TransitionType.slide,
    Routes.successStories: TransitionType.slide,

    // Settings — slide
    Routes.settings: TransitionType.slide,
    Routes.about: TransitionType.slide, // BUG 7 FIX
    Routes.deleteProfile: TransitionType.slide,
    Routes.changeMpin: TransitionType.slide,
    Routes.privacySettings: TransitionType.slide,
    Routes.privacyPolicy: TransitionType.slide,
    Routes.terms: TransitionType.slide,
    Routes.paymentRefundPolicy: TransitionType.slide,
    Routes.helpSupport: TransitionType.slide,
    Routes.supportChat: TransitionType.slide,
    Routes.notificationSettings: TransitionType.slide,
    Routes.blockedProfiles: TransitionType.slide,
    Routes.matchingPreferences: TransitionType.slide,
    Routes.filterSettings: TransitionType.slide,
    Routes.fontSettings: TransitionType.slide,

    // Premium — slide transition (matches Settings → About screen pattern)
    Routes.premiumUpgrade: TransitionType.slide,
    Routes.discoverCarousel: TransitionType.fade,
    Routes.adminDashboard: TransitionType.slide,
    Routes.adminDebug: TransitionType.fade,
  };

  /// Called by MaterialApp.onGenerateRoute — handles every named push.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final page = _buildPage(settings);
    if (page == null) return _notFound(settings.name);

    final type = _transitionMap[settings.name] ?? TransitionType.slide;
    return _buildRoute(page: page, settings: settings, type: type);
  }

  // ── Page factory ───────────────────────────────────────────────────────────
  static Widget? _buildPage(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case Routes.splash:
        return const AuthWrapper();
      case Routes.home:
        return const HomeScreen();
      case Routes.authSelection:
      case '/auth': // legacy alias
        return const AuthSelectionScreen();
      case Routes.login:
      case '/mpin-login': // legacy alias
        return const ExistingUserLoginScreen();
      case Routes.register:
        return const DisclaimerScreen();
      case Routes.mpinSetup:
      case '/setup-mpin': // legacy alias
        return const MpinSetupScreen();
      case Routes.forgotMpin:
        // BUG 28 FIX: Accept optional prefillMobile arg so the route can
        // pre-fill the mobile field when redirected from the login screen.
        final prefillMobile = (args is Map<String, dynamic>)
            ? args['prefillMobile'] as String?
            : null;
        return ForgotMpinScreen(prefillMobile: prefillMobile);
      case Routes.disclaimer:
        return const DisclaimerScreen();
      case Routes.onboarding:
      case '/welcome': // legacy alias
        return const OnboardingScreen();

      case Routes.profileWizard:
        if (args is Map<String, dynamic>) {
          // BUG 17 FIX: Clamp initialStep so an out-of-range value never crashes
          // the PageController. Valid range: 0–5 (6 steps total).
          final rawStep = args['initialStep'] as int? ?? 0;
          return ProfileWizardScreen(
            isEditMode: args['isEditMode'] as bool? ?? false,
            initialStep: rawStep.clamp(0, 5),
          );
        }
        return const ProfileWizardScreen();
      case Routes.myProfile:
      case '/profile': // legacy alias
        return const MyProfileScreen();
      case Routes.profileAnalytics:
        // Redirects to InterestsAnalyticsScreen(initialTabIndex: 0) — unified analytics hub.
        return const ProfileAnalyticsScreen();
      case Routes.whoSawProfile:
        return const WhoSawYourProfileScreen();
      case Routes.profileIncomplete:
        return const ProfileIncompleteScreen();

      case Routes.matches:
        return const MatchesScreen();
      case Routes.liked:
        return const LikedScreenV2();
      case Routes.successStories:
        return const SuccessStoriesScreen();
      case Routes.interests:
        final initialTab = args is Map && args['initialTabIndex'] is int
            ? (args['initialTabIndex'] as int)
            : 0;
        return InterestsAnalyticsScreen(initialTabIndex: initialTab);
      case Routes.messages:
        // MessagesScreen builds InterestsAnalyticsScreen(initialTabIndex: 3); see messages_screen.dart.
        return const MessagesScreen();
      case Routes.notifications:
        return const NotificationsScreen();

      case Routes.settings:
        return const SettingsScreen();
      // BUG 7 FIX: AboutScreen is now a proper named route.
      case Routes.about:
        return const AboutScreen();
      case Routes.deleteProfile:
        return const DeleteProfileScreen();
      case Routes.changeMpin:
        return const ChangeMpinScreen();
      case Routes.privacySettings:
        return const PrivacySettingsScreen();
      case Routes.privacyPolicy:
        return const PrivacyPolicyScreen();
      case Routes.terms:
        return const TermsScreen();
      case Routes.paymentRefundPolicy:
        return const PaymentRefundPolicyScreen();
      case Routes.helpSupport:
        return const HelpSupportScreen();
      case Routes.supportChat:
        return const SupportChatScreen();
      case Routes.notificationSettings:
        return const NotificationSettingsScreen();
      case Routes.blockedProfiles:
        return const BlockedProfilesScreen();
      case Routes.matchingPreferences:
        // BUG 20 FIX: The previous onSave was a no-op `(_) {}` that silently
        // discarded every preference change. Now the preferences are saved and
        // the screen pops — MatchesScreen re-queries via its service listener.
        return MatchingPreferencesScreen(
          onSave: (_) {
            // Preferences already persisted inside MatchingPreferencesScreen.
            // Just pop — the caller (MatchesScreen / Settings) re-queries.
          },
        );

      case Routes.filterSettings:
        return const FilterSettingsScreen();

      case Routes.fontSettings:
        return const FontSettingsScreen();

      case Routes.premiumUpgrade:
        return const PremiumScreen();
      case Routes.discoverCarousel:
        return const DiscoverCarouselScreen();

      case Routes.adminDashboard:
        // AdminGate enforces 3-layer security:
        //   1. Firestore is_admin flag
        //   2. Separate 6-digit Admin MPIN (FlutterSecureStorage)
        //   3. 5-minute session timeout with auto-lock
        return AdminGate(
          child: ChangeNotifierProvider<AdminService>.value(
            value: AdminService.instance,
            child: const AdminDashboardScreen(),
          ),
        );

      case Routes.adminDebug:
        if (kDebugMode) {
          return const _ReleaseOnlyBlockedPage(
            title: 'Debug Disabled',
            message: 'Debug widgets have been removed for production.',
          );
        }
        return const _ReleaseOnlyBlockedPage(
          title: 'Unavailable',
          message: 'Debug admin tools are not included in release builds.',
        );

      case Routes.apiKeyDebug:
        if (kDebugMode) {
          return const _ReleaseOnlyBlockedPage(
            title: 'Debug Disabled',
            message: 'Debug widgets have been removed for production.',
          );
        }
        return const _ReleaseOnlyBlockedPage(
          title: 'Unavailable',
          message: 'Debug tools are not included in release builds.',
        );

      default:
        return null;
    }
  }

  // ── Route builder ──────────────────────────────────────────────────────────
  static PageRoute<T> _buildRoute<T>({
    required Widget page,
    required RouteSettings settings,
    required TransitionType type,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      opaque: true,
      pageBuilder: (context, _, __) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: page,
      ),
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return _buildTransition(
          type: type,
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
    );
  }

  static Widget _buildTransition({
    required TransitionType type,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: _curve);

    switch (type) {
      // ── Slide right (standard forward navigation) ──────────────────────────
      case TransitionType.slide:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
          // Outgoing screen slides slightly left for a parallax feel
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.15, 0.0),
            ).animate(CurvedAnimation(
              parent: secondaryAnimation,
              curve: _curve,
            )),
            child: child,
          ),
        );

      // ── Slide up from bottom (modals, wizard, sheets-as-pages) ─────────────
      case TransitionType.slideUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );

      // ── Fade (tab-like destinations with no directional meaning) ───────────
      case TransitionType.fade:
        return FadeTransition(opacity: curved, child: child);

      // ── Fade + scale (reveals, premium, special screens) ──────────────────
      case TransitionType.fadeScale:
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
    }
  }

  // ── 404 fallback ───────────────────────────────────────────────────────────
  static Route<dynamic> _notFound(String? name) {
    return _buildRoute<void>(
      settings: RouteSettings(name: name),
      type: TransitionType.fade,
      page: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Page not found\n"$name"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Release/profile builds: blocks routes that must never ship as tools.
class _ReleaseOnlyBlockedPage extends StatelessWidget {
  final String title;
  final String message;

  const _ReleaseOnlyBlockedPage({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NavHelper — drop-in replacement for all Navigator calls in the app.
// Every screen should import this and use NavHelper instead of raw Navigator.
// ─────────────────────────────────────────────────────────────────────────────
class NavHelper {
  NavHelper._();

  // ── Standard push (forward, adds to stack) ─────────────────────────────────
  static Future<T?> push<T>(BuildContext context, String route,
      {Object? args}) {
    return Navigator.of(context).pushNamed<T>(route, arguments: args);
  }

  // ── Replace current screen (login → home, no back) ────────────────────────
  static Future<T?> replace<T>(BuildContext context, String route,
      {Object? args}) {
    return Navigator.of(context)
        .pushReplacementNamed<T, dynamic>(route, arguments: args);
  }

  // ── Clear entire stack and go to route (auth logout, onboarding done) ──────
  static Future<T?> clearAndGo<T>(BuildContext context, String route,
      {Object? args}) {
    return Navigator.of(context).pushNamedAndRemoveUntil<T>(
      route,
      (r) => false,
      arguments: args,
    );
  }

  // ── Pop current screen ─────────────────────────────────────────────────────
  static void pop<T>(BuildContext context, [T? result]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<T>(result);
    }
  }

  // ── Pop until named route ──────────────────────────────────────────────────
  static void popUntil(BuildContext context, String route) {
    Navigator.of(context).popUntil(ModalRoute.withName(route));
  }

  // ── Push a widget directly (for screens that carry runtime objects) ─────────
  // Use sparingly — prefer named routes where possible.
  static Future<T?> pushWidget<T>(
    BuildContext context,
    Widget page, {
    TransitionType transition = TransitionType.slide,
  }) {
    return Navigator.of(context).push<T>(
      AppRouter._buildRoute<T>(
        page: page,
        settings: const RouteSettings(),
        type: transition,
      ),
    );
  }

  // ── Convenience aliases for widget push ───────────────────────────────────
  static Future<T?> pushSlide<T>(BuildContext context, Widget page) =>
      pushWidget<T>(context, page, transition: TransitionType.slide);

  static Future<T?> pushSlideUp<T>(BuildContext context, Widget page) =>
      pushWidget<T>(context, page, transition: TransitionType.slideUp);

  static Future<T?> pushFade<T>(BuildContext context, Widget page) =>
      pushWidget<T>(context, page, transition: TransitionType.fade);

  static Future<T?> pushFadeScale<T>(BuildContext context, Widget page) =>
      pushWidget<T>(context, page, transition: TransitionType.fadeScale);
}
