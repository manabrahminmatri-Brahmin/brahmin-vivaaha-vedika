import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../features/auth/auth_controller.dart';
import '../core/app_router.dart';
import '../core/app_initializer.dart';
import '../services/block_service.dart';
import '../core/profile_completion_policy.dart';
import '../screens/home/home_screen.dart';
import '../screens/auth/auth_selection_screen.dart';
import '../screens/auth/existing_user_login_screen.dart';
import '../screens/profile/profile_wizard_screen.dart';
import '../screens/auth/mpin_setup_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_gate.dart';
import 'optimized_splash_screen.dart';

/// One job: decide which screen to show on app start.
///
/// Logic (in order):
///   1. Firebase already initialized in main.dart (use existing instance)
///   2. Read prefs (fresh from disk)
///   3. Explicit logout? → AuthSelection
///   4. user_logged_in + current_user_id present? → load user → route
///   5. Nothing? → AuthSelection (new install)
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _route;
  bool _selfHealAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      // ✅ Firebase already initialized in main.dart - no duplicate initialization
      debugPrint('✅ Using existing Firebase instance');

      // 1. Fresh prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final loggedOut = prefs.getBool('user_explicitly_logged_out') ?? false;
      var isLoggedIn = prefs.getBool('user_logged_in') ?? false;
      var userId = prefs.getString('current_user_id') ?? '';
      final isAdmin    = prefs.getBool('is_admin_user') ?? false;
      final adminUserId = prefs.getString('admin_user_id') ?? '';
      final mpinDone   = prefs.getBool('mpin_setup_complete') ?? false;
      final mpinVerified = prefs.getBool('mpin_verified') ?? false;
      final appLocked = prefs.getBool('app_locked') ?? false;
      final hasLogoutMarker = prefs.getInt('logout_timestamp') != null;
      var profileDone = prefs.getBool('profile_complete') ?? false;
      if (isLoggedIn && userId.isNotEmpty && mpinDone && !profileDone) {
        // Only hit the network when the device may still be on an old/incomplete wizard state.
        // Avoids blocking every cold start for users who already completed the profile here.
        final liveProfileDone =
            await ProfileCompletionPolicy.isProfileDoneForUserDoc(userId);
        profileDone = profileDone || liveProfileDone;
        await prefs.setBool('profile_complete', profileDone);
      }

      // Match NavigationService: admin flag only applies to this Firestore user id.
      // SECURITY FIX: Require both admin flag AND matching user ID to prevent unauthorized access
      final isAdminForThisUser = isAdmin &&
          userId.isNotEmpty &&
          adminUserId.isNotEmpty &&
          adminUserId == userId;

      debugPrint('🚀 START: loggedOut=$loggedOut isLoggedIn=$isLoggedIn '
          'userId=$userId isAdmin=$isAdmin adminUid=$adminUserId '
          'mpin=$mpinDone profile=$profileDone');

      // One-time startup self-heal:
      // If logout was NOT explicit and identity keys are missing while Firebase
      // has a live auth session, try restoring session from Firestore.
      final hasFirebaseSession = fb_auth.FirebaseAuth.instance.currentUser != null;
      final identityMissing = userId.isEmpty;
      final shouldSelfHeal =
          !loggedOut &&
          !_selfHealAttempted &&
          hasFirebaseSession &&
          identityMissing;
      if (shouldSelfHeal) {
        _selfHealAttempted = true;
        debugPrint('🩹 AuthWrapper self-heal: attempting session restore');
        if (mounted) {
          final auth = context.read<AuthController>();
          try {
            final healed = await auth
                .restoreSessionFromFirebaseAuth()
                .timeout(const Duration(seconds: 8), onTimeout: () => false);
            if (healed) {
              await prefs.reload();
              isLoggedIn = prefs.getBool('user_logged_in') ?? true;
              userId = prefs.getString('current_user_id') ?? auth.currentUser?.id ?? '';
              if (userId.isNotEmpty) {
                await prefs.setBool('user_logged_in', true);
                await prefs.remove('user_explicitly_logged_out');
              }
              debugPrint('✅ AuthWrapper self-heal success: userId=$userId');
            } else {
              debugPrint('⚠️ AuthWrapper self-heal failed (no restored user)');
            }
          } catch (e) {
            debugPrint('⚠️ AuthWrapper self-heal error: $e');
          }
        }
      }

      // 3. Explicit logout → must log in again
      if (loggedOut || !isLoggedIn || userId.isEmpty) {
        debugPrint('→ AuthSelection');
        _go(Routes.authSelection);
        return;
      }

      // 4. Known user with MPIN — ask for MPIN/biometric on fresh app entry.
      // The login screen has a remembered-user mode, so it will not ask mobile again.
      if (mpinDone &&
          userId.isNotEmpty &&
          (appLocked || hasLogoutMarker || !mpinVerified)) {
        debugPrint('→ Remembered MPIN Login');
        await prefs.setBool('app_locked', true);
        await prefs.setBool('mpin_verified', false);
        _go(Routes.login);
        return;
      }

      // 5. Logged-in user — load their data
      if (!mounted) return;
      final auth = context.read<AuthController>();
      try {
        await auth.initialize().timeout(const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('⚠️ auth init timeout - proceeding with cached state');
            });
      } catch (e) {
        debugPrint('⚠️ Auth init error (non-fatal): $e');
        // Don't redirect to login on network/initialization errors
        // The app will show the home screen and retry in background
      }
      if (!mounted) return;

      // 5. Route based on saved state (even if initialization had errors)
      if (isAdminForThisUser) {
        debugPrint('→ Admin Dashboard');
        _go(Routes.adminDashboard);
      } else if (!mpinDone) {
        debugPrint('→ MPIN Setup');
        _go(Routes.mpinSetup);
      } else if (!profileDone) {
        debugPrint('→ Profile Wizard');
        _go(Routes.profileWizard);
      } else {
        debugPrint('→ Home');
        _go(Routes.home);
        // Identity / auth_uid sync runs after first frame so login → Home feels fast;
        // screens that depend on Identity still call AppInitializer.initialize() themselves.
        unawaited(_runDeferredAppInitialization());
      }
    } catch (e) {
      debugPrint('❌ AuthWrapper critical error: $e');
      // Only go to login on critical errors, not network/timing issues
      _go(Routes.authSelection);
    }
  }

  Future<void> _runDeferredAppInitialization() async {
    try {
      final initResult = await AppInitializer.initialize();
      if (initResult.isError) {
        debugPrint(
          '⚠️ Deferred AppInitializer: ${initResult.message}',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id') ?? '';
      if (!mounted) return;
      if (userId.isNotEmpty) {
        final blockService = context.read<BlockService>();
        await blockService.syncFromFirestore(blockerDocId: userId);
      }
    } catch (e) {
      debugPrint('⚠️ Deferred AppInitializer error: $e');
    }
  }

  void _go(String r) {
    if (!mounted) return;
    setState(() => _route = r);
  }

  @override
  Widget build(BuildContext context) {
    if (_route == null) return const OptimizedSplashScreen();
    return switch (_route) {
      Routes.login          => const ExistingUserLoginScreen(),
      Routes.home           => const HomeScreen(),
      Routes.mpinSetup      => const MpinSetupScreen(),
      Routes.profileWizard  => const ProfileWizardScreen(),
      Routes.adminDashboard => AdminGate(child: const AdminDashboardScreen()),
      _                     => const AuthSelectionScreen(),
    };
  }
}
