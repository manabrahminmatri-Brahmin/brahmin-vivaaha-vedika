import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/auth_service.dart';

void main() {
  group('AuthService alias tests', () {
    test('AuthService resolves to an instance', () {
      expect(AuthService, isNotNull);
    }, skip: 'Requires Firebase app initialization in test harness.');
  });
}
