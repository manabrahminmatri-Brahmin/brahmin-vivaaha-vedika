// User Action Service - Re-export to new architecture
// This file is deprecated. Use features/engagement services instead

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/like_service_v2.dart';
import '../services/interest_service_v2.dart';
import '../widgets/action_button.dart' show ActionType;
import '../core/contract.dart';

export '../services/like_service_v2.dart';
export '../services/interest_service_v2.dart';

// For backwards compatibility
// Note: This service was split into LikeService and InterestService

class UserActionService {
  static final UserActionService _instance = UserActionService._();
  factory UserActionService() => _instance;
  UserActionService._();

  final _likes = LikeService();
  final _interests = InterestService();

  Stream<Set<String>> streamMyActionIds(ActionType type) {
    if (type == ActionType.like) {
      return _likes.streamLikes(userId: '', sent: true).map((list) => list
          .map((e) =>
              (e['user_id'] ?? e['doc_id'] ?? e['to_user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet());
    } else {
      return _interests.streamInterests(userId: '', sent: true).map((list) =>
          list
              .map(
                  (e) => (e['to_user_id'] ?? e['receiver_id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet());
    }
  }

  Stream<Set<String>> streamIncomingActionIds(ActionType type) {
    if (type == ActionType.like) {
      return _likes.streamLikes(userId: '', sent: false).map((list) => list
          .map((e) => (e['user_id'] ?? e['doc_id'] ?? e['from_user_id'] ?? '')
              .toString())
          .where((id) => id.isNotEmpty)
          .toSet());
    } else {
      return _interests.streamInterests(userId: '', sent: false).map((list) =>
          list
              .map(
                  (e) => (e['from_user_id'] ?? e['sender_id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet());
    }
  }

  Stream<List<Map<String, dynamic>>> streamIncomingInterestsWithData() {
    return _interests.streamInterests(userId: '', sent: false);
  }

  Future<bool> respondToInterest(String fromUserId, String response) async {
    try {
      // Backwards compatible helper: find the pending interest doc id and respond.
      final currentUserId = _interests.boundFirestoreUserId;
      if (currentUserId.isEmpty || fromUserId.isEmpty) return false;

      final interestId = '${fromUserId}_$currentUserId';
      final res = await _interests.respondToInterestWithResult(
        interestId: interestId,
        response: response,
      );
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Send an action (like or interest) to a target user
  Future<Map<String, dynamic>> sendAction({
    required String targetUserId,
    required ActionType type,
    String? message,
  }) async {
    try {
      if (type == ActionType.like) {
        final result = await _likes.likeProfile(targetUserId: targetUserId);
        final success = result['success'] as bool? ?? false;
        return {
          'success': success,
          'message': success ? 'Liked successfully' : 'Failed to like'
        };
      } else if (type == ActionType.interest) {
        final result = await _interests.sendInterest(
          receiverId: targetUserId,
          message: message ?? '',
        );
        final ok = result['success'] == true;
        final detail = (result['error'] ?? result['message'] ?? '').toString();
        return {
          'success': ok,
          'message': ok
              ? (detail.isNotEmpty ? detail : 'Interested')
              : (detail.isNotEmpty ? detail : 'Failed to send interest'),
        };
      }
      return {'success': false, 'message': 'Unknown action type'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Stream user metadata for a list of user IDs
  Stream<Map<String, Map<String, dynamic>>> streamUserMeta(
      [List<String>? userIds]) {
    final ids = userIds ?? [];
    if (ids.isEmpty) {
      return Stream.value({});
    }
    return FirebaseFirestore.instance
        .collection(Collections.users)
        .where(FieldPath.documentId, whereIn: ids.take(10).toList())
        .snapshots()
        .map((snap) {
      final Map<String, Map<String, dynamic>> result = {};
      for (final doc in snap.docs) {
        result[doc.id] = {'id': doc.id, ...doc.data()};
      }
      return result;
    });
  }
}
