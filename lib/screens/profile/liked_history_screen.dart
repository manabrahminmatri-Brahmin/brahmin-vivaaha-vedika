import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/safe_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/app_header.dart';
import '../../legacy/compatibility.dart';

/// Screen to show who has liked current user's profile
class LikedHistoryScreen extends StatefulWidget {
  const LikedHistoryScreen({super.key});

  @override
  State<LikedHistoryScreen> createState() => _LikedHistoryScreenState();
}

class _LikedHistoryScreenState extends State<LikedHistoryScreen> {
  List<Map<String, dynamic>> _likedByUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLikedHistory();
  }

  Future<void> _loadLikedHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final currentUser = authService.currentUser;
      final likeService = context.read<LikeService>();
      
      if (currentUser == null || currentUser.id.isEmpty) {
        if (mounted) {
          setState(() {
          _errorMessage = 'User ID not found';
          _isLoading = false;
        });
        }
        return;
      }

      // LikeService streams full user docs where liked_users contains me.
      final likedYouList = await likeService.getLikedYou().first;

      final enriched = <Map<String, dynamic>>[];
      for (final record in likedYouList) {
        final fromUserId =
            record['uid'] as String? ?? record['id'] as String? ?? '';
        if (fromUserId.isEmpty) continue;
        try {
          final userObj = await FirebaseService().getUserByAnyId(fromUserId);
          if (!mounted) return;
          if (userObj == null) continue;
          final userData = userObj.toDatabaseJson();
          if (_isProfileInactive(userData)) continue;
          enriched.add({
            'users': userData,
            'created_at': record['liked_at'] as String? ??
                record['created_at'] as String? ??
                '',
          });
        } catch (_) {
          // Skip on error — don't show stale/broken records
        }
      }

      if (mounted) {
        setState(() {
        _likedByUsers = enriched;
        _isLoading = false;
      });
      }

      debugPrint('✅ Loaded ${enriched.length} users who liked this profile');
    } catch (e) {
      if (mounted) {
        setState(() {
        _errorMessage = 'Failed to load liked history: $e';
        _isLoading = false;
      });
      }
      debugPrint('❌ Error loading liked history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Liked History',
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: null,
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryOrange),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.kumkumRed,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.kumkumRed,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadLikedHistory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_likedByUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history,
                size: 64,
                color: AC.textMuted(context),
              ),
              SizedBox(height: 16),
              Text(
                'No Liked History',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AC.textSub(context),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No one has liked your profile yet.\nComplete your profile to get more visibility!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AC.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLikedHistory,
      color: AppTheme.primaryOrange,
      child: Column(
        children: [
          // Header with count
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AC.card(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AC.surface(context),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: AppTheme.kumkumRed,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_likedByUsers.length} People',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AC.textSub(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'have liked your profile',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AC.textSub(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.1),

          // List of users who liked
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: _likedByUsers.length,
              itemBuilder: (context, index) {
                final likeData = _likedByUsers[index];
                final userData = likeData['users'];
                final likedAt = likeData['created_at'] as String? ?? '';
                
                if (userData == null) return const SizedBox.shrink();

                return _buildLikedUserCard(
                  userData,
                  likedAt,
                  index,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikedUserCard(
    Map<String, dynamic> userData,
    String? likedAt,
    int index,
  ) {
    final at = likedAt ?? '';
    final String email = userData['email'] ?? 'Unknown';
    final String profileId = userData['profile_id'] ?? 'Unknown';
    final String userId = userData['id'] ?? '';
    final Map<String, dynamic>? profile = userData['profile'];

    // Get display name from profile if available
    String displayName = email.split('@')[0]; // Default to email prefix
    if (profile != null) {
      final firstName = profile['first_name'] as String?;
      final lastName = profile['last_name'] as String?;
      if (firstName != null && firstName.isNotEmpty) {
        displayName = lastName != null && lastName.isNotEmpty 
            ? '$firstName $lastName' 
            : firstName;
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            SimplePhotoAvatar(
              photoUrl: null,
              name: displayName,
              size: 60,
              circle: true,
              isPremiumViewer: context.read<AuthService>().currentUser?.membership.isPremium ?? false,
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile ID: $profileId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AC.textSub(context),
              ),
            ),
            SizedBox(height: 2),
            Text(
              at.isEmpty ? 'Liked: Recently' : 'Liked: ${_formatDate(at)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryOrange,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: AC.textMuted(context)),
        onTap: () async {
          await SafeProfileNav.safeOpenProfileByUserId(context, userId: userId);
        },
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
  }

  /// Returns true if the user account should be treated as inactive/gone:
  /// - is_deleted == true  (backend hard-delete)
  /// - status == 'pending_deletion'  (user requested deletion, not yet purged)
  bool _isProfileInactive(Map<String, dynamic> userData) {
    if (userData['is_deleted'] == true) return true;
    final status = (userData['status'] as String? ?? '').toLowerCase();
    if (status == 'pending_deletion' || status == 'deleted' || status == 'deactivated') return true;
    return false;
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown date';
    }
  }
}
