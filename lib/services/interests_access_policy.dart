import '../models/user.dart';
import 'block_enforcement_policy.dart';
import 'block_service.dart';

/// Chat and action eligibility for Interests hub.
abstract final class InterestsAccessPolicy {
  InterestsAccessPolicy._();

  /// Live Firestore check — required before chat.
  static Future<bool> isEitherBlocked({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      BlockEnforcementPolicy.verifyBlockedForChat(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  /// Chat allowed only when interest is accepted, user is premium, and not blocked.
  static Future<String?> chatBlockReason({
    required User? me,
    required String peerUserId,
    String? peerProfileId,
    required String interestStatus,
    BlockService? blockService,
  }) async {
    final status = interestStatus.trim().toLowerCase();
    if (status != 'accepted') {
      return 'Chat is available after the interest is accepted.';
    }
    if (me == null) return 'Please sign in to chat.';
    if (!me.membership.isPremium) {
      return 'Chat is a Premium feature. Upgrade to continue.';
    }
    final peer = peerUserId.trim();
    if (peer.isEmpty) return 'Invalid member id for chat.';

    final blocked = await isEitherBlocked(
      actorUserDocId: me.id,
      peerUserDocId: peer,
      peerProfileId: peerProfileId,
    );
    if (blocked) {
      return 'You cannot chat with a blocked member.';
    }
    return null;
  }
}
