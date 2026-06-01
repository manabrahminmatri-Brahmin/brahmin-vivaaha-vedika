import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../services/block_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/app_header.dart';

/// Screen to manage blocked profiles
class BlockedProfilesScreen extends StatelessWidget {
  const BlockedProfilesScreen({super.key});

  static String _blockedSignature(BlockService b) {
    if (b.isLoading) return 'L';
    final ids = b.blockedUsers.map((u) => u.profileId).toList()..sort();
    return '${ids.length}:${ids.join('|')}';
  }

  @override
  Widget build(BuildContext context) {
    return Selector<BlockService, String>(
      selector: (_, b) => _blockedSignature(b),
      builder: (context, _, __) {
        final blockService = context.read<BlockService>();
        final blockedUsers = blockService.blockedUsers;

        return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Blocked Profiles',
      ),
      body: blockService.isLoading
          ? const Center(child: CircularProgressIndicator())
          : blockedUsers.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: blockedUsers.length,
                  itemBuilder: (context, index) {
                    final user = blockedUsers[index];
                    return _buildBlockedUserCard(context, user, blockService, index);
                  },
                ),
    );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppTheme.sacredGreen,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No Blocked Profiles',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'You haven\'t blocked anyone yet.\nBlocked profiles cannot see your profile.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AC.textMuted(context),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ).animate().fadeIn(),
      ),
    );
  }

  Widget _buildBlockedUserCard(
    BuildContext context,
    BlockedUser user,
    BlockService blockService,
    int index,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SimplePhotoAvatar(
          photoUrl: user.photo,
          name: user.name,
          size: 60,
          circle: true,
        ),
        title: Text(
          user.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'ID: ${user.profileId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
            Text(
              'Blocked on ${_formatDate(user.blockedAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
            if (user.reason != null && user.reason!.isNotEmpty)
              Text(
                'Reason: ${user.reason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.kumkumRed,
                    ),
              ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _showUnblockDialog(context, user, blockService),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.sacredGreen,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text(
            'Unblock',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX(begin: 0.1);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showUnblockDialog(BuildContext context, BlockedUser user, BlockService blockService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unblock Profile'),
        content: Text(
          'Are you sure you want to unblock ${user.name}?\n\nThey will be able to see your profile again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              blockService.unblockUser(user.profileId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${user.name} has been unblocked'),
                  backgroundColor: AppTheme.sacredGreen,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sacredGreen),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}
