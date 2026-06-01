import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared “soft touch” behaviour: light haptic + consistent ink on key surfaces.
///
/// Use [wrap] on header and custom actions; global [ElevatedButton]/[OutlinedButton]/
/// [TextButton] styles are tuned in [AppTheme] so most screens pick this up automatically.
abstract final class SoftTouch {
  SoftTouch._();

  static void impact() => HapticFeedback.lightImpact();

  /// Runs a light haptic, then the callback (skips haptic when [callback] is null).
  static VoidCallback? wrap(VoidCallback? callback) {
    if (callback == null) return null;
    return () {
      HapticFeedback.lightImpact();
      callback();
    };
  }

  /// [IconButton]s on the orange app bar (white icons, soft white ripple).
  static ButtonStyle orangeHeaderIconStyle({ButtonStyle? merge}) {
    final base = IconButton.styleFrom(
      foregroundColor: Colors.white,
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.26);
        }
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
    );
    return merge == null ? base : base.merge(merge);
  }
}
