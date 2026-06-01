import 'package:flutter_test/flutter_test.dart';

String? _validateMpin(String mpin) {
  if (mpin.length != 4) return 'MPIN must be 4 characters';
  if (!RegExp(r'^[0-9A-Za-z]{4}$').hasMatch(mpin)) {
    return 'MPIN must be alphanumeric';
  }
  const weak = {'1234', '0000', '1111'};
  if (weak.contains(mpin)) return 'Please choose a stronger MPIN';
  return null;
}

void main() {
  group('Registration and MPIN Flow Tests', () {
    test('MPIN Validation', () {
      // Test MPIN format validation
      expect(_validateMpin('5678'), isNull);
      expect(_validateMpin('12'), isNotNull);
      expect(_validateMpin('WXYZ'), isNull);
    });

    test('Mobile Number Validation', () {
      bool isValidMobile(String mobile) {
        return mobile.length == 10 && RegExp(r'^\d{10}$').hasMatch(mobile);
      }

      expect(isValidMobile('9876543210'), true);
      expect(isValidMobile('123456789'), false);
      expect(isValidMobile('98765432109'), false);
      expect(isValidMobile('abcdefghij'), false);
    });
  });
}
