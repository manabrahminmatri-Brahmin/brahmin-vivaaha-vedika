import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Beautiful gradient progress indicator with cultural theme
class GradientProgress extends StatelessWidget {
  final double progress;
  final double height;
  final double? width;
  final Color? backgroundColor;
  final List<Color>? gradientColors;
  final BorderRadius? borderRadius;
  final String? label;
  final TextStyle? labelStyle;
  final bool showPercentage;

  const GradientProgress({
    super.key,
    required this.progress,
    this.height = 8,
    this.width,
    this.backgroundColor,
    this.gradientColors,
    this.borderRadius,
    this.label,
    this.labelStyle,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? [
      AppTheme.primaryGold,
      AppTheme.primaryOrange,
      AppTheme.kumkumRed,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label!,
                style: labelStyle ?? TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AC.text(context),
                ),
              ),
              if (showPercentage)
                Text(
                  '${(progress * 100).toInt()}%',
                  style: labelStyle ?? TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryOrange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.textLight.withAlpha(30),
            borderRadius: borderRadius ?? BorderRadius.circular(height / 2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: borderRadius ?? BorderRadius.circular(height / 2),
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withAlpha(50),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular gradient progress indicator
class CircularGradientProgress extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final List<Color>? gradientColors;
  final Widget? child;
  final Color? backgroundColor;

  const CircularGradientProgress({
    super.key,
    required this.progress,
    this.size = 100,
    this.strokeWidth = 8,
    this.gradientColors,
    this.child,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? [
      AppTheme.primaryGold,
      AppTheme.primaryOrange,
      AppTheme.kumkumRed,
    ];

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Background circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeWidth,
              backgroundColor: backgroundColor ?? AppTheme.textLight.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(
                backgroundColor ?? AppTheme.textLight.withAlpha(30),
              ),
            ),
          ),
          // Progress circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(colors.first),
            ),
          ),
          // Child content
          if (child != null)
            Center(child: child!),
        ],
      ),
    );
  }
}

/// Profile completion progress with cultural theme
class ProfileCompletionProgress extends StatelessWidget {
  final double completionPercentage;
  final VoidCallback? onCompleteProfile;

  const ProfileCompletionProgress({
    super.key,
    required this.completionPercentage,
    this.onCompleteProfile,
  });

  @override
  Widget build(BuildContext context) {
    return CulturalDecorations.culturalCard(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline,
                color: AppTheme.primaryOrange,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Complete Your Profile',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryOrange,
                ),
              ),
              const Spacer(),
              Text(
                '${completionPercentage.toInt()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GradientProgress(
            progress: completionPercentage / 100,
            height: 12,
            gradientColors: [
              AppTheme.primaryGold,
              AppTheme.primaryOrange,
              AppTheme.kumkumRed,
            ],
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          if (completionPercentage < 100)
            ElevatedButton(
              onPressed: onCompleteProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Complete Profile',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AC.surface(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryOrange,
                  width: 1,
                ),
              ),
              child: Text(
                'Profile Complete!',
                style: TextStyle(
                  color: AppTheme.primaryOrange,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryOrange,
                  size: 20,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Cultural decorations for the progress widget
class CulturalDecorations {
  /// Creates a cultural card with rangoli background and temple borders
  static Widget culturalCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    double borderRadius = 12,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppTheme.primaryGold.withAlpha(100),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGold.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius - 2),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              AppTheme.primaryGold.withAlpha(10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: child,
      ),
    );
  }
}
