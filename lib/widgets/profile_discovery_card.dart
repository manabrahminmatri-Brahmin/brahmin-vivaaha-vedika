import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'membership_badge_chip.dart';
import 'online_status_indicator.dart';
import 'press_scale_card.dart';
import 'profile_photo.dart';

/// Shared profile row card for **Home** (Today's Matches / Recently Added) and **Matches** list.
///
/// Layout: photo column (with age/height under photo) + details; bottom row 50% [View Profile] / 50% [ID].
class ProfileDiscoveryCard extends StatelessWidget {
  static const double kPhotoSize = 126;

  /// Bottom row: [View Profile] and Profile ID share this exact height.
  static const double kBottomActionsHeight = 48;

  /// Shared list insets so Home and Matches profile rows share the same width.
  static const double kListHorizontalInset = 16;
  static const double kListTopInset = 12;
  static const double kListBottomInsetDefault = 100;

  /// Padding for vertical lists of [ProfileDiscoveryCard] (custom bottom on Home).
  static EdgeInsets listPadding({double? bottom}) => EdgeInsets.fromLTRB(
        kListHorizontalInset,
        kListTopInset,
        kListHorizontalInset,
        bottom ?? kListBottomInsetDefault,
      );

  final User user;
  final VoidCallback onTap;
  final bool showNewBadge;
  final List<Widget> additionalWrapChildren;

  /// Matches list: last seen under age (shorter card, tighter spacing).
  final bool compactPresence;

  const ProfileDiscoveryCard({
    super.key,
    required this.user,
    required this.onTap,
    this.showNewBadge = false,
    this.additionalWrapChildren = const [],
    this.compactPresence = false,
  });

  @override
  Widget build(BuildContext context) {
    final profile = user.profileForDiscovery;

    return PressScaleCard(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: compactPresence ? 16 : 20),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: AppTheme.primaryGold.withAlpha(30),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                compactPresence ? 12 : 16,
                16,
                compactPresence ? 8 : 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoColumn(
                    user: user,
                    profile: profile,
                    showNewBadge: showNewBadge,
                    isPremiumViewer: context
                            .read<AuthService>()
                            .currentUser
                            ?.membership
                            .isPremium ??
                        false,
                    compactPresence: compactPresence,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DetailsColumn(
                      profile: profile,
                      showNewBadge: showNewBadge,
                      additionalWrapChildren: additionalWrapChildren,
                    ),
                  ),
                ],
              ),
            ),
            if (!compactPresence)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: AC.textMuted(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: LivePresenceLabel(
                        userId: user.presenceWatchId,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              // center: stretch + unbounded vertical max (ListView/slivers) →
              // "size: MISSING" / hit-test errors on the Row.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: kBottomActionsHeight,
                      child: ElevatedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: kBottomActionsHeight,
                      child: _ProfileIdHalf(profileId: user.profileId),
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

  /// Feet/inches only for list cards (strips e.g. `(168 cm)` from wizard values).
  static String? heightForCard(String? raw) {
    final t = _nonEmptyTrim(raw);
    if (t == null) return null;
    final feetOnly = t
        .replaceAll(
          RegExp(r'\s*\(\s*\d+\s*cm\s*\)\s*', caseSensitive: false),
          '',
        )
        .trim();
    if (feetOnly.contains("'")) return feetOnly;
    if (RegExp(r'cm', caseSensitive: false).hasMatch(feetOnly)) {
      try {
        final cm = double.parse(feetOnly.replaceAll(RegExp(r'[^0-9.]'), ''));
        final totalFeet = cm / 30.48;
        final feet = totalFeet.floor();
        final inches = ((totalFeet - feet) * 12).round();
        return "$feet'${inches}\"";
      } catch (_) {
        return feetOnly;
      }
    }
    return feetOnly;
  }
}

class _PhotoColumn extends StatelessWidget {
  final User user;
  final UserProfile profile;
  final bool showNewBadge;
  final bool isPremiumViewer;
  final bool compactPresence;

  const _PhotoColumn({
    required this.user,
    required this.profile,
    required this.showNewBadge,
    required this.isPremiumViewer,
    this.compactPresence = false,
  });

  @override
  Widget build(BuildContext context) {
    final heightLine = ProfileDiscoveryCard.heightForCard(profile.height);
    return SizedBox(
      width: ProfileDiscoveryCard.kPhotoSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              OnlineStatusOverlay(
                userId: user.presenceWatchId,
                dotSize: 13,
                child: ProfilePhoto(
                  profile: profile,
                  ownerUserId: user.id,
                  ownerUserDoc: user.discoveryPhotoFirestoreMap(),
                  size: ProfileDiscoveryCard.kPhotoSize,
                  imageAlignment: Alignment.topCenter,
                  isPremiumViewer: isPremiumViewer,
                ),
              ),
              Positioned(
                bottom: 6,
                left: 6,
                child: MembershipBadgeChip(
                  isPremium: user.isPremium,
                  compact: true,
                ),
              ),
              if (showNewBadge)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.sacredGreen,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: compactPresence ? 6 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${profile.age} yrs',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AC.textSub(context),
                ),
              ),
              if (heightLine != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '•',
                    style: TextStyle(
                      fontSize: 12,
                      color: AC.textMuted(context),
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    heightLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AC.textMuted(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (compactPresence) ...[
            const SizedBox(height: 2),
            LivePresenceLabel(
              userId: user.presenceWatchId,
              compact: true,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsColumn extends StatelessWidget {
  final UserProfile profile;
  final bool showNewBadge;
  final List<Widget> additionalWrapChildren;

  const _DetailsColumn({
    required this.profile,
    required this.showNewBadge,
    required this.additionalWrapChildren,
  });

  @override
  Widget build(BuildContext context) {
    final rawName = '${profile.firstName} ${profile.lastName}'.trim();
    final displayName = rawName.isEmpty ? 'Member' : rawName;
    final locationParts = <String?>[
      profile.city,
      profile.state,
      profile.country,
    ]
        .map((s) => s?.trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final nak = _nonEmptyTrim(profile.nakshatra);
    final sect = _nonEmptyTrim(profile.sect);
    final marital = _nonEmptyTrim(profile.maritalStatus);
    final occ = _nonEmptyTrim(profile.occupation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AC.textSub(context),
                height: 1.25,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showNewBadge) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        if (occ != null)
          _discoveryMetaLine(
            context,
            Icons.work_outline,
            occ,
          ),
        if (locationParts.isNotEmpty) ...[
          const SizedBox(height: 5),
          _discoveryMetaLine(
            context,
            Icons.location_on_outlined,
            locationParts,
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (nak != null) profileDiscoveryChip(context, '⭐ $nak'),
            if (sect != null) profileDiscoveryChip(context, sect),
            if (marital != null) profileDiscoveryChip(context, marital),
            ...additionalWrapChildren,
          ],
        ),
      ],
    );
  }
}

class _ProfileIdHalf extends StatelessWidget {
  final String profileId;

  const _ProfileIdHalf({required this.profileId});

  @override
  Widget build(BuildContext context) {
    final id = profileId.trim();
    return Container(
      width: double.infinity,
      height: ProfileDiscoveryCard.kBottomActionsHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryGold.withAlpha(55),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Profile ID',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AC.textMuted(context),
              letterSpacing: 0.2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            id.isEmpty ? '—' : id,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.templeGold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

String? _nonEmptyTrim(String? value) {
  final t = value?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

Widget _discoveryMetaLine(BuildContext context, IconData icon, String text) {
  final style = TextStyle(
    color: AC.textSub(context),
    fontWeight: FontWeight.w500,
    height: 1.3,
    fontSize: 13,
  );
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 14, color: AC.textSub(context)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ],
  );
}

/// Styled chip for extra rows on [ProfileDiscoveryCard] (e.g. Matches-only fields).
Widget profileDiscoveryChip(BuildContext context, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppTheme.primaryGold.withAlpha(20),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.primaryGold.withAlpha(40), width: 1),
    ),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: AC.textSub(context),
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    ),
  );
}
