import 'package:flutter/material.dart';
import 'global_error_handler.dart';
import '../widgets/loading_widgets.dart';

/// Safe widget wrapper that catches errors and shows fallback UI
class SafeWidget extends StatelessWidget {
  final Widget child;
  final Widget fallback;
  final String? context;

  const SafeWidget({
    super.key,
    required this.child,
    this.fallback = const _DefaultErrorWidget(),
    this.context,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      errorBuilder: (error) => fallback,
      child: child,
    );
  }
}

/// Default error widget for safe wrapper
class _DefaultErrorWidget extends StatelessWidget {
  const _DefaultErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[300], size: 32),
          const SizedBox(height: 8),
          Text(
            'Unable to load content',
            style: TextStyle(
              color: const Color(0xFF9E9E9E),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Safe image loader with error handling
class SafeImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const SafeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ?? _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          GlobalErrorHandler().handleException(
            error,
            stackTrace,
            context: 'SafeImage: $imageUrl',
          );
          return errorWidget ?? _buildErrorWidget();
        },
      );
    } catch (e, stackTrace) {
      GlobalErrorHandler().handleException(
        e,
        stackTrace,
        context: 'SafeImage build: $imageUrl',
      );
      return errorWidget ?? _buildErrorWidget();
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEEEEEE),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEEEEEE),
      child: Icon(Icons.broken_image, color: const Color(0xFFBDBDBD)),
    );
  }
}

/// Safe future builder with error handling
class SafeFutureBuilder<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loadingWidget;
  final Widget Function(Object error)? errorBuilder;
  final String? errorContext;

  const SafeFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loadingWidget,
    this.errorBuilder,
    this.errorContext,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(child: LoadingIndicator(size: 44));
        }

        if (snapshot.hasError) {
          final error = snapshot.error!;
          final stackTrace = snapshot.stackTrace;

          GlobalErrorHandler().handleException(
            error,
            stackTrace,
            context: errorContext ?? 'SafeFutureBuilder',
          );

          return errorBuilder?.call(error) ?? _buildErrorWidget(error.toString());
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        try {
          return builder(context, snapshot.data as T);
        } catch (e, stackTrace) {
          GlobalErrorHandler().handleException(
            e,
            stackTrace,
            context: '${errorContext ?? 'SafeFutureBuilder'} - Build error',
          );
          return errorBuilder?.call(e) ?? _buildErrorWidget(e.toString());
        }
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[300]),
          const SizedBox(height: 8),
          Text(
            'Failed to load data',
            style: TextStyle(color: const Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }
}

/// Safe stream builder with error handling
class SafeStreamBuilder<T> extends StatelessWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loadingWidget;
  final Widget? emptyWidget;
  final Widget Function(Object error)? errorBuilder;
  final String? errorContext;

  const SafeStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingWidget,
    this.emptyWidget,
    this.errorBuilder,
    this.errorContext,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(child: LoadingIndicator(size: 44));
        }

        if (snapshot.hasError) {
          final error = snapshot.error!;
          final stackTrace = snapshot.stackTrace;

          GlobalErrorHandler().handleException(
            error,
            stackTrace,
            context: errorContext ?? 'SafeStreamBuilder',
          );

          return errorBuilder?.call(error) ?? _buildErrorWidget(error.toString());
        }

        if (!snapshot.hasData) {
          return emptyWidget ?? const SizedBox.shrink();
        }

        try {
          return builder(context, snapshot.data as T);
        } catch (e, stackTrace) {
          GlobalErrorHandler().handleException(
            e,
            stackTrace,
            context: '${errorContext ?? 'SafeStreamBuilder'} - Build error',
          );
          return errorBuilder?.call(e) ?? _buildErrorWidget(e.toString());
        }
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[300]),
          const SizedBox(height: 8),
          Text(
            'Failed to load data',
            style: TextStyle(color: const Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }
}

/// Safe button that handles tap errors
class SafeButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  /// Optional description for error reporting (not a [BuildContext]).
  final String? errorContext;

  const SafeButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.errorContext,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: style,
      onPressed: onPressed != null
          ? () {
              try {
                onPressed!();
              } catch (e, stackTrace) {
                GlobalErrorHandler().handleException(
                  e,
                  stackTrace,
                  context: errorContext ?? 'SafeButton onPressed',
                );
              }
            }
          : null,
      child: child,
    );
  }
}

/// Safe gesture detector that handles gesture errors
class SafeGestureDetector extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final String? errorContext;

  const SafeGestureDetector({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.errorContext,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap != null
          ? () {
              try {
                onTap!();
              } catch (e, stackTrace) {
                GlobalErrorHandler().handleException(
                  e,
                  stackTrace,
                  context: errorContext ?? 'SafeGestureDetector onTap',
                );
              }
            }
          : null,
      onDoubleTap: onDoubleTap != null
          ? () {
              try {
                onDoubleTap!();
              } catch (e, stackTrace) {
                GlobalErrorHandler().handleException(
                  e,
                  stackTrace,
                  context: errorContext ?? 'SafeGestureDetector onDoubleTap',
                );
              }
            }
          : null,
      onLongPress: onLongPress != null
          ? () {
              try {
                onLongPress!();
              } catch (e, stackTrace) {
                GlobalErrorHandler().handleException(
                  e,
                  stackTrace,
                  context: errorContext ?? 'SafeGestureDetector onLongPress',
                );
              }
            }
          : null,
      child: child,
    );
  }
}
