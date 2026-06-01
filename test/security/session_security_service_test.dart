import 'package:brahmin_vivaaha_vedika/services/security/session_security_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SessionSecurityService.clearSession);

  test('session token cleared on logout', () {
    SessionSecurityService.beginSession();
    final before = SessionSecurityService.currentWatermarkToken();
    SessionSecurityService.clearSession();
    SessionSecurityService.beginSession();
    final after = SessionSecurityService.currentWatermarkToken();
    expect(before, isNotEmpty);
    expect(after, isNotEmpty);
    expect(SessionSecurityService.sessionGeneration, greaterThan(1));
  });

  test('token is four uppercase alphanumeric chars', () {
    SessionSecurityService.beginSession();
    final token = SessionSecurityService.currentWatermarkToken();
    expect(token.length, 4);
    expect(token, matches(RegExp(r'^[A-Z2-9]{4}$')));
  });
}
