import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Soft touch button with haptic feedback and smooth animations
class SoftTouchButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double? height;
  final double? borderRadius;
  final EdgeInsets? padding;
  final TextStyle? textStyle;
  final Widget? icon;
  final bool isLoading;
  final bool enabled;
  final List<BoxShadow>? boxShadow;
  final Duration? animationDuration;

  const SoftTouchButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height,
    this.borderRadius,
    this.padding,
    this.textStyle,
    this.icon,
    this.isLoading = false,
    this.enabled = true,
    this.boxShadow,
    this.animationDuration,
  });

  @override
  State<SoftTouchButton> createState() => _SoftTouchButtonState();
}

class _SoftTouchButtonState extends State<SoftTouchButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _opacityController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: widget.animationDuration ?? const Duration(milliseconds: 150),
      vsync: this,
    );
    _opacityController = AnimationController(
      duration: widget.animationDuration ?? const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _opacityController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _opacityController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled || widget.isLoading) return;
    
    _scaleController.forward();
    _opacityController.forward();
    
    // Light haptic feedback for soft touch feel
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled || widget.isLoading) return;
    
    _scaleController.reverse();
    _opacityController.reverse();
    
    // Slightly stronger haptic feedback on release
    HapticFeedback.selectionClick();
  }

  void _handleTapCancel() {
    if (!widget.enabled || widget.isLoading) return;
    
    _scaleController.reverse();
    _opacityController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final defaultBgColor = widget.backgroundColor ?? AppTheme.primaryOrange;
    final defaultFgColor = widget.foregroundColor ?? Colors.white;
    
    return AnimatedBuilder(
      animation: _scaleController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: AnimatedBuilder(
            animation: _opacityController,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: GestureDetector(
                  onTapDown: _handleTapDown,
                  onTapUp: _handleTapUp,
                  onTapCancel: _handleTapCancel,
                  onTap: widget.enabled && !widget.isLoading ? widget.onPressed : null,
                  child: Container(
                    width: widget.width,
                    height: widget.height ?? 48,
                    padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.isLoading 
                          ? defaultBgColor.withAlpha(180)
                          : (widget.enabled ? defaultBgColor : defaultBgColor.withAlpha(100)),
                      borderRadius: BorderRadius.circular(widget.borderRadius ?? 12),
                      boxShadow: widget.boxShadow,
                    ),
                    child: widget.isLoading
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(defaultFgColor),
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (widget.icon != null) ...[
                                widget.icon!,
                                const SizedBox(width: 8),
                              ],
                              Text(
                                widget.text,
                                style: widget.textStyle ?? TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: defaultFgColor,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
