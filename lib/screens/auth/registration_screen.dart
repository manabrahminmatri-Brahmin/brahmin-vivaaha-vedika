import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../widgets/auth/auth_bank_widgets.dart';
import '../../widgets/auth/auth_pin_fields.dart';
import '../../widgets/auth/auth_screen_shell.dart';
import '../../services/otp_service.dart';
import '../../core/app_router.dart';
import '../../theme/app_theme.dart';

/// Registration flow — Step 1: Mobile OTP → Step 2: Alternate mobile → Step 3: Terms
/// Navigates to [NewMpinSetupScreen] on success.
class RegistrationScreen extends StatefulWidget {
  final bool disclosureAccepted;

  const RegistrationScreen({
    super.key,
    this.disclosureAccepted = false,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  // ── Controllers ───────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _otpSectionKey = GlobalKey();
  final _mobileController = TextEditingController();
  final _alternateMobileController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpPinFieldController = AuthPinFieldController();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _otpSent = false;
  bool _otpHasError = false;
  bool _otpVerified = false;
  bool _isLoading = false;
  bool _isRegistering = false; // Prevents duplicate doc from double-tap
  Duration? _remainingCooldown;
  Timer? _cooldownTimer;
  // Get auth service
  AuthService get authService => context.read<AuthService>();
  
  // verificationId is stored in AuthController after sendPhoneOtp

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (!widget.disclosureAccepted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, Routes.disclaimer);
      });
      return;
    }
    unawaited(_prepareNewRegistrationState());
  }

  Future<void> _prepareNewRegistrationState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_logged_in');
    await prefs.remove('mpin_verified');
    await prefs.remove('mpin_setup_complete');
    await prefs.remove('profile_complete');
    await prefs.remove('current_user_id');
    await prefs.remove('current_user_name');
    await prefs.remove('last_login_mobile');
    await prefs.remove('is_admin_user');
    await prefs.remove('admin_user_id');
    await prefs.remove('admin_login_verified');
    await prefs.remove('admin_session_active');
  }

  void _goBackSafely() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushNamedAndRemoveUntil(Routes.authSelection, (_) => false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _mobileController.dispose();
    _alternateMobileController.dispose();
    _otpController.dispose();
    _otpPinFieldController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _scrollOtpIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _otpSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ── Cooldown helper ─────────────────────────────────────────────────────
  String _formatCooldown(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  void _startCooldown() {
    setState(() => _remainingCooldown = const Duration(seconds: 60));
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingCooldown = Duration(seconds: 60 - timer.tick);
        if (_remainingCooldown!.inSeconds <= 0) {
          _remainingCooldown = null;
          timer.cancel();
        }
      });
    });
  }

  // ── OTP logic (2factor.in) ──────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    debugPrint('📱 REGISTRATION: _sendOtp started');

    try {
      await authService.initialize();   // 🔥 FIX: Initialize auth service first

      final mobile = _mobileController.text.trim();
      // 🔥 FIX: Use consistent mobile cleaning (handles +91, 91 prefix, spaces, dashes)
      final clean = OtpService.cleanMobileNumber(mobile);
      debugPrint('📱 Mobile: $mobile, Clean: $clean');

      // Check if already registered
      debugPrint('📱 Checking if user already exists...');
      try {
        final userExists = await authService.getUserByMobile(clean).timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        debugPrint('📱 User lookup result: ${userExists != null ? "EXISTS" : "NOT FOUND"}');
        if (!mounted) return;
        if (userExists != null) {
          _showError('This mobile number is already registered. Please login instead.');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ User lookup failed: $e — proceeding with OTP');
      }

      // Send OTP via Firebase Phone Auth (ZIP1 compatible - returns bool)
      debugPrint('📱 Sending OTP to: $clean');
      final sentResult = await authService.sendPhoneOtp(clean);
      final sent = sentResult.success;
      debugPrint('📱 sendPhoneOtp result: success=$sent');
      if (!mounted) return;

      if (sent) {
        setState(() {
          _otpSent = true;
          _startCooldown(); // Start 60-second cooldown
        });
        _scrollOtpIntoView();
        _showSnack('OTP sent to +91$clean', success: true);
      } else {
        _showError(authService.errorMessage ?? 'Failed to send OTP. Please try again.');
      }
    } catch (e) {
      debugPrint('❌ _sendOtp error: $e');
      if (mounted) _showError('Failed to send OTP. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      // 🔥 FIX: Use consistent mobile cleaning (handles +91, 91 prefix, spaces, dashes)
      final mobile = OtpService.cleanMobileNumber(_mobileController.text);
      
      // 2Factor.in manages session internally - no verificationId needed
      debugPrint('🔐 Registration: verifying OTP for $mobile');
      
      final verifyResult = await authService.verifyOTPWithMobile(mobile, otp, null);
      final verified = verifyResult.success;
      if (!mounted) return;

      if (verified) {
        setState(() {
          _isLoading = false;
          _otpVerified = true;
        });
        _showSnack('✅ Mobile number verified!', success: true);
        // User fills alternate mobile + accepts terms, then taps "Create Account"
      } else {
        setState(() => _otpHasError = true);
        _otpPinFieldController.shake();
        _otpController.clear();
        _showError(authService.errorMessage ?? 'Invalid OTP. Please try again.');
      }
    } catch (e) {
      debugPrint('_verifyOtp error: $e');
      if (mounted) {
        setState(() => _otpHasError = true);
        _otpPinFieldController.shake();
        _otpController.clear();
        _showError('OTP verification failed. Please try again.');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _completeRegistration() async {
    // DUPLICATE-PREVENTION FIX 1: Hard guard against double-tap / double-submit.
    // _isLoading alone is not enough — setState is async and two rapid taps can
    // both pass the check before the first tap's setState completes.
    if (_isRegistering) {
      debugPrint('⚠️ _completeRegistration: already in progress — ignoring duplicate call');
      return;
    }
    _isRegistering = true;

    debugPrint('📝 REGISTRATION: _completeRegistration started');

    setState(() => _isLoading = true);
    final authService = context.read<AuthService>();

    // DUPLICATE-PREVENTION FIX 2: Standardize the mobile number HERE, before
    // any lookup. The original code passed the raw text-field value to
    // getUserByMobile but a different (standardized) value to
    // registerWithMobileOtp — a format mismatch could cause the pre-check to
    // find nothing and the service to find (or create) a different doc.
    // 🔥 FIX: Use consistent mobile cleaning (handles +91, 91 prefix, spaces, dashes)
    final mobile = OtpService.cleanMobileNumber(_mobileController.text);

    // 🔥 FIX: Use consistent mobile cleaning for alternate mobile
    final altMobile = OtpService.cleanMobileNumber(_alternateMobileController.text);
    if (altMobile.isNotEmpty) {
      if (!RegExp(r'^\d{10}$').hasMatch(altMobile)) {
        _isRegistering = false;
        setState(() => _isLoading = false);
        _showError('Please enter a valid 10-digit alternate mobile number.');
        return;
      }
      if (altMobile == mobile || altMobile == '91$mobile') {
        _isRegistering = false;
        setState(() => _isLoading = false);
        _showError('Alternate mobile cannot be the same as your primary mobile.');
        return;
      }
    }

    // DUPLICATE-PREVENTION FIX 3: Pre-check for existing account.
    // If lookup FAILS (timeout / network error) → BLOCK registration.
    // The original code silently continued on failure, which allowed a second
    // Firestore doc to be created for a phone that already had one.
    try {
      final existingUserData = await authService.getUserByMobile(mobile).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Account lookup timed out'),
      ) ?? await authService.getUserByMobile('91$mobile').timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Account lookup timed out (91 prefix)'),
      );

      if (existingUserData != null) {
        if (!mounted) return;
        _isRegistering = false;
        setState(() => _isLoading = false);
        _showError('This mobile number is already registered. Please login instead.');
        return;
      }
    } on TimeoutException {
      if (!mounted) return;
      _isRegistering = false;
      setState(() => _isLoading = false);
      _showError('Network is slow. Please check your connection and try again.');
      return;
    } catch (e) {
      // Any lookup error blocks registration — do NOT silently continue.
      if (!mounted) return;
      _isRegistering = false;
      setState(() => _isLoading = false);
      debugPrint('❌ Registration pre-check failed: $e');
      _showError('Could not verify registration status. Please try again.');
      return;
    }

    try {
      debugPrint('🔍 Registration: Starting for $mobile');

      // Note: userData will be saved during profile setup; OTP is already verified by this point
      final result = await authService.registerWithMobileOtp(
        mobile,
        alternateMobile: altMobile.isEmpty ? null : altMobile,
      );

      debugPrint('✅ Registration result: ${result.success}');

      if (!mounted) return;
      _isRegistering = false;
      setState(() => _isLoading = false);

      if (result.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_logged_in', false);
        await prefs.setBool('mpin_setup_complete', false);
        await prefs.setBool('profile_complete', false);
        await prefs.remove('mpin_verified');
        await prefs.remove('last_login_mobile');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, Routes.mpinSetup);
      } else {
        _showError(result.message);
      }
    } catch (e) {
      debugPrint('❌ Registration exception: $e');
      if (!mounted) return;
      _isRegistering = false;
      setState(() => _isLoading = false);
      _showError('Registration failed. Please try again.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showError(String msg) {
    if (!mounted) return;                          // 🔥 FIX: guard first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.kumkumRed),
      );
    });
  }

  void _showSnack(String msg, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? AppTheme.sacredGreen : AppTheme.kumkumRed,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final step = !_otpSent ? 0 : !_otpVerified ? 1 : 2;
    return AuthScreenShell(
      showBack: true,
      onBack: _goBackSafely,
      screenTitle: 'Create account',
      screenSubtitle: 'Step ${step + 1} of 3',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepDots(total: 3, current: step),
            const SizedBox(height: 20),
            AuthSectionCard(child: _buildMobileSection()),
            if (_otpSent && !_otpVerified) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _otpSectionKey,
                child: AuthSectionCard(child: _buildOtpSection()),
              ),
            ],
            if (_otpVerified) ...[
              const SizedBox(height: 12),
              AuthSectionCard(child: _buildAltMobileSection()),
              const SizedBox(height: 16),
              _buildRegisterButton(),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Mobile Section ─────────────────────────────────────────────────────────
  Widget _buildMobileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthFieldLabel(
          'Primary mobile number',
          hint: 'OTP will be sent to this number',
        ),
        AuthMobilePinFormField(
          controller: _mobileController,
          enabled: !_otpSent,
        ),
        if (!_otpSent && !_isLoading) ...[
          const SizedBox(height: 6),
          Text(
            'OTP will be sent to your mobile number',
            style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.primaryOrange),
          ),
        ],
        if (!_otpSent) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _sendOtp,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AC.card(context),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_isLoading ? 'Sending OTP...' : 'Send OTP'),
              style: _primaryButtonStyle(),
            ),
          ),
        ] else if (_otpVerified) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.sacredGreen, size: 18),
              const SizedBox(width: 6),
              Text(
                'Mobile number verified',
                style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.sacredGreen),
              ),
            ],
          ),
        ],
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // ── OTP Section ────────────────────────────────────────────────────────────
  Widget _buildOtpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.lock_outline_rounded, title: 'Enter OTP'),
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
          fieldController: _otpPinFieldController,
          hasError: _otpHasError,
          onChanged: (_) {
            if (_otpHasError) setState(() => _otpHasError = false);
          },
          onCompleted: _verifyOtp,
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
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
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isLoading || _remainingCooldown != null
                  ? null
                  : () {
                      setState(() {
                        _otpSent = false;
                        _otpController.clear();
                        _sendOtp();
                      });
                    },
              child: Text(
                _remainingCooldown != null
                    ? 'Resend in ${_formatCooldown(_remainingCooldown!)}'
                    : 'Resend OTP',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: _remainingCooldown != null
                      ? AC.textMuted(context)
                      : AppTheme.primaryOrange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // ── Alt Mobile Section ─────────────────────────────────────────────────────
  Widget _buildAltMobileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthFieldLabel(
          'Alternate mobile (optional)',
          hint: 'Different from your primary number',
        ),
        AuthMobilePinFormField(
          controller: _alternateMobileController,
          required: false,
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            final err = validateAuthMobileDigits(v);
            if (err != null) return err;
            if (v == _mobileController.text.trim()) {
              return 'Must differ from primary mobile';
            }
            return null;
          },
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // ── Register Button ────────────────────────────────────────────────────────
  Widget _buildRegisterButton() {
    final bool canRegister = _otpVerified && !_isLoading;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canRegister ? _completeRegistration : null,
        style: _primaryButtonStyle(),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                'Create Account',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AC.textSub(context)),
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

ButtonStyle _primaryButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primaryOrange,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 0,
    textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
  );
}
