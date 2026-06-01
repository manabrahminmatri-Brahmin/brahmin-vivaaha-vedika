import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/utils/profile_field_mapping.dart';

void main() {
  group('ProfileFieldMapping.convertProfileToSnakeCase', () {
    test('maps withdrawnAt and responseMessage to snake_case', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1700000000000);
      final input = <String, dynamic>{
        'withdrawnAt': ts,
        'responseMessage': 'Accepted',
      };

      final result = ProfileFieldMapping.convertProfileToSnakeCase(input);

      expect(result.containsKey('withdrawn_at'), isTrue);
      expect(result.containsKey('response_message'), isTrue);
      expect(result.containsKey('withdrawnAt'), isFalse);
      expect(result.containsKey('responseMessage'), isFalse);
      expect(result['withdrawn_at'], ts);
      expect(result['response_message'], 'Accepted');
    });

    test('toSnakeCase resolves interest lifecycle keys', () {
      expect(ProfileFieldMapping.toSnakeCase('withdrawnAt'), 'withdrawn_at');
      expect(
        ProfileFieldMapping.toSnakeCase('responseMessage'),
        'response_message',
      );
    });

    test('toCamelCase resolves interest lifecycle keys', () {
      expect(ProfileFieldMapping.toCamelCase('withdrawn_at'), 'withdrawnAt');
      expect(
        ProfileFieldMapping.toCamelCase('response_message'),
        'responseMessage',
      );
    });

    test('auto-converts unknown camelCase keys via fallback', () {
      expect(
        ProfileFieldMapping.toSnakeCase('viewedByRecipient'),
        'viewed_by_recipient',
      );
    });

    test('does not warn for interest lifecycle keys on full map convert', () {
      final result = ProfileFieldMapping.convertProfileToSnakeCase({
        'withdrawnAt': 'x',
        'responseMessage': 'y',
        'viewedByRecipient': true,
      });
      expect(result.keys, containsAll(['withdrawn_at', 'response_message']));
      expect(result['viewed_by_recipient'], isTrue);
    });
  });
}
