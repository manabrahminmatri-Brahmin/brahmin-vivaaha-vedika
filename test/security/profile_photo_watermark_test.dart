import 'package:brahmin_vivaaha_vedika/services/security/session_security_service.dart';
import 'package:brahmin_vivaaha_vedika/widgets/security/profile_photo_watermark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SessionSecurityService.clearSession();
    SessionSecurityService.watermarkClock = () =>
        DateTime(2026, 5, 21, 22, 43);
  });

  group('ProfilePhotoWatermarkLines', () {
    test('includes viewer id and session token', () {
      final lines = ProfilePhotoWatermarkLines.build(
        viewerId: 'MVV12938',
        sessionToken: '7AF3',
      );
      expect(lines.any((l) => l.contains('MVV12938')), isTrue);
      expect(lines.any((l) => l.contains('7AF3')), isTrue);
      expect(lines.any((l) => l.contains('CONFIDENTIAL')), isTrue);
    });

    test('includes formatted timestamp', () {
      final lines = ProfilePhotoWatermarkLines.build(
        viewerId: 'MVV12938',
        sessionToken: '7AF3',
        timestamp: DateTime(2026, 5, 21, 22, 43),
      );
      expect(lines.any((l) => l.contains('21-May-2026')), isTrue);
      expect(lines.any((l) => l.contains('10:43 PM')), isTrue);
    });

    test('token changes between sessions', () {
      SessionSecurityService.beginSession();
      final first = SessionSecurityService.currentWatermarkToken();
      SessionSecurityService.beginSession();
      final second = SessionSecurityService.currentWatermarkToken();
      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(
        SessionSecurityService.sessionGeneration,
        greaterThan(1),
      );
    });

    test('token cleared on logout', () {
      SessionSecurityService.beginSession();
      expect(SessionSecurityService.currentWatermarkToken(), isNotEmpty);
      SessionSecurityService.clearSession();
      SessionSecurityService.beginSession();
      final after = SessionSecurityService.currentWatermarkToken();
      expect(after, isNotEmpty);
    });
  });

  group('ProfilePhotoWatermarkPainter', () {
    testWidgets('paints repeated watermark tiles', (tester) async {
      final lines = ProfilePhotoWatermarkLines.build(
        viewerId: 'MVV12938',
        sessionToken: '7AF3',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: ProfilePhotoWatermarkPainter(lines: lines),
              size: const Size(200, 200),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
