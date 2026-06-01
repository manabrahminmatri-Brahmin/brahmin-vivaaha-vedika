import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/call_function.dart';

/// Server-authoritative matrimony actions (interest, photo, chat, premium).
abstract final class MatrimonyGatewayService {
  MatrimonyGatewayService._();

  static Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await CallFunction(
        functionName: functionName,
        data: data,
      ).call();
      final raw = result.data;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return {'success': true, 'data': raw};
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'MatrimonyGatewayService.$functionName [${e.code}]: ${e.message}',
      );
      return {
        'success': false,
        'error': e.message ?? 'Request failed',
        'errorCode': e.code,
      };
    } catch (e) {
      debugPrint('MatrimonyGatewayService.$functionName: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> transitionInterest({
    required String interestId,
    required String action,
    String? declineReason,
    String? responseMessage,
    String? requesterId,
  }) =>
      _call('transitionInterestStatus', {
        'interestId': interestId,
        'action': action,
        if (declineReason != null && declineReason.isNotEmpty)
          'declineReason': declineReason,
        if (responseMessage != null && responseMessage.isNotEmpty)
          'responseMessage': responseMessage,
        if (requesterId != null && requesterId.isNotEmpty)
          'requesterId': requesterId,
      });

  static Future<Map<String, dynamic>> sendInterest({
    required String fromUserId,
    required String toUserId,
    String? message,
    bool forceResend = false,
  }) =>
      _call('createOrResendInterest', {
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        if (message != null && message.isNotEmpty) 'message': message,
        'forceResend': forceResend,
      });

  static Future<Map<String, dynamic>> transitionPhotoRequest({
    required String requestId,
    required String action,
  }) =>
      _call('transitionPhotoRequest', {
        'requestId': requestId,
        'action': action,
      });

  static Future<Map<String, dynamic>> withdrawPhotoRequest({
    required String requestId,
  }) =>
      transitionPhotoRequest(requestId: requestId, action: 'withdraw');

  static Future<Map<String, dynamic>> remindPhotoRequest({
    required String requestId,
  }) =>
      transitionPhotoRequest(requestId: requestId, action: 'remind');

  static Future<Map<String, dynamic>> createChatRoom({
    required String otherUserId,
    String? requesterId,
  }) =>
      _call('createChatRoom', {
        'otherUserId': otherUserId,
        if (requesterId != null && requesterId.isNotEmpty)
          'requesterId': requesterId,
      });

  static Future<Map<String, dynamic>> unlockContact({
    required String interestId,
    String? peerUserId,
  }) =>
      _call('unlockContact', {
        'interestId': interestId,
        if (peerUserId != null && peerUserId.isNotEmpty)
          'peerUserId': peerUserId,
      });

  static Future<Map<String, dynamic>> createPhotoRequest({
    required String toUserId,
    String? fromUserId,
    String? requesterProfileId,
    String? targetProfileId,
  }) =>
      _call('createPhotoRequest', {
        'toUserId': toUserId,
        if (fromUserId != null && fromUserId.isNotEmpty) 'fromUserId': fromUserId,
        if (requesterProfileId != null && requesterProfileId.isNotEmpty)
          'requesterProfileId': requesterProfileId,
        if (targetProfileId != null && targetProfileId.isNotEmpty)
          'targetProfileId': targetProfileId,
      });

  static Future<Map<String, dynamic>> validatePremiumAccess({
    String feature = '',
    String? userDocId,
  }) =>
      _call('validatePremiumAccess', {
        'feature': feature,
        if (userDocId != null && userDocId.isNotEmpty) 'userDocId': userDocId,
      });

  static Future<Map<String, dynamic>> ensureSupportThread({
    String? requesterId,
  }) =>
      _call('ensureSupportThread', {
        if (requesterId != null && requesterId.isNotEmpty)
          'requesterId': requesterId,
      });

  static Future<Map<String, dynamic>> sendSupportMessage({
    required String threadId,
    required String body,
    bool asAdmin = false,
    String? requesterId,
  }) =>
      _call('sendSupportMessage', {
        'threadId': threadId,
        'body': body,
        if (asAdmin) 'asAdmin': true,
        if (requesterId != null && requesterId.isNotEmpty)
          'requesterId': requesterId,
      });

  static Future<Map<String, dynamic>> markSupportThreadRead({
    required String threadId,
    bool asAdmin = false,
    String? requesterId,
  }) =>
      _call('markSupportThreadRead', {
        'threadId': threadId,
        if (asAdmin) 'asAdmin': true,
        if (requesterId != null && requesterId.isNotEmpty)
          'requesterId': requesterId,
      });
}
