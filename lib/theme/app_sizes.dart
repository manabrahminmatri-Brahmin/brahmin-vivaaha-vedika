import 'package:flutter/widgets.dart';

class AppSizes {
  // Spacing
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  // Radii
  static const double rSm = 10;
  static const double rMd = 16;
  static const double rLg = 24;

  // Bottom nav
  static const double bottomNavHeight = 72;
  static const double bottomNavMarginH = 16;
  static const double bottomNavMarginTop = 8;
  static const double bottomNavMarginBottom = 16;
  static const double bottomNavRadius = 28;

  /// Scrollable body padding under [HomeScreen]'s floating glass nav when
  /// `extendBody` is true (Matches tab, Interests tab, etc.).
  static double shellBottomContentInset(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).bottom;
    return pad +
        bottomNavMarginTop +
        bottomNavHeight +
        bottomNavMarginBottom +
        8;
  }
}

