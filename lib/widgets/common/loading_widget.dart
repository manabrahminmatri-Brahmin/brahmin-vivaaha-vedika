import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Custom loading widget with consistent styling
class LoadingWidget extends StatelessWidget {
  final String? message;
  final double? size;
  final Color? color;
  final double strokeWidth;
  final bool isCentered;

  const LoadingWidget({
    super.key,
    this.message,
    this.size,
    this.color,
    this.strokeWidth = 3.0,
    this.isCentered = true,
  });

  /// Small loading indicator
  const LoadingWidget.small({
    super.key,
    this.message,
    this.color,
  }) : size = 24.0,
       strokeWidth = 2.0,
       isCentered = false;

  /// Large loading indicator
  const LoadingWidget.large({
    super.key,
    this.message,
    this.color,
  }) : size = 48.0,
       strokeWidth = 4.0,
       isCentered = true;

  @override
  Widget build(BuildContext context) {
    final dim = (size ?? 32).toDouble();
    final Widget loadingIndicator = SizedBox(
      width: dim,
      height: dim,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppTheme.primaryOrange,
        ),
      ),
    );

    if (message != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          loadingIndicator,
          if (message != null) ...[
            SizedBox(height: dim <= 26 ? 16 : 12),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AC.textSub(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    }

    return isCentered ? Center(child: loadingIndicator) : loadingIndicator;
  }
}

/// Full screen loading widget
class FullScreenLoadingWidget extends StatelessWidget {
  final String? message;
  final Color? backgroundColor;
  final Widget? child;

  const FullScreenLoadingWidget({
    super.key,
    this.message,
    this.backgroundColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (child != null) child! else const LoadingWidget.large(),
            if (message != null) ...[
              SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AC.textSub(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading overlay widget
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? loadingMessage;
  final Color? overlayColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.loadingMessage,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: overlayColor ?? (Colors.black.withValues(alpha: 0.5)),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AC.card(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LoadingWidget.large(),
                    if (loadingMessage != null) ...[
                      SizedBox(height: 16),
                      Text(
                        loadingMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AC.textSub(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Skeleton loading widget
class SkeletonWidget extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Color? color;

  const SkeletonWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AC.textMuted(context),
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

/// List skeleton loading widget
class ListSkeletonWidget extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry? padding;

  const ListSkeletonWidget({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 80,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SkeletonWidget(width: 60, height: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonWidget(
                      width: double.infinity,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    SkeletonWidget(
                      width: double.infinity * 0.7,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Card skeleton loading widget
class CardSkeletonWidget extends StatelessWidget {
  final double? width;
  final double height;
  final EdgeInsetsGeometry? margin;

  const CardSkeletonWidget({
    super.key,
    this.width,
    required this.height,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin ?? const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SkeletonWidget(width: 48, height: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonWidget(
                        width: double.infinity * 0.6,
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      SkeletonWidget(
                        width: double.infinity * 0.4,
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SkeletonWidget(
              width: double.infinity * 0.8,
              height: 12,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            SkeletonWidget(
              width: double.infinity * 0.6,
              height: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}
