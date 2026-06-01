import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/safe_profile_nav.dart';
import '../../services/auth_service.dart';
import '../../services/profile_analytics_service.dart';
import '../../utils/profile_display_shuffle.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../models/user.dart';

class ProfileAnalyticsScreen extends StatefulWidget {
  const ProfileAnalyticsScreen({super.key});

  @override
  State<ProfileAnalyticsScreen> createState() => _ProfileAnalyticsScreenState();
}

class _ProfileAnalyticsScreenState extends State<ProfileAnalyticsScreen> {
  late Future<ProfileAnalyticsSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ProfileAnalyticsSummary> _load() async {
    final auth = context.read<AuthService>();
    final service = ProfileAnalyticsService(authService: auth);
    return service.loadAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Analytics')),
      body: FutureBuilder<ProfileAnalyticsSummary>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              message: snap.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snap.data;
          if (data == null) {
            return _ErrorView(
              message: 'Analytics unavailable',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _MetricGrid(data: data),
                const SizedBox(height: 16),
                if (data.profilesIViewedRecently.isNotEmpty)
                  _SectionCard(
                    title: 'Profiles you recently viewed',
                    subtitle:
                        'Order refreshes daily — swipe sideways, tap to open',
                    child: SizedBox(
                      height: 118,
                      child: Builder(
                        builder: (ctx) {
                          final uid =
                              ctx.watch<AuthService>().currentUser?.id;
                          final revisit = shuffleSeeded(
                            data.profilesIViewedRecently.take(40).toList(),
                            discoveryFeedSeed(
                              viewerUserId: uid,
                              salt: 'analytics_revisit_strip',
                            ),
                          ).take(16).toList();
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: revisit.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (c, i) =>
                                _RevisitTile(viewer: revisit[i]),
                          );
                        },
                      ),
                    ),
                  ),
                if (data.profilesIViewedRecently.isNotEmpty)
                  const SizedBox(height: 16),
                _SectionCard(
                  title: 'Who Viewed Me',
                  child: data.whoViewedMe.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No profile views yet.'),
                        )
                      : Column(
                          children: data.whoViewedMe.map((v) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: Colors.transparent,
                                child: ProfilePhoto(
                                  profile: UserProfile.fallbackForDiscovery(
                                    User(
                                      id: v.userId,
                                      profileId: v.profileId,
                                      email: '',
                                      password: '',
                                      mobileNumber: '',
                                    ),
                                  ),
                                  ownerUserId: v.userId,
                                  ownerUserDoc: {
                                    if ((v.photoUrl ?? '').trim().isNotEmpty) ...{
                                      'photo_url': v.photoUrl,
                                      'profile_picture': v.photoUrl,
                                    },
                                  },
                                  size: 40,
                                  circle: true,
                                  isPremiumViewer: true,
                                ),
                              ),
                              title: Text(v.name),
                              subtitle: Text(
                                [
                                  if ((v.profileId ?? '').isNotEmpty) v.profileId!,
                                  if ((v.city ?? '').isNotEmpty) v.city!,
                                ].join(' • '),
                              ),
                              trailing: Text(
                                _timeAgo(v.viewedAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppTheme.textMedium),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _MetricGrid extends StatelessWidget {
  final ProfileAnalyticsSummary data;
  const _MetricGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final items = <_MetricItem>[
      _MetricItem('Total Views', data.totalViews.toString()),
      _MetricItem('Weekly Views', data.weeklyViews.toString()),
      _MetricItem('Popularity Score', data.popularityScore.toStringAsFixed(1)),
      _MetricItem('Interest Acceptance', '${data.acceptancePercent.toStringAsFixed(1)}%'),
      _MetricItem('Ranking Percentile', '${data.rankingPercentile.toStringAsFixed(1)}%'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (i) => SizedBox(
              width: (MediaQuery.of(context).size.width - 42) / 2,
              child: _SectionCard(
                title: i.title,
                child: Text(
                  i.value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MetricItem {
  final String title;
  final String value;
  const _MetricItem(this.title, this.value);
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceLight2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMedium,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RevisitTile extends StatelessWidget {
  final ProfileViewer viewer;

  const _RevisitTile({required this.viewer});

  @override
  Widget build(BuildContext context) {
    final photo = (viewer.photoUrl ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => SafeProfileNav.safeOpenProfileByUserId(
          context,
          userId: viewer.userId,
        ),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.transparent,
                child: ProfilePhoto(
                  profile: UserProfile.fallbackForDiscovery(
                    User(
                      id: viewer.userId,
                      profileId: viewer.profileId,
                      email: '',
                      password: '',
                      mobileNumber: '',
                    ),
                  ),
                  ownerUserId: viewer.userId,
                  ownerUserDoc: {
                    if (photo.isNotEmpty) ...{
                      'photo_url': photo,
                      'profile_picture': photo,
                    },
                  },
                  size: 72,
                  circle: true,
                  isPremiumViewer: true,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                viewer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMedium,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
