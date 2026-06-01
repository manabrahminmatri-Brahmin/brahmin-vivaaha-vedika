import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Empty state widget with consistent styling
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imagePath;
  final Widget? customWidget;
  final VoidCallback? onAction;
  final String? actionText;
  final bool showAction;
  final EdgeInsetsGeometry? padding;

  const EmptyStateWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.imagePath,
    this.customWidget,
    this.onAction,
    this.actionText,
    this.showAction = false,
    this.padding,
  });

  /// No data empty state
  const EmptyStateWidget.noData({
    super.key,
    required this.title,
    this.subtitle,
    this.onAction,
    this.actionText,
    this.padding,
  }) : icon = Icons.inbox_outlined,
       imagePath = null,
       customWidget = null,
       showAction = onAction != null;

  /// No search results empty state
  const EmptyStateWidget.noSearchResults({
    super.key,
    this.subtitle,
    this.onAction,
    this.actionText,
    this.padding,
  }) : title = 'No results found',
       icon = Icons.search_off,
       imagePath = null,
       customWidget = null,
       showAction = onAction != null;

  /// Network error empty state
  const EmptyStateWidget.networkError({
    super.key,
    this.subtitle,
    this.onAction,
    this.actionText = 'Retry Connection',
    this.padding,
  }) : title = 'No Internet Connection',
       icon = Icons.wifi_off,
       imagePath = null,
       customWidget = null,
       showAction = true;

  /// Server error empty state
  const EmptyStateWidget.serverError({
    super.key,
    this.subtitle,
    this.onAction,
    this.actionText = 'Retry',
    this.padding,
  }) : title = 'Something went wrong',
       icon = Icons.error_outline,
       imagePath = null,
       customWidget = null,
       showAction = true;

  @override
  Widget build(BuildContext context) {
    // Check if this is a network error state
    final bool isNetworkError = title.toLowerCase().contains('internet') || 
                                 title.toLowerCase().contains('connection') ||
                                 title.toLowerCase().contains('offline');
    
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (customWidget != null)
            customWidget!
          else if (imagePath != null)
            Image.asset(
              imagePath!,
              width: isNetworkError ? 160 : 120,
              height: isNetworkError ? 160 : 120,
              fit: BoxFit.contain,
            )
          else
            Container(
              width: isNetworkError ? 120 : 80,
              height: isNetworkError ? 120 : 80,
              decoration: BoxDecoration(
                color: isNetworkError 
                    ? AppTheme.kumkumRed.withValues(alpha: 0.1)
                    : AppTheme.primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isNetworkError ? 60 : 40),
              ),
              child: Icon(
                icon ?? Icons.info_outline,
                size: isNetworkError ? 64 : 40,
                color: isNetworkError ? AppTheme.kumkumRed : AppTheme.primaryOrange,
              ),
            ),
          SizedBox(height: isNetworkError ? 32 : 24),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: isNetworkError ? 22 : null,
              color: isNetworkError ? AppTheme.kumkumRed : AC.text(context),
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            SizedBox(height: isNetworkError ? 12 : 8),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: isNetworkError ? 16 : null,
                color: AC.textSub(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (showAction && onAction != null) ...[
            SizedBox(height: isNetworkError ? 32 : 24),
            SizedBox(
              width: isNetworkError ? double.infinity : null,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isNetworkError ? AppTheme.sacredGreen : AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isNetworkError ? 32 : 24, 
                    vertical: isNetworkError ? 16 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  actionText ?? 'Action',
                  style: TextStyle(
                    fontSize: isNetworkError ? 18 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty list widget
class EmptyListWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onRefresh;
  final bool isRefreshable;

  const EmptyListWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.onRefresh,
    this.isRefreshable = true,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget.noData(
      title: title,
      subtitle: subtitle,
      onAction: isRefreshable ? onRefresh : null,
      actionText: 'Refresh',
    );
  }
}

/// Empty search widget
class EmptySearchWidget extends StatelessWidget {
  final String? searchQuery;
  final VoidCallback? onClearSearch;

  const EmptySearchWidget({
    super.key,
    this.searchQuery,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget.noSearchResults(
      subtitle: searchQuery != null 
          ? 'No results found for "$searchQuery"'
          : 'Try searching with different keywords',
      onAction: onClearSearch,
      actionText: 'Clear Search',
    );
  }
}

/// Empty favorites widget
class EmptyFavoritesWidget extends StatelessWidget {
  final VoidCallback? onExplore;

  const EmptyFavoritesWidget({
    super.key,
    this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return const EmptyStateWidget.noData(
      title: 'No favorites yet',
      subtitle: 'Start adding profiles to your favorites to see them here',
    );
  }
}

/// Empty messages widget
class EmptyMessagesWidget extends StatelessWidget {
  final VoidCallback? onStartChat;

  const EmptyMessagesWidget({
    super.key,
    this.onStartChat,
  });

  @override
  Widget build(BuildContext context) {
    return const EmptyStateWidget.noData(
      title: 'No messages yet',
      subtitle: 'Start a conversation to see your messages here',
    );
  }
}

/// Empty notifications widget
class EmptyNotificationsWidget extends StatelessWidget {
  final VoidCallback? onExplore;

  const EmptyNotificationsWidget({
    super.key,
    this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return const EmptyStateWidget.noData(
      title: 'No notifications',
      subtitle: 'You\'re all caught up! Check back later for updates',
    );
  }
}
