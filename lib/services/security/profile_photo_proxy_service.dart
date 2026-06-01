import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Variant for proxied profile photo bytes.
enum ProfilePhotoProxyVariant {
  /// Clear image — premium + privacy checks on server.
  full,

  /// Low-res blurred teaser for free-tier overlays.
  preview,
}

/// Builds authenticated proxy URLs for member profile photos.
///
/// Raw Cloudinary / Firebase Storage URLs must not be loaded in the UI when
/// [useProxy] is true and [ownerUserId] is set.
abstract final class ProfilePhotoProxyService {
  ProfilePhotoProxyService._();

  static const String _region = 'asia-south1';

  /// Set false only in tests that load fixture bytes directly.
  @visibleForTesting
  static bool useProxy = true;

  /// Whether profile photos are loaded via the authenticated proxy (production default).
  static bool get proxyEnabled => useProxy;

  /// Proxy variant for discover / coverflow cards from viewer tier.
  static ProfilePhotoProxyVariant variantForPremiumViewer(bool isPremiumViewer) {
    if (proxyEnabled && isPremiumViewer) {
      return ProfilePhotoProxyVariant.full;
    }
    return ProfilePhotoProxyVariant.preview;
  }

  static String get _projectId => DefaultFirebaseOptions.firebaseProjectId;

  static String get baseUrl =>
      'https://$_region-$_projectId.cloudfunctions.net/streamProfilePhoto';

  /// Proxied image URL (no CDN secret; access enforced server-side via ID token).
  static String imageUrl({
    required String ownerUserId,
    ProfilePhotoProxyVariant variant = ProfilePhotoProxyVariant.full,
  }) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return '';
    final variantParam =
        variant == ProfilePhotoProxyVariant.preview ? 'preview' : 'full';
    return '$baseUrl?ownerId=${Uri.encodeQueryComponent(owner)}'
        '&variant=$variantParam';
  }

  /// Resolve network source: proxy when enabled, else legacy direct URL.
  static String resolveNetworkUrl({
    required String? ownerUserId,
    required String? legacyDirectUrl,
    ProfilePhotoProxyVariant variant = ProfilePhotoProxyVariant.full,
    bool forceDirectUrl = false,
  }) {
    if (forceDirectUrl) {
      return (legacyDirectUrl ?? '').trim();
    }
    final owner = (ownerUserId ?? '').trim();
    if (useProxy && owner.isNotEmpty) {
      return imageUrl(ownerUserId: owner, variant: variant);
    }
    return (legacyDirectUrl ?? '').trim();
  }

  static bool shouldUseProxyFor({required String? ownerUserId, bool isOwner = false}) {
    if (!useProxy || isOwner) return false;
    return (ownerUserId ?? '').trim().isNotEmpty;
  }

  /// Firebase ID token for [Authorization: Bearer] on proxied GETs.
  static Future<Map<String, String>> authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const {};
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return const {};
      return {'Authorization': 'Bearer $token'};
    } catch (e) {
      debugPrint('ProfilePhotoProxyService.authHeaders: $e');
      return const {};
    }
  }
}
