import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics events for the Interests hub.
abstract final class InterestsHubAnalytics {
  InterestsHubAnalytics._();

  static FirebaseAnalytics? get _analytics {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  static Future<void> log(
    String name, {
    Map<String, Object>? params,
  }) async {
    try {
      await _analytics?.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('InterestsHubAnalytics.$name: $e');
    }
  }

  static Future<void> interestSent({String? toUserId}) => log(
        'interest_sent',
        params: {if (toUserId != null && toUserId.isNotEmpty) 'to_user_id': toUserId},
      );

  static Future<void> interestReceived({String? fromUserId}) => log(
        'interest_received',
        params: {
          if (fromUserId != null && fromUserId.isNotEmpty) 'from_user_id': fromUserId,
        },
      );

  static Future<void> interestAccepted({String? interestId}) => log(
        'interest_accepted',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> interestRejected({String? interestId}) => log(
        'interest_rejected',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> interestWithdrawn({String? interestId}) => log(
        'interest_withdrawn',
        params: {
          if (interestId != null && interestId.isNotEmpty) 'interest_id': interestId,
        },
      );

  static Future<void> photoRequestSent({String? toUserId}) => log(
        'photo_request_sent',
        params: {if (toUserId != null && toUserId.isNotEmpty) 'to_user_id': toUserId},
      );

  static Future<void> photoRequestApproved({String? requestId}) => log(
        'photo_request_approved',
        params: {
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      );

  static Future<void> photoRequestRejected({String? requestId}) => log(
        'photo_request_rejected',
        params: {
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      );

  static Future<void> birthRequestSent({String? ownerId}) => log(
        'birth_request_sent',
        params: {if (ownerId != null && ownerId.isNotEmpty) 'owner_id': ownerId},
      );

  static Future<void> birthRequestApproved({String? requestId}) => log(
        'birth_request_approved',
        params: {
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      );

  static Future<void> communityRequestSent({String? ownerId}) => log(
        'community_request_sent',
        params: {if (ownerId != null && ownerId.isNotEmpty) 'owner_id': ownerId},
      );

  static Future<void> communityRequestApproved({String? requestId}) => log(
        'community_request_approved',
        params: {
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      );

  static Future<void> profileViewOpened({String? profileId}) => log(
        'profile_view_opened',
        params: {
          if (profileId != null && profileId.isNotEmpty) 'profile_id': profileId,
        },
      );
}
