import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import 'membership_badge_chip.dart';
import 'profile_photo.dart';
import 'online_status_indicator.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.profile,
    super.key,
    this.onTap,
    this.onConnect,
  });

  final User profile;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 2,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.primaryOrange.withValues(alpha: 0.05),
                            AppTheme.primaryOrange.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                      child: profile.profile != null
                          ? ProfilePhoto(
                              profile: profile.profileForDiscovery,
                              ownerUserId: profile.id,
                              ownerUserDoc: profile.discoveryPhotoFirestoreMap(),
                              size: double.infinity,
                              isPremiumViewer: true,
                            )
                          : Container(
                              color: const Color(0xFFF0F0F0),
                              child: const Center(child: Icon(Icons.person, size: 40, color: AppTheme.textLight)),
                            ),
                    ),
                  ),

                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MembershipBadgeChip(
                          isPremium: profile.isPremium,
                          compact: false,
                        ),
                        if (profile.profile?.matchScore != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AC.card(context).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              'Match ${profile.profile!.matchScore}%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Online status dot — live Firestore stream
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: OnlineStatusIndicator(userId: profile.id),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.profile?.fullName ?? 'Unknown',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  Text(
                    '${profile.profile?.age ?? 'N/A'} yrs • '
                    '${profile.profile?.heightFeet ?? 'N/A'} • '
                    '${profile.profile?.city ?? 'N/A'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(context, profile.profile?.sect ?? 'N/A'),
                      _buildChip(context, profile.profile?.subSect ?? 'N/A'),
                      _buildChip(context, profile.profile?.city ?? 'N/A'),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Text(
                    profile.profile?.bio ?? 'No bio available',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onTap,
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onConnect,
                      child: const Text('View Contact'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.chipTheme.backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.chipTheme.labelStyle,
      ),
    );
  }
}
