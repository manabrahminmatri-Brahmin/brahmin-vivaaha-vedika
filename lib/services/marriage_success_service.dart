import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/call_function.dart';

/// Server-side marriage completion: deletes profile(s) and records success story.
abstract final class MarriageSuccessService {
  MarriageSuccessService._();

  static Future<Map<String, dynamic>> complete({
    required String matchSource,
    String? requesterId,
    bool skipStoryCreation = false,
  }) async {
    try {
      final result = await CallFunction(
        functionName: 'completeMarriageFixed',
        data: {
          'matchSource': matchSource,
          if (requesterId != null && requesterId.isNotEmpty)
            'requesterId': requesterId,
          if (skipStoryCreation) 'skipStoryCreation': true,
        },
      ).call();
      final raw = result.data;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return {'success': true};
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'MarriageSuccessService.complete [${e.code}]: ${e.message}',
      );
      return {
        'success': false,
        'error': e.message ?? 'Could not complete marriage profile removal',
        'errorCode': e.code,
      };
    } catch (e) {
      debugPrint('MarriageSuccessService.complete: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
