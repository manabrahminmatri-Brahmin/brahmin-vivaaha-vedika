import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Custom button widget with consistent styling
class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final bool isOutlined;
  final bool isFullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double? height;
  final double? width;
  final TextStyle? textStyle;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isOutlined = false,
    this.isFullWidth = false,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.height,
    this.width,
    this.textStyle,
    this.child,
    this.padding,
  });

  /// Primary button constructor
  const AppButton.primary({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isFullWidth = false,
    this.height,
    this.width,
    this.textStyle,
    this.padding,
  }) : isOutlined = false,
       backgroundColor = AppTheme.primaryOrange,
       foregroundColor = Colors.white,
       borderColor = null,
       child = null;

  /// Outlined button constructor
  const AppButton.outlined({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isFullWidth = false,
    this.height,
    this.width,
    this.textStyle,
    this.padding,
  }) : isOutlined = true,
       backgroundColor = Colors.transparent,
       foregroundColor = AppTheme.primaryOrange,
       borderColor = AppTheme.primaryOrange,
       child = null;

  /// Secondary button constructor
  const AppButton.secondary({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isFullWidth = false,
    this.height,
    this.width,
    this.textStyle,
    this.padding,
  }) : isOutlined = false,
       backgroundColor = AppTheme.surfaceLight2,
       foregroundColor = AppTheme.textDark,
       borderColor = null,
       child = null;

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor = isDisabled 
        ? AC.textMuted(context) 
        : backgroundColor;
    
    final effectiveForegroundColor = isDisabled 
        ? AC.textMuted(context) 
        : foregroundColor;
    
    final effectiveBorderColor = isDisabled 
        ? AC.textMuted(context) 
        : borderColor;

    final buttonChild = child ?? _buildTextContent(context);

    final button = SizedBox(
      width: isFullWidth ? double.infinity : width,
      height: height ?? 56,
      child: ElevatedButton(
        onPressed: isDisabled || isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: effectiveBackgroundColor,
          foregroundColor: effectiveForegroundColor,
          elevation: isOutlined ? 0 : 2,
          shadowColor: isOutlined ? Colors.transparent : null,
          side: isOutlined ? BorderSide(color: effectiveBorderColor!) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        child: buttonChild,
      ),
    );

    if (isLoading) {
      return Stack(
        children: [
          button,
          Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    effectiveForegroundColor ?? AppTheme.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return button;
  }

  Widget _buildTextContent(BuildContext context) {
    return Text(
      text,
      style: textStyle ?? Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: isDisabled ? AC.textMuted(context) : foregroundColor,
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
