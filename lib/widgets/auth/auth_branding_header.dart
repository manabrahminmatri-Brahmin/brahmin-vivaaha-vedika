import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Logo + "mana" / "Vivaaha Vedika" / subtitle block shared across auth screens.
class AuthBrandingHeader extends StatelessWidget {
  /// Full header for selection / registration intro screens.
  static const double logoSize = 144.9;
  static const double logoBorderRadius = 14;
  static const double gapLogoToTitle = 6;
  static const double gapManaToVivaaha = 2;
  static const double gapVivaahaToSubtitle = 2;

  /// Tighter header for sign-in / MPIN flows (fits one screen).
  static const double compactLogoSize = 106.26;
  static const double compactGapLogoToTitle = 4;

  final bool compact;

  const AuthBrandingHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? compactLogoSize : logoSize;
    final radius = compact ? 12.0 : logoBorderRadius;
    final manaSize = compact ? 26.0 : 34.0;
    final vivaahaSize = compact ? 22.0 : 30.0;
    final subtitleSize = compact ? 12.0 : 14.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withAlpha(20),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Icon(
                    Icons.account_balance_rounded,
                    size: compact ? 54.00 : 78.00,
                    color: AppTheme.primaryOrange,
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: compact ? compactGapLogoToTitle : gapLogoToTitle),
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'mana',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: manaSize,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryOrange,
                  height: 1.05,
                ),
              ),
              SizedBox(height: compact ? 1 : gapManaToVivaaha),
              Text(
                'Vivaaha Vedika',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: vivaahaSize,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryOrange,
                  height: 1.08,
                ),
              ),
              SizedBox(height: compact ? 2 : gapVivaahaToSubtitle),
              Text(
                'For Telugu Brahmin',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: subtitleSize,
                  color: AppTheme.primaryOrange.withAlpha(230),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
