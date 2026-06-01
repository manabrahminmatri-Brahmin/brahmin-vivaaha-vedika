import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/gender.dart';
import '../theme/app_theme.dart';
import '../services/security/profile_photo_proxy_service.dart';
import '../utils/profile_photo_cache.dart';
import '../utils/profile_photo_url_resolver.dart';
import 'security/profile_photo_security_context.dart';
import '../services/access_request_broadcast.dart';
import '../services/privacy_enforcement_service.dart';
import 'security/protected_profile_photo.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ProfilePhoto — THE one widget used for every profile photo in the app.
//
//  Variants (all same visual language, scaled by size):
//    • Small circle  — size: 60,  circle: true   (lists, tiles)
//    • Medium square — size: 110                 (match cards)
//    • Large square  — size: 140                 (home cards)
//    • Hero portrait — size: 220, height: 280     (profile detail)
//    • Own profile   — size: 200                 (my profile edit)
//
//  Rules (enforced here only — nowhere else):
//    isPhotoPrivate   → lock + "Photo Protected" + "Tap to Request"
//    !isPremiumViewer → blurred photo + lock + "Upgrade to View" overlay
//    no photo         → initial letter, gender-tinted background
//    public photo     → network image; loading spinner; error → initial fallback
//    showViewHint     → "⊕ Tap to view" gradient bar at bottom (detail screen)
//    onTap            → forwarded as-is; caller decides action
//
//  PHOTO ACCESS RULES:
//    • Free users    → photo is blurred + "Upgrade to View" shown
//    • Premium users → photo visible (subject to isPhotoPrivate check)
//    • isOwner       → always sees own photo unblurred, no premium check
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePhoto extends StatelessWidget {
  final UserProfile profile;
  final double size;
  final double? height;
  final bool circle;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool showViewHint;
  final Color? borderColor;
  final double borderWidth;
  final bool isOwner;

  /// Whether the VIEWER of this photo is a premium member.
  /// Set to true when displaying your own profile (isOwner = true already
  /// bypasses the check, but setting both to true is harmless).
  /// Defaults to false so all new call-sites are safe until updated.
  final bool isPremiumViewer;

  /// Firestore user document id of the member who owns this photo.
  final String? ownerUserId;

  /// Optional raw `users/{id}` doc for live privacy flags (root + nested profile).
  final Map<String, dynamic>? ownerUserDoc;

  /// When true, an approved photo request allows viewing a hidden/private photo.
  final bool photoAccessGranted;

  final Alignment imageAlignment;

  const ProfilePhoto({
    super.key,
    required this.profile,
    this.ownerUserId,
    this.ownerUserDoc,
    this.size = 110,
    this.height,
    this.circle = false,
    this.borderRadius,
    this.onTap,
    this.showViewHint = false,
    this.borderColor,
    this.borderWidth = 1.5,
    this.isOwner = false,
    this.isPremiumViewer = false,
    this.photoAccessGranted = false,
    this.imageAlignment = Alignment.center,
  });

  // ── Derived ───────────────────────────────────────────────────────────────
  double get _h    => height ?? size;
  double get _r    => circle ? size / 2 : (borderRadius ?? (size * 0.15).clamp(8, 28));

  String get _initial =>
      (profile.firstName.isNotEmpty ? profile.firstName[0] : '?').toUpperCase();

  Color get _avatarBg => profile.gender == Gender.female
      ? const Color(0xFFFFD6E0)
      : const Color(0xFFD6E8FF);

  Color get _avatarFg => profile.gender == Gender.female
      ? const Color(0xFFB5003A)
      : const Color(0xFF0057B5);

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveProfilePhotoUrl(
      profile: profile,
      userDoc: ownerUserDoc,
    );
    final proxyFallback = shouldAttemptProfilePhotoProxy(
      ownerUserId: ownerUserId,
      isOwner: isOwner,
    );
    final hasPicture = resolvedUrl.isNotEmpty || proxyFallback;
    final versionMs = profile.photoLastUpdated?.millisecondsSinceEpoch;
    final displayUrl = resolvedUrl.isNotEmpty
        ? ((versionMs != null && versionMs > 0)
            ? bustProfilePhotoCache(resolvedUrl, versionMs: versionMs)
            : resolvedUrl)
        : '';
    final imageCacheKey = resolvedUrl.isNotEmpty
        ? profilePhotoCacheKey(displayUrl, versionMs: versionMs)
        : 'proxy:${ownerUserId ?? profile.id}';
    // Use parsed profile privacy as primary source to avoid stale embedded
    // user-doc snapshots (seen in multi-device sessions) keeping old private
    // state after the owner switches photo to public.
    final isPrivateByProfile = profile.isPhotoPrivate ?? false;
    final isPrivateByDoc = PrivacyEnforcementService.isPhotoHiddenFromOthers(
      ownerUserDoc,
    );
    final isPrivateView = !isOwner &&
        !photoAccessGranted &&
        // Doc-level fallback only when profile payload is sparse.
        (isPrivateByProfile || (isPrivateByDoc && !hasPicture));
    final showRealPhoto = hasPicture &&
        !isPrivateView &&
        (isOwner || isPremiumViewer || photoAccessGranted);
    final blurForFreeViewer = hasPicture &&
        !isPrivateView &&
        !isOwner &&
        !isPremiumViewer &&
        !photoAccessGranted;

    Widget inner;

    if (isPrivateView) {
      // Private photo: always attempt to load via the authenticated proxy.
      // Proxy will allow the requester after photo-request acceptance, and
      // deny everyone else (we fall back to the same lock placeholder).
      //
      // NOTE: We must have `ownerUserId` to ensure proxy usage; otherwise we'd
      // risk loading a raw legacy URL.
      if (ownerUserId == null || ownerUserId!.trim().isEmpty) {
        inner = _PrivatePlaceholder(size: size, height: _h);
      } else {
        // Rebuild (and force proxied image cache refresh) after an
        // accept/approve changes the photo-access permission.
        inner = ValueListenableBuilder<int>(
          valueListenable: AccessRequestBroadcast.tick,
          builder: (context, tick, _) {
            final privateCacheKey = '$imageCacheKey|photoReq:$tick';
            return _NetImage(
              url: displayUrl,
              imageCacheKey: privateCacheKey,
              ownerUserId: ownerUserId,
              layoutWidth: size,
              layoutHeight: _h,
              imageAlignment: imageAlignment,
              fallback: _PrivatePlaceholder(size: size, height: _h),
              showHint: showViewHint,
              applyWatermark: !isOwner,
              isOwner: isOwner,
              proxyVariant: ProfilePhotoProxyVariant.full,
              viewerId: isOwner
                  ? ''
                  : ProfilePhotoSecurityContext.viewerProfileId(context),
              ownerProfileId: profile.id,
              allowLegacyDirectOnProxyFailure: false,
            );
          },
        );
      }
    } else if (showRealPhoto || (hasPicture && proxyFallback && isPremiumViewer)) {
      // Premium viewer — show real photo (direct URL or authenticated proxy).
      inner = _NetImage(
        url: displayUrl,
        imageCacheKey: imageCacheKey,
        ownerUserId: ownerUserId,
        layoutWidth: size,
        layoutHeight: _h,
        imageAlignment: imageAlignment,
        fallback: _Avatar(
            initial: _initial, bg: _avatarBg, fg: _avatarFg, size: size),
        showHint: showViewHint,
        applyWatermark: !isOwner,
        isOwner: isOwner,
        proxyVariant: ProfilePhotoProxyVariant.full,
        viewerId: isOwner ? '' : ProfilePhotoSecurityContext.viewerProfileId(context),
        ownerProfileId: profile.id,
        allowLegacyDirectOnProxyFailure:
            displayUrl.isNotEmpty && !isPrivateView,
      );
    } else if (blurForFreeViewer || (hasPicture && proxyFallback && !isPremiumViewer)) {
      // Free viewer — show blurred photo with "Upgrade to View" overlay
      inner = _PremiumBlurredPhoto(
        url: displayUrl,
        imageCacheKey: imageCacheKey,
        ownerUserId: ownerUserId,
        size: size,
        height: _h,
        imageAlignment: imageAlignment,
        viewerId: ProfilePhotoSecurityContext.viewerProfileId(context),
        ownerProfileId: profile.id,
      );
    } else {
      // No photo at all — show initial letter avatar
      inner = _Avatar(
          initial: _initial, bg: _avatarBg, fg: _avatarFg, size: size);
    }

    Widget box = Container(
      width: size,
      height: _h,
      decoration: circle
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: borderColor ?? AppTheme.primaryGold.withAlpha(60),
                  width: borderWidth))
          : BoxDecoration(
              borderRadius: BorderRadius.circular(_r),
              border: Border.all(
                  color: borderColor ?? AppTheme.primaryGold.withAlpha(50),
                  width: borderWidth)),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(circle ? size / 2 : _r - 1),
        child: inner,
      ),
    );

    return onTap != null
        ? GestureDetector(onTap: onTap, child: box)
        : box;
  }
}

// ── Private sub-widgets ───────────────────────────────────────────────────────

class _NetImage extends StatelessWidget {
  final String url;
  final String imageCacheKey;
  final double layoutWidth;
  final double layoutHeight;
  final Alignment imageAlignment;
  final Widget fallback;
  final bool showHint;
  final bool applyWatermark;
  final bool isOwner;
  final String? ownerUserId;
  final ProfilePhotoProxyVariant proxyVariant;
  final String viewerId;
  final String ownerProfileId;
  final bool allowLegacyDirectOnProxyFailure;

  const _NetImage({
    required this.url,
    required this.imageCacheKey,
    this.ownerUserId,
    required this.layoutWidth,
    required this.layoutHeight,
    required this.imageAlignment,
    required this.fallback,
    this.showHint = false,
    this.applyWatermark = true,
    this.isOwner = false,
    this.proxyVariant = ProfilePhotoProxyVariant.full,
    this.viewerId = '',
    this.ownerProfileId = '',
    this.allowLegacyDirectOnProxyFailure = false,
  });

  bool get _isNetwork =>
      url.startsWith('http://') || url.startsWith('https://');

  static int? _decodePixels(BuildContext context, double logical) {
    if (!logical.isFinite || logical <= 0) return null;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return (logical * dpr).round().clamp(1, 4096);
  }

  @override
  Widget build(BuildContext context) {
    final cacheW = _decodePixels(context, layoutWidth);
    final cacheH = _decodePixels(context, layoutHeight);
    final policy = ProtectedProfilePhoto.resolvePolicy();
    Widget photo;
    if (applyWatermark) {
      photo = ProtectedProfilePhoto(
        imageUrl: url,
        imageCacheKey: imageCacheKey,
        ownerUserId: ownerUserId,
        viewerId: viewerId,
        ownerId: ownerProfileId,
        sessionToken: ProfilePhotoSecurityContext.sessionToken(),
        proxyVariant: proxyVariant,
        isOwnerPhoto: isOwner,
        fit: BoxFit.cover,
        width: layoutWidth,
        height: layoutHeight,
        alignment: imageAlignment,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        restrictSensitiveViewing: policy.restrictSensitiveViewing,
        heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
        allowLegacyDirectOnProxyFailure: allowLegacyDirectOnProxyFailure,
        placeholder: Container(
          color: AC.surface2(context),
          child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primaryOrange),
          ),
        ),
        errorWidget: fallback,
      );
    } else if (_isNetwork) {
      photo = ProtectedProfilePhoto(
        imageUrl: url,
        imageCacheKey: imageCacheKey,
        ownerUserId: ownerUserId,
        viewerId: viewerId,
        ownerId: ownerProfileId,
        proxyVariant: proxyVariant,
        isOwnerPhoto: isOwner,
        fit: BoxFit.cover,
        width: layoutWidth,
        height: layoutHeight,
        alignment: imageAlignment,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        restrictSensitiveViewing: false,
        heavyBlurWhenRestricted: false,
        placeholder: Container(
          color: AC.surface2(context),
          child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primaryOrange),
          ),
        ),
        errorWidget: fallback,
      );
    } else {
      photo = Image.file(
        File(url),
        key: ValueKey(url),
        fit: BoxFit.cover,
        alignment: imageAlignment,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (!showHint) return photo;

    return SizedBox(
      width: layoutWidth,
      height: layoutHeight,
      child: Stack(
      clipBehavior: Clip.antiAlias,
      children: [
      photo,
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withAlpha(150),
                Colors.transparent,
              ],
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.zoom_in, color: Colors.white70, size: 14),
              SizedBox(width: 4),
              Text(
                'Tap to view',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _PremiumBlurredPhoto
//  Shown to free (non-premium, non-owner) viewers when a photo exists.
//  Renders the real image heavily blurred + a premium lock overlay on top.
//  This confirms a photo exists while protecting the actual content.
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumBlurredPhoto extends StatelessWidget {
  final String url;
  final String imageCacheKey;
  final double size;
  final double height;
  final Alignment imageAlignment;
  final String? ownerUserId;
  final String viewerId;
  final String ownerProfileId;

  const _PremiumBlurredPhoto({
    required this.url,
    required this.imageCacheKey,
    this.ownerUserId,
    required this.size,
    required this.height,
    required this.imageAlignment,
    this.viewerId = '',
    this.ownerProfileId = '',
  });

  @override
  Widget build(BuildContext context) {
    final iconSize   = (size * 0.22).clamp(16.0, 40.0);
    final labelSize  = (size * 0.10).clamp(8.0, 13.0);
    final badgePadH  = size < 80 ? 6.0 : 10.0;
    final badgePadV  = size < 80 ? 3.0 : 5.0;
    final showBadge  = size >= 60; // hide badge on very small avatars

    final policy = ProtectedProfilePhoto.resolvePolicy();
    Widget rawImage = ProtectedProfilePhoto(
      imageUrl: url,
      imageCacheKey: imageCacheKey,
      ownerUserId: ownerUserId,
      viewerId: viewerId,
      ownerId: ownerProfileId,
      sessionToken: ProfilePhotoSecurityContext.sessionToken(),
      proxyVariant: ProfilePhotoProxyVariant.preview,
      fit: BoxFit.cover,
      width: size,
      height: height,
      alignment: imageAlignment,
      memCacheWidth: 60,
      memCacheHeight: 60,
      restrictSensitiveViewing: policy.restrictSensitiveViewing,
      heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
      errorWidget: Container(color: AppTheme.primaryOrange.withAlpha(20)),
    );

    return SizedBox(
      width: size,
      height: height,
      child: Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        // ── Low-res underlying image (blurred via low resolution + filter) ─
        rawImage,

        // ── Heavy blur overlay (GPU-efficient) ──────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withAlpha(140),
                Colors.black.withAlpha(100),
                Colors.black.withAlpha(140),
              ],
            ),
          ),
        ),

        // ── Premium lock overlay ──────────────────────────────────────────
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: iconSize + 16,
                height: iconSize + 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(25),
                  border: Border.all(
                      color: AppTheme.primaryGold.withAlpha(180), width: 1.5),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: iconSize,
                  color: AppTheme.primaryGold,
                ),
              ),
              if (showBadge) ...[
                SizedBox(height: size < 100 ? 4 : 8),
                Container(
                  width: (size - 8).clamp(52.0, 400.0),
                  padding: EdgeInsets.symmetric(
                      horizontal: badgePadH, vertical: badgePadV),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryOrange,
                        AppTheme.primaryOrange.withAlpha(200),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryOrange.withAlpha(80),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(Icons.workspace_premium,
                            size: labelSize + 1, color: Colors.white),
                      ),
                      SizedBox(width: size < 100 ? 3 : 4),
                      Expanded(
                        child: Text(
                          size < 90 ? 'Upgrade' : 'Upgrade to View',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: labelSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initial;
  final Color bg, fg;
  final double size;

  const _Avatar({
    required this.initial,
    required this.bg,
    required this.fg,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: bg,
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: (size * 0.32).clamp(14.0, 52.0),
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      );
}

class _PrivatePlaceholder extends StatelessWidget {
  final double size, height;

  const _PrivatePlaceholder({required this.size, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: height,
        color: AC.surface2(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minSide = math.min(constraints.maxWidth, constraints.maxHeight);
            final compact = minSide < 72;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: compact
                      ? (minSide * 0.34).clamp(14.0, 22.0)
                      : (size * 0.24).clamp(18.0, 44.0),
                  color: AC.textSub(context),
                ),
                SizedBox(height: compact ? 2 : 6),
                Text(
                  compact ? 'Protected' : 'Photo\nProtected',
                  textAlign: TextAlign.center,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact
                        ? (minSide * 0.14).clamp(7.0, 9.0)
                        : (size * 0.10).clamp(9.0, 13.0),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMedium,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tap to Request',
                      style: TextStyle(
                        fontSize: (size * 0.08).clamp(8.0, 11.0),
                        fontWeight: FontWeight.w700,
                        color: AC.textSub(context),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SimplePhotoAvatar — for screens that only have a String? url + String name
//  (no UserProfile object) — blocked profiles, admin, shared access, liked.
//  Identical visual language to ProfilePhoto.
//
//  FIX: Image.network also uses ValueKey(photoUrl) here for the same reason.
// ─────────────────────────────────────────────────────────────────────────────

class SimplePhotoAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;
  final bool circle;
  final double? borderRadius;
  final Color? accentColor;

  /// Whether the current viewer is premium. When false and a photo exists,
  /// the avatar shows a blurred+locked overlay instead of the real photo.
  final bool isPremiumViewer;

  final String? ownerUserId;

  const SimplePhotoAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.ownerUserId,
    this.size = 60,
    this.circle = true,
    this.borderRadius,
    this.accentColor,
    this.isPremiumViewer = false,
  });

  String get _initial =>
      (name.isNotEmpty ? name[0] : '?').toUpperCase();

  double get _r => circle
      ? size / 2
      : (borderRadius ?? (size * 0.15).clamp(8, 24));

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.primaryGold;
    final hasPhoto = (photoUrl ?? '').isNotEmpty;

    final viewerId = ProfilePhotoSecurityContext.viewerProfileId(context);
    Widget inner;
    if (hasPhoto && isPremiumViewer) {
      final policy = ProtectedProfilePhoto.resolvePolicy();
      inner = ProtectedProfilePhoto(
        imageUrl: photoUrl!,
        ownerUserId: ownerUserId,
        viewerId: viewerId,
        ownerId: name,
        sessionToken: ProfilePhotoSecurityContext.sessionToken(),
        proxyVariant: ProfilePhotoProxyVariant.full,
        fit: BoxFit.cover,
        size: size,
        restrictSensitiveViewing: policy.restrictSensitiveViewing,
        heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
        placeholder: Container(
          color: AC.surface2(context),
          child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primaryOrange),
          ),
        ),
        errorWidget: _letterBox(accent),
      );
    } else if (hasPhoto && !isPremiumViewer) {
      inner = _PremiumBlurredPhoto(
        url: photoUrl!,
        imageCacheKey: profilePhotoCacheKey(photoUrl!),
        ownerUserId: ownerUserId,
        size: size,
        height: size,
        imageAlignment: Alignment.center,
        viewerId: viewerId,
        ownerProfileId: name,
      );
    } else {
      inner = _letterBox(accent);
    }

    return Container(
      width: size,
      height: size,
      decoration: circle
          ? BoxDecoration(
              shape: BoxShape.circle,
              border:
                  Border.all(color: accent.withAlpha(60), width: 1.5))
          : BoxDecoration(
              borderRadius: BorderRadius.circular(_r),
              border:
                  Border.all(color: accent.withAlpha(50), width: 1.5)),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(circle ? size / 2 : _r - 1),
        child: inner,
      ),
    );
  }

  Widget _letterBox(Color accent) => Container(
        color: accent.withAlpha(30),
        child: Center(
          child: Text(
            _initial,
            style: TextStyle(
              fontSize: (size * 0.35).clamp(12.0, 40.0),
              fontWeight: FontWeight.w800,
              color: accent.withAlpha(200),
            ),
          ),
        ),
      );
}
