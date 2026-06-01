import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_controller.dart';
import '../services/block_enforcement_policy.dart';
import '../screens/matches/profile_detail_screen.dart';

class SafeProfileNav {
  SafeProfileNav._();

  static Future<void> safeOpenProfileByUserId(
    BuildContext context, {
    required String userId,
    String? routeGuardInterestDocId,
  }) async {
    if (userId.trim().isEmpty) {
      _show(context, 'Profile unavailable right now');
      return;
    }
    final auth = context.read<AuthController>();

    // Use unified resolver that tries all ID types without guessing
    final user = await auth.getUserByAnyId(userId.trim());

    if (!context.mounted) return;
    if (user == null) {
      _show(context, 'Could not open profile right now');
      return;
    }
    final me = auth.currentUser;
    if (me != null &&
        await BlockEnforcementPolicy.verifyBlockedForOpenProfile(
          actorUserDocId: me.id,
          peerUserDocId: user.id,
          peerProfileId: user.profileId,
        )) {
      if (!context.mounted) return;
      _show(context, 'This profile is blocked.');
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          user: user,
          routeGuardInterestDocId: routeGuardInterestDocId,
        ),
      ),
    );
  }

  static Future<void> safeOpenProfileByProfileId(
    BuildContext context, {
    required String profileId,
    String? routeGuardInterestDocId,
  }) async {
    if (profileId.trim().isEmpty) {
      _show(context, 'Profile unavailable right now');
      return;
    }
    final auth = context.read<AuthController>();
    final user = await auth.getUserByProfileId(profileId.trim());
    if (!context.mounted) return;
    if (user == null) {
      _show(context, 'Could not open profile right now');
      return;
    }
    final me = auth.currentUser;
    if (me != null &&
        await BlockEnforcementPolicy.verifyBlockedForOpenProfile(
          actorUserDocId: me.id,
          peerUserDocId: user.id,
          peerProfileId: user.profileId,
        )) {
      if (!context.mounted) return;
      _show(context, 'This profile is blocked.');
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          user: user,
          routeGuardInterestDocId: routeGuardInterestDocId,
        ),
      ),
    );
  }

  static void _show(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
