import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/access_request_broadcast.dart';
import '../../services/security/device_security_service.dart';
import '../../services/security/profile_photo_proxy_service.dart';
import '../../services/security/session_security_service.dart';
import 'profile_photo_watermark.dart';
import 'proxied_profile_image.dart';

/// Member profile photo with dynamic tiled anti-misuse watermark.
///
/// Never renders a raw network/file image without overlay.
/// Always uses finite layout (never [StackFit.expand] under unbounded parents).
class ProtectedProfilePhoto extends StatelessWidget {
  const ProtectedProfilePhoto({
    super.key,
    this.imageUrl = '',
    this.imageCacheKey,
    required this.viewerId,
    this.ownerUserId,
    this.ownerId = '',
    this.sessionToken,
    this.proxyVariant = ProfilePhotoProxyVariant.full,
    this.isOwnerPhoto = false,
    this.fit = BoxFit.cover,
    this.size,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
    this.restrictSensitiveViewing = false,
    this.heavyBlurWhenRestricted = false,
    this.allowLegacyDirectOnProxyFailure = false,
  });

  /// Legacy direct URL — ignored when [ownerUserId] proxy is active.
  final String imageUrl;

  /// Disk/memory cache key (include version when URL is cache-busted).
  final String? imageCacheKey;

  /// Firestore `users/{id}` document id of the photo owner.
  final String? ownerUserId;

  final String viewerId;

  /// Public profile id shown in watermark (e.g. MVV12938).
  final String ownerId;
  final String? sessionToken;
  final ProfilePhotoProxyVariant proxyVariant;
  final bool isOwnerPhoto;
  final BoxFit fit;

  /// Square shorthand — applied when [width]/[height] are unset.
  final double? size;
  final double? width;
  final double? height;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Block clear photo on rooted/jailbroken device until limited mode.
  final bool restrictSensitiveViewing;

  /// Extra blur when device is compromised but user chose limited access.
  final bool heavyBlurWhenRestricted;

  final bool allowLegacyDirectOnProxyFailure;

  static const double defaultFallbackSize = 56;

  bool get _isLocalFile {
    final u = imageUrl.trim();
    if (u.isEmpty) return false;
    return !(u.startsWith('http://') || u.startsWith('https://'));
  }

  bool get _useProxy =>
      ProfilePhotoProxyService.shouldUseProxyFor(
        ownerUserId: ownerUserId,
        isOwner: isOwnerPhoto,
      );

  double? get _explicitWidth => width ?? size;
  double? get _explicitHeight => height ?? size;

  static double resolveDimension({
    required double? explicit,
    required double constraintMax,
    required double fallback,
  }) {
    if (explicit != null && explicit.isFinite && explicit > 0) {
      return explicit;
    }
    if (constraintMax.isFinite && constraintMax > 0) {
      return constraintMax;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedW = resolveDimension(
          explicit: _explicitWidth,
          constraintMax: constraints.maxWidth,
          fallback: defaultFallbackSize,
        );
        final resolvedH = resolveDimension(
          explicit: _explicitHeight,
          constraintMax: constraints.maxHeight,
          fallback: defaultFallbackSize,
        );

        if (restrictSensitiveViewing) {
          return _restrictedPlaceholder(resolvedW, resolvedH);
        }

        final token =
            sessionToken ?? SessionSecurityService.currentWatermarkToken();
        final lines = ProfilePhotoWatermarkLines.build(
          viewerId: viewerId,
          sessionToken: token,
          ownerId: ownerId,
        );

        return SizedBox(
          width: resolvedW,
          height: resolvedH,
          child: _buildProtectedStack(
            lines: lines,
            width: resolvedW,
            height: resolvedH,
          ),
        );
      },
    );
  }

  Widget _buildImageChild({
    required double width,
    required double height,
  }) {
    if (_useProxy) {
      // Ensure proxied-photo cache busting whenever a privacy/access change
      // is broadcast (owner hide/unhide, request accept/deny, etc).
      return ValueListenableBuilder<int>(
        valueListenable: AccessRequestBroadcast.tick,
        builder: (context, tick, _) {
          final baseKey = (imageCacheKey ?? '').trim();
          final fallbackKey = imageUrl.trim();
          final effectiveBase = baseKey.isNotEmpty ? baseKey : fallbackKey;
          final cacheKeyWithTick = '$effectiveBase|photoTick:$tick';

          return ProxiedProfileImage(
            ownerUserId: ownerUserId,
            legacyDirectUrl: imageUrl,
            cacheKey: cacheKeyWithTick,
            variant: proxyVariant,
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            memCacheWidth: memCacheWidth,
            memCacheHeight: memCacheHeight,
            placeholder: placeholder,
            errorWidget: errorWidget,
            allowLegacyDirectOnProxyFailure: allowLegacyDirectOnProxyFailure,
          );
        },
      );
    }
    if (!_isLocalFile && imageUrl.trim().isNotEmpty) {
      return ProxiedProfileImage(
        ownerUserId: ownerUserId,
        legacyDirectUrl: imageUrl,
        cacheKey: imageCacheKey,
        variant: proxyVariant,
        forceDirectUrl: true,
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: placeholder,
        errorWidget: errorWidget,
      );
    }
    if (_isLocalFile) {
      return Image.file(
        File(imageUrl),
        key: ValueKey('protected_file_$imageUrl'),
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        cacheWidth: memCacheWidth,
        cacheHeight: memCacheHeight,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            errorWidget ?? const Icon(Icons.broken_image_outlined),
      );
    }
    return errorWidget ??
        SizedBox(
          width: width,
          height: height,
        );
  }

  Widget _buildProtectedStack({
    required List<String> lines,
    required double width,
    required double height,
  }) {
    final imageChild = _buildImageChild(width: width, height: height);

    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: imageChild,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: ProfilePhotoWatermarkPainter(lines: lines),
            ),
          ),
        ),
        if (heavyBlurWhenRestricted)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        if (heavyBlurWhenRestricted)
          Center(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Restricted device — limited view',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _restrictedPlaceholder(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security, size: 36, color: Colors.grey.shade700),
          const SizedBox(height: 8),
          Text(
            'Photo unavailable on this device',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves device policy flags for protected rendering.
  static ProtectedPhotoPolicy resolvePolicy() {
    return ProtectedPhotoPolicy(
      restrictSensitiveViewing:
          DeviceSecurityService.shouldRestrictSensitivePhotos,
      heavyBlurWhenRestricted:
          DeviceSecurityService.useHeavyBlurOnSensitivePhotos &&
              DeviceSecurityService.limitedModeAccepted,
    );
  }
}

class ProtectedPhotoPolicy {
  const ProtectedPhotoPolicy({
    required this.restrictSensitiveViewing,
    required this.heavyBlurWhenRestricted,
  });

  final bool restrictSensitiveViewing;
  final bool heavyBlurWhenRestricted;
}
