// 🔥 LIKES SCREEN V2 - Full Architecture Migration
// Uses: LikeServiceV2, Result<T>, ErrorFirewall, AppIdentity
// NO: FirebaseFirestore.instance, old LikeService, raw errors

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

// NEW ARCHITECTURE IMPORTS
import '../../core/result.dart';
import '../../services/like_service_v2.dart';

// EXISTING IMPORTS (still needed)
import '../../services/block_service.dart';
import '../../core/safe_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/app_header.dart';
import '../../widgets/profile_photo.dart';
import '../../models/user.dart';
import '../../widgets/result_error_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LikedScreen V2
//
// MIGRATION COMPLETE:
//   ✅ Uses LikeServiceV2 with Result<T>
//   ✅ Proper error handling with ErrorFirewall
//   ✅ No direct Firestore access
//   ✅ Uses AppIdentity for user IDs
//   ✅ Mounted checks before UI updates
//   ✅ ResultBuilder for stream handling
//   ✅ Stream stored in initState to persist across navigation (Bug 2 fix)
// ─────────────────────────────────────────────────────────────────────────────

class LikedScreenV2 extends StatefulWidget {
  const LikedScreenV2({super.key});

  @override
  State<LikedScreenV2> createState() => _LikedScreenV2State();
}

class _LikedScreenV2State extends State<LikedScreenV2> {
  // Track if we're currently processing an unlike action
  bool _processingUnlike = false;

  // 🔥 FIX (Bug 2): Store the stream once in initState so it persists across
  // widget rebuilds and page navigation. Previously the stream was created
  // inside build(), which caused a new stream (and a fresh loading state)
  // every time the screen was visited or the widget rebuilt.
  late final Stream<Result<List<Map<String, dynamic>>>> _likesSentStream;

  @override
  void initState() {
    super.initState();
    _likesSentStream = LikeServiceV2().streamLikesSent();
  }

  @override
  Widget build(BuildContext context) {
    final blockedIds =
        context.select<BlockService, Set<String>>((b) => b.allBlockedPeerIds);

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: const AppHeader(
        title: 'Liked Profiles',
        showLogo: false,
      ),
      body: ResultBuilder<List<Map<String, dynamic>>>(
        // 🔥 FIX (Bug 2): Use the stored stream, not a freshly created one.
        stream: _likesSentStream,
        builder: (enrichedLikes) {
          // Filter blocked users
          final filteredLikes = enrichedLikes
              .where((like) {
                // 🔥 FIX (Bug 3): use 'user_id' (Fields.userId) which is what
                // _extractProfileData stores, falling back to 'id' (Fields.docId).
                final userId = like['user_id'] as String? ??
                               like['id'] as String? ??
                               like['uid'] as String? ?? '';
                final profileId = (like['profile_id'] as String? ?? '').trim();
                return !blockedIds.contains(userId) &&
                    (profileId.isEmpty || !blockedIds.contains(profileId));
              })
              .toList();

          if (filteredLikes.isEmpty) {
            return _buildEmptyState(
              icon: Icons.favorite_outline,
              title: 'No Liked Profiles',
              subtitle: 'Profiles you like will appear here',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              // Stream auto-refreshes; pull-to-refresh gives UX feedback.
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: filteredLikes.length,
              itemBuilder: (context, index) {
                final likeData = filteredLikes[index];
                return _LikedProfileTileV2(
                  likeData: likeData,
                  onUnlike: () => _confirmRemove(context, likeData),
                  onTap: () => _navigateToProfile(context, likeData),
                );
              },
            ),
          );
        },
        loadingBuilder: () => const ResultLoadingWidget(
          message: 'Loading liked profiles...',
        ),
        onRetry: () {
          setState(() {});
        },
      ),
    );
  }

  void _navigateToProfile(BuildContext context, Map<String, dynamic> likeData) {
    // 🔥 FIX (Bug 3): Use correct field keys from _extractProfileData.
    // 'user_id' = Fields.userId, 'id' = Fields.docId (both set to the same
    // Firestore doc ID). Previously the code tried 'docId' (camelCase) which
    // is NOT a key in the enriched map — the actual key is 'id'.
    final userId = likeData['user_id'] as String? ??
                   likeData['id'] as String? ??
                   likeData['uid'] as String? ?? '';
    final profileId = likeData['profile_id'] as String? ?? '';

    if (userId.isEmpty && profileId.isEmpty) {
      AppError.showError(context, 'Profile not found');
      return;
    }

    if (!mounted) return;

    if (profileId.isNotEmpty) {
      SafeProfileNav.safeOpenProfileByProfileId(
        context,
        profileId: profileId,
      );
    } else {
      SafeProfileNav.safeOpenProfileByUserId(
        context,
        userId: userId,
      );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    Map<String, dynamic> likeData,
  ) async {
    if (_processingUnlike) return;

    // 🔥 FIX (Bug 3): Correct field key for name — 'name' is directly set by
    // _extractProfileData; fall back to first_name + last_name.
    final name = likeData['name'] as String? ??
                 '${likeData['first_name'] ?? ''} ${likeData['last_name'] ?? ''}'.trim();
    // 🔥 FIX (Bug 3): Use correct key 'user_id' (not 'docId').
    final userId = likeData['user_id'] as String? ??
                   likeData['id'] as String? ??
                   likeData['uid'] as String? ?? '';

    if (userId.isEmpty) {
      if (!mounted) return;
      AppError.showError(context, 'Unable to remove like');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Like?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          name.isNotEmpty
              ? 'Remove your like from $name?'
              : 'Remove this like?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kumkumRed,
              foregroundColor: Colors.white,
            ),
            child: Text('Remove', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _processingUnlike = true);

    final result = await LikeServiceV2().unlikeUser(userId);

    if (!mounted) return;
    setState(() => _processingUnlike = false);

    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              name.isNotEmpty ? 'Removed like from $name' : 'Like removed',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: AppTheme.sacredGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      },
      error: (code, message) {
        AppError.showError(context, message);
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 Profile Tile - Uses enriched data from LikeServiceV2
// ─────────────────────────────────────────────────────────────────────────────

class _LikedProfileTileV2 extends StatelessWidget {
  final Map<String, dynamic> likeData;
  final VoidCallback onUnlike;
  final VoidCallback onTap;

  const _LikedProfileTileV2({
    required this.likeData,
    required this.onUnlike,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 FIX (Bug 3): Field keys now match what _extractProfileData stores:
    //   'name'      → set directly by _extractProfileData
    //   'photo_url' → Fields.photoUrl = 'photo_url'
    //   'location'  → Fields.location = 'location'
    //   'age'       → Fields.age = 'age'
    //   'profile_id'→ Fields.profileId = 'profile_id'
    final name = likeData['name'] as String? ??
                 '${likeData['first_name'] ?? ''} ${likeData['last_name'] ?? ''}'.trim();
    final photoUrl = likeData['photo_url'] as String? ?? '';
    final ownerUserId = (likeData['user_id'] as String? ??
            likeData['id'] as String? ??
            '')
        .trim();
    final ownerProfileId = (likeData['profile_id'] as String? ?? '').trim();
    final location = likeData['location'] as String? ?? '';
    final age = likeData['age'] as int?;
    final profileId = likeData['profile_id'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: ProfilePhoto(
                  profile: UserProfile.fallbackForDiscovery(
                    User(
                      id: ownerUserId.isNotEmpty
                          ? ownerUserId
                          : (ownerProfileId.isNotEmpty ? ownerProfileId : name),
                      profileId: ownerProfileId.isNotEmpty ? ownerProfileId : null,
                      email: '',
                      password: '',
                      mobileNumber: '',
                    ),
                  ),
                  ownerUserId: ownerUserId.isNotEmpty ? ownerUserId : null,
                  ownerUserDoc: {
                    if (photoUrl.isNotEmpty) ...{
                      'photo_url': photoUrl,
                      'profile_picture': photoUrl,
                    },
                  },
                  size: 60,
                  circle: true,
                  isPremiumViewer: true,
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : profileId,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (age != null || location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (age != null) '$age years',
                          if (location.isNotEmpty) location,
                        ].join(' • '),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Liked recently',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                onPressed: onUnlike,
                icon: const Icon(Icons.favorite, color: AppTheme.kumkumRed),
                tooltip: 'Remove like',
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1, end: 0);
  }
}