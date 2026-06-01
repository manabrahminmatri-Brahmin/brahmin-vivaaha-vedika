import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../../features/auth/auth_controller.dart';
// import '../../features/engagement/like_service.dart';
// import '../../features/engagement/interest_service.dart';
// import '../../services/notification_service.dart';
import '../../core/app_router.dart';
import '../../core/interest_badge_aggregator.dart';
import '../../services/auth_service.dart';
import '../../services/message_service.dart';
import '../../services/interest_service_v2.dart';
import '../../services/notification_service.dart';
import '../../services/like_service_v2.dart';
import '../../services/privacy_enforcement_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../../features/profile/profile_repository.dart';
import '../../repositories/activity_feed_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/profile_photo.dart';
import '../../models/user.dart';
import '../../core/safe_profile_nav.dart';

/// Activity Center - Central hub for all user interactions
/// Consolidates: Interests, Messages, Notifications, Profile Analytics
class ActivityCenterScreen extends StatefulWidget {
  const ActivityCenterScreen({super.key});

  @override
  State<ActivityCenterScreen> createState() => _ActivityCenterScreenState();
}

class _ActivityCenterScreenState extends State<ActivityCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    setState(() {});
  }

  Future<void> _loadAllData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final interestService = context.read<InterestService>();
      final notificationService = context.read<NotificationService>();
      final messageService = context.read<MessageService>();
      final userId = authService.currentUser?.id ?? '';
      if (userId.isEmpty) return;

      await Future.wait<void>([
        interestService.ensureHubLiveSync(userId),
        interestService.loadInterests(userId, force: true),
        notificationService.loadNotifications(userId, force: true),
        messageService.startListening(userId),
        messageService.loadMessages(userId, forceReload: true),
      ]);
    } catch (e) {
      debugPrint('❌ Error loading activity data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: CustomScrollView(
        slivers: [
          // Standardized Header - matching Home Screen style with logo
          SliverAppHeader(
            title: 'Activity Center',
            showLogo: true,
            showUpgradeButton: false,
            showNotifications: false,
            additionalActions: [
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white, size: 22),
                tooltip: 'Discover matches',
                onPressed: () => NavHelper.push(context, Routes.matches),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: Colors.white, size: 22),
                tooltip: 'Settings',
                onPressed: () => NavHelper.push(context, Routes.settings),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _loadAllData,
              ),
            ],
          ),

          // Tab Bar and Content
          SliverFillRemaining(
            hasScrollBody: true,
            child: Column(
              children: [
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AC.surface2(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    labelColor: AppTheme.primaryOrange,
                    unselectedLabelColor: AC.textSub(context),
                    indicator: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(51),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    tabs: const [
                      Tab(text: 'My Actions', icon: Icon(Icons.person)),
                      Tab(text: 'Activity About Me', icon: Icon(Icons.info)),
                      Tab(text: 'Interests', icon: Icon(Icons.favorite)),
                      Tab(text: 'Messages', icon: Icon(Icons.message)),
                    ],
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      MyActionsTab(),
                      ActivityAboutMeTab(),
                      InterestsTab(),
                      MessagesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// My Actions Tab - Profiles I interacted with
class MyActionsTab extends StatelessWidget {
  const MyActionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        context.select<AuthService, String?>((a) => a.currentUser?.id) ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AC.text(context),
            ),
          ),
          const SizedBox(height: 16),

          // Action Cards
          _buildActionCard(
            context,
            'Profiles I Liked',
            'Open liked profiles list',
            null,
            Icons.favorite,
            Colors.pink,
            () => Navigator.pushNamed(context, Routes.liked),
            countBuilder: currentUserId.isEmpty
                ? null
                : StreamBuilder(
                    stream: LikeServiceV2().streamLikesSent(),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      final count =
                          (data?.data ?? const <Map<String, dynamic>>[]).length;
                      return Text(
                        '$count',
                        style: TextStyle(
                            fontSize: 12, color: AC.textMuted(context)),
                      );
                    },
                  ),
          ),
          _buildActionCard(
            context,
            'Interests Sent',
            'Open interests and responses',
            null,
            Icons.send,
            Colors.orange,
            () => Navigator.pushNamed(context, Routes.interests),
            countBuilder: Builder(
              builder: (context) {
                final sent =
                    context.watch<InterestService>().interestsSent.length;
                return Text(
                  '$sent',
                  style: TextStyle(fontSize: 12, color: AC.textMuted(context)),
                );
              },
            ),
          ),
          _buildActionCard(
            context,
            'Profiles I Viewed',
            'Open profile analytics',
            null,
            Icons.visibility,
            Colors.blue,
            () => Navigator.pushNamed(context, Routes.profileAnalytics),
            countBuilder: currentUserId.isEmpty
                ? null
                : StreamBuilder<int>(
                    stream: ActivityFeedRepository()
                        .watchProfileViewsCountAsViewer(currentUserId),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Text(
                        '$count',
                        style: TextStyle(
                            fontSize: 12, color: AC.textMuted(context)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    String subtitle,
    int? count,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    Widget? countBuilder,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: AC.border(context), width: 0.5)
            : null,
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: AC.shadow(context),
                  blurRadius: 8,
                  offset: Offset(0, 4),
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
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AC.text(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: AC.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            countBuilder ??
                Text(
                  (count ?? 0).toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: AC.textMuted(context),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Activity About Me Tab - How others interact with my profile
class ActivityAboutMeTab extends StatelessWidget {
  const ActivityAboutMeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        context.select<AuthService, String?>((a) => a.currentUser?.id) ?? '';
    final interestSvc = context.watch<InterestService>();
    final interestsReceived = InterestBadgeAggregator.visibleReceivedTotal(
      interestSvc.interestsReceived.cast<Map<String, dynamic>>(),
    );
    final interestsSent = InterestBadgeAggregator.visibleSentTotal(
      interestSvc.interestsSent.cast<Map<String, dynamic>>(),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity About Me',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AC.text(context),
            ),
          ),
          const SizedBox(height: 16),

          // Activity Cards
          _buildActivityCard(
            context,
            'Profile Views',
            'Number of times your profile was viewed',
            '',
            Icons.visibility,
            Colors.blue,
            () => Navigator.pushNamed(context, Routes.whoSawProfile),
            countBuilder: currentUserId.isEmpty
                ? null
                : StreamBuilder<int>(
                    stream: ActivityFeedRepository()
                        .watchProfileViewsCountForViewedProfile(
                            currentUserId),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Text('$count');
                    },
                  ),
          ),
          _buildActivityCard(
            context,
            'Interest Received',
            'Number of interests you received',
            '$interestsReceived',
            Icons.favorite,
            Colors.green,
            () => Navigator.pushNamed(context, Routes.interests),
          ),
          _buildActivityCard(
            context,
            'Interested',
            'Number of interests you sent',
            '$interestsSent',
            Icons.send,
            Colors.orange,
            () => Navigator.pushNamed(context, Routes.interests),
          ),
          _buildActivityCard(
            context,
            'Profile Liked',
            'Number of times you were liked',
            '',
            Icons.bookmark,
            Colors.purple,
            () => Navigator.pushNamed(context, Routes.liked),
            countBuilder: currentUserId.isEmpty
                ? null
                : StreamBuilder(
                    stream: LikeServiceV2().streamLikesReceived(),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      final count =
                          (data?.data ?? const <Map<String, dynamic>>[]).length;
                      return Text('$count');
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    String title,
    String subtitle,
    String count,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    Widget? countBuilder,
  }) {
    return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Theme.of(context).brightness == Brightness.dark
                ? Border.all(color: AC.border(context), width: 0.5)
                : null,
            boxShadow: Theme.of(context).brightness == Brightness.dark
                ? const <BoxShadow>[]
                : [
                    BoxShadow(
                      color: AC.shadow(context),
                      blurRadius: 8,
                      offset: Offset(0, 4),
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
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AC.text(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: AC.textMuted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                DefaultTextStyle(
                  style: TextStyle(fontSize: 12, color: AC.textMuted(context)),
                  child: countBuilder ?? Text(count),
                ),
              ],
            ),
          ),
        ));
  }
}

/// Interests Tab - Combined sent and received interests
class InterestsTab extends StatefulWidget {
  const InterestsTab({super.key});

  @override
  State<InterestsTab> createState() => _InterestsTabState();
}

class _InterestsTabState extends State<InterestsTab> {
  final Set<String> _selectedInterests = {};
  bool _isSelectionMode = false;
  final PrivacyEnforcementService _privacyService = PrivacyEnforcementService();

  String _interestIdFromRow(Map<String, dynamic> row) =>
      InterestBadgeAggregator.interestDocumentId(row);

  String _safeString(dynamic v) => (v ?? '').toString().trim();

  String _titleForSentRow(Map<String, dynamic> row) {
    final fn = _safeString(row['to_first_name']);
    final ln = _safeString(row['to_last_name']);
    final name = ('$fn $ln').trim();
    if (name.isNotEmpty) return 'Interested in $name';
    final pid = _safeString(row['to_profile_id']);
    return pid.isNotEmpty ? 'Interested in $pid' : 'Interested';
  }

  String _titleForReceivedRow(Map<String, dynamic> row) {
    final fn = _safeString(row['from_first_name']);
    final ln = _safeString(row['from_last_name']);
    final name = ('$fn $ln').trim();
    if (name.isNotEmpty) return 'Interest received from $name';
    final pid = _safeString(row['from_profile_id']);
    return pid.isNotEmpty ? 'Interest received from $pid' : 'Interest received';
  }

  String _subtitleForRow(Map<String, dynamic> row) {
    final msg = _safeString(row['message']);
    if (msg.isNotEmpty) return msg;
    final status = _safeString(row['status']);
    return status.isNotEmpty ? 'Status: $status' : '';
  }

  String _timeAgoFromAny(dynamic raw) {
    try {
      DateTime? dt;
      if (raw is Timestamp) dt = raw.toDate();
      if (raw is String && raw.isNotEmpty) dt = DateTime.tryParse(raw);
      if (dt == null) return '';
      final diff = DateTime.now().difference(dt.toLocal());
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      final weeks = (diff.inDays / 7).floor();
      return '${weeks}w ago';
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'accepted') return AppTheme.sacredGreen;
    if (s == 'rejected' || s == 'declined') return AppTheme.kumkumRed;
    if (s == 'withdrawn') return Colors.grey;
    return AppTheme.primaryOrange; // pending/default
  }

  void _toggleSelection(String interestId) {
    setState(() {
      if (_selectedInterests.contains(interestId)) {
        _selectedInterests.remove(interestId);
        if (_selectedInterests.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedInterests.add(interestId);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedInterests.clear();
      _isSelectionMode = false;
    });
  }

  void _showMessageOptions(String interestId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AC.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Interest from $name',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AC.text(context),
                ),
              ),
            ),
            _buildOptionTile(
              context,
              Icons.message,
              'Send Message',
              Colors.blue,
              () {
                Navigator.pop(context);
                if (!mounted) return;
                Navigator.pushNamed(context, Routes.messages);
              },
            ),
            _buildOptionTile(
              context,
              Icons.person,
              'View Profile',
              Colors.green,
              () {
                Navigator.pop(context);
                _openInterestProfile(interestId);
              },
            ),
            _buildOptionTile(
              context,
              Icons.favorite,
              'Accept Interest',
              AppTheme.primaryOrange,
              () {
                Navigator.pop(context);
                if (!mounted) return;
                _acceptInterest(interestId);
              },
            ),
            _buildOptionTile(
              context,
              Icons.close,
              'Decline Interest',
              Colors.red,
              () {
                Navigator.pop(context);
                if (!mounted) return;
                _declineInterest(interestId);
              },
            ),
            _buildOptionTile(
              context,
              Icons.undo,
              'Withdraw (Sent)',
              Colors.grey,
              () {
                Navigator.pop(context);
                if (!mounted) return;
                _withdrawInterest(interestId);
              },
            ),
            _buildOptionTile(
              context,
              Icons.notifications_active_outlined,
              'Send Reminder (Sent)',
              AppTheme.primaryOrange,
              () {
                Navigator.pop(context);
                if (!mounted) return;
                _sendReminder(interestId);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openInterestProfile(String interestId) async {
    final interests = context.read<InterestService>();
    final row = [
      ...interests.visibleInterestsReceived,
      ...interests.visibleInterestsSent,
    ].cast<Map<String, dynamic>>().firstWhere(
      (e) => InterestBadgeAggregator.interestRowMatchesDocId(e, interestId),
      orElse: () => <String, dynamic>{},
    );
    if (row.isEmpty) return;
    final profileId =
        ((row['from_profile_id'] ?? row['to_profile_id']) as String? ?? '')
            .trim();
    final userId =
        ((row['from_user_id'] ?? row['to_user_id']) as String? ?? '').trim();
    final me = context.read<AuthService>().currentUser;
    if (me != null && userId.isNotEmpty) {
      final candidate =
          await context.read<AuthService>().getUserByAnyId(userId);
      if (candidate != null) {
        final candidateDoc =
            await ProfileRepository().getUserDocumentDataCacheFirst(
          candidate.id,
        );
        final allowed = _privacyService.canViewerSeeProfile(
          viewer: me,
          candidate: candidate,
          candidateDoc: candidateDoc,
        );
        if (!allowed) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('This profile is hidden by privacy settings.')),
          );
          return;
        }
      }
    }
    if (!mounted) return;
    if (profileId.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByProfileId(
        context,
        profileId: profileId,
        routeGuardInterestDocId: interestId,
      );
      return;
    }
    if (userId.isNotEmpty) {
      await SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: userId,
        routeGuardInterestDocId: interestId,
      );
    }
  }

  Widget _buildOptionTile(
    BuildContext context,
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AC.text(context),
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _acceptInterest(String interestId) async {
    final interestService = context.read<InterestService>();
    final auth = context.read<AuthService>();
    final result = await interestService.respondToInterestWithResult(
      interestId: interestId,
      response: 'accepted',
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final uid = auth.currentUser?.id ?? '';
      if (uid.isNotEmpty) {
        // ignore: discarded_futures
        interestService.loadInterests(uid, force: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interest accepted!'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text((result['error'] ?? 'Failed to accept interest').toString()),
        backgroundColor: AppTheme.kumkumRed,
      ),
    );
  }

  Future<void> _declineInterest(String interestId) async {
    final interestService = context.read<InterestService>();
    final auth = context.read<AuthService>();
    final result = await interestService.respondToInterestWithResult(
      interestId: interestId,
      response: 'rejected',
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final uid = auth.currentUser?.id ?? '';
      if (uid.isNotEmpty) {
        // ignore: discarded_futures
        interestService.loadInterests(uid, force: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interest declined'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text((result['error'] ?? 'Failed to decline interest').toString()),
        backgroundColor: AppTheme.kumkumRed,
      ),
    );
  }

  Future<void> _withdrawInterest(String interestId) async {
    final interestService = context.read<InterestService>();
    final auth = context.read<AuthService>();
    final result = await interestService.withdrawInterestWithResult(
        interestId: interestId);
    if (!mounted) return;
    if (result['success'] == true) {
      final uid = auth.currentUser?.id ?? '';
      if (uid.isNotEmpty) {
        // ignore: discarded_futures
        interestService.loadInterests(uid, force: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interest withdrawn'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text((result['error'] ?? 'Failed to withdraw interest').toString()),
        backgroundColor: AppTheme.kumkumRed,
      ),
    );
  }

  Future<void> _sendReminder(String interestId) async {
    final interestService = context.read<InterestService>();
    try {
      await interestService.sendInterestReminderForSentRow(interestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder sent successfully'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send reminder: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final interestService = context.watch<InterestService>();
    final sent = interestService.visibleInterestsSent
        .where((row) => _interestIdFromRow(row).isNotEmpty)
        .toList();
    final received = interestService.visibleInterestsReceived
        .where((row) => _interestIdFromRow(row).isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Column(
        children: [
          // Selection Mode Header
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AC.surface2(context),
              child: Row(
                children: [
                  Text(
                    '${_selectedInterests.length} selected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AC.text(context),
                    ),
                  ),
                  Spacer(),
                  TextButton(
                    onPressed: _clearSelection,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),

          // Interest List
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Interests',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sent Interests Section
                  Text(
                    'Interested',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AC.surface2(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: sent.isEmpty
                          ? [
                              _buildEmptyMessageState(
                                  context, 'No sent interests'),
                            ]
                          : sent.map((row) {
                              final id = _interestIdFromRow(row);
                              final status = _safeString(row['status']);
                              final time = _timeAgoFromAny(
                                row['updated_at'] ??
                                    row['created_at'] ??
                                    row['sent_at'] ??
                                    row['sentAt'],
                              );
                              return _buildInterestItem(
                                context,
                                id,
                                _titleForSentRow(row),
                                _subtitleForRow(row),
                                time,
                                _statusColor(status),
                                false,
                              );
                            }).toList(),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Received Interests Section
                  Text(
                    'Interest Received',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AC.surface2(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: received.isEmpty
                          ? [
                              _buildEmptyMessageState(
                                  context, 'No received interests'),
                            ]
                          : received.map((row) {
                              final id = _interestIdFromRow(row);
                              final status = _safeString(row['status']);
                              final time = _timeAgoFromAny(
                                row['updated_at'] ??
                                    row['created_at'] ??
                                    row['sent_at'] ??
                                    row['sentAt'],
                              );
                              final canRespond =
                                  status.toLowerCase() == 'pending';
                              return _buildInterestItem(
                                context,
                                id,
                                _titleForReceivedRow(row),
                                _subtitleForRow(row),
                                time,
                                _statusColor(status),
                                canRespond,
                              );
                            }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterestItem(
    BuildContext context,
    String interestId,
    String name,
    String profession,
    String timeAgo,
    Color statusColor,
    bool canRespond, {
    String? photoUrl,
  }) {
    final isSelected = _selectedInterests.contains(interestId);

    final isSentRow = name.toLowerCase().startsWith('interested');
    final isPending = statusColor == AppTheme.primaryOrange;

    final canDelete = !isPending;
    Widget content = GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(interestId);
        } else {
          // Show message options on tap
          _showMessageOptions(interestId, name);
        }
      },
      onLongPress: () {
        _toggleSelection(interestId);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppTheme.primaryOrange, width: 2)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Border.all(color: AC.border(context), width: 0.5)
                  : null),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Selection checkbox
                  if (_isSelectionMode)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryOrange
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryOrange
                              : AC.border(context),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: isSelected
                          ? Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),

                  // Profile photo
                  _buildProfileAvatar(photoUrl, name, statusColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AC.text(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profession,
                          style: TextStyle(
                            fontSize: 14,
                            color: AC.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action buttons for received interests
                  if (canRespond && !_isSelectionMode)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: AC.textMuted(context)),
                      onSelected: (value) {
                        switch (value) {
                          case 'message':
                            _showMessageOptions(interestId, name);
                            break;
                          case 'accept':
                            _acceptInterest(interestId);
                            break;
                          case 'decline':
                            _declineInterest(interestId);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'message',
                          child: Row(
                            children: [
                              Icon(Icons.message, size: 18),
                              SizedBox(width: 8),
                              Text('Send Message'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'accept',
                          child: Row(
                            children: [
                              Icon(Icons.favorite,
                                  size: 18, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Accept'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'decline',
                          child: Row(
                            children: [
                              Icon(Icons.close, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Decline'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_isSelectionMode)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canRespond)
                      OutlinedButton.icon(
                        onPressed: () => _acceptInterest(interestId),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Accept'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.sacredGreen,
                          side: const BorderSide(color: AppTheme.sacredGreen),
                        ),
                      ),
                    if (canRespond)
                      OutlinedButton.icon(
                        onPressed: () => _declineInterest(interestId),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.kumkumRed,
                          side: const BorderSide(color: AppTheme.kumkumRed),
                        ),
                      ),
                    if (isPending && isSentRow)
                      OutlinedButton.icon(
                        onPressed: () => _withdrawInterest(interestId),
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Withdraw'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: const BorderSide(color: Colors.grey),
                        ),
                      ),
                    if (isPending && isSentRow)
                      OutlinedButton.icon(
                        onPressed: () => _sendReminder(interestId),
                        icon: const Icon(Icons.notifications_active_outlined,
                            size: 16),
                        label: const Text('Reminder'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryOrange,
                          side: const BorderSide(color: AppTheme.primaryOrange),
                        ),
                      ),
                    if (canDelete)
                      OutlinedButton.icon(
                        onPressed: () => _showMessageOptions(interestId, name),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.kumkumRed,
                          side: const BorderSide(color: AppTheme.kumkumRed),
                        ),
                      ),
                  ],
                ),
              if (!_isSelectionMode) const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontSize: 12,
                      color: AC.textMuted(context),
                    ),
                  ),
                  if (canRespond) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Can Respond',
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return content;
  }

  Widget _buildProfileAvatar(String? photoUrl, String name, Color statusColor) {
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(12),
        border: hasPhoto
            ? Border.all(color: statusColor.withAlpha(100), width: 2)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ProfilePhoto(
          profile: UserProfile.fallbackForDiscovery(
            User(
              id: name.isNotEmpty ? name.toLowerCase().replaceAll(' ', '_') : 'member',
              email: '',
              password: '',
              mobileNumber: '',
            ),
          ),
          ownerUserDoc: hasPhoto
              ? <String, dynamic>{
                  'photo_url': photoUrl,
                  'profile_picture': photoUrl,
                }
              : null,
          size: 60,
          isPremiumViewer: true,
        ),
      ),
    );
  }

  Widget _buildEmptyMessageState(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: AC.textMuted(context),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Messages Tab - Combined inbox and sent messages
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final Set<String> _selectedMessages = {};
  final Set<String> _pendingDeleteIds = {};
  final Map<String, Timer> _pendingDeleteTimers = <String, Timer>{};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final userId = context.read<AuthService>().currentUser?.id ?? '';
      if (userId.isEmpty) return;
      final ms = context.read<MessageService>();
      await ms.startListening(userId);
      await ms.loadMessages(userId, forceReload: true);
    });
  }

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _pendingDeleteTimers.clear();
    _pendingDeleteIds.clear();
    super.dispose();
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessages.contains(messageId)) {
        _selectedMessages.remove(messageId);
        if (_selectedMessages.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessages.add(messageId);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMessages.clear();
      _isSelectionMode = false;
    });
  }

  void _openMessage(String messageId, String name) {
    // Navigate to message detail screen
    if (!mounted) return;
    Navigator.pushNamed(context, Routes.messages);
  }

  Future<void> _deleteMessage(
      _ActivityMessageRow row, String currentUserId) async {
    if (row.id.isEmpty || currentUserId.isEmpty) return;
    final messageService = context.read<MessageService>();

    if (mounted) {
      setState(() => _pendingDeleteIds.add(row.id));
    } else {
      _pendingDeleteIds.add(row.id);
    }

    _pendingDeleteTimers[row.id]?.cancel();
    _pendingDeleteTimers[row.id] = Timer(const Duration(seconds: 3), () async {
      try {
        await messageService.deleteMessage(
          messageId: row.id,
          currentUserId: currentUserId,
          messageType: row.type == 'photo_request' ? 'photo_request' : null,
        );
        await messageService.loadMessages(
          currentUserId,
          forceReload: true,
        );
      } finally {
        _pendingDeleteTimers.remove(row.id);
        if (mounted) {
          setState(() => _pendingDeleteIds.remove(row.id));
        } else {
          _pendingDeleteIds.remove(row.id);
        }
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Message deleted'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppTheme.primaryOrange,
            onPressed: () {
              _pendingDeleteTimers[row.id]?.cancel();
              _pendingDeleteTimers.remove(row.id);
              if (!mounted) return;
              setState(() => _pendingDeleteIds.remove(row.id));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        context.select<AuthService, String?>((a) => a.currentUser?.id) ?? '';
    final messageService = context.watch<MessageService>();
    final allRows = _buildRowsFromService(messageService, currentUserId);
    final visibleRows =
        allRows.where((row) => !_pendingDeleteIds.contains(row.id)).toList();
    final inboxRows = visibleRows.where((row) => row.isIncoming).toList();
    final sentRows = visibleRows.where((row) => !row.isIncoming).toList();

    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Column(
        children: [
          // Selection Mode Header
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AC.surface2(context),
              child: Row(
                children: [
                  Text(
                    '${_selectedMessages.length} selected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AC.text(context),
                    ),
                  ),
                  Spacer(),
                  TextButton(
                    onPressed: _clearSelection,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),

          // Message List
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Inbox Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AC.surface2(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: inboxRows.isEmpty
                          ? [
                              _buildEmptyMessageState(
                                  context, 'No inbox messages'),
                            ]
                          : inboxRows
                              .map((row) => _buildMessageItem(
                                    context,
                                    row,
                                    currentUserId,
                                  ))
                              .toList(),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Sent Messages Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AC.surface2(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: sentRows.isEmpty
                          ? [
                              _buildEmptyMessageState(
                                  context, 'No sent messages'),
                            ]
                          : sentRows
                              .map((row) => _buildMessageItem(
                                    context,
                                    row,
                                    currentUserId,
                                  ))
                              .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    _ActivityMessageRow row,
    String currentUserId,
  ) {
    final messageId = row.id;
    final name = row.name;
    final message = row.body;
    final timeAgo = row.timeAgo;
    final statusColor = row.color;
    final isUnread = row.isUnread;
    final isSelected = _selectedMessages.contains(messageId);

    Widget child = GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(messageId);
        } else {
          _openMessage(messageId, name);
        }
      },
      onLongPress: () {
        _toggleSelection(messageId);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppTheme.primaryOrange, width: 2)
              : (isUnread
                  ? Border.all(color: AppTheme.primaryOrange, width: 2)
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Border.all(color: AC.border(context), width: 0.5)
                      : null)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Selection checkbox
                  if (_isSelectionMode)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryOrange
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryOrange
                              : AC.border(context),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: isSelected
                          ? Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),

                  // Profile icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AC.text(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 14,
                            color: AC.textMuted(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Action buttons
                  if (!_isSelectionMode)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: AC.textMuted(context)),
                      onSelected: (value) {
                        switch (value) {
                          case 'open':
                            _openMessage(messageId, name);
                            break;
                          case 'reply':
                            _openMessage(messageId, name);
                            break;
                          case 'delete':
                            _deleteMessage(row, currentUserId);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.message, size: 18),
                              SizedBox(width: 8),
                              Text('Open Message'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reply',
                          child: Row(
                            children: [
                              Icon(Icons.reply, size: 18, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Reply'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontSize: 12,
                      color: AC.textMuted(context),
                    ),
                  ),
                  if (isUnread) ...[
                    Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AC.surface(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Unread',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Swipe to delete (practice-app style). Uses the same undo mechanism as menu delete.
    child = Dismissible(
      key: ValueKey('msg_$messageId'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteMessage(row, currentUserId);
        return false; // we hide via pendingDeleteIds + undo timer
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.kumkumRed,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            SizedBox(width: 10),
            Icon(Icons.delete, color: Colors.white),
          ],
        ),
      ),
      child: child,
    );

    return child;
  }

  Widget _buildEmptyMessageState(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: AC.textMuted(context),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  List<_ActivityMessageRow> _buildRowsFromService(
    MessageService messageService,
    String currentUserId,
  ) {
    final rows = <_ActivityMessageRow>[];
    final all = messageService.getAllMessages();
    for (final raw in all) {
      final id = (raw['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) continue;

      final fromUserId =
          ((raw['from_user_id'] ?? raw['fromUserId']) as String?)?.trim() ?? '';
      final toUserId =
          ((raw['to_user_id'] ?? raw['toUserId']) as String?)?.trim() ?? '';
      final isIncoming = toUserId == currentUserId ||
          (toUserId.isNotEmpty && fromUserId != currentUserId);

      final fromName =
          ((raw['from_first_name'] ?? raw['fromFirstName']) as String?)
                  ?.trim() ??
              'Someone';
      final toName =
          ((raw['to_first_name'] ?? raw['toFirstName']) as String?)?.trim() ??
              'Someone';
      final displayName = isIncoming ? fromName : toName;
      final body = ((raw['body'] as String?) ??
              (raw['message'] as String?) ??
              (raw['note'] as String?) ??
              'New message')
          .trim();

      final createdAtRaw =
          ((raw['created_at'] ?? raw['sent_at'] ?? raw['sentAt']) as String?)
              ?.trim();
      final createdAt =
          createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;
      final status = (raw['status'] as String? ?? '').toLowerCase();
      final isRead =
          (raw['is_read'] as bool?) ?? (raw['isRead'] as bool?) ?? false;

      rows.add(
        _ActivityMessageRow(
          id: id,
          type: (raw['type'] as String?) ?? 'message',
          isIncoming: isIncoming,
          name: displayName.isEmpty ? 'Someone' : displayName,
          body: body.isEmpty ? 'New message' : body,
          timeAgo: createdAt != null ? _formatTimeAgo(createdAt) : 'Just now',
          isUnread: isIncoming && !isRead && status == 'pending',
          color: _colorForName(displayName),
        ),
      );
    }
    return rows;
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    return '${weeks}w ago';
  }

  Color _colorForName(String input) {
    if (input.isEmpty) return AppTheme.primaryOrange;
    const palette = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
    ];
    return palette[input.codeUnitAt(0) % palette.length];
  }
}

class _ActivityMessageRow {
  final String id;
  final String type;
  final bool isIncoming;
  final String name;
  final String body;
  final String timeAgo;
  final bool isUnread;
  final Color color;

  const _ActivityMessageRow({
    required this.id,
    required this.type,
    required this.isIncoming,
    required this.name,
    required this.body,
    required this.timeAgo,
    required this.isUnread,
    required this.color,
  });
}
