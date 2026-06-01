import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/app_firebase_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import '../core/firestore_doc_map.dart';
import '../utils/firestore_timestamp_utils.dart';
import 'access_request_broadcast.dart';
import 'notification_service.dart';
import 'premium_entitlement_service.dart';

/// Service to handle access requests for community references.
/// Mirrors the flow of BirthDetailsService:
/// 1. Premium user sends request → owner gets notification
/// 2. Owner can grant or deny
/// 3. Requester sees status update (granted/denied)
/// 4. No admin involvement.
class CommunityReferenceService {
  static final CommunityReferenceService _instance = CommunityReferenceService._internal();
  factory CommunityReferenceService() => _instance;
  CommunityReferenceService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Custom logging method for CommunityReferenceService
  void log(String message) => debugPrint('[CommunityRef] $message');

  Future<void> _ensureAuthSession() async {
    if (FirebaseAuth.instance.currentUser != null) {
      return;
    }
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
    } catch (e, st) {
      log('CommunityReferenceService: auth session unavailable: $e\nStackTrace: $st');
      rethrow;
    }
  }

  // Firestore collection paths
  static const String _collection = 'community_reference_requests';

  Future<String> _resolveUserDocId(String anyId) async {
    final raw = anyId.trim();
    if (raw.isEmpty) return '';
    final byDoc = await _db.collection(Collections.users).doc(raw).get();
    if (byDoc.exists) return byDoc.id;
    final byAuth = await _db
        .collection(Collections.users)
        .where('auth_uid', isEqualTo: raw)
        .limit(1)
        .get();
    if (byAuth.docs.isNotEmpty) return byAuth.docs.first.id;
    final byProfile = await _db
        .collection(Collections.users)
        .where('profile_id', isEqualTo: raw)
        .limit(1)
        .get();
    if (byProfile.docs.isNotEmpty) return byProfile.docs.first.id;
    return '';
  }

  Future<String> resolveUserDocId(String anyId) => _resolveUserDocId(anyId);

  /// Send a community reference access request (premium user → profile owner)
  /// SECURITY FIX: Requires platinum membership
  Future<void> sendRequest({
    required String requesterId,
    required String requesterProfileId,
    required String requesterName,
    required String ownerId,
    required String ownerProfileId,
    required String ownerName,
    bool forceResend = false,
  }) async {
    await _ensureAuthSession();
    await PremiumEntitlementService.requireEntitled(
      feature: PremiumEntitlementService.featureCommunityReference,
      denialMessage:
          'Platinum membership required to send community reference requests',
    );

    final requesterDocId = await _resolveUserDocId(requesterId);
    final ownerDocId = await _resolveUserDocId(ownerId);
    if (requesterDocId.isEmpty) {
      log('❌ BLOCKED: CommunityReferenceService.sendRequest invalid requesterId');
      throw Exception('Not signed in');
    }
    if (ownerDocId.isEmpty || requesterDocId == ownerDocId) {
      log('❌ BLOCKED: CommunityReferenceService.sendRequest invalid ownerId');
      throw Exception('Invalid owner');
    }
    final requestDocId = '${requesterDocId}_$ownerDocId';
    log('🧬 Community SEND requesterId=$requesterDocId ownerId=$ownerDocId docId=$requestDocId');

    try {
      if (requesterDocId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      if (ownerDocId.isEmpty || requesterDocId == ownerDocId) {
        throw Exception('Missing or invalid owner profileDocId');
      }
      
      // 🔥 CRITICAL: Sync auth_uid before Cloud Function call for security rule validation
      final currentAuthUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentAuthUid != null) {
        await _db.collection(Collections.users).doc(requesterDocId).set({
          'auth_uid': currentAuthUid,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        log('[CommunityReferenceService] synced auth_uid for requester');
      }
      
      log('[CommunityReferenceService] Sending request: requester=$requesterDocId owner=$ownerDocId');
      // Compatibility payload: snake_case first, with camelCase aliases.
      await appFirebaseFunctions.httpsCallable('sendCommunityRequest').call({
        'requester_id': requesterDocId,
        'requester_profile_id': requesterProfileId,
        'requester_name': requesterName,
        'owner_id': ownerDocId,
        'owner_profile_id': ownerProfileId,
        'owner_name': ownerName,
        'force_resend': forceResend,
        'request_id': requestDocId,
        'requesterId': requesterDocId,
        'requesterProfileId': requesterProfileId,
        'requesterName': requesterName,
        'ownerId': ownerDocId,
        'ownerProfileId': ownerProfileId,
        'ownerName': ownerName,
        'forceResend': forceResend,
        'requestId': requestDocId,
      });
      log('[CommunityReferenceService] Request sent via callable');
      AccessRequestBroadcast.notifyChanged();
    } on FirebaseFunctionsException catch (e) {
      final msg = '[${e.code}] ${e.message ?? 'Unknown callable error'}';
      log('❌ CommunityReferenceService.sendRequest callable failed: $msg');
      throw Exception(msg);
    }
  }

  /// Send a reminder for an existing pending request.
  Future<void> sendReminder({
    required String requesterId,
    required String requesterProfileId,
    required String requesterName,
    required String ownerId,
    required String ownerProfileId,
    required String ownerName,
  }) {
    return sendRequest(
      requesterId: requesterId,
      requesterProfileId: requesterProfileId,
      requesterName: requesterName,
      ownerId: ownerId,
      ownerProfileId: ownerProfileId,
      ownerName: ownerName,
      forceResend: true,
    );
  }

  /// Get current access status for a given requester-owner pair
  /// Returns: null (no request), 'pending', 'granted', or 'denied'
  Future<String?> getAccessStatus({
    required String requesterId,
    required String ownerId,
  }) async {
    await _ensureAuthSession();
    final requesterDocId = await _resolveUserDocId(requesterId);
    final ownerDocId = await _resolveUserDocId(ownerId);
    if (requesterDocId.isEmpty || ownerDocId.isEmpty) return null;
    final canonicalId = '${requesterDocId}_$ownerDocId';
    final first = await _db.collection(_collection).doc(canonicalId).get();
    if (first.exists) return first.data()?['status'] as String?;
    return null;
  }

  /// Real-time stream of access status (for UI updates without refresh)
  Stream<String?> watchAccessStatus({
    required String requesterId,
    required String ownerId,
  }) async* {
    final requesterDocId = await _resolveUserDocId(requesterId);
    final ownerDocId = await _resolveUserDocId(ownerId);
    if (requesterDocId.isEmpty || ownerDocId.isEmpty) {
      yield null;
      return;
    }
    final canonicalId = '${requesterDocId}_$ownerDocId';
    yield* _db.collection(_collection)
        .doc(canonicalId)
        .snapshots()
        .map((snap) => snap.data()?['status'] as String?);
  }

  /// Real-time status when doc id is known (notifications use `doc_id` directly).
  Stream<String?> watchCommunityReferenceRequestStatusByDocId(
      String documentId) async* {
    final id = documentId.trim();
    if (id.isEmpty) return;
    await _ensureAuthSession();
    yield* _db
        .collection(_collection)
        .doc(id)
        .snapshots()
        .map((snap) =>
            snap.exists ? (snap.data()?['status'] as String?) : null);
  }

  /// Sent requests by requester (for Sent tab).
  Future<List<Map<String, dynamic>>> getSentRequestsForRequester(
      String requesterId) async {
    try {
      await _ensureAuthSession();
      var snap = await _db
          .collection(_collection)
          .where('requester_id', isEqualTo: requesterId)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 10));
      // Fallback for legacy/mixed docs where requester_id was auth uid style.
      if (snap.docs.isEmpty) {
        snap = await _db
            .collection(_collection)
            .where('requester_auth_uid', isEqualTo: requesterId)
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10));
      }
      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        try {
          rows.add(accessRequestRowFromDoc(doc));
        } catch (e) {
          log(
            '[CommunityReferenceService] skip sent doc ${doc.id}: $e',
          );
        }
      }

      rows.sort(compareRequestRowsNewestFirst);
      return rows;
    } catch (e) {
      log('[CommunityReferenceService] getSentRequestsForRequester failed: $e');
      return [];
    }
  }

  /// Withdraw a pending sent request.
  Future<void> withdrawRequest({
    required String requesterId,
    required String ownerId,
    String? requestId,
  }) async {
    await _ensureAuthSession();
    final requesterDocId = requesterId.trim();
    final ownerDocId = ownerId.trim();
    final requestDocId = (requestId ?? '').trim();
    if ((requesterDocId.isEmpty || ownerDocId.isEmpty) && requestDocId.isEmpty) {
      log('❌ BLOCKED: CommunityReferenceService.withdrawRequest invalid IDs');
      throw Exception('CommunityReferenceService.withdrawRequest: invalid requester/owner ID');
    }
    final canonicalDocId =
        requestDocId.isNotEmpty ? requestDocId : '${requesterDocId}_$ownerDocId';
    log('🧬 Community WITHDRAW requesterId=$requesterDocId ownerId=$ownerDocId docId=$canonicalDocId');
    final res = await (() async {
      try {
        return await appFirebaseFunctions
            .httpsCallable('withdrawCommunityRequest')
            .call({
          'requestId': canonicalDocId,
          'request_id': canonicalDocId,
          'requesterId': requesterDocId,
          'requester_id': requesterDocId,
          'ownerId': ownerDocId,
          'owner_id': ownerDocId,
        });
      } on FirebaseFunctionsException catch (e) {
        final msg = (e.message ?? '').toLowerCase();
        if (e.code == 'failed-precondition' && msg.contains('pending')) {
          AccessRequestBroadcast.notifyChanged();
          unawaited(
            NotificationService().markPrivacyNotificationsReadForRequestDoc(
              canonicalDocId,
              settledStatus: null,
            ),
          );
          return null;
        }
        final err = '[${e.code}] ${e.message ?? 'Unknown callable error'}';
        log('❌ CommunityReferenceService.withdrawRequest callable failed: $err');
        throw Exception(err);
      }
    })();
    if (res == null) {
      AccessRequestBroadcast.notifyChanged();
      return;
    }
    final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
    final deleted = data['deleted'] == true;
    final reason = (data['reason'] as String? ?? '').trim();
    if (!deleted) {
      if (reason == 'not_found' || reason == 'already_processed') {
        AccessRequestBroadcast.notifyChanged();
        unawaited(
          NotificationService().markPrivacyNotificationsReadForRequestDoc(
            canonicalDocId,
            settledStatus: reason == 'already_processed'
                ? (data['status'] as String? ?? 'granted')
                : null,
          ),
        );
        return;
      }
      throw Exception('Withdraw failed: request not found or already processed.');
    }
    AccessRequestBroadcast.notifyChanged();
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        canonicalDocId,
        settledStatus: 'withdrawn',
      ),
    );
  }

  // ignore: unused_element
  Future<DocumentReference<Map<String, dynamic>>?> _resolveRequestDocRef({
    required String requesterId,
    required String ownerId,
  }) async {
    final requestId = '${requesterId}_$ownerId';
    final directRef = _db.collection(_collection).doc(requestId);
    final directSnap = await directRef.get();
    if (directSnap.exists) return directRef;
    return null;
  }

  /// Owner GRANTS the request → notify requester
  Future<void> grantRequest({
    required String requesterId,
    required String ownerId,
  }) async {
    final requestId = '${requesterId}_$ownerId';
    await appFirebaseFunctions
        .httpsCallable('transitionCommunityRequestStatus')
        .call({
      'requestId': requestId,
      'action': 'grant',
    });

    log('[CommunityReferenceService] Access granted: $requestId');
  }

  /// Unified method to accept or reject community reference requests
  Future<void> respondToCommunityRequest({
    required String requestId,
    required bool isAccepted,
  }) async {
    await appFirebaseFunctions
        .httpsCallable('transitionCommunityRequestStatus')
        .call({
      'requestId': requestId,
      'action': isAccepted ? 'grant' : 'deny',
    });
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        requestId,
        settledStatus: isAccepted ? 'granted' : 'denied',
      ),
    );
  }

  /// Owner revokes previously granted community-reference access.
  Future<void> revokeCommunityRequest({
    required String requestId,
  }) async {
    await appFirebaseFunctions
        .httpsCallable('transitionCommunityRequestStatus')
        .call({
      'requestId': requestId,
      'action': 'revoke',
    });
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        requestId,
        settledStatus: 'revoked',
      ),
    );
  }

  /// Owner pauses granted community-reference access (status → stopped).
  Future<void> stopCommunityRequest({
    required String requestId,
  }) async {
    await appFirebaseFunctions
        .httpsCallable('transitionCommunityRequestStatus')
        .call({
      'requestId': requestId,
      'action': 'stop',
    });
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        requestId,
        settledStatus: 'stopped',
      ),
    );
  }

  /// Owner DENIES the request → notify requester
  Future<void> denyRequest({
    required String requesterId,
    required String ownerId,
  }) async {
    final requestId = '${requesterId}_$ownerId';
    await appFirebaseFunctions
        .httpsCallable('transitionCommunityRequestStatus')
        .call({
      'requestId': requestId,
      'action': 'deny',
    });

    log('[CommunityReferenceService] Access denied: $requestId');
  }

  /// Check if a user has been granted access to another user's community references
  Future<bool> hasAccess({
    required String requesterId,
    required String ownerId,
  }) async {
    final status = await getAccessStatus(requesterId: requesterId, ownerId: ownerId);
    return status == 'granted';
  }

  /// Get all pending requests for a profile owner (to show in notifications)
  Stream<QuerySnapshot> getPendingRequestsForOwner(String ownerId) {
    // Prefer owner_id; fallback to owner_auth_uid if empty result.
    return _db
        .collection(_collection)
        .where('owner_id', isEqualTo: ownerId)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .asyncMap((primary) async {
      if (primary.docs.isNotEmpty) return primary;
      final fallback = await _db
          .collection(_collection)
          .where('owner_auth_uid', isEqualTo: ownerId)
          .where('status', isEqualTo: 'pending')
          .orderBy('created_at', descending: true)
          .get();
      return fallback;
    });
  }

  /// Cancel an existing request (requester cancels their own request)
  Future<void> cancelRequest({
    required String requesterId,
    required String ownerId,
  }) async {
    await withdrawRequest(requesterId: requesterId, ownerId: ownerId);
    log('[CommunityReferenceService] Request cancelled: ${requesterId}_$ownerId');
  }
}
