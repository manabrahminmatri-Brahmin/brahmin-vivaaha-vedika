import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Enhanced loading state widget with better UX
/// Provides consistent loading indicators across the app
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final double? size;
  final Color? color;
  final bool isOverlay;

  const LoadingIndicator({
    super.key,
    this.message,
    this.size,
    this.color,
    this.isOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    final double s = ((size ?? 48).clamp(24.0, 96.0)).toDouble();
    final Color ringColor =
        color ?? Theme.of(context).colorScheme.primary;
    final loadingWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s,
          height: s,
          child: CircularProgressIndicator(
            strokeWidth: s >= 40 ? 3.5 : 2.5,
            color: ringColor,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (isOverlay) {
      return Container(
        color: AppTheme.primaryOrange.withAlpha(128),
        child: Center(child: loadingWidget),
      );
    }

    return Center(child: loadingWidget);
  }
}

/// Modal, non-dismissible blocking loader (long operations). Pop with `Navigator.pop(context)`.
Future<void> showManaBlockingDialog(
  BuildContext context, {
  String? message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(45),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Full-screen dimmed barrier with centered spinner (no dialog inset). Pop to dismiss.
Future<void> showManaFullScreenBlockingOverlay(
  BuildContext context, {
  String? message,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Loading',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, __) {
      final msgStyle = Theme.of(ctx).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withAlpha(230),
            fontWeight: FontWeight.w600,
          );
      return PopScope(
        canPop: false,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: Colors.white,
                  ),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: msgStyle,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Smart loading wrapper that handles loading states gracefully
class SmartLoader<T> extends StatefulWidget {
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;
  final String? loadingMessage;
  final Duration? timeout;

  const SmartLoader({
    super.key,
    required this.future,
    required this.builder,
    this.errorBuilder,
    this.loadingBuilder,
    this.loadingMessage,
    this.timeout,
  });

  @override
  State<SmartLoader<T>> createState() => _SmartLoaderState<T>();
}

class _SmartLoaderState<T> extends State<SmartLoader<T>> {
  Object? _error;
  T? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _executeFuture();
  }

  @override
  void didUpdateWidget(SmartLoader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future != widget.future) {
      _executeFuture();
    }
  }

  void _executeFuture() async {
  setState(() {
    _isLoading = true;
    _error = null;
    _data = null;
  });

  try {
    final future = widget.timeout != null
        ? widget.future.timeout(widget.timeout!)
        : widget.future;

    final result = await future;
    if (mounted) {
      setState(() {
        _data = result;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = e;
      });
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingBuilder?.call(context) ??
          LoadingIndicator(message: widget.loadingMessage);
    }

    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          _buildErrorWidget(context, _error!);
    }

    if (_data != null) {
      return widget.builder(context, _data as T);
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorWidget(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).hintColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _executeFuture,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer loading effect for better perceived performance
class ShimmerLoader extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            baseColor ?? AppTheme.textLight,
            highlightColor ?? AppTheme.textLight,
            baseColor ?? AppTheme.textLight,
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}
