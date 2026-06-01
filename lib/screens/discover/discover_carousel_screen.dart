import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/discover_profile_vm.dart';
import '../../services/auth_service.dart';
import '../../services/interest_service_v2.dart';
import '../../services/block_service.dart';
import '../../services/discover_service.dart' show DiscoverService;
import '../../services/user_action_service.dart';
import '../../screens/matches/profile_detail_screen.dart';
import '../../core/app_router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_button.dart' show ActionType;
import '../../widgets/celebration_effects.dart';
import '../../widgets/profile_coverflow_card.dart';

class DiscoverCarouselScreen extends StatefulWidget {
  const DiscoverCarouselScreen({super.key});

  @override
  State<DiscoverCarouselScreen> createState() => _DiscoverCarouselScreenState();
}

class _DiscoverCarouselScreenState extends State<DiscoverCarouselScreen> {
  late final PageController _pageController;
  DiscoverService? _discoverService;
  final List<DiscoverProfileVm> _profiles = <DiscoverProfileVm>[];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isActionBusy = false;
  String? _error;
  Timer? _snapDebounce;
  final Set<String> _prefetchedImages = <String>{};
  bool _showActionOverlay = true;

  static const double _viewportFraction = 0.84;

  static const double _headerFontSize = 18;
  static const double _subtitleFontSize = 12;
  static const Color _headerTextColor = Colors.white;

  PreferredSizeWidget _premiumDiscoverAppBar() {
    return AppBar(
      toolbarHeight: 72,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Premium Discover',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: _headerFontSize,
              fontWeight: FontWeight.w700,
              color: _headerTextColor,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Curated Premium Profiles',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: _subtitleFontSize,
              fontWeight: FontWeight.w500,
              color: _headerTextColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _snapDebounce?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _snapToNearest() {
    if (!_pageController.hasClients || _profiles.isEmpty) return;
    _snapDebounce?.cancel();
    _snapDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || !_pageController.hasClients || _profiles.isEmpty) return;
      final page = _pageController.page ?? _currentIndex.toDouble();
      final target = page.round().clamp(0, _profiles.length - 1);
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onCardTap(int index) {
    if (index == _currentIndex) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileDetailScreen(
            userId: _profiles[index].userId,
            heroTag: _profiles[index].heroTag,
          ),
        ),
      );
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    final block = context.read<BlockService>();
    final me = auth.currentUser;
    if (me != null && me.id.isNotEmpty) {
      await block.syncFromFirestore(blockerDocId: me.id);
    }
    _discoverService = DiscoverService(authService: auth, blockService: block);
    await _loadInitial();
  }

  Future<void> _loadInitial() async {
    final service = _discoverService;
    if (service == null) return;
    service.resetPagination();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _profiles.clear();
      _currentIndex = 0;
    });
    try {
      final canRefresh = await service.canManualRefresh();
      if (!canRefresh) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Fresh curated recommendations unlock shortly.';
        });
        return;
      }
      final first = await service.getDiscoverProfiles(limit: 12);
      await service.markManualRefreshUsed();
      if (!mounted) return;
      setState(() {
        _profiles.addAll(first);
        _isLoading = false;
      });
      _prefetchAround(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load discover profiles: $e';
      });
    }
  }

  Future<void> _loadMoreIfNeeded(int index) async {
    final service = _discoverService;
    if (service == null) return;
    if (_isLoadingMore || !service.hasMore) return;
    if (index < _profiles.length - 3) return;
    setState(() => _isLoadingMore = true);
    try {
      final next = await service.getDiscoverProfiles(limit: 10);
      if (!mounted) return;
      if (next.isNotEmpty) {
        setState(() => _profiles.addAll(next));
      }
      _prefetchAround(_currentIndex);
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _prefetchAround(int centerIndex) {
    if (!mounted || _profiles.isEmpty) return;
    final targets = <int>[
      centerIndex,
      centerIndex + 1,
      centerIndex + 2,
    ].where((i) => i >= 0 && i < _profiles.length);

    for (final i in targets) {
      final url = _profiles[i].imageUrl.trim();
      if (url.isEmpty || _prefetchedImages.contains(url)) continue;
      _prefetchedImages.add(url);
      precacheImage(NetworkImage(url), context);
    }
  }

  DiscoverProfileVm? get _currentProfile =>
      (_profiles.isEmpty || _currentIndex < 0 || _currentIndex >= _profiles.length)
          ? null
          : _profiles[_currentIndex];

  Future<void> _handleExpressInterest({bool superMatch = false}) async {
    final item = _currentProfile;
    if (item == null || _isActionBusy) return;
    setState(() => _isActionBusy = true);
    try {
      final auth = context.read<AuthService>();
      final me = auth.currentUser;
      final isPremium = me?.membership.isPremium ?? false;
      if (superMatch && !isPremium) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Super Match is a premium feature.')),
        );
        return;
      }
      final actionSvc = UserActionService();
      final result = await actionSvc.sendAction(
        targetUserId: item.userId,
        type: ActionType.interest,
        message: superMatch ? 'Super Match request from discover carousel' : null,
      );
      if (superMatch && result['success'] == true) {
        final meId = me?.id ?? '';
        await _discoverService?.recordSuperMatch(
          currentUserId: meId,
          targetUserId: item.userId,
        );
      }
      if (!mounted) return;
      if (result['success'] == true) {
        final meId = me?.id.trim() ?? '';
        if (meId.isNotEmpty) {
          context.read<InterestService>().upsertSentInterestLocal(
            interestId: '${meId}_${item.userId.trim()}',
            fromUserId: meId,
            toUserId: item.userId.trim(),
          );
        }
        unawaited(CelebrationEffects.showInterestBurst(context));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result['message'] ?? 'Action processed').toString())),
      );
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _handleShortlist() async {
    final item = _currentProfile;
    if (item == null || _isActionBusy) return;
    setState(() => _isActionBusy = true);
    try {
      final actionSvc = UserActionService();
      final result = await actionSvc.sendAction(
        targetUserId: item.userId,
        type: ActionType.like,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result['message'] ?? 'Shortlisted').toString())),
      );
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _handlePass() async {
    final item = _currentProfile;
    if (item == null || _isActionBusy) return;
    setState(() => _isActionBusy = true);
    try {
      final me = context.read<AuthService>().currentUser;
      await _discoverService?.markRejected(me?.id ?? '', item.userId);
      if (!mounted) return;
      final removedIndex = _currentIndex;
      setState(() {
        _profiles.removeAt(removedIndex);
        if (_profiles.isEmpty) {
          _currentIndex = 0;
        } else if (_currentIndex >= _profiles.length) {
          _currentIndex = _profiles.length - 1;
        }
      });
      if (_profiles.isNotEmpty && _pageController.hasClients) {
        final target = _currentIndex.clamp(0, _profiles.length - 1);
        _pageController.jumpToPage(target);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passed profile')),
      );
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium =
        context.watch<AuthService>().currentUser?.membership.isPremium ?? false;
    if (!isPremium) {
      return Scaffold(
        appBar: _premiumDiscoverAppBar(),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 54,
                    color: AppTheme.primaryOrange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '3D Discover is available for Premium members only.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      Routes.premiumUpgrade,
                    ),
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('Upgrade to Premium'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _premiumDiscoverAppBar(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadInitial,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _profiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 56),
                            const SizedBox(height: 8),
                            Text(
                              'No discover profiles available right now',
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                '3D Discover only shows profiles at or above '
                                '${DiscoverService.kDiscover3dMinAshtakootPercent.round()}% '
                                'Ashtakoot match (both nakshatras required). Pull to refresh.',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadInitial,
                        child: GestureDetector(
                          onVerticalDragEnd: (details) {
                            final v = details.primaryVelocity ?? 0;
                            if (v < -220) {
                              setState(() => _showActionOverlay = true);
                            } else if (v > 220) {
                              setState(() => _showActionOverlay = false);
                            }
                          },
                          child: Column(
                          children: [
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenW = MediaQuery.sizeOf(context).width;
                  final cardWidth = screenW * _viewportFraction;
                  final maxH = constraints.maxHeight;
                  if (!maxH.isFinite || maxH <= 0) {
                    return const SizedBox.shrink();
                  }
                  // Lower bound must not exceed maxH — `.clamp(400, maxH)` crashes when maxH < 400.
                  final minCardHeight = math.min(400.0, maxH);
                  final cardHeight = math
                      .min(maxH * 0.96, cardWidth * 1.28)
                      .clamp(minCardHeight, maxH);

                  return NotificationListener<ScrollEndNotification>(
                onNotification: (_) {
                  _snapToNearest();
                  return false;
                },
                child: PageView.builder(
                  // Default [Clip.hardEdge] clips rotated 3D cards; photos look
                  // cut off or "missing" on the sides even when URLs load fine.
                  clipBehavior: Clip.none,
                  controller: _pageController,
                  itemCount: _profiles.length,
                  padEnds: true,
                  pageSnapping: true,
                  onPageChanged: (value) {
                    if (!mounted) return;
                    setState(() => _currentIndex = value);
                    _loadMoreIfNeeded(value);
                    _prefetchAround(value);
                  },
                  itemBuilder: (context, index) {
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        final page = _pageController.hasClients
                            ? (_pageController.page ?? _currentIndex.toDouble())
                            : _currentIndex.toDouble();
                        final distance = page - index;
                        final absDistance = distance.abs();

                        final scale = (1 - (absDistance * 0.15)).clamp(0.75, 1.0);
                        final rotationY = distance * 0.35;
                        final blurStrength = (absDistance * 0.18).clamp(0.0, 0.2);
                        final opacity = (1 - (absDistance * 0.2)).clamp(0.55, 1.0);
                        final depth = (100 - absDistance * 10).clamp(0.0, 100.0);

                        return Center(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0013)
                              ..rotateY(rotationY)
                              ..translateByDouble(0.0, absDistance * 8, depth, 1.0),
                            child: SizedBox(
                              height: cardHeight,
                              child: ProfileCoverflowCard(
                                profile: _profiles[index],
                                scale: scale,
                                blurStrength: blurStrength,
                                opacity: opacity,
                                isCentered: absDistance < 0.12,
                                heroTag: _profiles[index].heroTag,
                                onTap: () => _onCardTap(index),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _profiles.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  width: _currentIndex == index ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _currentIndex == index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor.withAlpha(140),
                  ),
                ),
              ),
            ),
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _showActionOverlay && _currentProfile != null
                  ? Padding(
                      key: const ValueKey('discover_actions'),
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: _buildDiscoverActionTray(context),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
          ],
                          ),
                        ),
                      ),
      ),
    );
  }

  /// Two-row action bar: row1 Express / Shortlist / Pass — row2 Super Match / Full profile.
  Widget _buildDiscoverActionTray(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(236),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(90)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _actionChip(
                  context,
                  icon: Icons.favorite_border_rounded,
                  label: 'Express Interest',
                  onTap: _isActionBusy ? null : () => _handleExpressInterest(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionChip(
                  context,
                  icon: Icons.bookmark_add_outlined,
                  label: 'Shortlist',
                  onTap: _isActionBusy ? null : _handleShortlist,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionChip(
                  context,
                  icon: Icons.close_rounded,
                  label: 'Pass',
                  onTap: _isActionBusy ? null : _handlePass,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _actionChip(
                  context,
                  icon: Icons.workspace_premium_rounded,
                  label: 'Super Match',
                  onTap: _isActionBusy
                      ? null
                      : () => _handleExpressInterest(superMatch: true),
                  highlight: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionChip(
                  context,
                  icon: Icons.open_in_new_rounded,
                  label: 'View Full Profile',
                  onTap: _isActionBusy || _currentProfile == null
                      ? null
                      : () => _onCardTap(_currentIndex),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlight = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg =
        highlight ? AppTheme.primaryOrange.withAlpha(26) : Colors.transparent;
    final border = highlight ? AppTheme.primaryOrange : cs.outline.withAlpha(120);
    final fg = highlight ? AppTheme.primaryOrange : cs.onSurface;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: fg),
      label: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.15,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        side: BorderSide(color: border),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
