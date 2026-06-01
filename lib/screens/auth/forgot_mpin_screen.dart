import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/auth/auth_bank_widgets.dart';
import '../../widgets/auth/auth_pin_fields.dart';
import '../../widgets/auth/auth_screen_shell.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/otp_service.dart';
import '../../services/navigation_service.dart';
import '../../core/app_router.dart';
import '../../theme/app_theme.dart';

/// Forgot MPIN — 3-step flow: verify mobile → OTP → set new MPIN.
/// Consolidates duplicate OTP + rate-limit logic from the old screen.
class ForgotMpinScreen extends StatefulWidget {
  /// Pre-fill mobile when redirected from new-device login flow.
  final String? prefillMobile;
  const ForgotMpinScreen({super.key, this.prefillMobile});

  @override
  State<ForgotMpinScreen> createState() => _ForgotMpinScreenState();
}

class _ForgotMpinScreenState extends State<ForgotMpinScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  final _newMpinController = TextEditingController();
  final _confirmMpinController = TextEditingController();
  final _otpPinFieldController = AuthPinFieldController();
  final _newMpinPinFieldController = AuthPinFieldController();
  final _confirmMpinPinFieldController = AuthPinFieldController();

  // ── State ────────────────────────────────────────────────────────────────
  bool _otpHasError = false;
  bool _confirmMpinHasError = false;
  bool _isLoading = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  Duration? _remainingCooldown;
  Timer? _cooldownTimer;
  User? _foundUser; // Store the found user for MPIN reset

  bool get _hasPrefilledMobile =>
      (widget.prefillMobile ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Pre-fill mobile when redirected from new-device login
    final prefill = widget.prefillMobile;
    if (prefill != null && prefill.isNotEmpty) {
      _mobileController.text = OtpService.cleanMobileNumber(prefill);
      // Show helpful message for existing users
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'We will verify your registered mobile number to reset MPIN.',
              ),
              backgroundColor: AppTheme.primaryOrange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _mobileController.dispose();
    _newMpinController.dispose();
    _confirmMpinController.dispose();
    // PinCodeTextField may still detach during unmount; dispose OTP controller last.
    _otpController.dispose();
    _otpPinFieldController.dispose();
    _newMpinPinFieldController.dispose();
    _confirmMpinPinFieldController.dispose();
    super.dispose();
  }

  String _formatCooldown(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String _maskedMobile(String mobile) {
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return 'your registered mobile';
    return '******${digits.substring(digits.length - 4)}';
  }

  Future<void> _signInWithAnotherMobile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_logged_in');
    await prefs.remove('mpin_verified');
    await prefs.remove('current_user_id');
    await prefs.remove('current_user_name');
    await prefs.remove('last_login_mobile');
    await prefs.setBool('user_explicitly_logged_out', true);
    NavigationService().invalidateCaches();
    if (!mounted) return;
    _goBackSafely();
  }

  void _goBackSafely() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushNamedAndRemoveUntil(Routes.authSelection, (_) => false);
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // 🔥 FIX: Use consistent mobile cleaning (handles +91, 91 prefix, spaces, dashes)
    final clean = OtpService.cleanMobileNumber(_mobileController.text);
    final authService = context.read<AuthService>();

    debugPrint('📱 FORGOT MPIN: _sendOtp started');
    debugPrint('📱 Mobile input (clean): $clean');

    // ── FIX: Ensure Firebase anonymous auth session exists before any Firestore
    // query. On the Forgot-MPIN screen the user is NOT yet logged in, so
    // FirebaseAuth.currentUser is null and every Firestore read returns
    // permission-denied. signInAnonymously() is safe — it returns the same UID
    // for an existing anonymous account on this device, no data is lost.
    try {
      if (firebase_auth.FirebaseAuth.instance.currentUser == null) {
        debugPrint('📱 No Firebase session, signing in anonymously...');
        await firebase_auth.FirebaseAuth.instance.signInAnonymously();
        debugPrint('✅ Anonymous sign-in successful, UID: ${firebase_auth.FirebaseAuth.instance.currentUser?.uid}');
      } else {
        debugPrint('📱 Existing Firebase session: ${firebase_auth.FirebaseAuth.instance.currentUser?.uid}');
      }
    } catch (e) {
      debugPrint('⚠️ ForgotMpin: could not restore Firebase session: $e');
    }

    // Must be a registered mobile.
    // Try both "8985xxxxxx" and "918985xxxxxx" — some accounts may be stored
    // with the country code prefix depending on how they registered.
    debugPrint('📱 Looking up user by mobile: $clean');
    User? match;
    try {
      match = await authService.getUserByMobile(clean);
      debugPrint('📱 getUserByMobile($clean) result: ${match != null ? "FOUND (id=${match.id})" : "NOT FOUND"}');
      // Fallback: try with 91 prefix if not found
      if (match == null && !clean.startsWith('91')) {
        debugPrint('📱 Trying with 91 prefix: 91$clean');
        match = await authService.getUserByMobile('91$clean');
        debugPrint('📱 getUserByMobile(91$clean) result: ${match != null ? "FOUND (id=${match.id})" : "NOT FOUND"}');
      }
    } catch (e) {
      debugPrint('❌ FORGOT MPIN: getUserByMobile error: $e');
      if (!mounted) return;
      final msg = e.toString().contains('TimeoutException')
          ? 'Network timeout — please check your connection and try again.'
          : 'Error looking up account: ${e.toString()}';
      _showError(msg);
      setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    if (match == null) {
      debugPrint("❌ FORGOT MPIN: User NOT found → showing register");
      _showError('Mobile number not found. Please register first.');
      setState(() => _isLoading = false);
      return;
    } else {
      debugPrint("✅ FORGOT MPIN: User found → proceeding");
    }

    // Store the found user for later use in MPIN reset
    _foundUser = match;

    // Use the new restoreExistingSession(User) overload that properly
    // sets in-memory state and SharedPreferences without writing to Firestore.
    debugPrint('📱 Restoring session for user: ${match.id}');
    await authService.restoreExistingSession(match.mobileNumber);

    // Send OTP via Firebase Phone Auth
    debugPrint('📱 Sending OTP to: $clean');
    final sentResult = await authService.sendPhoneOtp(clean);
    final sent = sentResult.success;
    debugPrint('📱 sendPhoneOtp result: success=$sent');
    if (!mounted) return;

    // Small delay to prevent widget tree conflicts during state transition
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (sent) _otpSent = true;
    });

    if (sent) {
      if (mounted) {
        _showSnack('OTP sent to +91$clean', success: true);
      }
    } else {
      if (mounted) {
        final err = authService.errorMessage ?? 'Failed to send OTP';
        // Show simpler error to avoid widget tree issues
        _showError('OTP failed: $err');
      }
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() => _isLoading = true);
    final authService = context.read<AuthService>();

    // 🔥 FIX: Always clean mobile number before verify (strip +91, spaces, dashes)
    final verifyMobile = _mobileController.text
        .trim()
        .replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // 2Factor.in manages session internally - no verificationId needed
    debugPrint('🔐 Verifying OTP for $verifyMobile');

    final verifyResult = await authService.verifyOTPWithMobile(
      verifyMobile,
      otp,
      null,
    );
    final verified = verifyResult.success;
    
    // Small delay to prevent widget tree conflicts during state transition
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _otpVerified = verified;
      if (!verified) {
        _otpHasError = true;
      }
    });

    if (!verified) {
      _otpPinFieldController.shake();
      _otpController.clear();
    }

    if (mounted) {
      _showSnack(
        verified ? 'OTP verified!' : (verifyResult.message),
        success: verified,
      );
    }
  }

  Future<void> _resetMpin() async {
    if (!_formKey.currentState!.validate()) return;

    final newMpin = _newMpinController.text;
    final confirmMpin = _confirmMpinController.text;

    if (newMpin.length != 4) {
      _showError('MPIN must be 4 digits.');
      return;
    }
    if (newMpin != confirmMpin) {
      _showError('MPINs do not match.');
      return;
    }

    setState(() => _isLoading = true);
    final authService = context.read<AuthService>();

    try {
      // restoreExistingSession() in _sendOtp already initialized AuthService
      // and persisted the correct userId. Do NOT call initialize() here —
      // it would re-run _loadUserData which could overwrite _currentUser with
      // a stale or null value if the device had no prior session.

      // Use setMpinForUser() to write to the correct Firestore doc
      // (the anonymous Firebase session's UID is different from the real user's doc ID)
      final userId = _foundUser?.id ?? authService.currentUser?.id ?? '';
      if (userId.isEmpty) {
        setState(() => _isLoading = false);
        _showError('User session lost. Please try again.');
        return;
      }
      final result = await authService.setMpinForUser(
        _mobileController.text.trim(),
        newMpin,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.success) {
        // BUG 11 FIX: restore all session flags so /home is shown, not /login
        final authService2 = context.read<AuthService>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('mpin_setup_complete', true);
        await prefs.setBool('user_logged_in', true);
        await prefs.remove('user_explicitly_logged_out');  // Clear logout flag
        final u = authService2.currentUser;
        if (u != null) {
          await prefs.setString('current_user_id', u.id);
          await prefs.setString('current_user_name', u.profile?.fullName ?? u.firstName);
          await prefs.setString('last_login_mobile', u.mobileNumber);
          final p = u.profile;
          final hasProfile = p != null &&
              (p.firstName.isNotEmpty == true) &&
              (p.occupation?.isNotEmpty == true ||
               p.education?.isNotEmpty == true ||
               p.aboutMe?.isNotEmpty == true);
          if (hasProfile) await prefs.setBool('profile_complete', true);
          await authService.markSessionMpinVerified();
        }
        NavigationService().invalidateCaches();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account restored! Welcome back.'),
            backgroundColor: AppTheme.sacredGreen,
          ),
        );
        final route = await NavigationService().getInitialRoute();
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
      } else {
        _showError(result.message);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to reset MPIN. Please try again.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    // Schedule after current frame to avoid lifecycle conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.kumkumRed),
      );
    });
  }

  void _showSnack(String msg, {required bool success}) {
    if (!mounted) return;
    // Schedule after current frame to avoid lifecycle conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ),
      );
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Step: 0 = mobile, 1 = OTP, 2 = new MPIN
    final step = !_otpSent ? 0 : !_otpVerified ? 1 : 2;

    return AuthScreenShell(
      showBack: true,
      onBack: _goBackSafely,
      screenTitle: 'Reset MPIN',
      screenSubtitle: 'Step ${step + 1} of 3',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepDots(total: 3, current: step),
            const SizedBox(height: 16),
            // ── Step 0 : Mobile ──────────────────────────────
            AuthSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthFieldLabel(
                    'Registered mobile number',
                    hint: 'Enter the number linked to your account',
                  ),
                  if (_hasPrefilledMobile) ...[
                    Text(
                      'Forgot MPIN? We\'ll send an OTP to your registered mobile number ending in ${_mobileController.text.length >= 4 ? _mobileController.text.substring(_mobileController.text.length - 4) : '****'}.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AC.textSub(context),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryOrange.withAlpha(55),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_rounded,
                            color: AppTheme.primaryOrange,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _maskedMobile(_mobileController.text),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: AC.text(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  AuthMobilePinFormField(
                    controller: _mobileController,
                    enabled: !_otpSent && !_hasPrefilledMobile,
                  ),
                  if (_remainingCooldown != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Resend available in ${_formatCooldown(_remainingCooldown!)}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppTheme.kumkumRed,
                      ),
                    ),
                  ],
                  if (!_otpSent) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading || _remainingCooldown != null
                            ? null
                            : _sendOtp,
                        icon: _isLoading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AC.card(context),
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(_isLoading ? 'Sending…' : 'Send OTP'),
                        style: _primaryButtonStyle(color: AppTheme.primaryOrange),
                      ),
                    ),
                    if (_hasPrefilledMobile) ...[
                      AuthTouchLink(
                        label: 'Not you? Sign in with another mobile number',
                        onPressed:
                            _isLoading ? null : _signInWithAnotherMobile,
                      ),
                    ],
                  ] else if (_otpVerified) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.sacredGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Mobile verified',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppTheme.sacredGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (_otpSent && !_otpVerified) ...[
              const SizedBox(height: 12),
              AuthSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(
                      icon: Icons.lock_outline_rounded,
                      title: 'Enter OTP',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'A 6-digit OTP was sent to +91 ${_mobileController.text}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthOtpPinField(
                      controller: _otpController,
                      accentColor: AppTheme.kumkumRed,
                      fieldController: _otpPinFieldController,
                      hasError: _otpHasError,
                      onChanged: (_) {
                        if (_otpHasError) setState(() => _otpHasError = false);
                      },
                      onCompleted: _verifyOtp,
                    ),
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppTheme.primaryOrange,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Verifying OTP…',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AC.textSub(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _remainingCooldown != null
                              ? null
                              : () {
                                  if (!mounted) return;
                                  setState(() {
                                    _otpSent = false;
                                    _otpController.clear();
                                  });
                                  _sendOtp();
                                },
                          child: Text(
                            _remainingCooldown != null
                                ? 'Resend in ${_formatCooldown(_remainingCooldown!)}'
                                : 'Resend OTP',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _remainingCooldown != null
                                  ? AC.textMuted(context)
                                  : AppTheme.primaryOrange,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (!mounted) return;
                            setState(() {
                              _otpSent = false;
                              _otpController.clear();
                            });
                          },
                          child: Text(
                            'Change Number',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppTheme.primaryOrange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_otpVerified) ...[
              const SizedBox(height: 12),
              AuthSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(
                      icon: Icons.pin_outlined,
                      title: 'Set New MPIN',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'New MPIN',
                        style: TextStyle(
                          fontSize: 13,
                          color: AC.textSub(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AuthMpinPinField(
                      controller: _newMpinController,
                      fieldController: _newMpinPinFieldController,
                      onChanged: (_) {
                        if (_confirmMpinHasError) {
                          setState(() => _confirmMpinHasError = false);
                        }
                      },
                      onCompleted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Confirm MPIN',
                        style: TextStyle(
                          fontSize: 13,
                          color: AC.textSub(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AuthMpinPinField(
                      controller: _confirmMpinController,
                      fieldController: _confirmMpinPinFieldController,
                      hasError: _confirmMpinHasError,
                      onChanged: (_) {
                        if (_confirmMpinHasError) {
                          setState(() => _confirmMpinHasError = false);
                        }
                      },
                      onCompleted: (value) {
                        FocusScope.of(context).unfocus();
                        if (value == _newMpinController.text) {
                          _resetMpin();
                        } else {
                          setState(() => _confirmMpinHasError = true);
                          _confirmMpinPinFieldController.shake();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('MPINs do not match — try again'),
                              backgroundColor: AppTheme.kumkumRed,
                            ),
                          );
                          _confirmMpinController.clear();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _resetMpin,
                        style: _primaryButtonStyle(color: AppTheme.kumkumRed),
                        child: _isLoading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AC.card(context),
                                ),
                              )
                            : Text(
                                'Set MPIN',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets & shared helpers ─────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.kumkumRed),
        SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AC.text(context),
          ),
        ),
      ],
    );
  }
}

ButtonStyle _primaryButtonStyle({Color color = AppTheme.primaryOrange}) {
  return ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 0,
    textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
  );
}
