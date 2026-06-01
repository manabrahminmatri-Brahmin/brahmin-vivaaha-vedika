import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brahmin_vivaaha_vedika/services/two_factor_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TwoFactorService', () {
    test('rejects invalid mobile numbers before calling provider', () async {
      var called = false;
      final service = TwoFactorService.forTesting(
        apiKey: 'test-key',
        httpGet: (url, {required timeout, required debugLabel}) async {
          called = true;
          return http.Response('{}', 200);
        },
      );

      final result = await service.sendOtp('12345');

      expect(result.success, isFalse);
      expect(result.message, contains('Invalid mobile number'));
      expect(called, isFalse);
    });

    test('cleans mobile number and persists provider session after send',
        () async {
      Uri? requestedUrl;
      final service = TwoFactorService.forTesting(
        apiKey: 'test-key',
        httpGet: (url, {required timeout, required debugLabel}) async {
          requestedUrl = url;
          return http.Response(
            jsonEncode({'Status': 'Success', 'Details': 'session-123'}),
            200,
          );
        },
      );

      final result = await service.sendOtp('+91 98765-43210');

      expect(result.success, isTrue);
      expect(result.sessionId, 'session-123');
      expect(requestedUrl.toString(),
          contains('/test-key/SMS/9876543210/AUTOGEN'));

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('2fa_sessions')!) as Map<String, dynamic>;
      expect(stored['9876543210']['id'], 'session-123');
    });

    test('appends approved template name to send URL when configured', () async {
      Uri? requestedUrl;
      final service = TwoFactorService.forTesting(
        apiKey: 'test-key',
        otpTemplate: 'MyAppOTP',
        httpGet: (url, {required timeout, required debugLabel}) async {
          requestedUrl = url;
          return http.Response(
            jsonEncode({'Status': 'Success', 'Details': 'session-tpl'}),
            200,
          );
        },
      );

      final result = await service.sendOtp('9876543210');

      expect(result.success, isTrue);
      expect(
        requestedUrl.toString(),
        'https://2factor.in/API/V1/test-key/SMS/9876543210/AUTOGEN/MyAppOTP',
      );
    });

    test('buildSendOtpUrl omits template segment when name is empty', () {
      expect(
        TwoFactorService.buildSendOtpUrl('key', '9876543210', ''),
        'https://2factor.in/API/V1/key/SMS/9876543210/AUTOGEN',
      );
    });

    test('loads persisted session for verification and clears it on success',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '2fa_sessions',
        jsonEncode({
          '9876543210': {
            'id': 'session-123',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          },
        }),
      );

      final service = TwoFactorService.forTesting(
        apiKey: 'test-key',
        httpGet: (url, {required timeout, required debugLabel}) async {
          expect(url.toString(),
              contains('/test-key/SMS/VERIFY/session-123/654321'));
          return http.Response(
            jsonEncode({'Status': 'Success', 'Details': 'OTP Matched'}),
            200,
          );
        },
      );

      final result = await service.verifyOtp('919876543210', '654321');

      expect(result.success, isTrue);
      final stored =
          jsonDecode(prefs.getString('2fa_sessions')!) as Map<String, dynamic>;
      expect(stored.containsKey('9876543210'), isFalse);
    });
  });
}
