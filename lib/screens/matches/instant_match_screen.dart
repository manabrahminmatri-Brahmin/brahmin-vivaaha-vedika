import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../core/safe_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../utils/profile_display_shuffle.dart';
import '../../widgets/app_header.dart';
import '../../widgets/membership_badge_chip.dart';
import '../../widgets/profile_photo.dart';
import '../../legacy/compatibility.dart';

/// Instant Match Discovery — loads real profiles using the same
/// AuthService.getMatchingProfiles() pipeline as the Matches tab.
class InstantMatchScreen extends StatefulWidget {
  const InstantMatchScreen({super.key});
  @override
  State<InstantMatchScreen> createState() => _InstantMatchScreenState();
}

class _InstantMatchScreenState extends State<InstantMatchScreen> {
  bool _isLoading = false;
  List<User> _matches = [];
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final filters = context.read<FilterService>().current;
      final page = await context.read<AuthService>().getMatchingProfiles(
            filters: filters,
          );
      if (!mounted) return;
      final raw = page.users.where((u) => u.profile != null).toList();
      final viewerId = context.read<AuthService>().currentUser?.id;
      setState(() {
        _matches = shuffleUsersForDiscovery(
          raw,
          viewerUserId: viewerId,
          salt: 'instant_matches',
        );
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  void _openProfile(User user) {
    // ignore: discarded_futures
    SafeProfileNav.safeOpenProfileByUserId(context, userId: user.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(title: 'Instant Matches', showLogo: true),
      body: _isLoading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppTheme.primaryOrange),
              const SizedBox(height: 20),
              Text('Finding matches…',
                  style: TextStyle(fontSize: 15, color: AC.textSub(context))),
            ]))
          : _error != null
              ? _errorState()
              : _matches.isEmpty
                  ? _emptyState()
                  : _matchList(),
    );
  }

  Widget _errorState() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 56, color: AppTheme.kumkumRed),
      const SizedBox(height: 16),
      Text('Could not load matches',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AC.text(context))),
      const SizedBox(height: 8),
      Text(_error ?? '', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AC.textSub(context))),
      const SizedBox(height: 20),
      ElevatedButton.icon(onPressed: _load,
        icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange, foregroundColor: Colors.white)),
    ])));

  Widget _emptyState() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.people_outline, size: 72, color: AC.textMuted(context)),
      const SizedBox(height: 20),
      Text('No instant matches found',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
              color: AC.text(context))),
      const SizedBox(height: 8),
      Text('Try relaxing your filters or check back later.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AC.textSub(context))),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: _load,
        icon: const Icon(Icons.refresh), label: const Text('Refresh'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange, foregroundColor: Colors.white)),
    ])));

  Widget _matchList() => RefreshIndicator(
    onRefresh: _load, color: AppTheme.primaryOrange,
    child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _matches.length,
      itemBuilder: (_, i) => _MatchCard(
          user: _matches[i], onTap: () => _openProfile(_matches[i])),
    ),
  );
}

class _MatchCard extends StatelessWidget {
  final User user;
  final VoidCallback onTap;
  const _MatchCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profile = user.profile!;
    final name = '${profile.firstName} ${profile.lastName}'.trim();
    final age = '${profile.age} yrs';
    final location = profile.city ?? profile.nativePlaceCity ?? profile.nativePlace ?? '';
    final occupation = profile.occupation ?? '';
    final viewerPremium =
        context.read<AuthService>().currentUser?.membership.isPremium ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AC.shadow(context).withAlpha(40),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ProfilePhoto(
                    profile: user.profileForDiscovery,
                    ownerUserId: user.id,
                    ownerUserDoc: user.discoveryPhotoFirestoreMap(),
                    size: 70,
                    isPremiumViewer: viewerPremium,
                  ),
                ),
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: MembershipBadgeChip(isPremium: user.membership.isPremium),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w700, color: AC.text(context))),
              const SizedBox(height: 3),
              if (age.isNotEmpty || location.isNotEmpty)
                Text([age, location].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 13, color: AC.textSub(context))),
              if (occupation.isNotEmpty)
                Text(occupation, style: TextStyle(
                    fontSize: 12, color: AC.textSub(context))),
              const SizedBox(height: 4),
              Text('ID: ${user.profileId}', style: const TextStyle(fontSize: 11,
                  color: AppTheme.templeGold, fontWeight: FontWeight.w600)),
            ])),
            Icon(Icons.chevron_right_rounded,
                color: AC.textSub(context), size: 22),
          ]),
        ),
      ),
    );
  }

}
