// 🔥 RESULT ERROR WIDGET - Proper error UI for Result<T>
// Never just Text(result.message)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/result.dart';
import '../core/error_firewall.dart';
import '../theme/app_theme.dart';

/// ResultErrorWidget - Displays Result errors properly
class ResultErrorWidget extends StatelessWidget {
  final Result<dynamic> result;
  final VoidCallback? onRetry;
  final bool showRetry;
  final String? title;
  
  const ResultErrorWidget({
    super.key,
    required this.result,
    this.onRetry,
    this.showRetry = true,
    this.title,
  });
  
  @override
  Widget build(BuildContext context) {
    final userMessage = ErrorFirewall.toUserMessage(result.errorCode);
    final canRetry = result.errorCode == 'network-error' ||
                     result.errorCode == 'timeout' ||
                     result.errorCode == 'unavailable';
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppTheme.kumkumRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getErrorIcon(),
                color: AppTheme.kumkumRed,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            Text(
              title ?? 'Oops!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.kumkumRed,
              ),
            ),
            const SizedBox(height: 8),
            
            // User-friendly message
            Text(
              userMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            
            // Retry button (if applicable)
            if (showRetry && canRetry && onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(
                  'Try Again',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  IconData _getErrorIcon() {
    switch (result.errorCode) {
      case 'network-error':
      case 'unavailable':
        return Icons.wifi_off;
      case 'timeout':
        return Icons.timer_off;
      case 'not-found':
        return Icons.search_off;
      case 'permission-denied':
        return Icons.block;
      case 'not-authenticated':
        return Icons.lock_outline;
      default:
        return Icons.error_outline;
    }
  }
}

/// ResultLoadingWidget - Shows loading state
class ResultLoadingWidget extends StatelessWidget {
  final String? message;
  
  const ResultLoadingWidget({super.key, this.message});
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppTheme.primaryOrange,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ResultEmptyWidget - Shows empty state
class ResultEmptyWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;
  
  const ResultEmptyWidget({
    super.key,
    this.message = 'No data found',
    this.icon = Icons.inbox_outlined,
    this.onAction,
    this.actionLabel,
  });
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryOrange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ResultBuilder - StreamBuilder helper for `Result<T>` streams.
class ResultBuilder<T> extends StatelessWidget {
  final Stream<Result<T>> stream;
  final Widget Function(T data) builder;
  final Widget Function()? loadingBuilder;
  final Widget Function(Result<T> result)? errorBuilder;
  final VoidCallback? onRetry;
  
  const ResultBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.onRetry,
  });
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Result<T>>(
      stream: stream,
      builder: (context, snapshot) {
        // Loading state
        if (!snapshot.hasData) {
          return loadingBuilder?.call() ?? 
                 const ResultLoadingWidget();
        }
        
        final result = snapshot.data!;
        
        // Error state
        if (result.isError) {
          return errorBuilder?.call(result) ??
                 ResultErrorWidget(
                   result: result,
                   onRetry: onRetry,
                 );
        }
        
        // Success state
        if (result.data == null) {
          return const ResultEmptyWidget();
        }
        
        return builder(result.data as T);
      },
    );
  }
}
