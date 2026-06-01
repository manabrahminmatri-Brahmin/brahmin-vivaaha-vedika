import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/features/auth/auth_controller.dart';

void main() {
  group('hashMpinForTesting', () {
    test('matches salted SHA-256 output used by auth flows', () {
      final expected = sha256
          .convert(utf8.encode('mana_matrimony_mpin_salt1234'))
          .toString();

      expect(hashMpinForTesting('1234'), expected);
    });

    test('is deterministic and preserves leading zeroes', () {
      expect(hashMpinForTesting('0123'), hashMpinForTesting('0123'));
      expect(hashMpinForTesting('0123'), isNot(hashMpinForTesting('123')));
    });
  });
}
