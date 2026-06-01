import 'package:flutter/material.dart';

/// Unified transition helper — use for EVERY screen push/replace in the app.
///
/// Usage:
///   Navigator.push(context, AppTransitions.slideUp(const MyScreen()));
///   Navigator.push(context, AppTransitions.slide(const MyScreen()));
///   Navigator.push(context, AppTransitions.fade(const MyScreen()));
class AppTransitions {
  AppTransitions._();

  static const Duration _duration = Duration(milliseconds: 280);
  static const Curve _curve = Curves.easeOutCubic;

  // Opaque scaffold-colored backdrop — matches light/dark theme (no flash).
  static Widget _bg(BuildContext context, Widget page) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: page,
      );

  /// Slide in from the right (standard forward navigation)
  static PageRoute<T> slide<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      pageBuilder: (context, _, __) => _bg(context, page),
      transitionDuration: _duration,
      reverseTransitionDuration: _duration,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: _curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  /// Slide up from bottom (modals, bottom sheets as full page)
  static PageRoute<T> slideUp<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      pageBuilder: (context, _, __) => _bg(context, page),
      transitionDuration: _duration,
      reverseTransitionDuration: _duration,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: _curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  /// Fade transition (for tab switches and detail overlays)
  static PageRoute<T> fade<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      pageBuilder: (context, _, __) => _bg(context, page),
      transitionDuration: _duration,
      reverseTransitionDuration: _duration,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: _curve),
          child: child,
        );
      },
    );
  }

  /// Fade + slight scale up (for profile cards, dialogs)
  static PageRoute<T> fadeScale<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      pageBuilder: (context, _, __) => _bg(context, page),
      transitionDuration: _duration,
      reverseTransitionDuration: _duration,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: _curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
