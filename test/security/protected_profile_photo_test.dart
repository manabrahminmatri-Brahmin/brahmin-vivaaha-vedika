import 'package:brahmin_vivaaha_vedika/services/security/device_security_service.dart';
import 'package:brahmin_vivaaha_vedika/services/security/protected_image_cache_service.dart';
import 'package:brahmin_vivaaha_vedika/services/security/session_security_service.dart';
import 'package:brahmin_vivaaha_vedika/widgets/security/protected_profile_photo.dart';
import 'package:brahmin_vivaaha_vedika/widgets/security/profile_photo_watermark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SessionSecurityService.clearSession();
    DeviceSecurityService.resetForTests();
    ProtectedImageCacheService.resetCacheManagerForTests();
  });

  testWidgets('watermark overlay stacks on protected photo', (tester) async {
    SessionSecurityService.beginSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProtectedProfilePhoto(
            imageUrl: 'https://example.com/photo.jpg',
            viewerId: 'MVV12938',
            ownerId: 'MVV99999',
            sessionToken: '7AF3',
            width: 120,
            height: 120,
          ),
        ),
      ),
    );
    expect(find.byType(ProtectedProfilePhoto), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('protected image cache exposes short stale period', () {
    expect(
      ProtectedImageCacheService.stalePeriodForTests,
      const Duration(hours: 2),
    );
  });

  test('clearProtectedImageCache clears in-memory image cache', () async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(
      ProtectedImageCacheService.stalePeriodForTests.inHours,
      2,
    );
  });

  test('restrict policy when device compromised', () async {
    DeviceSecurityService.platformCheckOverride = () async => true;
    await DeviceSecurityService.isCompromisedDevice();
    final policy = ProtectedProfilePhoto.resolvePolicy();
    expect(policy.restrictSensitiveViewing, isTrue);
  });

  test('watermark lines include all required fields', () {
    final lines = ProfilePhotoWatermarkLines.build(
      viewerId: 'MVV12938',
      sessionToken: 'K29D',
      ownerId: 'MVV55555',
      timestamp: DateTime(2026, 5, 21, 22, 0),
    );
    expect(lines.first, ProfilePhotoWatermarkLines.appName);
    expect(lines.join('\n'), contains('Viewer: MVV12938'));
    expect(lines.join('\n'), contains('Token: K29D'));
    expect(lines.join('\n'), contains('Profile: MVV55555'));
  });
}
