import 'package:flutter/foundation.dart';

import '../core/firestore_doc_map.dart';
import '../features/profile/profile_repository.dart';
import '../models/user.dart' as app_models;
import 'profile_deletion_service.dart';

/// Hides birth / community / photo access requests when the other party deleted.
abstract final class AccessRequestVisibility {
  AccessRequestVisibility._();

  static final Map<String, bool> _visibilityByPeerId = <String, bool>{};

  static void invalidateCache() => _visibilityByPeerId.clear();

  /// Last [isPeerIdVisible] result — used to avoid per-card async re-checks (flicker).
  static bool? peekPeerVisible(String rawPeerId) {
    final peerId = rawPeerId.trim();
    if (peerId.isEmpty) return false;
    return _visibilityByPeerId[peerId];
  }

  static String incomingPeerId(Map<String, dynamic> row) {
    final m = normalizeFirestoreMap(row);
    final kind = (m['_privacy_kind'] as String? ?? '').toLowerCase();
    if (kind == 'photo') {
      return (m['from_user_id'] ??
              m['fromUserId'] ??
              m['requester_id'] ??
              '')
          .toString()
          .trim();
    }
    return (m['requester_id'] ??
            m['requesterId'] ??
            m['requester_auth_uid'] ??
            '')
        .toString()
        .trim();
  }

  static String outgoingPeerId(Map<String, dynamic> row) {
    final m = normalizeFirestoreMap(row);
    final kind = (m['_privacy_kind'] as String? ?? '').toLowerCase();
    if (kind == 'photo') {
      return (m['to_user_id'] ??
              m['toUserId'] ??
              m['to_profile_id'] ??
              m['owner_id'] ??
              '')
          .toString()
          .trim();
    }
    return (m['owner_id'] ??
            m['ownerId'] ??
            m['owner_auth_uid'] ??
            '')
        .toString()
        .trim();
  }

  static bool userIsEngagementVisible(app_models.User? user) {
    if (user == null) return false;
    if (user.isDeleted) return false;
    return true;
  }

  static Future<bool> isPeerIdVisible(String rawPeerId) async {
    final peerId = rawPeerId.trim();
    if (peerId.isEmpty) return false;

    final cached = _visibilityByPeerId[peerId];
    if (cached != null) return cached;

    try {
      final user = await ProfileRepository().lookupUserByAnyId(peerId);
      if (!userIsEngagementVisible(user)) {
        _visibilityByPeerId[peerId] = false;
        return false;
      }
      final raw = await ProfileRepository().getUserDocumentDataCacheFirst(
        user!.id,
      );
      final visible = !ProfileDeletionService.isUserHiddenFromEngagement(raw);
      _visibilityByPeerId[peerId] = visible;
      return visible;
    } catch (e) {
      debugPrint('AccessRequestVisibility.isPeerIdVisible($peerId): $e');
      _visibilityByPeerId[peerId] = false;
      return false;
    }
  }

  static Future<Map<String, bool>> resolveVisibility(
    Iterable<String> peerIds,
  ) async {
    final unique = peerIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final out = <String, bool>{};
    await Future.wait(
      unique.map((id) async {
        out[id] = await isPeerIdVisible(id);
      }),
    );
    return out;
  }

  static Future<Map<String, Map<String, dynamic>>> filterIncomingOwnerRows(
    Map<String, Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final peerIds = rows.values.map(incomingPeerId);
    final visible = await resolveVisibility(peerIds);
    return {
      for (final e in rows.entries)
        if (visible[incomingPeerId(e.value)] == true) e.key: e.value,
    };
  }

  static Future<List<Map<String, dynamic>>> filterOutgoingRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final visible = await resolveVisibility(rows.map(outgoingPeerId));
    return [
      for (final row in rows)
        if (visible[outgoingPeerId(row)] == true) row,
    ];
  }
}
