import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import 'membership_badge_chip.dart';
import 'profile_photo.dart';
import '../services/verification_service.dart';
import 'online_status_indicator.dart';

/// Beautiful profile card for displaying matches with dark mode support
class ProfileCard extends StatelessWidget {
  final UserProfile profile;
  final String? userId;
  final String? profileId;
  final bool isPremium;
  final VoidCallback? onTap;
  final VoidCallback? onLike;

  final bool isOnline;
  final DateTime? lastActive;

  const ProfileCard({
    super.key,
    required this.profile,
    this.userId,
    this.profileId,
    this.isPremium = false,
    this.isOnline = false,
    this.lastActive,
    this.onTap,
    this.onLike,
  });

  @override
  Widget build(BuildContext context) {

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AC.shadow(context).withAlpha(31),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Image
            Stack(
              children: [
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    color: AC.card(context),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AC.border(context),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ProfilePhoto(
                          profile: profile,
                          ownerUserId: userId,
                          ownerUserDoc: {
                            if ((profile.profilePicture ?? '')
                                .trim()
                                .isNotEmpty) ...{
                              'profile_picture': profile.profilePicture,
                              'photo_url': profile.profilePicture,
                            },
                            'is_photo_private': profile.isPhotoPrivate ?? false,
                            'isPhotoPrivate': profile.isPhotoPrivate ?? false,
                            'profile': profile.toJson(),
                          },
                          size: 80,
                          height: 100,
                          isPremiumViewer: isPremium,
                        ),
                      ),
                    ),
                  ),
                ),

                // Premium + verification + online — bottom of photo (keeps face clear)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (userId != null && userId!.isNotEmpty) ...[
                            OnlineStatusIndicator(
                              userId: userId!,
                              dotSize: 14,
                            ),
                            const SizedBox(width: 6),
                          ],
                          MembershipBadgeChip(isPremium: isPremium),
                        ],
                      ),
                      if (userId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Consumer<VerificationService>(
                            builder: (context, verificationService, _) {
                              final isVerified = verificationService.isVerified;
                              final badgeCount =
                                  verificationService.verificationBadgeCount;
                              if (!isVerified || badgeCount == 0) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.sacredGreen,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.sacredGreen.withAlpha(40),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      color: AC.card(context),
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '$badgeCount',
                                      style: TextStyle(
                                        color: AC.card(context),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Like Button
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: onLike,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AC.card(context),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.kumkumRed.withAlpha(30),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_outline,
                        color: AppTheme.kumkumRed,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Profile Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          profile.fullName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${profile.age} yrs',
                          style: TextStyle(
                            color: AC.text(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (profileId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID: $profileId',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.templeGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    Icons.work_outline,
                    profile.occupation ?? 'Not specified',
                  ),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.school_outlined,
                    profile.education ?? 'Not specified',
                  ),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.location_on_outlined,
                    [profile.city ?? '', profile.state ?? '']
                        .where((s) => s.isNotEmpty)
                        .join(', '),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (profile.sect != null) _buildTag(profile.sect!),
                      if (profile.gothram != null) _buildTag(profile.gothram!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textLight),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: AppTheme.textMedium),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(50)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.templeGold,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
