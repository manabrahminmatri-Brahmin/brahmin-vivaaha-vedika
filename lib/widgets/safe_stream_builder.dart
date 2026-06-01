import 'package:flutter/material.dart';

/// Safe stream builder wrapper that prevents crashes
class SafeStreamBuilder<T> extends StatelessWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Widget? emptyWidget;
  final String? emptyMessage;

  const SafeStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingWidget,
    this.errorWidget,
    this.emptyWidget,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        // Error state
        if (snapshot.hasError) {
          return errorWidget ?? _buildErrorWidget(context, snapshot.error);
        }

        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ?? _buildLoadingWidget(context);
        }

        // No data state
        if (!snapshot.hasData) {
          return emptyWidget ?? _buildEmptyWidget(context);
        }

        // Handle empty list/data
        final data = snapshot.data as T;
        bool isEmpty = false;
        
        if (data is List && data.isEmpty) {
          isEmpty = true;
        } else if (data is Map && data.isEmpty) {
          isEmpty = true;
        } else if (data is String && data.isEmpty) {
          isEmpty = true;
        }

        if (isEmpty) {
          return emptyWidget ?? _buildEmptyWidget(context);
        }

        // Data available
        return builder(context, data);
      },
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorWidget(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Unknown error',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage ?? 'No data available',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe future builder wrapper
class SafeFutureBuilder<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Widget? emptyWidget;
  final String? emptyMessage;

  const SafeFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loadingWidget,
    this.errorWidget,
    this.emptyWidget,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        // Error state
        if (snapshot.hasError) {
          return errorWidget ?? _buildErrorWidget(context, snapshot.error);
        }

        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ?? _buildLoadingWidget(context);
        }

        // No data state
        if (!snapshot.hasData) {
          return emptyWidget ?? _buildEmptyWidget(context);
        }

        // Handle empty list/data
        final data = snapshot.data as T;
        bool isEmpty = false;
        
        if (data is List && data.isEmpty) {
          isEmpty = true;
        } else if (data is Map && data.isEmpty) {
          isEmpty = true;
        } else if (data is String && data.isEmpty) {
          isEmpty = true;
        }

        if (isEmpty) {
          return emptyWidget ?? _buildEmptyWidget(context);
        }

        // Data available
        return builder(context, data);
      },
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorWidget(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Unknown error',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage ?? 'No data available',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
