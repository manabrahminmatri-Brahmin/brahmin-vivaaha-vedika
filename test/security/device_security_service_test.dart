import 'package:brahmin_vivaaha_vedika/services/security/device_security_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DeviceSecurityService.resetForTests);

  test('isCompromisedDevice uses override', () async {
    DeviceSecurityService.platformCheckOverride = () async => true;
    expect(await DeviceSecurityService.isCompromisedDevice(), isTrue);
    expect(DeviceSecurityService.shouldRestrictSensitivePhotos, isTrue);
  });

  testWidgets('shows compromised device warning dialog', (tester) async {
    DeviceSecurityService.platformCheckOverride = () async => true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await DeviceSecurityService.ensureCompromisedWarningAcknowledged(
                    context,
                    userId: 'u1',
                    profileId: 'MVV1',
                  );
                },
                child: const Text('Check'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(find.text('Security risk detected'), findsOneWidget);
    expect(find.text('Continue Limited'), findsOneWidget);
    await tester.tap(find.text('Continue Limited'));
    await tester.pumpAndSettle();
    expect(DeviceSecurityService.limitedModeAccepted, isTrue);
    expect(DeviceSecurityService.shouldRestrictSensitivePhotos, isFalse);
    expect(DeviceSecurityService.useHeavyBlurOnSensitivePhotos, isTrue);
  });
}
