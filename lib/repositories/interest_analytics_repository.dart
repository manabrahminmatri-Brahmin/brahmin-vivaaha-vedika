import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/access_request_status.dart';
import '../core/contract.dart';
import '../core/firestore_doc_map.dart';
import '../services/matrimony_gateway_service.dart';

/// Firestore access for the interests hub (`interests_analytics_screen`).
///
/// Preserves legacy collection name **`birth_requests`** (plural) and query
/// semantics — do not confuse with [Collections.birthRequest].
class InterestAnalyticsRepository {
  static final InterestAnalyticsRepository _instance =
      InterestAnalyticsRepository._();
  factory InterestAnalyticsRepository() => _instance;
  InterestAnalyticsRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _birthRequests = 'birth_requests';

  static Map<String, Map<String, dynamic>> _rowsByDocId(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return {
      for (final d in snapshot.docs) d.id: firestoreRowFromDoc(d),
    };
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenBirthRequestsPendingOwnerDocId({
    required String ownerDocId,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = ownerDocId.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(_birthRequests)
        .where('owner_id', isEqualTo: id)
        .where(
          'status',
          whereIn: AccessRequestStatus.ownerIncomingWhereIn,
        )
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenBirthRequestsPendingOwnerAuthUid({
    required String authUid,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = authUid.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(_birthRequests)
        .where('owner_auth_uid', isEqualTo: id)
        .where(
          'status',
          whereIn: AccessRequestStatus.ownerIncomingWhereIn,
        )
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenCommunityReferencePendingOwnerDocId({
    required String ownerDocId,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = ownerDocId.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(Collections.communityReferenceRequests)
        .where('owner_id', isEqualTo: id)
        .where('status', whereIn: const ['pending', 'granted', 'revoked'])
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenCommunityReferencePendingOwnerAuthUid({
    required String authUid,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = authUid.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(Collections.communityReferenceRequests)
        .where('owner_auth_uid', isEqualTo: id)
        .where(
          'status',
          whereIn: AccessRequestStatus.ownerIncomingWhereIn,
        )
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenPhotoRequestsPendingToUserId({
    required String userDocId,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = userDocId.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(Collections.photoRequests)
        .where('to_user_id', isEqualTo: id)
        .where(
          'status',
          whereIn: AccessRequestStatus.photoOwnerIncomingWhereIn,
        )
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  StreamSubscription<Map<String, Map<String, dynamic>>>
      listenPhotoRequestsPendingToProfileId({
    required String profileId,
    required void Function(Map<String, Map<String, dynamic>> rows) onData,
    void Function(Object error)? onError,
  }) {
    final id = profileId.trim();
    if (id.isEmpty) {
      return const Stream<Map<String, Map<String, dynamic>>>.empty()
          .listen((_) {}, onError: onError);
    }
    return _db
        .collection(Collections.photoRequests)
        .where('to_profile_id', isEqualTo: id)
        .where(
          'status',
          whereIn: AccessRequestStatus.photoOwnerIncomingWhereIn,
        )
        .snapshots()
        .map(_rowsByDocId)
        .listen(onData, onError: onError ?? (_) {});
  }

  static void _ensurePhotoTransitionApplied(
    Map<String, dynamic> gateway, {
    required String expectedStatus,
    String? failureLabel,
  }) {
    if (gateway['success'] != true) {
      throw Exception(
        gateway['error']?.toString() ??
            failureLabel ??
            'Photo request update failed',
      );
    }
    if (gateway['duplicateIgnored'] != true) return;
    final status = AccessRequestStatus.normalize(gateway['status']);
    if (status != expectedStatus) {
      throw Exception(
        '${failureLabel ?? 'Photo request update failed'} (current status: $status)',
      );
    }
  }

  /// Owner accepts/denies incoming photo request (server callable).
  Future<void> mergePhotoRequestResponse({
    required String requestId,
    required bool accept,
  }) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final gateway = await MatrimonyGatewayService.transitionPhotoRequest(
      requestId: id,
      action: accept ? 'approve' : 'reject',
    );
    _ensurePhotoTransitionApplied(
      gateway,
      expectedStatus:
          accept ? AccessRequestStatus.granted : AccessRequestStatus.denied,
      failureLabel: accept
          ? 'Could not grant photo access'
          : 'Could not decline photo request',
    );
  }

  /// Owner revokes previously granted photo access.
  Future<void> mergePhotoRequestRevoke(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final gateway = await MatrimonyGatewayService.transitionPhotoRequest(
      requestId: id,
      action: 'revoke',
    );
    _ensurePhotoTransitionApplied(
      gateway,
      expectedStatus: AccessRequestStatus.revoked,
      failureLabel: 'Could not revoke photo access',
    );
  }

  /// Owner pauses granted photo access without a full revoke.
  Future<void> mergePhotoRequestStop(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final gateway = await MatrimonyGatewayService.transitionPhotoRequest(
      requestId: id,
      action: 'stop',
    );
    _ensurePhotoTransitionApplied(
      gateway,
      expectedStatus: AccessRequestStatus.stopped,
      failureLabel: 'Could not stop photo access',
    );
  }

  /// Sender withdraws pending photo request (server callable — rules block client writes).
  Future<void> mergePhotoRequestWithdrawn(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final gateway = await MatrimonyGatewayService.withdrawPhotoRequest(
      requestId: id,
    );
    if (gateway['success'] != true) {
      throw Exception(
        gateway['error']?.toString() ?? 'Photo request withdraw failed',
      );
    }
  }

  /// Sender nudges pending photo request (server callable).
  Future<void> mergePhotoRequestReminder(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final gateway = await MatrimonyGatewayService.remindPhotoRequest(
      requestId: id,
    );
    if (gateway['success'] != true) {
      throw Exception(
        gateway['error']?.toString() ?? 'Photo request reminder failed',
      );
    }
  }

  /// Accepted interest rows for mutual-matches tab — same dual queries + enrich as prior UI.
  Future<List<Map<String, dynamic>>> loadAcceptedInterestsForMatches(
    String rawUserId,
  ) async {
    final userId = rawUserId.trim();
    if (userId.isEmpty) return [];

    final sentAccepted = await _db
        .collection(Collections.interests)
        .where('from_user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    final receivedAccepted = await _db
        .collection(Collections.interests)
        .where('to_user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    final matches = <Map<String, dynamic>>[];

    for (final doc in [...sentAccepted.docs, ...receivedAccepted.docs]) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;

      final fromUserId = data['from_user_id'] as String? ?? '';
      final toUserId = data['to_user_id'] as String? ?? '';
      final isSentByMe = fromUserId == userId;
      final partnerId = isSentByMe ? toUserId : fromUserId;
      final partnerFirst = isSentByMe
          ? (data['to_first_name'] as String? ?? '')
          : (data['from_first_name'] as String? ?? '');
      final partnerLast = isSentByMe
          ? (data['to_last_name'] as String? ?? '')
          : (data['from_last_name'] as String? ?? '');
      final partnerPid = isSentByMe
          ? (data['to_profile_id'] as String? ?? '')
          : (data['from_profile_id'] as String? ?? '');
      final partnerPhoto = isSentByMe
          ? (data['to_photo_url'] as String? ?? '')
          : (data['from_photo_url'] as String? ?? '');

      data['_partner_id'] = partnerId;
      data['_partner_name'] = '$partnerFirst $partnerLast'.trim();
      data['_partner_pid'] = partnerPid;
      data['_partner_photo'] = partnerPhoto;
      data['_is_sent_by_me'] = isSentByMe;

      matches.add(data);
    }

    matches.sort((a, b) {
      final aTime =
          (a['updated_at'] as String?) ?? (a['created_at'] as String?) ?? '';
      final bTime =
          (b['updated_at'] as String?) ?? (b['created_at'] as String?) ?? '';
      return bTime.compareTo(aTime);
    });

    return matches;
  }
}
