import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/auth/auth_pin_fields.dart';
import 'package:provider/provider.dart';
import '../../core/app_initializer.dart';
import '../../core/result.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/navigation_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../core/app_router.dart';

class MpinSetupScreen extends StatefulWidget {
  const MpinSetupScreen({super.key});
  @override
  State<MpinSetupScreen> createState() => _MpinSetupScreenState();
}

class _MpinSetupScreenState extends State<MpinSetupScreen> {
  final _pin1 = TextEditingController();
  final _pin2 = TextEditingController();
  final _confirmMpinPinFieldController = AuthPinFieldController();
  bool _isLoading = false;
  bool _confirmMpinHasError = false;
  bool _pin1Done = false;

  /// True until first session check finishes.
  bool _sessionCheckPending = true;

  /// Non-null: MPIN cannot be set until user signs out and re-registers or logs in.
  String? _blockReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    final auth = context.read<AuthService>();
    if (auth.currentUser != null) {
      if (mounted) {
        setState(() {
          _sessionCheckPending = false;
          _blockReason = null;
        });
      }
      return;
    }
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      if (mounted) {
        setState(() {
          _sessionCheckPending = false;
          _blockReason =
              'You are not signed in. Go back and use New Registration or Existing Login.';
        });
      }
      return;
    }
    bool ok = false;
    try {
      ok = await auth.restoreSessionFromFirebaseAuth().timeout(
        const Duration(seconds: 12),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('⚠️ MPIN setup session restore failed: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _sessionCheckPending = false;
      _blockReason = ok
          ? null
          : 'No profile was found for this device session. This usually means registration did not finish. Sign out and register again with your mobile number.';
    });
  }

  Future<void> _startOverToAuthSelection() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthService>();
      await auth.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_id');
    } catch (e) {
      debugPrint('⚠️ startOver: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.authSelection,
      (_) => false,
    );
  }

  @override
  void dispose() {
    _pin1.dispose();
    _pin2.dispose();
    _confirmMpinPinFieldController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_blockReason != null) {
      _err(_blockReason!);
      return;
    }
    if (_pin1.text.length != 4) {
      _err('Enter all 4 digits');
      return;
    }
    if (_pin1.text != _pin2.text) {
      _err('MPINs do not match');
      _pin2.clear();
      setState(() {});
      return;
    }
    setState(() => _isLoading = true);

    debugPrint('🔐 MPIN SETUP: Starting _save()');
    debugPrint('🔐 MPIN: ${_pin1.text.hashCode} (hash)');

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      debugPrint('🔐 AuthService currentUser: ${authService.currentUser?.id}');
      debugPrint(
          '🔐 Firebase Auth UID: ${FirebaseAuth.instance.currentUser?.uid}');

      final result = await authService.setMpin(_pin1.text);
      debugPrint(
          '🔐 setMpin result: success=${result.success}, message=${result.message}');

      if (!mounted) return;
      if (result.success) {
        debugPrint('✅ MPIN setup complete, initializing app...');

        // 🔥 GAP 2 FIX: Initialize app identity before navigation
        final initResult = await AppInitializer.initialize().timeout(
          const Duration(seconds: 25),
          onTimeout: () => Result.error(
            'timeout',
            'Setup timed out. Check your connection and try again.',
          ),
        );
        if (initResult.isError) {
          debugPrint('❌ App initialization failed: ${initResult.message}');
          _err('Login failed. Please try again.');
          setState(() => _isLoading = false);
          return;
        }
        debugPrint('✅ App initialized successfully');

        // Prefs used by NavigationService.getInitialRoute / AuthWrapper
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('mpin_setup_complete', true);
        await prefs.setBool('user_logged_in', true);
        await prefs.remove('user_explicitly_logged_out');
        await authService.markSessionMpinVerified();
        NavigationService().invalidateCaches();
        if (!mounted) return;
        await NavigationService().navigateToAppropriateScreen(context);
      } else {
        _err(result.message);
      }
    } catch (e) {
      debugPrint('❌ MPIN setup error: $e');
      if (mounted) _err('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: AppTheme.kumkumRed));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.card(context),
      appBar: AppBar(
        title: Text('Setup MPIN',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.primaryOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(22),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 38, color: AppTheme.primaryOrange),
            ),
            const SizedBox(height: 20),
            Text('Set Your MPIN',
                style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AC.text(context))),
            const SizedBox(height: 8),
            Text('Create a 4-digit PIN to secure your account',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: AC.textSub(context))),
            const SizedBox(height: 20),
            if (_sessionCheckPending)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (_blockReason != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withAlpha(22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.kumkumRed.withAlpha(80),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cannot set MPIN yet',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AC.text(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _blockReason!,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AC.textSub(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : _startOverToAuthSelection,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryOrange,
                          side: const BorderSide(color: AppTheme.primaryOrange),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Sign out and start again',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 12),

            // ── Enter MPIN ───────────────────────────────────────────────
            _fieldLabel('Enter MPIN', context),
            const SizedBox(height: 10),
            AuthMpinPinField(
              controller: _pin1,
              enabled: _blockReason == null && !_sessionCheckPending,
              onChanged: (v) => setState(() => _pin1Done = v.length == 4),
              onCompleted: (_) {
                setState(() => _pin1Done = true);
                FocusScope.of(context).nextFocus();
              },
            ),
            const SizedBox(height: 24),

            // ── Confirm MPIN ─────────────────────────────────────────────
            _fieldLabel('Confirm MPIN', context),
            const SizedBox(height: 10),
            AuthMpinPinField(
              controller: _pin2,
              enabled:
                  _blockReason == null && !_sessionCheckPending && _pin1Done,
              fieldController: _confirmMpinPinFieldController,
              hasError: _confirmMpinHasError,
              onChanged: (_) {
                if (_confirmMpinHasError) setState(() => _confirmMpinHasError = false);
              },
              onCompleted: (v) {
                FocusScope.of(context).unfocus();
                if (v == _pin1.text) {
                  _save();
                } else {
                  setState(() => _confirmMpinHasError = true);
                  _confirmMpinPinFieldController.shake();
                  _err('MPINs do not match');
                  _pin2.clear();
                }
              },
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (_isLoading || _blockReason != null || _sessionCheckPending)
                        ? null
                        : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text('Set MPIN',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _fieldLabel(String t, BuildContext ctx) => Align(
      alignment: Alignment.centerLeft,
      child: Text(t,
          style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: AC.text(ctx))),
    );

