import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discover_profile_vm.dart';
import '../services/auth_service.dart';
import '../services/access_request_broadcast.dart';
import '../services/security/profile_photo_proxy_service.dart';
import '../theme/app_theme.dart';
import 'security/profile_photo_security_context.dart';
import 'security/protected_profile_photo.dart';

class ProfileCoverflowCard extends StatelessWidget {
  final DiscoverProfileVm profile;
  final double scale;
  final double opacity;
  final double blurStrength;
  final bool isCentered;
  final String heroTag;
  final VoidCallback onTap;

  const ProfileCoverflowCard({
    super.key,
    required this.profile,
    required this.scale,
    required this.opacity,
    required this.blurStrength,
    required this.isCentered,
    required this.heroTag,
    required this.onTap,
  });

  /// Attempt load when discover supplied a URL (proxy for hidden photos too).
  bool get _canShowPhoto => profile.imageUrl.trim().isNotEmpty;

  String _photoSourceUrl(BuildContext context) {
    final direct = profile.imageUrl.trim();
    if (direct.isNotEmpty) return direct;
    final isPremiumViewer =
        context.read<AuthService>().currentUser?.membership.isPremium ?? false;
    return ProfilePhotoProxyService.resolveNetworkUrl(
      ownerUserId: profile.userId,
      legacyDirectUrl: null,
      variant: isPremiumViewer
          ? ProfilePhotoProxyVariant.full
          : ProfilePhotoProxyVariant.preview,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale.clamp(0.72, 1.0),
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isCentered ? 70 : 36),
                    blurRadius: isCentered ? 24 : 12,
                    offset: Offset(0, isCentered ? 10 : 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: heroTag,
                        child: !_canShowPhoto
                            ? Container(
                                color: AppTheme.surfaceLight2,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 64,
                                  color: AppTheme.textMedium,
                                ),
                              )
                            : SizedBox.expand(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: AccessRequestBroadcast.tick,
                                  builder: (context, tick, _) {
                                    return ProtectedProfilePhoto(
                                      imageCacheKey:
                                          'coverflow:${profile.userId}:$tick',
                                      imageUrl: _photoSourceUrl(context),
                                      ownerUserId: profile.userId,
                                      viewerId:
                                          ProfilePhotoSecurityContext.viewerProfileId(
                                              context),
                                      ownerId: profile.profileId,
                                      sessionToken:
                                          ProfilePhotoSecurityContext.sessionToken(),
                                      proxyVariant:
                                          ProfilePhotoProxyService
                                              .variantForPremiumViewer(
                                        context
                                                .read<AuthService>()
                                                .currentUser
                                                ?.membership
                                                .isPremium ??
                                            false,
                                      ),
                                      fit: BoxFit.cover,
                                      restrictSensitiveViewing:
                                          ProtectedProfilePhoto.resolvePolicy()
                                              .restrictSensitiveViewing,
                                      heavyBlurWhenRestricted:
                                          ProtectedProfilePhoto.resolvePolicy()
                                              .heavyBlurWhenRestricted,
                                      placeholder: Container(
                                        color: AppTheme.surfaceLight2,
                                        alignment: Alignment.center,
                                        child: const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      ),
                                      allowLegacyDirectOnProxyFailure:
                                          !profile.isPhotoHiddenFromOthers &&
                                              profile.imageUrl
                                                  .trim()
                                                  .isNotEmpty &&
                                              !profile.imageUrl
                                                  .contains('streamProfilePhoto'),
                                      errorWidget: Container(
                                        color: AppTheme.surfaceLight2,
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.person_rounded,
                                          size: 64,
                                          color: AppTheme.textMedium,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withAlpha(20),
                              Colors.black.withAlpha(40),
                              Colors.black.withAlpha(170),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (blurStrength > 0.01)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(
                                (blurStrength * 110).clamp(0, 120).toInt()),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (profile.isPremium)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGold.withAlpha(220),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.workspace_premium,
                                        size: 14, color: Colors.black87),
                                    SizedBox(width: 4),
                                    Text(
                                      'Premium',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Text(
                            '${profile.name}, ${profile.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${profile.profession} • ${profile.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${profile.profileId}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(34),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              profile.compatibilityLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return card;
  }
}
