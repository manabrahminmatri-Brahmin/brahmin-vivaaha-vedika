import 'block_service.dart';

/// How block checks are applied across the app.
///
/// **Cache-only** ([BlockService.isEitherBlocked]): discover/matches filtering,
/// UI badges, blocked-tab lists. Safe when stale for a short window.
///
/// **Live Firestore** ([BlockService.verifyEitherBlockedLive]): send interest,
/// photo request, open profile, chat room creation, send message. Always hits
/// server so cross-device blocks apply immediately.
abstract final class BlockEnforcementPolicy {
  BlockEnforcementPolicy._();

  // ── UI / filtering (cache OK) ─────────────────────────────────────────────

  static bool isHiddenFromDiscovery({
    required BlockService blocks,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      blocks.isEitherBlocked(
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  // ── Sensitive actions (live verification required) ────────────────────────

  static Future<bool> verifyBlockedForSendInterest({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      BlockService.verifyEitherBlockedLive(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  static Future<bool> verifyBlockedForPhotoRequest({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      BlockService.verifyEitherBlockedLive(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  static Future<bool> verifyBlockedForOpenProfile({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      BlockService.verifyEitherBlockedLive(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );

  static Future<bool> verifyBlockedForChat({
    required String actorUserDocId,
    required String peerUserDocId,
    String? peerProfileId,
  }) =>
      BlockService.verifyEitherBlockedLive(
        actorUserDocId: actorUserDocId,
        peerUserDocId: peerUserDocId,
        peerProfileId: peerProfileId,
      );
}
