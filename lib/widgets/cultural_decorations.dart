import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Simple modern decorations for clean design
class SimpleDecorations {
  
  /// Creates a simple border decoration
  static Widget simpleBorder({
    required Widget child,
    double padding = 16,
    Color? borderColor,
  }) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? AppTheme.grayVeryLight,
          width: 1,
        ),
      ),
      child: child,
    );
  }
  
  /// Creates a simple card decoration
  static Widget simpleCard({
    required Widget child,
    required BuildContext context,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
