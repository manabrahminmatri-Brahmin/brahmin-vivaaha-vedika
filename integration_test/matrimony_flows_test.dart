import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:brahmin_vivaaha_vedika/services/engagement_gateway_service.dart';
import 'package:brahmin_vivaaha_vedika/services/matrimony_gateway_service.dart';
import 'package:brahmin_vivaaha_vedika/services/premium_entitlement_service.dart';
import 'package:brahmin_vivaaha_vedika/widgets/security/server_premium_gate.dart';

/// Integration tests — widget + optional live Firebase (MVV_LIVE_INTEGRATION=true).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final live = Platform.environment['MVV_LIVE_INTEGRATION'] == 'true';

  group('Widgets (always run)', () {
    testWidgets('ServerPremiumGate settles with server denial without Firebase init',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ServerPremiumGate(
            feature: PremiumEntitlementService.featurePaywall,
            loading: const Text('loading'),
            builder: (context, entitled) => Text(entitled ? 'yes' : 'no'),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 12));
      expect(find.text('no'), findsOneWidget);
    });
  });

  group('Live gateway (MVV_LIVE_INTEGRATION=true)', () {
    testWidgets('validatePremiumAccess returns map', (tester) async {
      if (!live) return;
      final r = await MatrimonyGatewayService.validatePremiumAccess(
        feature: PremiumEntitlementService.featureSendInterest,
      );
      expect(r.containsKey('success'), isTrue);
    });

    testWidgets('recordProfileView callable responds', (tester) async {
      if (!live) return;
      final viewed = Platform.environment['MVV_TEST_VIEWED_USER_ID'] ?? '';
      if (viewed.isEmpty) return;
      final r = await EngagementGatewayService.recordProfileView(
        viewedUserId: viewed,
      );
      expect(r['success'], isTrue);
    });
  });
}
