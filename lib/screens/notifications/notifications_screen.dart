import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../services/birth_details_service.dart';
import '../../services/community_reference_service.dart';
import '../../repositories/notification_repository.dart';
import '../../services/notification_service.dart';
import '../../services/message_service.dart';
import '../../services/premium_entitlement_service.dart';
import '../../services/interest_service_v2.dart' show InterestService;
import '../../core/backend/firestore_service.dart';
import '../../legacy/compatibility.dart' hide AuthService;
import '../../core/app_router.dart';
import '../../core/safe_profile_nav.dart';
import '../../core/request_ui_contract.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/request_action_bar.dart';
import '../../utils/safe_data_extractor.dart';

/// Notifications screen — uses [NotificationService] as the single source of truth
/// for Firestore notifications (same list as the bell badge).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _scrollCtrl = ScrollController();
  _NotificationFilter _activeFilter = _NotificationFilter.all;
  final Set<String> _pendingDeleteKeys = <String>{};
  final Map<String, Timer> _pendingDeleteTimers = <String, Timer>{};
  String? _primedUserId;

  Future<void> _refreshCounts(String userId) async {
    if (userId.isEmpty) return;
    final auth = context.read<AuthService>().currentUser;
    final profileId = auth?.profileId ?? '';
    final authUid = auth?.authUid ?? '';
    final ns = context.read<NotificationService>();
    await Future.wait([
      ns.refreshUnreadCount(userId),
      ns.refreshPrivacyRequestReconcile(
        userId,
        profileId: profileId,
        authUid: authUid,
      ),
      context.read<MessageService>().loadMessages(userId, forceReload: true),
    ]);
  }

  bool _isInterestType(String type) {
    switch (type) {
      case 'interest':
      case 'interest_received':
      case 'interest_reminder':
      case 'interest_accepted':
      case 'interest_declined':
      case 'mutual_interest':
        return true;
      default:
        return false;
    }
  }

  Future<void> _markInterestViewedFromNotification(
    Map<String, dynamic> notification,
    String currentUserId,
  ) async {
    final interestService = context.read<InterestService>();
    final type = (notification['type'] as String? ?? '').toLowerCase();
    if (!_isInterestType(type)) return;

    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final interestId = (data['interest_id'] as String?) ??
        (notification['interest_id'] as String?) ??
        '';
    if (interestId.isEmpty) return;

    try {
      await interestService.markInterestViewedByRecipient(interestId);
      // Keep interest badge in sync immediately.
      await interestService.loadInterests(currentUserId);
    } catch (e) {
      debugPrint('⚠️ mark interest viewed failed for $interestId: $e');
    }
  }

  void _primeNotificationsForUser(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty || _primedUserId == uid) return;
    _primedUserId = uid;
    final ns = context.read<NotificationService>();
    final ms = context.read<MessageService>();
    ns.startListening(uid);
    // ignore: discarded_futures
    ns.loadNotifications(uid, force: true, limit: 100);
    // ignore: discarded_futures
    ms.loadMessages(uid, forceReload: true);
    final interestService = context.read<InterestService>();
    // ignore: discarded_futures
    final auth = context.read<AuthService>().currentUser;
    final profileId = auth?.profileId ?? '';
    final authUid = auth?.authUid ?? '';
    // ignore: discarded_futures
    ns.refreshPrivacyRequestReconcile(uid, profileId: profileId, authUid: authUid);
    // ignore: discarded_futures
    interestService.loadInterests(uid).then((_) {
      if (!mounted) return;
      ns.reconcileInterestReceivedNotifications(
        interestService.interestsReceived,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthService>().currentUser?.id ?? '';
      _primeNotificationsForUser(userId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthService>().currentUser?.id ?? '';
      _primeNotificationsForUser(userId);
    });
  }

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _pendingDeleteTimers.clear();
    _pendingDeleteKeys.clear();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId =
        context.select<AuthService, String?>((a) => a.currentUser?.id);
    final notificationService = context.watch<NotificationService>();
    final messageService = context.watch<MessageService>();
    final uid = userId ?? '';
    final notifReady =
        uid.isNotEmpty && notificationService.hasFetchedForUser(uid);

    final unifiedItems = _buildUnifiedItems(
      notificationService.notifications,
      messageService.messagesReceived,
    );
    final visibleItems = unifiedItems.where((item) {
      final source = item['_source'] as String? ?? 'notification';
      final id = item['id'] as String? ?? '';
      if (id.isEmpty) return true;
      return !_pendingDeleteKeys.contains('$source:$id');
    }).toList();
    final filteredItems = _applyFilter(visibleItems);

    // Only block while a fetch is actively running — avoids infinite spinner when
    // initState ran before auth hydrated and never called loadNotifications.
    final blockingLoad =
        uid.isNotEmpty && !notifReady && notificationService.isLoading;

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Notifications',
        showLogo: true,
        showNotifications:
            false, // Don't show notification icon in notifications screen
        additionalActions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unifiedItems.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear all notifications',
                  onPressed: userId != null
                      ? () async {
                          final ns = context.read<NotificationService>();
                          final ms = context.read<MessageService>();
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear All Notifications'),
                              content: const Text(
                                  'Are you sure you want to clear all notifications? This action cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.kumkumRed),
                                  child: const Text('Clear All'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            for (final timer in _pendingDeleteTimers.values) {
                              timer.cancel();
                            }
                            _pendingDeleteTimers.clear();
                            if (mounted) {
                              setState(() => _pendingDeleteKeys.clear());
                            }
                            await ns.clearAllNotifications(userId);
                            await ms.clearAllMessages(userId);
                            await _refreshCounts(userId);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All notifications cleared'),
                                backgroundColor: AppTheme.sacredGreen,
                              ),
                            );
                          }
                        }
                      : null,
                ),
              if (notificationService.unreadCount > 0)
                IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Mark all as read',
                  onPressed: userId != null
                      ? () async {
                          final notificationService =
                              context.read<NotificationService>();
                          await notificationService.markAllAsRead(userId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('All notifications marked as read'),
                              backgroundColor: AppTheme.sacredGreen,
                            ),
                          );
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
      body: blockingLoad
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                final u = userId ?? '';
                await Future.wait([
                  context
                      .read<NotificationService>()
                      .loadNotifications(u, force: true, limit: 100),
                  context
                      .read<MessageService>()
                      .loadMessages(u, forceReload: true),
                ]);
              },
              child: filteredItems.isEmpty
                  ? CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (messageService.isLoading && unifiedItems.isEmpty)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        if (messageService.isLoading && unifiedItems.isEmpty)
                          const LinearProgressIndicator(minHeight: 2),
                        _buildFilterChips(unifiedItems),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final row = filteredItems[index];
                              return _buildNotificationTile(row, userId ?? '');
                            },
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  List<Map<String, dynamic>> _buildUnifiedItems(
    List<Map<String, dynamic>> notifications,
    List<Map<String, dynamic>> incomingMessages,
  ) {
    final notif =
        notifications.map((e) => {...e, '_source': 'notification'}).toList();
    final msgs =
        incomingMessages.map((e) => {...e, '_source': 'message'}).toList();
    final all = [...notif, ...msgs];
    all.sort((a, b) {
      final ad = SafeDataExtractor.parseFirestoreDate(a['created_at']);
      final bd = SafeDataExtractor.parseFirestoreDate(b['created_at']);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return all;
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> items) {
    switch (_activeFilter) {
      case _NotificationFilter.notifications:
        return items
            .where((e) => (e['_source'] as String? ?? '') == 'notification')
            .toList();
      case _NotificationFilter.messages:
        return items
            .where((e) => (e['_source'] as String? ?? '') == 'message')
            .toList();
      case _NotificationFilter.all:
        return items;
    }
  }

  Widget _buildFilterChips(List<Map<String, dynamic>> items) {
    int unreadFor(Map<String, dynamic> e) {
      final source = e['_source'] as String? ?? '';
      if (source == 'notification') {
        return NotificationRepository.isUnread(e) ? 1 : 0;
      }
      if (source == 'message') {
        return MessageService.isIncomingUnread(e) ? 1 : 0;
      }
      return 0;
    }

    final unreadTotal =
        items.fold<int>(0, (sum, e) => sum + unreadFor(e));
    final unreadNotifications = items
        .where((e) => (e['_source'] as String? ?? '') == 'notification')
        .fold<int>(0, (sum, e) => sum + unreadFor(e));
    final unreadMessages = items
        .where((e) => (e['_source'] as String? ?? '') == 'message')
        .fold<int>(0, (sum, e) => sum + unreadFor(e));

    Widget chip({
      required _NotificationFilter filter,
      required String label,
      required int count,
    }) {
      final selected = _activeFilter == filter;
      return ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => setState(() => _activeFilter = filter),
        selectedColor: AppTheme.primaryOrange.withAlpha(35),
        labelStyle: TextStyle(
          color: selected ? AppTheme.primaryOrange : AC.textSub(context),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected
              ? AppTheme.primaryOrange.withAlpha(120)
              : AC.border(context),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(filter: _NotificationFilter.all, label: 'All', count: unreadTotal),
          chip(
            filter: _NotificationFilter.notifications,
            label: 'Notifications',
            count: unreadNotifications,
          ),
          chip(
            filter: _NotificationFilter.messages,
            label: 'Messages',
            count: unreadMessages,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: AC.textMuted(context).withAlpha(100),
          ),
          SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AC.textMuted(context),
                ),
          ),
          SizedBox(height: 8),
          Text(
            'You\'ll see notifications here when someone\nshows interest or requests to view your photo',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AC.textMuted(context),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(
      Map<String, dynamic> notification, String userId) {
    final isPremium =
        context.read<AuthService>().currentUser?.membership.isPremium ?? false;
    final source = notification['_source'] as String? ?? 'notification';
    final type = notification['type'] as String? ?? '';
    final rawTitle = notification['title'] as String? ?? '';
    // Firestore stores the body as 'body' — legacy docs may use 'message'
    final rawMessage = notification['body'] as String? ??
        notification['message'] as String? ??
        '';

    // ── Derive human-readable title/body for message-source items ──────────
    // Photo request docs have no 'title'/'body' — build them from their fields.
    String title = rawTitle;
    String message = rawMessage;
    if (source == 'message') {
      final direction =
          (notification['direction'] as String? ?? '').toLowerCase();
      final status =
          (notification['status'] as String? ?? 'pending').toLowerCase();
      final fromFirst = notification['from_first_name'] as String? ?? 'Someone';
      final toFirst = notification['to_first_name'] as String? ?? 'Someone';

      if (type == 'photo_request') {
        if (title.isEmpty) {
          title = direction == 'received'
              ? 'Photo Request from $fromFirst'
              : 'Photo Request sent to $toFirst';
        }
        if (message.isEmpty) {
          if (direction == 'received') {
            message = (status == 'approved' ||
                    status == 'granted' ||
                    status == 'accepted')
                ? 'You accepted this photo request'
                : (status == 'rejected' || status == 'denied')
                    ? 'You rejected this photo request'
                    : '$fromFirst wants to view your photos';
          } else {
            message = (status == 'approved' ||
                    status == 'granted' ||
                    status == 'accepted')
                ? 'Your photo request was accepted ✓'
                : (status == 'rejected' || status == 'denied')
                    ? 'Your photo request was declined'
                    : 'Waiting for $toFirst to respond…';
          }
        }
      } else {
        if (title.isEmpty) title = 'Message';
        if (!isPremium) {
          message =
              'You have a message from a Premium member. Upgrade to view it.';
        } else if (message.isEmpty) {
          message = 'You have a new message';
        }
      }
    }

    final isRead = source == 'notification'
        ? !NotificationRepository.isUnread(notification)
        : !MessageService.isIncomingUnread(notification);

    // Profile IDs can exist at top-level (message source) or under data (notifications).
    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final relatedProfileId = _resolveTapProfileId(
      source: source,
      type: type,
      currentUserId: userId,
      topLevel: notification,
      data: data,
    );

    final requestDocId = notification['request_doc_id'] as String? ??
        data['request_doc_id'] as String?;
    final requesterId = notification['related_user_id'] as String? ??
        data['liker_user_id'] as String? ??
        data['viewer_user_id'] as String?;

    final date = SafeDataExtractor.parseFirestoreDate(
      notification['created_at'] ?? notification['timestamp'],
    );

    final timeAgo = date != null ? _getTimeAgo(date) : '';
    final stateLabel = _resolveRequestStateLabel(
      type: type,
      statusRaw:
          (notification['status'] as String?) ?? (data['status'] as String?),
    );
    final stateColor = _requestStateColor(stateLabel);

    return Dismissible(
      key: Key('$source:${notification['id'] as String? ?? ''}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.kumkumRed,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(width: 20),
          ],
        ),
      ),
      onDismissed: (direction) async {
        final id = notification['id'] as String? ?? '';
        if (id.isEmpty) return;
        final key = '$source:$id';
        final notificationService = context.read<NotificationService>();
        final messageService = context.read<MessageService>();

        if (mounted) {
          setState(() => _pendingDeleteKeys.add(key));
        } else {
          _pendingDeleteKeys.add(key);
        }

        _pendingDeleteTimers[key]?.cancel();
        _pendingDeleteTimers[key] = Timer(const Duration(seconds: 3), () async {
          try {
            if (source == 'message') {
              final messageType =
                  (notification['type'] as String? ?? '') == 'photo_request'
                      ? 'photo_request'
                      : null;
              await messageService.deleteMessage(
                messageId: id,
                currentUserId: userId,
                messageType: messageType,
              );
            } else {
              await notificationService.deleteNotification(id);
            }
            await _refreshCounts(userId);
          } finally {
            _pendingDeleteTimers.remove(key);
            if (mounted) {
              setState(() => _pendingDeleteKeys.remove(key));
            } else {
              _pendingDeleteKeys.remove(key);
            }
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Item deleted'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Undo',
                textColor: AppTheme.primaryOrange,
                onPressed: () {
                  _pendingDeleteTimers[key]?.cancel();
                  _pendingDeleteTimers.remove(key);
                  if (!mounted) return;
                  setState(() => _pendingDeleteKeys.remove(key));
                },
              ),
            ),
          );
      },
      child: InkWell(
        onTap: () async {
          if (source == 'message') {
            final chatEntitled = await PremiumEntitlementService.isEntitled(
              feature: PremiumEntitlementService.featureChat,
            );
            if (!chatEntitled) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Message preview is locked. Upgrade to Premium to open chat.',
                  ),
                  backgroundColor: AppTheme.primaryOrange,
                ),
              );
              Navigator.pushNamed(context, Routes.premiumUpgrade);
              return;
            }
          }
          if (!mounted) return;
          final notificationService = context.read<NotificationService>();
          final messageService = context.read<MessageService>();
          if (source == 'notification') {
            await notificationService.markAsRead(notification['id'] as String);
            await _markInterestViewedFromNotification(notification, userId);
          } else if (source == 'message') {
            final id = notification['id'] as String? ?? '';
            if (id.isNotEmpty) {
              final mt =
                  (notification['type'] as String? ?? '').toLowerCase() ==
                          'photo_request'
                      ? 'photo_request'
                      : 'message';
              await messageService.markMessageAsRead(
                messageId: id,
                messageType: mt,
              );
            }
          }
          if (!mounted) return;

          String? interestRouteGuardId;
          if (_isInterestType(type)) {
            final raw = (data['interest_id'] as String? ??
                    notification['interest_id'] as String? ??
                    '')
                .trim();
            if (raw.isNotEmpty) interestRouteGuardId = raw;
          }

          // Navigate based on type
          if (relatedProfileId != null && relatedProfileId.isNotEmpty) {
            await _handleNotificationTap(
              type,
              relatedProfileId,
              routeGuardInterestDocId: interestRouteGuardId,
            );
            // nothing uses context after this — ok
          } else {
            if (!mounted) return; // 🔥 FIX: ADD
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile unavailable for this notification'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isRead ? AC.card(context) : AppTheme.textMedium.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? Colors.transparent
                  : AppTheme.textMedium.withAlpha(50),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: _getIconGradient(type),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIcon(type),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  color: isRead
                                      ? AppTheme.textDark
                                      : AppTheme.textMedium,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.kumkumRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AC.textMuted(context),
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                    ),
                    if (stateLabel != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: stateColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: stateColor.withAlpha(55)),
                          ),
                          child: Text(
                            stateLabel,
                            style: TextStyle(
                              color: stateColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (timeAgo.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        timeAgo,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AC.textMuted(context).withAlpha(150),
                              fontSize: 11,
                            ),
                      ),
                    ],
                    // ── Grant / Deny buttons for birth_request (owner side) ──
                    if (type == 'birth_request' && requestDocId != null)
                      _buildBirthRequestActions(
                        context,
                        notification: notification,
                        docId: requestDocId,
                        userId: userId,
                      ),
                    // ── Grant / Deny buttons for community_reference_request (owner side) ──
                    if (type == 'community_reference_request' &&
                        requestDocId != null)
                      _buildCommunityReferenceRequestActions(
                        context,
                        notification: notification,
                        docId: requestDocId,
                        userId: userId,
                      ),
                    // ── Accept / Reject buttons for photo_request (owner side) ──
                    if (type == 'photo_request' && requestDocId != null)
                      _buildPhotoRequestActions(
                        context,
                        notification: notification,
                        docId: requestDocId,
                        requesterId: requesterId ?? '',
                        userId: userId,
                      ),
                    // ── Accept / Decline buttons for interest_received (recipient side) ──
                    if (type == 'interest_received' &&
                        relatedProfileId != null &&
                        relatedProfileId.isNotEmpty)
                      _buildInterestReceivedActions(
                        context,
                        notification: notification,
                        profileId: relatedProfileId,
                        userId: userId,
                      ),
                    // ── View Interest Response buttons (for interest_accepted/declined) ──
                    if ((type == 'interest_accepted' ||
                            type == 'interest_declined') &&
                        relatedProfileId != null &&
                        relatedProfileId.isNotEmpty)
                      _buildInterestResponseActions(
                        context,
                        notification: notification,
                        profileId: relatedProfileId,
                        userId: userId,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _resolveRequestStateLabel({
    required String type,
    String? statusRaw,
  }) {
    final normalizedStatus = (statusRaw ?? '').toLowerCase();
    if (normalizedStatus.isNotEmpty) {
      if (normalizedStatus == 'pending') return 'Pending';
      if (normalizedStatus == 'approved' ||
          normalizedStatus == 'accepted' ||
          normalizedStatus == 'granted') {
        return RequestUiContract.accepted;
      }
      if (normalizedStatus == 'rejected' ||
          normalizedStatus == 'declined' ||
          normalizedStatus == 'denied') {
        return 'Rejected';
      }
      if (normalizedStatus == 'completed' || normalizedStatus == 'done') {
        return 'Completed';
      }
    }

    switch (type) {
      case 'photo_request':
      case 'birth_request':
      case 'community_reference_request':
      case 'interest':
      case 'interest_received': // stored type from firebase_service
      case 'interest_reminder':
        return 'Pending';
      case 'photo_request_approved':
      case 'birth_request_granted':
      case 'community_reference_granted':
        return RequestUiContract.accepted;
      case 'interest_accepted':
      case 'mutual_interest':
        return RequestUiContract.accepted;
      case 'photo_request_rejected':
      case 'birth_request_denied':
      case 'community_reference_denied':
      case 'interest_declined':
        return 'Rejected';
      default:
        return null;
    }
  }

  String? _resolveTapProfileId({
    required String source,
    required String type,
    required String currentUserId,
    required Map<String, dynamic> topLevel,
    required Map<String, dynamic> data,
  }) {
    final topFromUserId = (topLevel['from_user_id'] as String?) ?? '';
    final topToUserId = (topLevel['to_user_id'] as String?) ?? '';
    final dataFromUserId = (data['from_user_id'] as String?) ?? '';
    final dataToUserId = (data['to_user_id'] as String?) ?? '';

    if (source == 'message') {
      if (topFromUserId == currentUserId && topToUserId.isNotEmpty) {
        return topToUserId;
      }
      if (topToUserId == currentUserId && topFromUserId.isNotEmpty) {
        return topFromUserId;
      }
      if (topToUserId.isNotEmpty) return topToUserId;
      if (topFromUserId.isNotEmpty) return topFromUserId;
    }

    switch (type) {
      case 'photo_request':
      case 'interest_received': // stored type from firebase_service
        if (dataFromUserId.isNotEmpty) return dataFromUserId;
        if (dataToUserId.isNotEmpty) return dataToUserId;
        break;
      case 'interest_reminder':
        final rp = (topLevel['related_profile_id'] as String?)?.trim() ?? '';
        if (rp.isNotEmpty) return rp;
        final fp = (data['from_profile_id'] as String?)?.trim() ?? '';
        if (fp.isNotEmpty) return fp;
        if (dataFromUserId.isNotEmpty) return dataFromUserId;
        break;
      case 'photo_request_approved':
      case 'photo_request_rejected':
        // Requester should navigate to owner profile (to_user_id), never self.
        if (dataToUserId.isNotEmpty) return dataToUserId;
        if (dataFromUserId.isNotEmpty) return dataFromUserId;
        break;
    }

    return (topLevel['related_user_id'] as String?) ??
        (data['responder_user_id'] as String?) ??
        (data['liker_user_id'] as String?) ??
        (data['viewer_user_id'] as String?) ??
        (data['from_user_id'] as String?) ??
        (data['to_user_id'] as String?);
  }

  Color _requestStateColor(String? label) {
    switch (label) {
      case 'Pending':
        return AppTheme.primaryOrange;
      case RequestUiContract.accepted:
        return AppTheme.sacredGreen;
      case 'Rejected':
        return AppTheme.kumkumRed;
      case 'Completed':
        return AppTheme.peacockBlue;
      default:
        return AppTheme.textMedium;
    }
  }

  // ── Grant / Deny action row shown on the owner's birth_request notification ─
  Widget _buildBirthRequestActions(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String userId,
  }) {
    // Already responded? Don't show buttons again.
    final responded = notification['_responded'] as bool? ?? false;
    if (responded) return const SizedBox.shrink();

    final notificationService = context.read<NotificationService>();
    final authService = context.read<AuthService>();
    final ownerName = authService.currentUser?.profile?.fullName ?? 'Someone';
    final rawRequesterId = notification['related_user_id'] as String? ?? '';
    final requesterId = rawRequesterId.isNotEmpty
        ? rawRequesterId
        : (docId.contains('_') ? docId.split('_').first : '');

    return StreamBuilder<String?>(
      stream:
          BirthDetailsService().watchBirthRequestStatusByDocId(docId),
      builder: (context, snap) {
        final status = (snap.data ?? '').toLowerCase();
        final shouldShow = snap.hasData && status == 'pending';
        if (!shouldShow) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: RequestActionBar(
            first: RequestActionItem(
              label: RequestUiContract.accept,
              icon: Icons.check,
              isPrimary: true,
              color: AppTheme.sacredGreen,
              onPressed: () async {
                await _respondToBirthRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'accepted',
                  requesterId: requesterId,
                  ownerName: ownerName,
                  userId: userId,
                  notificationService: notificationService,
                );
              },
            ),
            second: RequestActionItem(
              label: RequestUiContract.decline,
              icon: Icons.close,
              color: AppTheme.kumkumRed,
              onPressed: () async {
                await _respondToBirthRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'denied',
                  requesterId: requesterId,
                  ownerName: ownerName,
                  userId: userId,
                  notificationService: notificationService,
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ── Grant / Deny action row for community_reference_request (owner side) ───
  Widget _buildCommunityReferenceRequestActions(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String userId,
  }) {
    // Already responded — hide buttons to prevent double-action.
    final responded = notification['_responded'] as bool? ?? false;
    if (responded) return const SizedBox.shrink();

    final notificationService = context.read<NotificationService>();
    final authService = context.read<AuthService>();
    final ownerName = authService.currentUser?.profile?.fullName ?? 'Someone';

    // requesterId lives in 'related_user_id' (top-level) or data map.
    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final rawRequesterId = notification['related_user_id'] as String? ??
        data['requester_id'] as String? ??
        '';
    // Fall back to parsing docId (format: requesterId_ownerId)
    final requesterId = rawRequesterId.isNotEmpty
        ? rawRequesterId
        : (docId.contains('_') ? docId.split('_').first : '');

    return StreamBuilder<String?>(
      stream: CommunityReferenceService()
          .watchCommunityReferenceRequestStatusByDocId(docId),
      builder: (context, snap) {
        final status = (snap.data ?? '').toLowerCase();
        final shouldShow = snap.hasData && status == 'pending';
        if (!shouldShow) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: RequestActionBar(
            first: RequestActionItem(
              label: RequestUiContract.accept,
              icon: Icons.check,
              isPrimary: true,
              color: AppTheme.sacredGreen,
              onPressed: () async {
                await _respondToCommunityReferenceRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'granted',
                  requesterId: requesterId,
                  ownerName: ownerName,
                  userId: userId,
                  notificationService: notificationService,
                );
              },
            ),
            second: RequestActionItem(
              label: RequestUiContract.decline,
              icon: Icons.close,
              color: AppTheme.kumkumRed,
              onPressed: () async {
                await _respondToCommunityReferenceRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'denied',
                  requesterId: requesterId,
                  ownerName: ownerName,
                  userId: userId,
                  notificationService: notificationService,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _respondToCommunityReferenceRequest(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String status,
    required String requesterId,
    required String ownerName,
    required String userId,
    required NotificationService notificationService,
  }) async {
    if (docId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to process request — missing request ID.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      return;
    }

    // docId format is 'requesterId_ownerId' — extract requesterId from it if empty
    final effectiveRequesterId = requesterId.isNotEmpty
        ? requesterId
        : docId.contains('_')
            ? docId.split('_').first
            : '';

    if (effectiveRequesterId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to process — could not identify requester.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      return;
    }

    try {
      await CommunityReferenceService().respondToCommunityRequest(
        requestId: docId,
        isAccepted: status == 'granted',
      );

      // Mark the notification as read so it won't show buttons again.
      try {
        final notifId = notification['id'] as String? ?? '';
        if (notifId.isNotEmpty) {
          await notificationService.markAsRead(notifId);
        }
        await notificationService.markPrivacyNotificationsReadForRequestDoc(
          docId,
          settledStatus: status,
        );
      } catch (markErr) {
        debugPrint('⚠️ markAsRead failed (non-fatal): $markErr');
      }

      // Hide the buttons immediately in local state.
      notification['_responded'] = true;
      if (!context.mounted) return;
      setState(() {});
      final label = status == 'granted'
          ? 'Community reference access granted ✓'
          : 'Community reference request declined';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(label),
        backgroundColor:
            status == 'granted' ? AppTheme.sacredGreen : AppTheme.kumkumRed,
      ));
    } catch (e) {
      debugPrint('❌ _respondToCommunityReferenceRequest failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Failed to ${status == 'granted' ? 'grant' : 'deny'} request. Please try again.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
    }
  }

  // ── Accept / Reject action row shown on the owner's photo_request notification ─
  Widget _buildPhotoRequestActions(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String requesterId,
    required String userId,
  }) {
    final responded = notification['_responded'] as bool? ?? false;
    if (responded) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.check, size: 15),
              label: const Text(RequestUiContract.accept,
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.sacredGreen,
                side: BorderSide(color: AppTheme.sacredGreen),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                await _respondToPhotoRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'granted',
                  requesterId: requesterId,
                  userId: userId,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Reject', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.kumkumRed,
                side: BorderSide(color: AppTheme.kumkumRed),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                await _respondToPhotoRequest(
                  context,
                  notification: notification,
                  docId: docId,
                  status: 'denied',
                  requesterId: requesterId,
                  userId: userId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToPhotoRequest(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String status,
    required String requesterId,
    required String userId,
  }) async {
    try {
      final notificationService = context.read<NotificationService>();
      await FirestoreService().respondToPhotoRequest(
        requestId: docId,
        status: status,
      );
      final notifId = notification['id'] as String? ?? '';
      if (notifId.isNotEmpty) {
        // Remove acted notification immediately to avoid duplicate/misleading actions.
        await notificationService.deleteNotification(notifId);
      }
      await notificationService.markPrivacyNotificationsReadForRequestDoc(
        docId,
        settledStatus: status,
      );
      notification['_responded'] = true;
      if (!context.mounted) return;
      setState(() {});
      final accepted = status == 'granted' || status == 'accepted';
      final label = accepted
          ? 'Photo access granted ✓'
          : 'Photo request declined';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(label),
        backgroundColor: accepted ? AppTheme.sacredGreen : AppTheme.kumkumRed,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppTheme.kumkumRed,
      ));
    }
  }

  Future<void> _respondToBirthRequest(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String docId,
    required String status,
    required String requesterId,
    required String ownerName,
    required String userId,
    required NotificationService notificationService,
  }) async {
    // Validate inputs before hitting Firestore
    if (docId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to process request — missing request ID.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      return;
    }
    if (requesterId.isEmpty) {
      // Try to recover requesterId from docId (format: requesterId_ownerId)
      debugPrint(
          '⚠️ _respondToBirthRequest: requesterId empty, extracting from docId=$docId');
    }
    final effectiveRequesterId = requesterId.isNotEmpty
        ? requesterId
        : docId.contains('_')
            ? docId.split('_').first
            : '';

    // Safe requester profile ID — try notification field first,
    // then fall back to empty string (respondToRequest handles it gracefully)
    final requesterProfileId =
        (notification['related_profile_id'] as String? ?? '').trim();

    try {
      // Step 1: Update birth_requests document (owner grants/denies)
      await BirthDetailsService().respondToRequest(
        docId: docId,
        status: status,
        requesterId: effectiveRequesterId,
        requesterProfileId: requesterProfileId,
        ownerName: ownerName,
      );

      // Step 2: Mark the notification as read — non-fatal if it fails
      try {
        final notifId = notification['id'] as String? ?? '';
        if (notifId.isNotEmpty) {
          await notificationService.markAsRead(notifId);
        }
        await notificationService.markPrivacyNotificationsReadForRequestDoc(
          docId,
          settledStatus: status,
        );
      } catch (markErr) {
        // Non-fatal — the Grant/Deny succeeded; just log the mark-read failure
        debugPrint('⚠️ markAsRead failed (non-fatal): $markErr');
      }

      // Update local state to hide the buttons immediately
      notification['_responded'] = true;
      if (!context.mounted) return;
      setState(() {});
      final label =
          status == 'granted' ? 'Access granted ✓' : 'Request declined';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(label),
        backgroundColor:
            status == 'granted' ? AppTheme.sacredGreen : AppTheme.kumkumRed,
      ));
    } catch (e) {
      debugPrint('❌ _respondToBirthRequest failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Failed to ${status == 'granted' ? 'grant' : 'deny'} request. Please try again.'),
        backgroundColor: AppTheme.kumkumRed,
      ));
    }
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'interest':
      case 'interest_received': // stored type from firebase_service
        return Icons.favorite;
      case 'interest_reminder':
        return Icons.notifications_active_outlined;
      case 'mutual_interest':
        return Icons.favorite;
      case 'interest_accepted':
        return Icons.favorite;
      case 'interest_declined':
        return Icons.info_outline;
      case 'photo_request':
        return Icons.photo_camera;
      case 'photo_request_approved':
        return Icons.check_circle;
      case 'photo_request_rejected':
        return Icons.cancel;
      case 'birth_request':
        return Icons.cake_outlined;
      case 'birth_request_granted':
        return Icons.verified_outlined;
      case 'birth_request_denied':
        return Icons.cancel_outlined;
      case 'community_reference_request':
        return Icons.people_outline;
      case 'community_reference_granted':
        return Icons.verified_outlined;
      case 'community_reference_denied':
        return Icons.cancel_outlined;
      case 'message':
        return Icons.message;
      default:
        return Icons.notifications;
    }
  }

  Gradient _getIconGradient(String type) {
    switch (type) {
      case 'interest':
      case 'interest_received': // stored type from firebase_service
      case 'mutual_interest':
        return AppTheme.goldGradient;
      case 'interest_reminder':
        return LinearGradient(
          colors: [
            AppTheme.primaryOrange,
            AppTheme.primaryOrange.withAlpha(200)
          ],
        );
      case 'interest_accepted':
        return LinearGradient(
          colors: [AppTheme.sacredGreen, AppTheme.sacredGreen.withAlpha(200)],
        );
      case 'interest_declined':
        return LinearGradient(
          colors: [AppTheme.kumkumRed, AppTheme.kumkumRed.withAlpha(200)],
        );
      case 'photo_request':
        return AppTheme.primaryGradient;
      case 'photo_request_approved':
        return LinearGradient(
          colors: [AppTheme.sacredGreen, AppTheme.sacredGreen.withAlpha(200)],
        );
      case 'photo_request_rejected':
        return LinearGradient(
          colors: [AppTheme.kumkumRed, AppTheme.kumkumRed.withAlpha(200)],
        );
      case 'birth_request':
        return AppTheme.goldGradient;
      case 'birth_request_granted':
        return LinearGradient(
          colors: [AppTheme.sacredGreen, AppTheme.sacredGreen.withAlpha(200)],
        );
      case 'birth_request_denied':
        return LinearGradient(
          colors: [AppTheme.kumkumRed, AppTheme.kumkumRed.withAlpha(200)],
        );
      case 'community_reference_request':
        return AppTheme.goldGradient;
      case 'community_reference_granted':
        return LinearGradient(
          colors: [AppTheme.sacredGreen, AppTheme.sacredGreen.withAlpha(200)],
        );
      case 'community_reference_denied':
        return LinearGradient(
          colors: [AppTheme.kumkumRed, AppTheme.kumkumRed.withAlpha(200)],
        );
      default:
        return AppTheme.primaryGradient;
    }
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(date);
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // ── Accept / Decline buttons shown to the recipient of interest_received ──
  Widget _buildInterestReceivedActions(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String profileId,
    required String userId,
  }) {
    final responded = notification['_responded'] as bool? ?? false;
    if (responded) return const SizedBox.shrink();

    // Interest doc id is stored in data.interest_id or derived from the notification id
    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final interestId = data['interest_id'] as String? ??
        notification['interest_id'] as String? ??
        notification['id'] as String? ??
        '';

    if (interestId.isEmpty) return const SizedBox.shrink();

    Future<void> respond(String status) async {
      final notificationService = context.read<NotificationService>();
      try {
        final interestService = context.read<InterestService>();
        final result = await interestService.respondToInterestWithResult(
          interestId: interestId,
          response: status == 'accepted' ? 'accepted' : 'rejected',
        );
        if (result['success'] != true) {
          throw Exception('respondToInterest returned false');
        }
        // Mark the notification as read and hide buttons
        final notifId = notification['id'] as String? ?? '';
        if (notifId.isNotEmpty) {
          await notificationService.markAsRead(notifId);
        }
        notification['_responded'] = true;
        if (!context.mounted) return;
        setState(() {});
        final label =
            status == 'accepted' ? 'Interest accepted ✓' : 'Interest declined';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(label),
          backgroundColor:
              status == 'accepted' ? AppTheme.sacredGreen : AppTheme.kumkumRed,
        ));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.favorite, size: 15),
              label: const Text(RequestUiContract.accept,
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.sacredGreen,
                side: BorderSide(color: AppTheme.sacredGreen),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => respond('accepted'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 15),
              label: const Text(RequestUiContract.decline,
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.kumkumRed,
                side: BorderSide(color: AppTheme.kumkumRed),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => respond('declined'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterestResponseActions(
    BuildContext context, {
    required Map<String, dynamic> notification,
    required String profileId,
    required String userId,
  }) {
    final type = notification['type'] as String? ?? '';
    final isAccepted = type == 'interest_accepted';

    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final interestRouteGuardId = (data['interest_id'] as String? ??
            notification['interest_id'] as String? ??
            '')
        .trim();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          // ── View Profile ──────────────────────────────────────────────
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(
                isAccepted ? Icons.favorite : Icons.info_outline,
                size: 15,
              ),
              label: Text(
                isAccepted ? 'View Profile' : 'View Details',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryOrange,
                side: BorderSide(color: AppTheme.primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                await _handleNotificationTap(
                  type,
                  profileId,
                  routeGuardInterestDocId: interestRouteGuardId.isEmpty
                      ? null
                      : interestRouteGuardId,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // ── Go to Interests ───────────────────────────────────────
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.people, size: 15),
              label:
                  const Text('View Interests', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textMedium,
                side: BorderSide(color: AppTheme.textMedium),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pushNamed(context, Routes.interests);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(
    String type,
    String profileId, {
    String? routeGuardInterestDocId,
  }) async {
    if (!mounted || profileId.trim().isEmpty) return;
    final resolvedUser =
        await FirestoreService().getUserByAnyId(profileId.trim());
    if (!mounted) return;
    if (resolvedUser != null) {
      await SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: resolvedUser.id,
        routeGuardInterestDocId: routeGuardInterestDocId,
      );
      return;
    }
    await SafeProfileNav.safeOpenProfileByProfileId(
      context,
      profileId: profileId.trim(),
      routeGuardInterestDocId: routeGuardInterestDocId,
    );
  }
}

enum _NotificationFilter { all, notifications, messages }
