import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Simple field label (bank-style).
class AuthFieldLabel extends StatelessWidget {
  final String text;
  final String? hint;

  const AuthFieldLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AC.textMuted(context),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AC.textSub(context),
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

/// Single content card used across auth flows.
class AuthBankCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AuthBankCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Full-width tappable secondary link (e.g. "Not you? Use another number").
class AuthTouchLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;

  const AuthTouchLink({
    super.key,
    required this.label,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: padding,
            tapTargetSize: MaterialTapTargetSize.padded,
            foregroundColor: AppTheme.primaryOrange,
            disabledForegroundColor: AC.textMuted(context),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard section card for registration, login, and forgot-MPIN steps.
class AuthSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    return AuthBankCard(
      padding: padding,
      child: child,
    );
  }
}

/// Footer links: Register | Forgot MPIN (bank-style).
class AuthFooterLinks extends StatelessWidget {
  final VoidCallback? onRegister;
  final VoidCallback? onForgotMpin;
  final bool showRegister;
  final bool showForgotMpin;

  const AuthFooterLinks({
    super.key,
    this.onRegister,
    this.onForgotMpin,
    this.showRegister = true,
    this.showForgotMpin = true,
  });

  @override
  Widget build(BuildContext context) {
    final links = <Widget>[];

    void addLink(String label, VoidCallback? onTap) {
      if (onTap == null) return;
      if (links.isNotEmpty) {
        links.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '|',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AC.textMuted(context),
              ),
            ),
          ),
        );
      }
      links.add(
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryOrange,
            ),
          ),
        ),
      );
    }

    if (showRegister) addLink('New user? Register', onRegister);
    if (showForgotMpin) addLink('Forgot MPIN?', onForgotMpin);

    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: links,
      ),
    );
  }
}

/// Minimal step dots (e.g. ● ○ ○).
class AuthStepDots extends StatelessWidget {
  final int total;
  final int current;

  const AuthStepDots({
    super.key,
    required this.total,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: done || active
                ? AppTheme.primaryOrange
                : AppTheme.surfaceLight2,
          ),
        );
      }),
    );
  }
}

/// Primary / secondary action row (Biometric | Continue).
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppTheme.primaryOrange;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AC.card(context),
                ),
              )
            : Text(label),
      ),
    );
  }
}
