import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/security/profile_photo_proxy_service.dart';
import '../../services/security/protected_image_cache_service.dart';

/// Network image that loads via the authenticated profile photo proxy when applicable.
///
/// On proxy failure, falls back to [legacyDirectUrl] only when the caller has
/// already enforced photo privacy (e.g. [ProtectedProfilePhoto] / canViewPhoto).
/// Do not pass snapshot URLs here when the viewer lacks photo access.
class ProxiedProfileImage extends StatefulWidget {
  const ProxiedProfileImage({
    super.key,
    required this.ownerUserId,
    this.legacyDirectUrl,
    this.cacheKey,
    this.variant = ProfilePhotoProxyVariant.full,
    this.forceDirectUrl = false,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
    this.filterQuality = FilterQuality.medium,
    this.allowLegacyDirectOnProxyFailure = false,
  });

  final String? ownerUserId;
  final String? legacyDirectUrl;
  final String? cacheKey;
  final ProfilePhotoProxyVariant variant;
  final bool forceDirectUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;
  final FilterQuality filterQuality;

  /// When true, a failed proxied load may fall back to [legacyDirectUrl] (discover
  /// cards for premium viewers where the URL is already visibility-checked).
  final bool allowLegacyDirectOnProxyFailure;

  @override
  State<ProxiedProfileImage> createState() => _ProxiedProfileImageState();
}

class _ProxiedProfileImageState extends State<ProxiedProfileImage> {
  bool _useDirectFallback = false;

  @override
  void didUpdateWidget(ProxiedProfileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUserId != widget.ownerUserId ||
        oldWidget.legacyDirectUrl != widget.legacyDirectUrl ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.forceDirectUrl != widget.forceDirectUrl) {
      _useDirectFallback = false;
    }
  }

  String? get _legacyDirect {
    final u = (widget.legacyDirectUrl ?? '').trim();
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return null;
  }

  bool get _canFallbackToDirect =>
      !_useDirectFallback &&
      !widget.forceDirectUrl &&
      _legacyDirect != null &&
      (widget.allowLegacyDirectOnProxyFailure ||
          !ProfilePhotoProxyService.proxyEnabled);

  @override
  Widget build(BuildContext context) {
    final useDirect = widget.forceDirectUrl || _useDirectFallback;
    final url = ProfilePhotoProxyService.resolveNetworkUrl(
      ownerUserId: widget.ownerUserId,
      legacyDirectUrl: widget.legacyDirectUrl,
      variant: widget.variant,
      forceDirectUrl: useDirect,
    );
    if (url.isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    Widget buildResolvedImage(Map<String, String> headers) {
      final resolvedCacheKey = (widget.cacheKey ?? url).trim().isNotEmpty
          ? (widget.cacheKey ?? url)
          : url;
      return CachedNetworkImage(
        imageUrl: url,
        key: ValueKey(
          'proxied_${widget.variant.name}_${useDirect ? 'direct' : 'proxy'}_$resolvedCacheKey',
        ),
        cacheKey: resolvedCacheKey,
        httpHeaders: headers.isEmpty ? null : headers,
        cacheManager: ProtectedImageCacheService.cacheManagerOrNull,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        filterQuality: widget.filterQuality,
        placeholder: (_, __) =>
            widget.placeholder ??
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        errorWidget: (_, __, ___) {
          if (_canFallbackToDirect) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _useDirectFallback = true);
            });
            return widget.placeholder ??
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
          }
          return widget.errorWidget ??
              const Icon(Icons.broken_image_outlined);
        },
      );
    }

    if (useDirect) {
      return buildResolvedImage(const <String, String>{});
    }

    // Prevent early unauthenticated proxy requests at app startup.
    // The auth stream triggers a rebuild as soon as the user is ready.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) {
          return widget.placeholder ??
              const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
        }
        return FutureBuilder<Map<String, String>>(
          future: ProfilePhotoProxyService.authHeaders(),
          builder: (context, snapshot) {
            final headers = snapshot.data ?? const <String, String>{};
            if (headers.isEmpty) {
              return widget.placeholder ??
                  const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
            }
            return buildResolvedImage(headers);
          },
        );
      },
    );
  }
}
