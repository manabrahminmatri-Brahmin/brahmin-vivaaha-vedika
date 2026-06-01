import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/app_firebase_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/access_request_status.dart';
import '../core/contract.dart';
import '../core/firestore_doc_map.dart';
import '../utils/firestore_timestamp_utils.dart';

import 'access_request_broadcast.dart';
import 'notification_service.dart';
import 'premium_entitlement_service.dart';

/// Handles the full birth-details request / grant / deny lifecycle.
///
/// Flow:
///   1. Premium requester calls [sendRequest] → creates doc in `birth_requests`
///      with status = 'pending', notifies the profile owner.
///   2. Owner sees the notification → taps Grant or Deny.
///   3. Owner calls [respondToRequest] → updates status to 'granted' or 'denied',
///      notifies the requester.
///   4. Requester calls [getAccessStatus] → returns 'granted' / 'denied' / 'pending' / null.
///   5. Widget shows actual birth details only when status == 'granted'.
///
/// No admin involvement at any step.
class BirthDetailsService {
  static final BirthDetailsService _instance = BirthDetailsService._();
  factory BirthDetailsService() => _instance;
  BirthDetailsService._();

  final _db = FirebaseFirestore.instance;

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
      debugPrint('⚠️ BirthDetailsService: auth session unavailable: $e\n$st');
      rethrow;
    }
  }

  // ── Document ID convention: "{requesterId}_{ownerId}" ────────────────────
  String _docId(String requesterId, String ownerId) =>
      '${requesterId}_$ownerId';

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

  // ─────────────────────────────────────────────────────────────────────────
  // SEND REQUEST (requester side)
  // ─────────────────────────────────────────────────────────────────────────
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
      feature: PremiumEntitlementService.featureBirthDetails,
      denialMessage: 'Premium membership required to request birth details',
    );

    final requesterDocId = await _resolveUserDocId(requesterId);
    final ownerDocId = await _resolveUserDocId(ownerId);
    if (requesterDocId.isEmpty) {
      debugPrint('❌ BLOCKED: BirthDetailsService.sendRequest invalid requesterId');
      throw Exception('BirthDetailsService.sendRequest: invalid requesterId');
    }
    if (ownerDocId.isEmpty || requesterDocId == ownerDocId) {
      debugPrint('❌ BLOCKED: BirthDetailsService.sendRequest invalid ownerId');
      throw Exception('BirthDetailsService.sendRequest: invalid ownerId');
    }
    
    // 🔥 CRITICAL: Sync auth_uid before Cloud Function call for security rule validation
    final currentAuthUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentAuthUid != null) {
      await _db.collection(Collections.users).doc(requesterDocId).set({
        'auth_uid': currentAuthUid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ BirthDetailsService: synced auth_uid for requester');
    }
    
    final requestDocId = _docId(requesterDocId, ownerDocId);
    debugPrint('🧬 Birth SEND requesterId=$requesterDocId ownerId=$ownerDocId docId=$requestDocId');
    try {
      try {
        // Compatibility payload: snake_case first, with camelCase aliases.
        await appFirebaseFunctions.httpsCallable('sendBirthRequest').call({
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
        debugPrint('✅ BirthDetailsService.sendRequest callable success');
        AccessRequestBroadcast.notifyChanged();
      } on FirebaseFunctionsException catch (e) {
        final msg = '[${e.code}] ${e.message ?? 'Unknown callable error'}';
        debugPrint('❌ BirthDetailsService.sendRequest callable failed: $msg');
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('❌ BirthDetailsService.sendRequest: $e');
      rethrow;
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

  // ─────────────────────────────────────────────────────────────────────────
  // RESPOND (owner side — called from notifications screen)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> respondToRequest({
    required String docId,
    required String status,          // 'granted' or 'denied'
    required String requesterId,
    required String requesterProfileId,
    required String ownerName,
  }) async {
    if (docId.isEmpty) throw Exception('respondToRequest: docId is empty');
    final action = status == 'granted' ? 'grant' : 'deny';
    await appFirebaseFunctions
        .httpsCallable('transitionBirthRequestStatus')
        .call({
      'requestId': docId,
      'action': action,
    });
    final settled = status == 'granted' ? 'granted' : 'denied';
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        docId,
        settledStatus: settled,
      ),
    );
  }

  /// Owner revokes previously granted birth-details access.
  Future<void> revokeRequest({
    required String docId,
  }) async {
    if (docId.isEmpty) throw Exception('revokeRequest: docId is empty');
    await appFirebaseFunctions
        .httpsCallable('transitionBirthRequestStatus')
        .call({
      'requestId': docId,
      'action': 'revoke',
    });
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        docId,
        settledStatus: 'revoked',
      ),
    );
  }

  /// Owner pauses granted birth-details access (status → stopped).
  Future<void> stopRequest({
    required String docId,
  }) async {
    if (docId.isEmpty) throw Exception('stopRequest: docId is empty');
    await appFirebaseFunctions
        .httpsCallable('transitionBirthRequestStatus')
        .call({
      'requestId': docId,
      'action': 'stop',
    });
    unawaited(
      NotificationService().markPrivacyNotificationsReadForRequestDoc(
        docId,
        settledStatus: AccessRequestStatus.stopped,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET ACCESS STATUS  (requester side — drives widget display)
  // Returns: 'granted' | 'denied' | 'revoked' | 'pending' | null (no request yet)
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> getAccessStatus({
    required String requesterId,
    required String ownerId,
  }) async {
    try {
      await _ensureAuthSession();
      final requesterDocId = await _resolveUserDocId(requesterId);
      final ownerDocId = await _resolveUserDocId(ownerId);
      if (requesterDocId.isEmpty || ownerDocId.isEmpty) return null;
      final canonicalId = _docId(requesterDocId, ownerDocId);
      final first = await _db
          .collection('birth_requests')
          .doc(canonicalId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (first.exists) return first.data()?['status'] as String?;
      return null;
    } catch (e) {
      debugPrint('❌ BirthDetailsService.getAccessStatus: $e');
      return null;
    }
  }

  /// Real-time stream of access status for requester-owner pair.
  Stream<String?> watchAccessStatus({
    required String requesterId,
    required String ownerId,
  }) async* {
    await _ensureAuthSession();
    final requesterDocId = await _resolveUserDocId(requesterId);
    final ownerDocId = await _resolveUserDocId(ownerId);
    if (requesterDocId.isEmpty || ownerDocId.isEmpty) {
      yield null;
      return;
    }
    final canonicalId = _docId(requesterDocId, ownerDocId);
    yield* _db
        .collection('birth_requests')
        .doc(canonicalId)
        .snapshots()
        .map((snap) => snap.data()?['status'] as String?);
  }

  /// Real-time access status when the canonical document id is already known
  /// (e.g. notification payload `doc_id`).
  Stream<String?> watchBirthRequestStatusByDocId(String documentId) async* {
    final id = documentId.trim();
    if (id.isEmpty) return;
    await _ensureAuthSession();
    yield* _db
        .collection('birth_requests')
        .doc(id)
        .snapshots()
        .map((snap) =>
            snap.exists ? (snap.data()?['status'] as String?) : null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET PENDING REQUESTS FOR OWNER (used in notifications / profile screen)
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPendingRequestsForOwner(
      String ownerId) async {
    try {
      await _ensureAuthSession();
      var snap = await _db
          .collection('birth_requests')
          .where('owner_id', isEqualTo: ownerId)
          .where('status', isEqualTo: 'pending')
          .get()
          .timeout(const Duration(seconds: 8));
      // Fallback for legacy/mixed docs where owner_id was auth uid style.
      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('birth_requests')
            .where('owner_auth_uid', isEqualTo: ownerId)
            .where('status', isEqualTo: 'pending')
            .get()
            .timeout(const Duration(seconds: 8));
      }
      final rows = snap.docs.map(accessRequestRowFromDoc).toList();
      rows.sort(compareRequestRowsNewestFirst);
      return rows;
    } catch (e) {
      debugPrint('❌ BirthDetailsService.getPendingRequestsForOwner: $e');
      return [];
    }
  }

  /// Sent requests by requester (for Sent tab).
  Future<List<Map<String, dynamic>>> getSentRequestsForRequester(
      String requesterId) async {
    try {
      await _ensureAuthSession();
      var snap = await _db
          .collection('birth_requests')
          .where('requester_id', isEqualTo: requesterId)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 10));
      // Fallback for legacy/mixed docs where requester_id was auth uid style.
      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('birth_requests')
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
          debugPrint(
            '⚠️ BirthDetailsService skip sent doc ${doc.id}: $e',
          );
        }
      }

      rows.sort(compareRequestRowsNewestFirst);
      return rows;
    } catch (e) {
      debugPrint('❌ BirthDetailsService.getSentRequestsForRequester: $e');
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
      debugPrint('❌ BLOCKED: BirthDetailsService.withdrawRequest invalid IDs');
      throw Exception('BirthDetailsService.withdrawRequest: invalid requester/owner ID');
    }
    final canonicalDocId =
        requestDocId.isNotEmpty ? requestDocId : _docId(requesterDocId, ownerDocId);
    debugPrint('🧬 Birth WITHDRAW requesterId=$requesterDocId ownerId=$ownerDocId docId=$canonicalDocId');
    final res = await (() async {
      try {
        return await appFirebaseFunctions
            .httpsCallable('withdrawBirthRequest')
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
        debugPrint('❌ BirthDetailsService.withdrawRequest callable failed: $err');
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
    final directRef = _db.collection('birth_requests').doc(_docId(requesterId, ownerId));
    final directSnap = await directRef.get();
    if (directSnap.exists) return directRef;
    return null;
  }
}
