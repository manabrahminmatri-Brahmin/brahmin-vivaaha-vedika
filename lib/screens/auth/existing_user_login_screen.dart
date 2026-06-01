import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user.dart';
import '../../widgets/auth/auth_bank_widgets.dart';
import '../../widgets/auth/auth_pin_fields.dart';
import '../../widgets/auth/auth_screen_shell.dart';
import 'disclaimer_screen.dart';
import '../../services/auth_service.dart';
import '../../services/admin_session_bootstrap.dart';
import '../../features/auth/local_auth_service.dart';
import '../../services/navigation_service.dart';
import '../../core/app_router.dart';
import '../../core/app_initializer.dart';
import '../../core/contract.dart';
import '../../core/result.dart';
import '../../core/identity_service.dart';
import '../../theme/app_theme.dart';
import 'forgot_mpin_screen.dart';

/// Unified login screen — same UI for every user.
///
/// Flow:
///   1. User enters 10-digit mobile → taps Continue
///      • ALL users → look up in Firestore (no hardcoded admin shortcut)
///        – NOT FOUND   → "Not registered" dialog
///        – FOUND       → "Account found" confirmation → show MPIN field
///   2. User enters 4-digit MPIN → auto-submit on 4th digit
///      • After MPIN verified → check users/{id}.is_admin in Firestore
///        – is_admin == true  → /admin dashboard
///        – is_admin != true  → /home or /profile-wizard
///      • Wrong MPIN   → error snack + clear field
///
/// Admin detection is now Firestore-based (is_admin field), not hardcoded.
class ExistingUserLoginScreen extends StatefulWidget {
  /// When true, opened from app entry — no back; footer links for register / forgot MPIN.
  final bool isEntryPoint;

  const ExistingUserLoginScreen({super.key, this.isEntryPoint = false});

  @override
  State<ExistingUserLoginScreen> createState() =>
      _ExistingUserLoginScreenState();
}

class _ExistingUserLoginScreenState extends State<ExistingUserLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _mpinController = TextEditingController();
  final _mpinPinFieldController = AuthPinFieldController();

  bool _isLoading = false;
  bool _mpinHasError = false;
  bool _userFound = false;
  bool _deviceBiometricsAvailable = false;
  String? _biometricUserId;
  String? _rememberedUserId;
  String? _rememberedName;
  String? _rememberedMobile;
  /// Name shown on MPIN screen after mobile lookup (before login completes).
  String? _loginDisplayName;
  bool _rememberedMode = false;

  String _safeMobileText() {
    if (!mounted) return '';
    try {
      return _mobileController.text.trim();
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
    _initBiometricState();
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _mpinController.dispose();
    _mpinPinFieldController.dispose();
    super.dispose();
  }

  Future<void> _initBiometricState() async {
    final service = LocalAuthService();
    final canUse = await service.canUseBiometrics();
    final userId = await service.getLastEnabledUserId();
    if (!mounted) return;
    setState(() {
      _deviceBiometricsAvailable = canUse;
      _biometricUserId = userId;
    });
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('current_user_id') ?? '').trim();
    final mobile = (prefs.getString('last_login_mobile') ?? '').trim();
    final savedName = (prefs.getString('current_user_name') ?? '').trim();
    final mpinDone = prefs.getBool('mpin_setup_complete') ?? false;
    final loggedOut = prefs.getBool('user_explicitly_logged_out') ?? false;

    if (userId.isEmpty || !mpinDone || loggedOut) return;

    var displayName = savedName;
    if (displayName.isEmpty) {
      try {
        if (!mounted) return;
        final user = await context.read<AuthService>().getUserById(userId);
        final profile = user?.profile;
        displayName = (profile?.firstName ?? '').trim();
        if (displayName.isEmpty) {
          displayName = (profile?.fullName ?? '').trim();
        }
        if (mobile.isEmpty && user != null) {
          await prefs.setString('last_login_mobile', user.mobileNumber);
        }
      } catch (e) {
        debugPrint('⚠️ remembered user lookup failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _rememberedUserId = userId;
      _rememberedName = displayName.isNotEmpty ? displayName : null;
      _rememberedMobile =
          mobile.isNotEmpty ? mobile : prefs.getString('last_login_mobile');
      _rememberedMode = true;
      _userFound = true;
      if ((_rememberedMobile ?? '').isNotEmpty) {
        _mobileController.text = _rememberedMobile!;
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: AppTheme.kumkumRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _maskedMobile(String mobile) {
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return 'your registered mobile';
    return '******${digits.substring(digits.length - 4)}';
  }

  /// First name (or full name) for MPIN greeting — skips wizard draft placeholders.
  String _resolveUserDisplayName(User? user) {
    if (user == null) return '';

    bool isPlaceholder(String s) {
      final t = s.trim().toLowerCase();
      return t.isEmpty || t == 'draft' || t == 'profile' || t == 'user';
    }

    final profile = user.profile;
    if (profile != null) {
      final first = profile.firstName.trim();
      if (!isPlaceholder(first)) return first;
      final full = profile.fullName.trim();
      if (!isPlaceholder(full) && full.toLowerCase() != 'draft profile') {
        return full;
      }
      final last = profile.lastName.trim();
      if (!isPlaceholder(last)) return last;
    }

    final fromUser = user.firstName.trim();
    if (!isPlaceholder(fromUser)) return fromUser;
    return '';
  }

  String _resolveGreetingName(BuildContext context) {
    final remembered = (_rememberedName ?? '').trim();
    if (remembered.isNotEmpty) return remembered;

    final fromLookup = (_loginDisplayName ?? '').trim();
    if (fromLookup.isNotEmpty) return fromLookup;

    return _resolveUserDisplayName(context.read<AuthService>().currentUser);
  }

  Future<void> _useAnotherMobile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_logged_in');
    await prefs.remove('mpin_verified');
    await prefs.remove('current_user_id');
    await prefs.remove('current_user_name');
    await prefs.remove('last_login_mobile');
    await prefs.setBool('user_explicitly_logged_out', true);
    NavigationService().invalidateCaches();
    if (!mounted) return;
    setState(() {
      _rememberedMode = false;
      _rememberedUserId = null;
      _rememberedName = null;
      _rememberedMobile = null;
      _loginDisplayName = null;
      _userFound = false;
      _mobileController.clear();
      _mpinController.clear();
      _mpinHasError = false;
    });
  }

  /// MPIN screen → mobile entry (remembered user clears saved session).
  Future<void> _returnToMobileEntry() async {
    if (_isLoading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_rememberedMode) {
      await _useAnotherMobile();
      return;
    }
    if (!mounted) return;
    setState(() {
      _userFound = false;
      _loginDisplayName = null;
      _mpinController.clear();
      _mpinHasError = false;
    });
  }

  Future<void> _ensureFirebaseSessionForLogin() async {
    if (fb_auth.FirebaseAuth.instance.currentUser != null) return;
    try {
      await fb_auth.FirebaseAuth.instance.signInAnonymously();
      debugPrint('✅ Anonymous Firebase session restored for login');
    } catch (e) {
      debugPrint('⚠️ Could not restore Firebase session for login: $e');
    }
  }

  void _goBackSafely() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushNamedAndRemoveUntil(Routes.authSelection, (_) => false);
  }

  // ── STEP 1 — Look up mobile ───────────────────────────────────────────────
  Future<void> _lookupUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    debugPrint('🔍 LOGIN STEP 1: _lookupUser started');
    debugPrint('🔍 Mobile input: ${_safeMobileText()}');

    // If a session exists, reuse it — even if the UID differs from the stored
    // doc ID. The Firestore rules now allow updates where the doc's own 'id'
    // field matches (see firestore.rules), so a UID mismatch no longer blocks
    // profile updates or interest operations.
    if (fb_auth.FirebaseAuth.instance.currentUser == null) {
      debugPrint('🔍 No Firebase session, signing in anonymously...');
      try {
        await fb_auth.FirebaseAuth.instance.signInAnonymously();
        debugPrint('✅ Anonymous sign-in successful');
        debugPrint('🔍 Firebase UID: ${fb_auth.FirebaseAuth.instance.currentUser?.uid}');
      } catch (e) {
        debugPrint('❌ Anonymous sign-in failed: $e');
      }
    } else {
      debugPrint('🔍 Existing Firebase session found: ${fb_auth.FirebaseAuth.instance.currentUser?.uid}');
    }

    debugPrint('🔍 Initializing authService...');
    if (!mounted) return;
    final authService = context.read<AuthService>();
    if (!authService.isInitialized) {
      await authService.initialize();
    }
    if (!mounted) return;
    debugPrint('🔍 authService initialized. currentUser: ${authService.currentUser?.id}');

    final mobile = _safeMobileText();
    debugPrint('🔍 Looking up user by mobile: $mobile');
    final userData = await authService.getUserByMobile(mobile);
    debugPrint('🔍 getUserByMobile result: ${userData != null ? "FOUND (id=${userData.id})" : "NOT FOUND"}');

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (userData == null) {
      debugPrint("❌ LOGIN: User NOT found → showing registration");
      _showNotRegisteredDialog();
    } else {
      debugPrint("✅ LOGIN: User found → proceeding");
      debugPrint("🔍 User id: ${userData.id}, has mpinHash: ${userData.mpinHash != null}");
      authService.setCurrentUser(userData);

      // Sync auth_uid after user found (required for Firestore security rules)
      try {
        // During lookup flow, identity may not be initialized yet on a fresh
        // install/device. Write auth_uid against the discovered Firestore doc id.
        final identityService = IdentityService();
        final firebaseAuthUid = await identityService.getFirebaseAuthUid();
        if (firebaseAuthUid != null && firebaseAuthUid.isNotEmpty) {
          await FirebaseFirestore.instance.collection(Collections.users).doc(userData.id).set({
            'auth_uid': firebaseAuthUid,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        debugPrint('✅ Auth UID synced for user: ${userData.id} → $firebaseAuthUid');
      } catch (e) {
        debugPrint('⚠️ Auth UID sync error (non-fatal): $e');
      }
      
      // Prime identity so restore works after reinstall/device switch before MPIN submit.
      try {
        final identityService = IdentityService();
        await identityService.setUserId(userData.id);
        final pid = userData.profileId;
        await identityService.setProfileId(pid.isNotEmpty ? pid : userData.id);
      } catch (e) {
        debugPrint('⚠️ Identity prefill error (non-fatal): $e');
      }

      _showUserFoundDialog(userData);
    }
  }

  // ── STEP 2 — Verify MPIN and route ───────────────────────────────────────
  Future<void> _loginWithMpin(String mpin) async {
    if (mpin.length != 4) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    debugPrint('🔐 LOGIN STEP 2: _loginWithMpin started with MPIN');

    // ── REGULAR USER LOGIN (all users go through this path) ─
    final authService = context.read<AuthService>();
    final swTotal = Stopwatch()..start();
    try {
      debugPrint('🔐 Initializing authService...');
      final swInit = Stopwatch()..start();
      await _ensureFirebaseSessionForLogin();
      if (!authService.isInitialized) {
        await authService.initialize().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Auth initialization timed out');
          },
        );
      }
      swInit.stop();
      if (kDebugMode) {
        debugPrint('⏱️ LOGIN timing [init]: ${swInit.elapsedMilliseconds}ms');
      }
      if (!mounted) return;              // 🔥 FIX: guard after await
      debugPrint('🔐 authService initialized. currentUser: ${authService.currentUser?.id}');

      // First restore the remembered user or verify the mobile-entered user.
      final mobile = _safeMobileText();
      User? userExists;
      final swLookup = Stopwatch()..start();
      if (_rememberedMode && (_rememberedUserId ?? '').isNotEmpty) {
        debugPrint('🔐 Looking up remembered user: $_rememberedUserId');
        userExists = await authService.getUserById(_rememberedUserId!);
      } else {
        debugPrint('🔐 Looking up user by mobile: $mobile');
        userExists = await authService.getUserByMobile(mobile);
      }
      swLookup.stop();
      if (kDebugMode) {
        debugPrint('⏱️ LOGIN timing [lookup]: ${swLookup.elapsedMilliseconds}ms');
      }
      debugPrint('🔐 login user lookup result: ${userExists != null ? "FOUND (id=${userExists.id})" : "NOT FOUND"}');

      if (userExists == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showErrorSnack(_rememberedMode
            ? 'Saved account could not be restored. Please sign in again.'
            : 'Mobile number not registered. Please register first.');
        return;
      }

      await authService.setCurrentUser(userExists);

      // Then verify MPIN using the real user's doc ID (not the anonymous UID)
      debugPrint('🔐 Verifying MPIN for user: ${userExists.id}');
      final swVerify = Stopwatch()..start();
      final success = await authService.verifyMpinForUser(userExists.id, mpin);
      swVerify.stop();
      if (kDebugMode) {
        debugPrint('⏱️ LOGIN timing [verify_mpin]: ${swVerify.elapsedMilliseconds}ms');
      }
      debugPrint('🔐 verifyMpinForUser result: $success, error: ${authService.errorMessage}');
      if (!mounted) return;

      if (!success) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        final err = authService.errorMessage ?? 'Invalid MPIN';
        debugPrint('🔐 MPIN verification failed: $err');
        if (err == 'NEW_DEVICE_NO_MPIN') {
          _showNewDeviceDialog();
        } else if (err.startsWith('PENDING_DELETION:')) {
          final days =
              int.tryParse(err.split(':').elementAtOrNull(1) ?? '') ?? 0;
          if (days <= 0) {
            _showErrorSnack(
              'Your 7-day restore window has ended. Profile removal is scheduled.',
            );
            return;
          }
          _showRestoreAccountDialog(days);
        } else {
          if (!mounted) return;
          setState(() => _mpinHasError = true);
          _mpinPinFieldController.shake();
          _showErrorSnack(err.isNotEmpty ? err : 'Invalid MPIN. Please try again.');
          if (mounted) _mpinController.clear();
        }
        return;
      }
      debugPrint('✅ MPIN verified successfully!');

      // ── CHECK IF USER IS ADMIN (Firestore-based role check) ─
      final currentUser = authService.currentUser;
      final isAdmin = currentUser?.isAdmin == true;
      if (!mounted) return;

      if (isAdmin) {
        // ── ADMIN PATH: Perform admin-specific setup ─
        final currentUser = authService.currentUser!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_logged_in',          true);
        await prefs.setBool('mpin_setup_complete',      true);
        await prefs.setBool('profile_complete',         true);
        await prefs.setBool('is_admin_user',            true);  // cache for cold-start routing
        await prefs.setString('current_user_id',        currentUser.id);  // CRITICAL: must match admin_user_id
        await prefs.setString('current_user_name',      currentUser.profile?.fullName ?? currentUser.firstName);
        await prefs.setString('admin_user_id',          currentUser.id);  // Required for admin routing
        await prefs.remove('user_explicitly_logged_out');       // clear logout flag
        // Signal to AdminGate that login MPIN was just verified
        await prefs.setBool('admin_login_verified',     true);
        await authService.markSessionMpinVerified();
        NavigationService().invalidateCaches();

        // BIOMETRIC FIX: persist the mobile number
        await prefs.setString('last_login_mobile',
            currentUser.mobileNumber.isNotEmpty ? currentUser.mobileNumber : _safeMobileText());

        // 🔥 CRITICAL: Set profile_id in IdentityService before any auth operations
        try {
          final identityService = IdentityService();
          await identityService.setProfileId(currentUser.profileId);
          await identityService.setUserId(currentUser.id);
          debugPrint('✅ IdentityService initialized for ${currentUser.profileId}');
        } catch (e) {
          debugPrint('⚠️ IdentityService setup error (non-fatal): $e');
        }

        // ADMIN FIX: sync auth_uid on the Firestore user doc
        try {
          await authService.syncAuthUid(currentUser.id);
          debugPrint('✅ Admin auth_uid synced for ${currentUser.id}');
        } catch (e) {
          debugPrint('⚠️ Admin auth_uid sync error (non-fatal): $e');
        }

        try {
          await AdminSessionBootstrap.ensureAccess(userDocId: currentUser.id);
        } catch (e) {
          debugPrint('⚠️ admin session bootstrap failed (non-fatal): $e');
        }

        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushNamedAndRemoveUntil(
            context, Routes.adminDashboard, (r) => false);
        return;
      }

      // ── REGULAR USER PATH ─
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', userExists.id);  // CRITICAL: must be set
      await prefs.setString('current_user_name', userExists.profile?.fullName ?? userExists.firstName);
      await prefs.setBool('user_logged_in', true);
      await prefs.setBool('mpin_setup_complete', true);
      await prefs.setBool('profile_complete', true);  // CRITICAL: Required for home routing
      await prefs.remove('user_explicitly_logged_out');  // Clear logout flag
      // Prevent stale admin state from routing normal users into admin dashboard.
      await prefs.setBool('is_admin_user', false);
      await prefs.remove('admin_user_id');
      await prefs.remove('admin_login_verified');
      await prefs.remove('admin_session_active');
      await prefs.setString(
          'last_login_mobile', userExists.mobileNumber.isNotEmpty ? userExists.mobileNumber : _safeMobileText());

      // Set current user in AuthService so subsequent operations work
      // ZIP1 compatibility: setCurrentUser(user) without lockApp parameter
      await authService.setCurrentUser(userExists);
      if (!mounted) return;

      // 🔥 CRITICAL: Set profile_id in IdentityService before any app operations
      try {
        final identityService = IdentityService();
        await identityService.setProfileId(userExists.profileId);
        await identityService.setUserId(userExists.id);
        debugPrint('✅ IdentityService initialized for ${userExists.profileId}');
      } catch (e) {
        debugPrint('⚠️ IdentityService setup error (non-fatal): $e');
      }

      // 🔥 CRITICAL: Verify auth_uid sync before app initialization
      try {
        final fbUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
        if (fbUid != null) {
          await authService.syncAuthUid(userExists.id);
          debugPrint('✅ Auth UID sync completed for ${userExists.id}');
        }
      } catch (e) {
        debugPrint('⚠️ Auth UID sync failed: $e');
      }

      await authService.markSessionMpinVerified();

      // 🔥 INITIALIZE APP IDENTITY - Critical for all services
      final swAppInit = Stopwatch()..start();
      final initResult = await AppInitializer.initialize().timeout(
        const Duration(seconds: 25),
        onTimeout: () => Result.error(
          'timeout',
          'Login timed out. Check your connection and try again.',
        ),
      );
      swAppInit.stop();
      if (kDebugMode) {
        debugPrint(
          '⏱️ LOGIN timing [app_initializer]: ${swAppInit.elapsedMilliseconds}ms',
        );
      }
      if (!mounted) return;
      if (initResult.isError) {
        debugPrint('❌ App initialization failed: ${initResult.message}');
        setState(() => _isLoading = false);
        _showErrorSnack('Login failed: ${initResult.message}. Please try again.');
        return;
      }

      NavigationService().invalidateCaches();
      final swRoute = Stopwatch()..start();
      final route = await NavigationService()
          .getInitialRoute()
          .timeout(const Duration(seconds: 10), onTimeout: () => Routes.home);
      swRoute.stop();
      if (kDebugMode) {
        debugPrint('⏱️ LOGIN timing [resolve_route]: ${swRoute.elapsedMilliseconds}ms');
      }
      if (!mounted) return;
      swTotal.stop();
      if (kDebugMode) {
        debugPrint('⏱️ LOGIN timing [total]: ${swTotal.elapsedMilliseconds}ms');
      }
      setState(() => _isLoading = false);
      Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnack(
        'Login timed out. Check your internet connection and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnack('Login error: $e');
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithBiometric() async {
    final userId = _biometricUserId;
    if (userId == null || _isLoading) return;

    setState(() => _isLoading = true);
    final localAuthService = LocalAuthService();
    final didVerify = await localAuthService.authenticate(
      reason: 'Use biometrics to sign in securely',
    );
    if (!mounted) return;                // 🔥 FIX: guard already present ✓

    if (!didVerify) {
      setState(() => _isLoading = false);
      _showErrorSnack('Biometric verification cancelled or failed.');
      return;
    }

    try {
      final authService = context.read<AuthService>();
      await _ensureFirebaseSessionForLogin();
      if (!authService.isInitialized) {
        await authService.initialize();
      }
      if (!mounted) return;                // 🔥 FIX: guard after await
      // Validate biometric toggle is still enabled for this user.
      final isEnabledForUser =
          await localAuthService.isEnabledForUser(userId);
      if (!mounted) return;
      if (!isEnabledForUser) {
        setState(() => _isLoading = false);
        _showErrorSnack('Biometric login is disabled for this account. Use MPIN.');
        return;
      }

      // Restore user session WITHOUT asking mobile number again.
      // Prefer user-id restore, fallback to last mobile restore.
      var restoredUser = await authService.getUserById(userId);
      if (restoredUser == null) {
        final prefs = await SharedPreferences.getInstance();
        final lastMobile = (prefs.getString('last_login_mobile') ?? '').trim();
        if (lastMobile.isNotEmpty) {
          final restored = await authService.restoreExistingSession(lastMobile);
          if (restored.success) {
            restoredUser = authService.currentUser;
          }
        }
      } else {
        await authService.setCurrentUser(restoredUser);
      }

      if (!mounted) return;
      if (restoredUser == null) {
        setState(() => _isLoading = false);
        _showErrorSnack(
          'Unable to restore account for biometric login. Please sign in with mobile + MPIN once.',
        );
        return;
      }

      // ── CHECK IF USER IS ADMIN (same logic as MPIN flow) ─
      final isAdmin = restoredUser.isAdmin;
      if (!mounted) return;

      if (isAdmin) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_logged_in', true);
        await prefs.setBool('mpin_setup_complete', true);
        await prefs.setBool('profile_complete', true);
        await prefs.setBool('is_admin_user', true);
        await prefs.setString('current_user_id', restoredUser.id);
        await prefs.setString('current_user_name',
            restoredUser.profile?.fullName ?? restoredUser.firstName);
        await prefs.setString('admin_user_id', restoredUser.id);
        await prefs.remove('user_explicitly_logged_out');
        await prefs.setBool('admin_login_verified', true);
        await authService.markSessionMpinVerified();
        await prefs.setString('last_login_mobile', restoredUser.mobileNumber);
        NavigationService().invalidateCaches();
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushNamedAndRemoveUntil(
            context, Routes.adminDashboard, (r) => false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', restoredUser.id);
      await prefs.setString('current_user_name',
          restoredUser.profile?.fullName ?? restoredUser.firstName);
      await prefs.setBool('user_logged_in', true);
      await prefs.setBool('mpin_setup_complete', true);
      await prefs.setBool('profile_complete', true);
      await prefs.remove('user_explicitly_logged_out');
      await prefs.setBool('is_admin_user', false);
      await prefs.remove('admin_user_id');
      await prefs.remove('admin_login_verified');
      await prefs.remove('admin_session_active');
      await prefs.setString('last_login_mobile', restoredUser.mobileNumber);

      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      try {
        final identityService = IdentityService();
        await identityService.setProfileId(restoredUser.profileId);
        await identityService.setUserId(restoredUser.id);
        final currentUserId = restoredUser.id;
        
        // Only sync auth_uid if profile_id is available
        final firebaseAuthUid = identityService.getFirebaseAuthUid();
        if (currentUserId.isNotEmpty) {
          await FirebaseFirestore.instance.collection(Collections.users).doc(currentUserId).set({
            'auth_uid': firebaseAuthUid,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint('✅ Auth UID synced after biometric login: $currentUserId → $firebaseAuthUid');
        }
      } catch (e) {
        debugPrint('⚠️ Biometric auth_uid sync error (non-fatal): $e');
      }

      // 🔥 INITIALIZE APP IDENTITY - Critical for all services
      final bioInitResult = await AppInitializer.initialize();
      if (!mounted) return;
      if (bioInitResult.isError) {
        debugPrint('❌ App initialization failed after biometric: ${bioInitResult.message}');
        setState(() => _isLoading = false);
        _showErrorSnack('Login failed: ${bioInitResult.message}. Please try again.');
        return;
      }

      NavigationService().invalidateCaches();
      final route = await NavigationService().getInitialRoute();
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnack('Biometric login failed: $e');
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _showNotRegisteredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
                color: AppTheme.kumkumRed.withAlpha(20),
                shape: BoxShape.circle),
            child: const Icon(Icons.person_off_rounded,
                color: AppTheme.kumkumRed, size: 34),
          ),
          const SizedBox(height: 16),
          Text('Not Registered',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppTheme.kumkumRed)),
          const SizedBox(height: 10),
          Text(
            'This mobile number is not registered with Mana Vivaaha Vedika.\nPlease register to create your profile.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AC.textSub(ctx), height: 1.55),
          ),
          const SizedBox(height: 20),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryOrange,
                side: const BorderSide(color: AppTheme.primaryOrange),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Try Again',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (!mounted) return;
                Navigator.pushReplacement(context,
                    MaterialPageRoute(
                        builder: (_) => const DisclaimerScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
              child: Text('Register Now',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserFoundDialog(User user) {
    if (!mounted) return;
    final name = _resolveUserDisplayName(user);
    final hasMpin = user.mpinHash != null && user.mpinHash!.isNotEmpty;

    // If user doesn't have MPIN set up, redirect to MPIN setup
    if (!hasMpin) {
      _redirectToMpinSetup(user);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(20),
                shape: BoxShape.circle),
            child: const Icon(Icons.verified_user_rounded,
                color: AppTheme.sacredGreen, size: 34),
          ),
          const SizedBox(height: 16),
          Text('Account Found! 🎉',
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: AppTheme.sacredGreen),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            name.isNotEmpty
                ? 'Hi $name! Enter your 4-digit MPIN to sign in.'
                : 'You are registered with Mana Vivaaha Vedika.\nEnter your 4-digit MPIN to sign in.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AC.textSub(ctx), height: 1.55),
          ),
          const SizedBox(height: 20),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (!mounted) return;
                setState(() {
                  _loginDisplayName = _resolveUserDisplayName(user);
                  _userFound = true;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: Text('Enter MPIN',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _redirectToMpinSetup(User user) async {
    // Set user as current user first
    final authService = context.read<AuthService>();
    authService.setCurrentUser(user);

    // Navigate to MPIN setup screen
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      Routes.mpinSetup,
    );
  }

  void _showNewDeviceDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(20),
                shape: BoxShape.circle),
            child: const Icon(Icons.phone_android_rounded,
                color: AppTheme.primaryOrange, size: 34),
          ),
          const SizedBox(height: 16),
          Text('New Device Detected',
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Your MPIN is not stored on this device.\nVerify your mobile via OTP to set a new MPIN.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AC.textSub(ctx), height: 1.55),
          ),
          const SizedBox(height: 20),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (!mounted) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ForgotMpinScreen(
                      prefillMobile: _safeMobileText()),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: Text('Verify via OTP',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRestoreAccountDialog(int daysLeft) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.restore, color: AppTheme.primaryOrange),
          const SizedBox(width: 8),
          const Text('Restore Account?'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AC.border(context)),
            ),
            child: Column(children: [
              const Icon(Icons.timer_outlined,
                  color: AppTheme.primaryOrange, size: 36),
              const SizedBox(height: 10),
              Text('$daysLeft day${daysLeft == 1 ? '' : 's'} left to restore',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppTheme.primaryOrange)),
              const SizedBox(height: 6),
              Text(
                'Your account is scheduled for deletion.\nWould you like to restore it?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AC.textSub(context)),
              ),
            ]),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _proceedAfterPendingLogin();
            },
            child: const Text('Leave as Scheduled'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _restoreAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.sacredGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Restore My Account'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreAccount() async {
    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      if (user == null) return;
      final result = await authService.cancelProfileDeletion(user.id);
      if (!mounted) return;
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🎉 Account restored! Welcome back!'),
          backgroundColor: AppTheme.sacredGreen,
          duration: Duration(seconds: 3),
        ));
        _proceedAfterPendingLogin();
      } else {
        _showErrorSnack('Restore failed');
      }
    } catch (e) {
      if (mounted) _showErrorSnack('Error: $e');
    }
  }

  Future<void> _proceedAfterPendingLogin() async {
    final authService = context.read<AuthService>();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setBool('user_logged_in', true);
    await prefs.setBool('mpin_setup_complete', true);
    await prefs.remove('user_explicitly_logged_out');  // Clear logout flag
    final loggedInUser = authService.currentUser;
    if (loggedInUser != null) {
      await prefs.setString('current_user_id', loggedInUser.id);
      final p = loggedInUser.profile;
      if (p != null && p.firstName.isNotEmpty == true) {
        await prefs.setBool('profile_complete', true);
      }
      await authService.markSessionMpinVerified();
    }
    NavigationService().invalidateCaches();
    if (mounted) {
      final route = await NavigationService().getInitialRoute();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    }
  }

  /// Biometric button is visible always; enabled only when device hardware supports it.
  bool _isBiometricButtonEnabled() =>
      _deviceBiometricsAvailable && !_isLoading;

  Future<void> _onBiometricButtonPressed() async {
    if (!_deviceBiometricsAvailable) {
      _showErrorSnack(
        'Biometric login is not available on this device.',
      );
      return;
    }
    if (_biometricUserId == null) {
      _showErrorSnack(
        'Sign in with MPIN first, then enable biometric login in Settings.',
      );
      return;
    }
    if (_rememberedMode &&
        _rememberedUserId != null &&
        _biometricUserId != _rememberedUserId) {
      _showErrorSnack(
        'Biometric login is set up for a different account. Use MPIN.',
      );
      return;
    }
    await _loginWithBiometric();
  }

  void _submitMpinFromButton() {
    final mpin = _mpinController.text.trim();
    if (mpin.length != 4) {
      setState(() => _mpinHasError = true);
      _mpinPinFieldController.shake();
      _showErrorSnack('Enter your 4-digit MPIN');
      return;
    }
    FocusScope.of(context).unfocus();
    _loginWithMpin(mpin);
  }

  Widget _authFooter(BuildContext context) {
    if (!widget.isEntryPoint && !_userFound) return const SizedBox.shrink();
    return AuthFooterLinks(
      showRegister: widget.isEntryPoint && !_userFound,
      showForgotMpin: true,
      onRegister: widget.isEntryPoint && !_userFound
          ? () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DisclaimerScreen()),
              )
          : null,
      onForgotMpin: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ForgotMpinScreen(prefillMobile: _safeMobileText()),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AuthScreenShell(
      showBack: !widget.isEntryPoint,
      onBack: widget.isEntryPoint ? null : _goBackSafely,
      screenTitle: _userFound ? 'Enter MPIN' : 'Login to your account',
      screenSubtitle: _userFound
          ? 'Use MPIN or biometric to continue'
          : 'Enter your registered mobile number',
      scrollable: true,
      resizeToAvoidBottomInset: true,
      footer: _authFooter(context),
      body: _userFound
          ? _buildMpinFixedBody(context)
          : _buildMobileLookupBody(context),
    );
  }

  /// MPIN entry — parent [AuthScreenShell] scrolls when keyboard is open.
  Widget _buildMpinFixedBody(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AuthBankCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHelloHeader(context),
                const SizedBox(height: 10),
                Text(
                  'Enter your 4-digit MPIN',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AC.textMuted(context),
                  ),
                ),
                const SizedBox(height: 10),
                AuthMpinPinField(
                  compact: true,
                  controller: _mpinController,
                  fieldController: _mpinPinFieldController,
                  hasError: _mpinHasError,
                  autoFocus: true,
                  onChanged: (_) {
                    if (_mpinHasError) {
                      setState(() => _mpinHasError = false);
                    }
                  },
                  onCompleted: (value) {
                    FocusScope.of(context).unfocus();
                    _loginWithMpin(value);
                  },
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 8),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _buildBiometricContinueRow(
                  context,
                  onContinue: _submitMpinFromButton,
                  continueLabel: 'Continue',
                ),
                AuthTouchLink(
                  label: _rememberedMode
                      ? 'Not you? Use another number'
                      : 'Change mobile number',
                  onPressed: _isLoading ? null : _returnToMobileEntry,
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelloHeader(BuildContext context) {
    final name = _resolveGreetingName(context);
    final mobile = (_rememberedMobile ?? _safeMobileText()).trim();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withAlpha(22),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_rounded,
            color: AppTheme.primaryOrange,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name.isNotEmpty) ...[
                Text(
                  'Hello, $name',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AC.text(context),
                  ),
                ),
                if (mobile.isNotEmpty) const SizedBox(height: 2),
              ],
              if (mobile.isNotEmpty)
                Text(
                  _maskedMobile(mobile),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AC.textMuted(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricContinueRow(
    BuildContext context, {
    required VoidCallback onContinue,
    required String continueLabel,
  }) {
    final bioEnabled = _isBiometricButtonEnabled();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: bioEnabled ? _onBiometricButtonPressed : null,
            icon: Icon(
              Icons.fingerprint_rounded,
              size: 20,
              color: bioEnabled
                  ? AppTheme.primaryOrange
                  : AC.textMuted(context),
            ),
            label: Text(
              'Biometric',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: bioEnabled
                    ? AppTheme.primaryOrange
                    : AC.textMuted(context),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: bioEnabled
                  ? AppTheme.primaryOrange
                  : AC.textMuted(context),
              disabledForegroundColor: AC.textMuted(context),
              side: BorderSide(
                color: bioEnabled
                    ? AppTheme.primaryOrange
                    : AppTheme.surfaceLight2,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : onContinue,
            style: _primaryButtonStyle().copyWith(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AC.card(context),
                    ),
                  )
                : Text(
                    continueLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLookupBody(BuildContext context) {
    return Form(
      key: _formKey,
      child: AuthSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthFieldLabel(
              'Mobile number',
              hint: '10-digit number registered with us',
            ),
            AuthMobilePinFormField(
              controller: _mobileController,
              autoFocus: true,
            ),
            const SizedBox(height: 12),
            _buildBiometricContinueRow(
              context,
              onContinue: () {
                if (_formKey.currentState?.validate() ?? false) {
                  _lookupUser();
                }
              },
              continueLabel: 'Continue',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

ButtonStyle _primaryButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primaryOrange,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 0,
    textStyle:
        GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
  );
}

