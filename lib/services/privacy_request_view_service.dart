import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import '../core/firestore_repository.dart';

/// Marks privacy-request docs viewed so Received/Sent hub badges can decrement.
abstract final class PrivacyRequestViewService {
  PrivacyRequestViewService._();

  static Future<void> markViewedByOwner(String docId) async {
    await _merge(docId, 'birth_requests', {'viewed_by_owner': true});
  }

  static Future<void> markCommunityViewedByOwner(String docId) async {
    await _merge(docId, Collections.communityReferenceRequests, {
      'viewed_by_owner': true,
    });
  }

  static Future<void> markPhotoViewedByOwner(String docId) async {
    await _merge(docId, Collections.photoRequests, {'viewed_by_owner': true});
  }

  static Future<void> markBirthViewedByRequester(String docId) async {
    await _merge(docId, 'birth_requests', {'viewed_by_requester': true});
  }

  static Future<void> markCommunityViewedByRequester(String docId) async {
    await _merge(docId, Collections.communityReferenceRequests, {
      'viewed_by_requester': true,
    });
  }

  static Future<void> markPhotoViewedByRequester(String docId) async {
    await _merge(docId, Collections.photoRequests, {
      'viewed_by_requester': true,
    });
  }

  static Future<void> _merge(
    String docId,
    String collection,
    Map<String, dynamic> fields,
  ) async {
    final id = docId.trim();
    if (id.isEmpty) return;
    try {
      final result = await FirestoreRepository.setDocument(
        collection,
        id,
        fields,
        merge: true,
      );
      if (result.isError) {
        final msg = result.message ?? '';
        if (msg.contains('permission') ||
            msg.contains('Permission') ||
            msg.contains('unavailable')) {
          return;
        }
        debugPrint(
          '⚠️ PrivacyRequestViewService.$collection/$id: $msg',
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      debugPrint('⚠️ PrivacyRequestViewService.$collection/$id: $e');
    } catch (e) {
      debugPrint('⚠️ PrivacyRequestViewService.$collection/$id: $e');
    }
  }
}
