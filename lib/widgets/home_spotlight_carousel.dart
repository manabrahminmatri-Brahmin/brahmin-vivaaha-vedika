import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_router.dart';
import '../models/user.dart';
import '../screens/matches/profile_detail_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_transitions.dart';
import 'online_status_indicator.dart';
import 'profile_photo.dart';
import 'soft_touch.dart';

/// Picks diverse spotlight profiles from an already-loaded match list (no I/O).
/// Premium members first, then remaining order preserved.
List<User> pickSpotlightUsers(List<User> matches, {int max = 5}) {
  if (matches.isEmpty) return const [];
  final out = <User>[];
  final seen = <String>{};
  for (final u in matches) {
    if (u.membership.isPremium && !seen.contains(u.id)) {
      out.add(u);
      seen.add(u.id);
      if (out.length >= max) return out;
    }
  }
  for (final u in matches) {
    if (!seen.contains(u.id)) {
      out.add(u);
      seen.add(u.id);
      if (out.length >= max) break;
    }
  }
  return out;
}

/// Horizontal “Spotlight” row for **Home → Today's Matches** only.
///
/// - One **static** promo tile (profile completion vs Premium).
/// - Remaining tiles are **algorithmic** picks from [matches] (same data as the list below).
/// - Does not replace or restyle [ProfileDiscoveryCard]; sits above it.
class HomeSpotlightCarousel extends StatelessWidget {
  final List<User> matches;

  const HomeSpotlightCarousel({super.key, required this.matches});

  static const double _rowHeight = 196;
  static const double _cardWidth = 168;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    if (matches.length < 2) return const SizedBox.shrink();

    final auth = context.watch<AuthService>();
    final viewerPremium = auth.currentUser?.membership.isPremium ?? false;
    final completion = auth.currentUser?.profile?.computedCompletionPercentage ?? 100;
    final featured = pickSpotlightUsers(matches, max: 5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Spotlight',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Swipe for picks — same matches as below',
                    style: TextStyle(
                      fontSize: 12,
                      color: AC.textSub(context),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 1 + featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: _gap),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _PromoTile(
                    completionPercent: completion,
                    viewerPremium: viewerPremium,
                  );
                }
                final user = featured[i - 1];
                return _SpotlightProfileTile(
                  user: user,
                  viewerPremium: viewerPremium,
                  onTap: () => _openProfile(context, user),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, User user) {
    SoftTouch.impact();
    Navigator.push(
      context,
      AppTransitions.slide(ProfileDetailScreen(user: user)),
    );
  }
}

class _PromoTile extends StatelessWidget {
  final int completionPercent;
  final bool viewerPremium;

  const _PromoTile({
    required this.completionPercent,
    required this.viewerPremium,
  });

  @override
  Widget build(BuildContext context) {
    final incomplete = completionPercent < 85;
    final title = incomplete ? 'Polish your profile' : 'Go Premium';
    final subtitle = incomplete
        ? 'Stronger profiles get better matches'
        : 'Unlock Discover 3D & more visibility';
    final icon = incomplete ? Icons.auto_fix_high_rounded : Icons.workspace_premium_rounded;

    return SizedBox(
      width: HomeSpotlightCarousel._cardWidth,
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            SoftTouch.impact();
            if (incomplete) {
              Navigator.of(context).pushNamed(
                '/profile-wizard',
                arguments: {
                  'isEditMode': false,
                  'initialStep': 0,
                },
              ).then((_) {
                if (context.mounted) {
                  context.read<AuthService>().refreshUserData();
                }
              });
            } else {
              NavHelper.push(context, Routes.premiumUpgrade);
            }
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: incomplete
                    ? [
                        AppTheme.primaryOrange.withValues(alpha: 0.92),
                        AppTheme.primaryOrangeDark.withValues(alpha: 0.95),
                      ]
                    : [
                        AppTheme.primaryGold.withValues(alpha: 0.95),
                        const Color(0xFFB8860B),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        incomplete ? 'Continue' : (viewerPremium ? 'Manage' : 'View plans'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotlightProfileTile extends StatelessWidget {
  final User user;
  final bool viewerPremium;
  final VoidCallback onTap;

  const _SpotlightProfileTile({
    required this.user,
    required this.viewerPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = user.profileForDiscovery;
    final name = [p.firstName, p.lastName]
        .where((e) => e.trim().isNotEmpty)
        .join(' ')
        .trim();
    final label = name.isEmpty ? 'Profile' : name;

    return SizedBox(
      width: HomeSpotlightCarousel._cardWidth,
      child: Material(
        color: AC.card(context),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: user.membership.isPremium
                    ? AppTheme.primaryGold.withValues(alpha: 0.55)
                    : AC.border(context),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: OnlineStatusOverlay(
                      userId: user.presenceWatchId,
                      dotSize: 11,
                      alignment: Alignment.topRight,
                      child: ProfilePhoto(
                        profile: p,
                        ownerUserId: user.id,
                        ownerUserDoc: user.discoveryPhotoFirestoreMap(),
                        size: HomeSpotlightCarousel._cardWidth,
                        height: HomeSpotlightCarousel._rowHeight,
                        borderRadius: 0,
                        isPremiumViewer: viewerPremium,
                        isOwner: false,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LivePresenceLabel(
                              userId: user.presenceWatchId,
                              compact: true,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                shadows: [
                                  Shadow(
                                    blurRadius: 6,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 8,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (user.membership.isPremium)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryGold
                                          .withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Premium',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4A3B00),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Pick',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
