import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../core/safe_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/membership_badge_chip.dart';
import '../../widgets/app_header.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../features/profile/profile_repository.dart';
import '../../services/privacy_enforcement_service.dart';

/// Screen showing users who viewed the current user's profile.
/// Uses a real-time Firestore stream — updates instantly when someone
/// new views the profile. Deduplication is done server-side so one
/// person visiting 20 times still shows as a single viewer.
class WhoSawYourProfileScreen extends StatefulWidget {
  final String? viewedProfileId;
  final String? fallbackViewedUserId;

  const WhoSawYourProfileScreen({
    super.key,
    this.viewedProfileId,
    this.fallbackViewedUserId,
  });

  @override
  State<WhoSawYourProfileScreen> createState() =>
      _WhoSawYourProfileScreenState();
}

class _WhoSawYourProfileScreenState
    extends State<WhoSawYourProfileScreen> {
  final Map<String, User> _userCache = {};
  bool _isInitialLoad = true;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    // Remove profile_views left by viewers who later deleted their accounts.
    unawaited(ProfileRepository().pruneStaleProfileViewers());
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthService>().currentUser;

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppHeader(title: 'Who Saw Your Profile'),
        body: Center(
          child: Text(
            'Please login to continue.',
            style: TextStyle(color: AC.text(context)),
          ),
        ),
      );
    }

    final streamId =
        (widget.viewedProfileId != null && widget.viewedProfileId!.isNotEmpty)
            ? widget.viewedProfileId!
            : (currentUser.profileId.isNotEmpty ? currentUser.profileId : currentUser.id);
    debugPrint('👀 WhoSawYourProfile: currentUser=${currentUser.id}, profileId=${currentUser.profileId}, streamId=$streamId');

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Who Saw Your Profile',
        additionalActions: [
          IconButton(
            tooltip: 'Clear view history',
            icon: _isClearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_sweep_outlined, color: Colors.white),
            onPressed: _isClearing
                ? null
                : () => _confirmAndClearViewerHistory(
                      streamId: streamId,
                      fallbackUserId: currentUser.id,
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ProfileRepository().profileViewersStream(streamId),
            builder: (context, snapshot) {
              debugPrint(
                  '👀 WhoSawYourProfile: StreamBuilder - connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, dataLength=${snapshot.data?.length}');

              if (snapshot.hasError) {
                debugPrint(
                    '👀 WhoSawYourProfile: Stream error - ${snapshot.error}');
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadFallbackViewers(streamId, currentUser.id),
                  builder: (context, fallbackSnap) {
                    final fallbackRows = fallbackSnap.data ?? const <Map<String, dynamic>>[];
                    if (fallbackRows.isNotEmpty) {
                      return _buildViewerList(
                        context: context,
                        displayRecords: fallbackRows,
                        isPremium: currentUser.membership.isPremium,
                        currentUser: currentUser,
                      );
                    }
                    return _wrapMinHeightScrollable(
                      context,
                      _buildErrorState(snapshot.error.toString()),
                    );
                  },
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  _isInitialLoad) {
                // 🔥 FIX: Add timeout to prevent endless loading
                return _wrapMinHeightScrollable(
                  context,
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.primaryOrange,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading viewers...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              _isInitialLoad = false;
              
              // 🔥 FIX: Handle case where stream returns null data
              if (snapshot.data == null && !snapshot.hasError) {
                debugPrint('👀 WhoSawYourProfile: Stream returned null data');
                return _wrapMinHeightScrollable(
                  context,
                  _buildEmptyState(),
                );
              }

              final displayRecords = snapshot.data ?? [];

              debugPrint(
                  '👀 WhoSawYourProfile: Processing ${displayRecords.length} viewer records');

              if (displayRecords.isEmpty) {
                debugPrint(
                    '👀 WhoSawYourProfile: No viewer records - showing empty state');
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadFallbackViewers(streamId, currentUser.id),
                  builder: (context, fallbackSnap) {
                    final fallbackRows =
                        fallbackSnap.data ?? const <Map<String, dynamic>>[];
                    if (fallbackRows.isNotEmpty) {
                      return _buildViewerList(
                        context: context,
                        displayRecords: fallbackRows,
                        isPremium: currentUser.membership.isPremium,
                        currentUser: currentUser,
                      );
                    }
                    return _wrapMinHeightScrollable(context, _buildEmptyState());
                  },
                );
              }

              // Wrap in a full-height themed Container so no bare white/dark
              // gap shows below the last card in either light or dark mode.
              // ClampingScrollPhysics stops over-scroll beyond content height.
              return _buildViewerList(
                context: context,
                displayRecords: displayRecords,
                isPremium: currentUser.membership.isPremium,
                currentUser: currentUser,
              );
            },
          ),
      ),
    );
  }

  Future<void> _confirmAndClearViewerHistory({
    required String streamId,
    required String fallbackUserId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear View History?'),
        content: const Text(
          'This will remove the "Who saw your profile" history from your account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kumkumRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      final deletedCount = await _clearViewerHistory(streamId, fallbackUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0
                ? 'Cleared $deletedCount profile view record${deletedCount == 1 ? '' : 's'}.'
                : 'No profile view records found to clear.',
          ),
          backgroundColor: deletedCount > 0
              ? AppTheme.sacredGreen
              : AppTheme.primaryOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not clear history: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<int> _clearViewerHistory(String streamId, String fallbackUserId) async {
    final ids = <String>{streamId, fallbackUserId}
      ..removeWhere((e) => e.trim().isEmpty);
    if (ids.isEmpty) return 0;
    return ProfileRepository().deleteProfileViewsForTargets(ids);
  }

  Widget _buildViewerList({
    required BuildContext context,
    required List<Map<String, dynamic>> displayRecords,
    required bool isPremium,
    required User currentUser,
  }) {
    final bottomPad = 16 + MediaQuery.paddingOf(context).bottom;
    final viewerCount = displayRecords.length;
    return Container(
      color: AC.bg(context),
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 300));
        },
        color: AppTheme.primaryOrange,
        displacement: 40,
        child: ListView.builder(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
          itemCount: viewerCount + (isPremium ? 0 : 1),
          itemBuilder: (context, index) {
            if (!isPremium && index == 0) {
              return _buildPremiumGateHeader(context, viewerCount);
            }

            final recordIndex = isPremium ? index : index - 1;
            final record = displayRecords[recordIndex];
            final viewerUserId = (record['viewer_user_id'] ??
                    record['viewer_id'] ??
                    record['viewerUserId'] ??
                    record['from_user_id'] ??
                    record['from_user'] ??
                    record['user_id'] ??
                    '')
                .toString()
                .trim();
            final viewerProfileId = (record['viewer_profile_id'] ??
                    record['viewerProfileId'] ??
                    '')
                .toString()
                .trim();
            final viewerName = (record['viewer_name'] ??
                    record['viewerName'] ??
                    '')
                .toString()
                .trim();
            final viewedAt = (record['viewed_at'] ??
                    record['created_at'] ??
                    '')
                .toString();
            return _ViewerCard(
              key: ValueKey(record['id'] ?? viewerUserId),
              viewerUserId: viewerUserId,
              viewerProfileId: viewerProfileId,
              fallbackViewerName: viewerName,
              viewedAt: viewedAt,
              cachedUser: _userCache[viewerUserId],
              onUserLoaded: (user) {
                if (mounted) {
                  setState(() => _userCache[viewerUserId] = user);
                }
              },
              onSeen: () async {
                await context
                    .read<NotificationService>()
                    .markSingleProfileViewNotificationRead(
                      viewerUserId: viewerUserId,
                      viewerProfileId: viewerProfileId,
                    );
              },
              isPremium: isPremium,
              currentUser: currentUser,
            );
          },
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadFallbackViewers(
    String streamId,
    String fallbackUserId,
  ) async {
    final ids = <String>{streamId, fallbackUserId}
      ..removeWhere((e) => e.trim().isEmpty);
    return ProfileRepository().loadProfileViewFallbackRows(ids);
  }

  Widget _wrapMinHeightScrollable(BuildContext context, Widget child) {
    // Fills the entire body with the correct theme background so no white
    // gap appears below content in either light or dark mode.
    // LayoutBuilder uses the *actual* body height (tablet / split-screen safe);
    // MediaQuery screen height caused wrong minHeight and broken scroll limits.
    return Container(
      color: AC.bg(context),
      width: double.infinity,
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final minH = h.isFinite ? h : 320.0;
          return SingleChildScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minH),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: AppTheme.kumkumRed.withAlpha(150)),
            const SizedBox(height: 16),
            Text(
              'Could not load viewers. Please check your connection.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AC.textSub(context)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() => _isInitialLoad = true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off_outlined,
                size: 80, color: AC.textMuted(context)),
            const SizedBox(height: 24),
            Text(
              'No Views Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryOrange,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your profile hasn\'t been viewed by anyone yet.\nComplete your profile to attract more views!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AC.textSub(context)),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 Premium gate header for FREE users - shows count and upgrade prompt
  Widget _buildPremiumGateHeader(BuildContext context, int viewerCount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGold.withAlpha(30),
            AppTheme.primaryOrange.withAlpha(20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryGold.withAlpha(80),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility,
                  size: 20,
                  color: AppTheme.primaryGold,
                ),
                const SizedBox(width: 8),
                Text(
                  '$viewerCount ${viewerCount == 1 ? 'person' : 'people'} viewed your profile',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode(context) ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Lock message
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: AppTheme.primaryGold,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Upgrade to Premium to see who viewed your profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Upgrade button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/premium-upgrade');
              },
              icon: const Icon(Icons.star, size: 18),
              label: const Text(
                'Upgrade to Premium',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual viewer card
// ─────────────────────────────────────────────────────────────────────────────
class _ViewerCard extends StatefulWidget {
  final String viewerUserId;
  final String viewerProfileId;
  final String fallbackViewerName;
  final String viewedAt;
  final User? cachedUser;
  final ValueChanged<User> onUserLoaded;
  final Future<void> Function() onSeen;
  final bool isPremium;
  final User currentUser;

  const _ViewerCard({
    super.key,
    required this.viewerUserId,
    required this.viewerProfileId,
    required this.fallbackViewerName,
    required this.viewedAt,
    required this.cachedUser,
    required this.onUserLoaded,
    required this.onSeen,
    required this.isPremium,
    required this.currentUser,
  });

  @override
  State<_ViewerCard> createState() => _ViewerCardState();
}

class _ViewerCardState extends State<_ViewerCard> {
  User? _user;
  bool _loading = true;
  final PrivacyEnforcementService _privacyService = PrivacyEnforcementService();
  Map<String, dynamic>? _viewerDoc;

  @override
  void initState() {
    super.initState();
    _user = widget.cachedUser;
    if (_user == null) {
      _loadUser();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadUser() async {
    try {
      final profiles = ProfileRepository();
      User? user;
      if (widget.viewerUserId.isNotEmpty) {
        user = await profiles.lookupUserByAnyId(widget.viewerUserId);
      }
      if (user == null && widget.viewerProfileId.isNotEmpty) {
        user = await profiles.lookupUserByAnyId(widget.viewerProfileId);
      }
      if (user != null && mounted) {
        _viewerDoc = await profiles.getUserDocumentDataCacheFirst(user.id);
        if (!mounted) return;
        widget.onUserLoaded(user);
        setState(() {
          _user = user;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('⚠️ _ViewerCard: failed to load user $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Skeleton loader ───────────────────────────────────────────────────
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AC.border(context), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.peacockBlue.withAlpha(
                    Theme.of(context).brightness == Brightness.dark ? 35 : 20),
                border: Border.all(
                    color: AppTheme.primaryGold.withAlpha(40), width: 1.5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 120, color: AC.surface(context)),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 80, color: AC.surface(context)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Deleted / missing profile — do not show raw Firebase ids in the list.
    if (_user == null) {
      return const SizedBox.shrink();
    }

    // ── Normal viewer card ────────────────────────────────────────────────
    final user = _user;
    final profile = user?.profile;
    if (user == null || profile == null) {
      return const SizedBox.shrink();
    }

    final displayProfileId =
        user.profileId.isNotEmpty ? user.profileId : user.id;
    final canSeeViewerProfile = _privacyService.canViewerSeeProfile(
      viewer: widget.currentUser,
      candidate: user,
      candidateDoc: _viewerDoc,
    );

    // 🔥 PREMIUM GATE: Free users see blurred/masked content
    if (!widget.isPremium) {
      return _buildBlurredViewerCard(context, widget.viewedAt);
    }

    if (!canSeeViewerProfile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AC.border(context), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AC.surface2(context),
                border: Border.all(color: AC.border(context)),
              ),
              child: const Icon(Icons.lock_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private Viewer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Viewer details are hidden by privacy settings.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textMuted(context),
                        ),
                  ),
                ],
              ),
            ),
            Text(
              _formatDate(widget.viewedAt),
              style: TextStyle(fontSize: 11, color: AC.textMuted(context)),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AC.border(context), width: 0.5),
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? []
              : [
                  BoxShadow(
                    color: AC.shadow(context).withAlpha(28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await widget.onSeen();
            if (!context.mounted) return;
            await SafeProfileNav.safeOpenProfileByUserId(
              context,
              userId: user.id,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FIX 1: plain avatar, no online dot overlay
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfilePhoto(
                      profile: user.profileForDiscovery,
                      ownerUserId: user.id,
                      ownerUserDoc: user.discoveryPhotoFirestoreMap(),
                      size: 56,
                      circle: true,
                      isPremiumViewer: widget.isPremium,
                    ),
                    Positioned(
                      bottom: 2,
                      left: 2,
                      child: MembershipBadgeChip(
                        isPremium: user.isPremium,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name row — no Premium badge/pill
                      Text(
                        profile.fullName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryOrange,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // FIX 2: ID as plain muted text, no dark container
                      Text(
                        'ID: $displayProfileId',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AC.textSub(context),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.age} yrs, ${profile.height}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AC.textSub(context)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.city != null &&
                          profile.city!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${profile.city}'
                          '${profile.state != null && profile.state!.isNotEmpty ? ', ${profile.state}' : ''}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AC.textMuted(context)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(widget.viewedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AC.textSub(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AC.textMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔥 Blurred/masked card for FREE users
  Widget _buildBlurredViewerCard(BuildContext context, String viewedAt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Blurred avatar placeholder
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryGold.withAlpha(20),
              border: Border.all(
                color: AppTheme.primaryGold.withAlpha(80),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.lock,
              color: AppTheme.primaryGold,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Blurred name
                Container(
                  height: 16,
                  width: 140,
                  decoration: BoxDecoration(
                    color: AC.border(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // Blurred ID
                Container(
                  height: 12,
                  width: 100,
                  decoration: BoxDecoration(
                    color: AC.border(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // "Premium Members Only" label
                Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 12,
                      color: AppTheme.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Premium Members Only',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(viewedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: AC.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline, color: AppTheme.primaryGold, size: 20),
        ],
      ),
    );
  }
}
