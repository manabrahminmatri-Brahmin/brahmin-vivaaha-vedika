import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Global button styles and configurations for consistent soft touch feel
class GlobalButtonStyles {
  /// Primary soft touch button style
  static ButtonStyle primaryButton({
    Color? backgroundColor,
    Color? foregroundColor,
    double? borderRadius,
    EdgeInsets? padding,
    BoxShadow? boxShadow,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color?>(
        backgroundColor ?? AppTheme.primaryOrange,
      ),
      foregroundColor: WidgetStatePropertyAll<Color?>(
        foregroundColor ?? Colors.white,
      ),
      elevation: WidgetStatePropertyAll<double>(4),
      shadowColor: WidgetStatePropertyAll<Color?>(
        (Colors.black.withAlpha(30)),
      ),
      padding: WidgetStatePropertyAll<EdgeInsets?>(
        padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 12),
        ),
      ),
      animationDuration: const Duration(milliseconds: 150),
    );
  }

  /// Secondary soft touch button style
  static ButtonStyle secondaryButton({
    Color? backgroundColor,
    Color? foregroundColor,
    double? borderRadius,
    EdgeInsets? padding,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color?>(
        backgroundColor ?? Colors.transparent,
      ),
      foregroundColor: WidgetStatePropertyAll<Color?>(
        foregroundColor ?? AppTheme.primaryOrange,
      ),
      elevation: WidgetStatePropertyAll<double>(0),
      padding: WidgetStatePropertyAll<EdgeInsets?>(
        padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 12),
          side: BorderSide(
            color: foregroundColor ?? AppTheme.primaryOrange,
            width: 1.5,
          ),
        ),
      ),
      animationDuration: const Duration(milliseconds: 150),
    );
  }

  /// Danger button style (for delete, cancel actions)
  static ButtonStyle dangerButton({
    double? borderRadius,
    EdgeInsets? padding,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(AppTheme.kumkumRed),
      foregroundColor: WidgetStatePropertyAll<Color>(Colors.white),
      elevation: WidgetStatePropertyAll<double>(4),
      shadowColor: WidgetStatePropertyAll<Color>(
        AppTheme.kumkumRed.withAlpha(30),
      ),
      padding: WidgetStatePropertyAll<EdgeInsets?>(
        padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 12),
        ),
      ),
      animationDuration: const Duration(milliseconds: 150),
    );
  }

  /// Upgrade button style (premium features)
  static ButtonStyle upgradeButton({
    double? borderRadius,
    EdgeInsets? padding,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(AppTheme.kumkumRed),
      foregroundColor: WidgetStatePropertyAll<Color>(Colors.white),
      elevation: WidgetStatePropertyAll<double>(4),
      shadowColor: WidgetStatePropertyAll<Color>(
        AppTheme.kumkumRed.withAlpha(30),
      ),
      padding: WidgetStatePropertyAll<EdgeInsets?>(
        padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 12),
        ),
      ),
      animationDuration: const Duration(milliseconds: 150),
    );
  }
}

/// Extension methods for enhanced button interactions
extension ButtonExtensions on Widget {
  /// Add soft touch feel to any button
  Widget withSoftTouch({
    required VoidCallback onPressed,
    bool enabled = true,
    Duration? animationDuration,
  }) {
    return GestureDetector(
      onTapDown: enabled ? (_) => HapticFeedback.lightImpact() : null,
      onTapUp: enabled ? (_) => HapticFeedback.selectionClick() : null,
      onTap: enabled ? onPressed : null,
      child: AnimatedScale(
        scale: enabled ? 1.0 : 0.95,
        duration: animationDuration ?? const Duration(milliseconds: 100),
        child: this,
      ),
    );
  }
}
