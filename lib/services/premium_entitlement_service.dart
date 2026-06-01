import 'package:flutter/foundation.dart';

import '../core/app_identity.dart';
import '../models/membership.dart';
import 'matrimony_gateway_service.dart';

/// Server-authoritative premium checks — do not trust client-side membership flags alone.
abstract final class PremiumEntitlementService {
  PremiumEntitlementService._();

  /// Feature keys validated server-side via [validatePremiumAccess].
  static const String featureSendInterest = 'send_interest';
  static const String featureViewContact = 'view_contact';
  static const String featureViewPrivatePhoto = 'view_private_photo';
  static const String featureChat = 'chat';
  static const String featureBirthDetails = 'birth_details_request';
  static const String featureCommunityReference = 'community_reference_request';
  static const String featurePaywall = 'premium_paywall';

  /// Local/cache hint for badges and labels only — not for access control.
  static bool displayPremiumHint(Membership? membership) =>
      membership?.isPremium ?? false;

  static Future<bool> isEntitled({
    String feature = '',
    String? userDocId,
    Membership? localMembershipHint,
  }) async {
    final docId = (userDocId ?? IdentityProvider.userDocId).trim();
    final result = await MatrimonyGatewayService.validatePremiumAccess(
      feature: feature,
      userDocId: docId.isNotEmpty ? docId : null,
    );
    if (result['success'] == true && result['entitled'] == true) {
      return true;
    }
    final code = (result['errorCode'] as String?) ?? '';
    if (localMembershipHint != null && localMembershipHint.isPremium) {
      debugPrint(
        'PremiumEntitlementService: using active local membership '
        '(gateway success=${result['success']}, entitled=${result['entitled']}, code=$code)',
      );
      return true;
    }
    if (result['success'] != true) {
      debugPrint(
        'PremiumEntitlementService: validation failed ($code) — ${result['error']}',
      );
    }
    return false;
  }

  static Future<void> requireEntitled({
    String feature = '',
    String? userDocId,
    Membership? localMembershipHint,
    String denialMessage = 'Premium membership required.',
  }) async {
    final entitled = await isEntitled(
      feature: feature,
      userDocId: userDocId,
      localMembershipHint: localMembershipHint,
    );
    if (!entitled) {
      throw Exception(denialMessage);
    }
  }
}
