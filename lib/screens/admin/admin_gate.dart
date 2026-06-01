import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/admin_session_bootstrap.dart';
import '../../core/contract.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminGate — session flags + timeout. Admin role verified via Firestore is_admin field.
// Re-login validates MPIN against stored hash and verifies is_admin == true in Firestore.
// ─────────────────────────────────────────────────────────────────────────────

const Duration _kAdminSessionTimeout = Duration(minutes: 30);

class AdminGate extends StatefulWidget {
  final Widget child;
  const AdminGate({super.key, required this.child});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> with WidgetsBindingObserver {
  _AdminAuthState _state = _AdminAuthState.checking;
  Timer? _sessionTimer;
  Duration _effectiveTimeout = _kAdminSessionTimeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock when app goes to background
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        _state == _AdminAuthState.granted) {
      _lockSession();
    }
  }

  // ── Access check ─────────────────────────────────────────────────────────
  // Entry flags checked in order of freshness:
  //   1. 'admin_login_verified'  — single-use, written right after MPIN login
  //   2. 'admin_session_active'  — durable session flag, survives widget rebuilds
  //   3. 'is_admin_user'         — written at login; survives cold restarts
  //
  // All three paths delegate to _verifyCurrentAdminStatus() which:
  //   • Fast-denies if 'is_admin_user' pref is false (no Firestore call)
  //   • Attempts a Firestore read to catch server-side revocations
  //   • Falls back to the cached pref when Firestore is unreachable
  //     (permission-denied because anonymous-auth UID ≠ doc ID, network
  //     errors, timeouts, etc.) — this prevents the dashboard from going
  //     blank just because Firestore is slow or rejects an anon read.
  //
  // Only an explicit server-side revocation (is_admin=false in Firestore
  // confirmed successfully) or a deliberate logout clears the prefs.
  Future<void> _checkAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Path 1: fresh login just completed ─────────────────────────────
      final loginVerified = prefs.getBool('admin_login_verified') ?? false;
      if (loginVerified) {
        // Promote to durable session flag BEFORE the async Firestore call
        // so a widget rebuild mid-flight doesn't lose the grant.
        await prefs.remove('admin_login_verified');
        await prefs.setBool('admin_session_active', true);

        if (await _verifyCurrentAdminStatus()) {
          _startSession();
          return;
        }
        // Firestore positively confirmed revocation.
        await _clearAdminPrefs(prefs);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/auth-selection', (r) => false);
        }
        return;
      }

      // ── Path 2: widget rebuild / tab switch during active session ───────
      final sessionActive = prefs.getBool('admin_session_active') ?? false;
      if (sessionActive) {
        if (await _verifyCurrentAdminStatus()) {
          _startSession();
          return;
        }
        await _clearAdminPrefs(prefs);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/auth-selection', (r) => false);
        }
        return;
      }

      // ── Path 3: cold-restart with cached admin flag ─────────────────────
      final isAdminUser = prefs.getBool('is_admin_user') ?? false;
      if (isAdminUser) {
        if (await _verifyCurrentAdminStatus()) {
          await prefs.setBool('admin_session_active', true);
          _startSession();
          return;
        }
        await _clearAdminPrefs(prefs);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/auth-selection', (r) => false);
        }
        return;
      }

      // ── No valid entry — send to login ──────────────────────────────────
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/auth-selection', (r) => false);
      }
    } catch (e) {
      debugPrint('❌ AdminGate._checkAccess: $e');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/auth-selection', (r) => false);
      }
    }
  }

  /// Clear all admin-related SharedPreferences keys on revocation / logout.
  Future<void> _clearAdminPrefs(SharedPreferences prefs) async {
    await prefs.remove('admin_session_active');
    await prefs.remove('admin_login_verified');
    await prefs.setBool('is_admin_user', false);
    await prefs.remove('admin_user_id');
  }

  /// Verify current user's admin status.
  ///
  /// Strategy (fastest → most authoritative):
  ///   1. Read `is_admin_user` from SharedPreferences (set during login).
  ///      If false → deny immediately (no Firestore round-trip needed).
  ///   2. Attempt a real-time Firestore read to confirm `is_admin == true`
  ///      on the user document. This catches revocations made server-side.
  ///   3. If the Firestore read fails for ANY reason (permission-denied when
  ///      the anonymous-auth UID doesn't match the doc ID, network error,
  ///      timeout, etc.) — fall back to trusting the SharedPreferences value
  ///      that was written during a successful MPIN-verified login. This
  ///      prevents the dashboard from going blank just because Firestore is
  ///      slow or the security rule requires a different auth context.
  Future<bool> _verifyCurrentAdminStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Fast deny — pref was explicitly cleared on logout/revocation.
      final prefIsAdmin = prefs.getBool('is_admin_user') ?? false;
      if (!prefIsAdmin) {
        debugPrint('🔒 AdminGate: is_admin_user pref is false — denying');
        return false;
      }

      final userId = prefs.getString('current_user_id') ?? '';
      if (userId.isEmpty) {
        debugPrint('🔒 AdminGate: no current_user_id — denying');
        return false;
      }

      // Attempt Firestore confirmation (best-effort — non-fatal).
      try {
        final doc = await FirebaseFirestore.instance
            .collection(Collections.users)
            .doc(userId)
            .get()
            .timeout(const Duration(seconds: 8));

        if (doc.exists) {
          final isAdmin = doc.data()?['is_admin'] == true;
          debugPrint('🔒 AdminGate: Firestore admin check for $userId: $isAdmin');
          if (!isAdmin) {
            // Server-side revocation — clear the cached pref so future
            // sessions also get denied.
            await prefs.setBool('is_admin_user', false);
          }
          return isAdmin;
        }
        // Doc missing — treat as not-admin.
        debugPrint('🔒 AdminGate: user doc $userId not found — denying');
        return false;
      } catch (firestoreErr) {
        // Firestore is unreachable or returned permission-denied (common when
        // the anonymous-auth UID doesn't match the Firestore doc ID).
        // Fall back to the pref that was written during a successful login.
        debugPrint('⚠️ AdminGate: Firestore check failed ($firestoreErr) — '
            'trusting is_admin_user pref=$prefIsAdmin');
        return prefIsAdmin;
      }
    } catch (e) {
      debugPrint('❌ AdminGate: Error verifying admin status: $e');
      return false;
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────
  void _startSession() {
    _scheduleSessionTimer();
    if (mounted) setState(() => _state = _AdminAuthState.granted);
    // Write/refresh admin_sessions so Firestore rules always pass.
    // Called on first login AND after every session timeout re-login.
    _writeAdminSession();
  }

  Future<void> _scheduleSessionTimer() async {
    _sessionTimer?.cancel();
    _effectiveTimeout = await _resolveSessionTimeout();
    _sessionTimer = Timer(_effectiveTimeout, _lockSession);
  }

  Future<Duration> _resolveSessionTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getInt('admin_session_timeout_min');
      if (local != null && local >= 1) {
        return Duration(minutes: local.clamp(1, 240));
      }
      final doc = await FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('global')
          .get();
      final raw = doc.data()?['session_timeout_min'];
      int mins = 30;
      if (raw is int) mins = raw;
      if (raw is num) mins = raw.round();
      mins = mins.clamp(1, 240);
      await prefs.setInt('admin_session_timeout_min', mins);
      return Duration(minutes: mins);
    } catch (_) {
      return _kAdminSessionTimeout;
    }
  }

  void _writeAdminSession() {
    // Run async — ensures Firebase session exists before writing
    _ensureSessionAndWrite();
  }

  Future<void> _ensureSessionAndWrite() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('✅ AdminGate: Firebase session restored');
      }
      final prefs = await SharedPreferences.getInstance();
      final userDocId = prefs.getString('current_user_id') ?? '';
      if (userDocId.isEmpty) return;
      await AdminSessionBootstrap.ensureAccess(userDocId: userDocId);
      final fbUid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('✅ AdminGate: admin session bootstrap uid=$fbUid');
    } catch (e) {
      debugPrint('⚠️ AdminGate: admin session bootstrap failed: $e');
    }
  }

  void _refreshSession() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_effectiveTimeout, _lockSession);
  }

  void _lockSession() {
    _sessionTimer?.cancel();
    // Clear persistent session flag so a widget rebuild doesn't bypass relogin
    SharedPreferences.getInstance().then(
        (p) => p.remove('admin_session_active'));
    if (mounted) setState(() => _state = _AdminAuthState.relogin);
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AdminAuthState.checking:
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));

      case _AdminAuthState.denied:
        // Should never reach here now — _checkAccess redirects to /auth-selection.
        // Kept as safety fallback; auto-redirect after frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
                context, '/auth-selection', (r) => false);
          }
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));

      case _AdminAuthState.relogin:
        return _AdminReloginScreen(
          onSuccess: () {
            _startSession();
          },
        );

      case _AdminAuthState.granted:
        return Listener(
          onPointerDown: (_) => _refreshSession(),
          child: widget.child,
        );
    }
  }
}

enum _AdminAuthState { checking, denied, granted, relogin }

// ─────────────────────────────────────────────────────────────────────────────
// Admin Re-login Screen (after session timeout) — validates MPIN via AuthService
// and verifies is_admin == true in Firestore. No hardcoded secrets.
// ─────────────────────────────────────────────────────────────────────────────
class _AdminReloginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const _AdminReloginScreen({required this.onSuccess});

  @override
  State<_AdminReloginScreen> createState() => _AdminReloginScreenState();
}

class _AdminReloginScreenState extends State<_AdminReloginScreen> {
  final _pinCtrl = TextEditingController();
  bool _checking = false;
  String? _error;
  int _failed    = 0;

  @override
  void dispose() { _pinCtrl.dispose(); super.dispose(); }

  Future<void> _submit(String mpin) async {
    if (_checking) return;
    final authService = context.read<AuthService>();
    FocusScope.of(context).unfocus();
    setState(() { _checking = true; _error = null; });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      // Use MPIN-only login to verify the admin's MPIN against stored hash
      final prefs = await SharedPreferences.getInstance();
      final mobile = prefs.getString('last_login_mobile') ?? '';
      final result = await authService.loginByMpinOnly(mobile: mobile, mpin: mpin);
      if (!mounted) return;
      
      if (result.success) {
        // MPIN matched - now verify this user is still an admin in Firestore
        final currentUser = authService.currentUser;
        if (currentUser == null) {
          setState(() {
            _checking = false;
            _error = 'Session error. Please login again.';
          });
          return;
        }
        
        // Check is_admin field in Firestore (best-effort — non-fatal).
        // If Firestore is unreachable, trust the MPIN match + cached pref.
        bool isAdmin = false;
        try {
          final doc = await FirebaseFirestore.instance
              .collection(Collections.users)
              .doc(currentUser.id)
              .get()
              .timeout(const Duration(seconds: 8));
          isAdmin = doc.data()?['is_admin'] == true;
        } catch (fsErr) {
          // Fallback: trust the is_admin_user pref written at login time.
          final prefs2 = await SharedPreferences.getInstance();
          isAdmin = prefs2.getBool('is_admin_user') ?? false;
          debugPrint('⚠️ AdminRelogin: Firestore check failed ($fsErr) — '
              'trusting is_admin_user pref=$isAdmin');
        }
        
        if (!isAdmin) {
          // User is no longer an admin - clear and redirect
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('admin_session_active');
          await prefs.setBool('is_admin_user', false);
          await prefs.remove('admin_user_id');
          if (mounted) {
            setState(() {
              _checking = false;
              _error = 'Admin privileges revoked. Redirecting to login...';
            });
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/auth-selection', (r) => false);
            }
          }
          return;
        }
        
        // Valid admin - update all session flags so _verifyCurrentAdminStatus
        // and AuthWrapper both agree this is an admin on the next cold start.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('admin_login_verified', true);
        await prefs.setBool('is_admin_user', true);
        await prefs.setString('admin_user_id', currentUser.id);
        await prefs.setString('current_user_id', currentUser.id);
        await prefs.setBool('admin_session_active', true);
        if (mounted) widget.onSuccess();
      } else if (result.message == 'Invalid MPIN') {
        _failed++;
        _pinCtrl.clear();
        setState(() {
          _checking = false;
          _error = _failed >= 3
              ? 'Incorrect MPIN ($_failed attempts). Tap below to go to login.'
              : 'Incorrect MPIN. Please try again.';
        });
      } else if (result.message == 'User not found') {
        setState(() {
          _checking = false;
          _error =
              'No saved user profile on this device. Sign in from the main app login, then open admin again.';
        });
      } else {
        // Error case
        setState(() {
          _checking = false;
          _error = result.message.isNotEmpty
              ? result.message
              : 'Login failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _checking = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.card(context),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
        title: const Text('Session Expired'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock,
                  size: 36, color: AppTheme.primaryOrange),
            ),
            const SizedBox(height: 20),
            Text('Re-enter Admin MPIN',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: AC.text(context))),
            const SizedBox(height: 8),
            Text('Your session expired due to inactivity. Enter your 4-digit MPIN to continue.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AC.textSub(context), height: 1.6)),
            const SizedBox(height: 36),

            // PIN field
            PinCodeTextField(
              appContext: context,
              length: 4,
              controller: _pinCtrl,
              enabled: !_checking,
              autoFocus: true,
              keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              animationType: AnimationType.scale,
              animationDuration: const Duration(milliseconds: 150),
              obscureText: true,
              obscuringWidget: Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryOrange),
              ),
              // FIX: enableActiveFill true removes the gray background bar.
              enableActiveFill: true,
              backgroundColor: Colors.transparent,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(16),
                fieldHeight: 62,
                fieldWidth: 62,
                borderWidth: 1.5,
                activeFillColor: AppTheme.primaryOrange.withAlpha(12),
                activeColor: AppTheme.primaryOrange,
                selectedFillColor: AppTheme.primaryOrange.withAlpha(20),
                selectedColor: AppTheme.primaryOrange,
                inactiveFillColor: AC.card(context),
                inactiveColor: AC.border(context),
              ),
              onChanged: (_) {},
              onCompleted: _submit,
            ),

            if (_checking) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withAlpha(14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppTheme.kumkumRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppTheme.kumkumRed)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 36),

            // Go to login (full logout) — clear session flags
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('admin_session_active');
                if (mounted) {
                  navigator.pushNamedAndRemoveUntil(
                      '/auth-selection', (r) => false);
                }
              },
              child: Text('Not you? Go to Login',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AC.textSub(context),
                      decoration: TextDecoration.underline,
                      decorationColor: AC.textSub(context))),
            ),
          ],
        ),
      ),
    );
  }
}
