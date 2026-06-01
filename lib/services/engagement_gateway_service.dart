import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/call_function.dart';

/// Server-authoritative profile views and likes.
abstract final class EngagementGatewayService {
  EngagementGatewayService._();

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
        'EngagementGatewayService.$functionName [${e.code}]: ${e.message}',
      );
      return {
        'success': false,
        'error': e.message ?? 'Request failed',
        'errorCode': e.code,
      };
    } catch (e) {
      debugPrint('EngagementGatewayService.$functionName: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> recordProfileView({
    required String viewedUserId,
  }) =>
      _call('recordProfileView', {'viewedUserId': viewedUserId});

  static Future<Map<String, dynamic>> recordLike({
    required String targetUserId,
  }) =>
      _call('recordLike', {
        'targetUserId': targetUserId,
        'action': 'like',
      });

  static Future<Map<String, dynamic>> recordUnlike({
    required String targetUserId,
  }) =>
      _call('recordLike', {
        'targetUserId': targetUserId,
        'action': 'unlike',
      });

  /// Server cleanup: profile views + pending birth/community/photo requests
  /// involving deleted members (client rules cannot delete these rows).
  static Future<Map<String, dynamic>> pruneStaleEngagementForMe() =>
      _call('pruneStaleEngagementForMe', const {});
}
