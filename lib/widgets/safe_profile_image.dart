import 'package:flutter/material.dart';
import '../models/user.dart';
import 'profile_photo.dart';
import '../utils/safe_data_extractor.dart';

/// Safe profile image widget with proper error handling
class SafeProfileImage extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;
  final bool circle;
  final String? placeholderText;
  final Color? backgroundColor;
  final Color? textColor;

  const SafeProfileImage({
    super.key,
    required this.user,
    this.size = 50.0,
    this.circle = true,
    this.placeholderText,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = SafeDataExtractor.getUserPhotoUrl(user);
    final displayName = SafeDataExtractor.getUserDisplayName(user);
    final ownerUserId = (user['id'] ?? user['user_id'] ?? user['userDocId'] ?? '')
        .toString()
        .trim();
    final ownerProfileId =
        (user['profile_id'] ?? user['profileId'] ?? '').toString().trim();
    return ProfilePhoto(
      profile: UserProfile.fallbackForDiscovery(
        User(
          id: ownerUserId.isNotEmpty
              ? ownerUserId
              : (ownerProfileId.isNotEmpty
                  ? ownerProfileId
                  : (displayName.isNotEmpty ? displayName : 'member')),
          profileId: ownerProfileId.isNotEmpty ? ownerProfileId : null,
          email: '',
          password: '',
          mobileNumber: '',
        ),
      ),
      ownerUserId: ownerUserId.isNotEmpty ? ownerUserId : null,
      ownerUserDoc: {
        if (photoUrl.isNotEmpty) ...{
          'photo_url': photoUrl,
          'profile_picture': photoUrl,
        },
      },
      size: size,
      circle: circle,
      isPremiumViewer: true,
    );
  }

}

/// Enhanced profile image widget with online status and tap handling
class EnhancedProfileImage extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;
  final VoidCallback? onTap;
  final bool showOnlineStatus;
  final bool circle;

  const EnhancedProfileImage({
    super.key,
    required this.user,
    this.size = 50.0,
    this.onTap,
    this.showOnlineStatus = false,
    this.circle = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = SafeProfileImage(
      user: user,
      size: size,
      circle: circle,
    );

    if (showOnlineStatus) {
      image = Stack(
        children: [
          image,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: BoxDecoration(
                color: Colors.green,
                border: Border.all(color: Colors.white, width: 2),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      image = GestureDetector(
        onTap: onTap,
        child: image,
      );
    }

    return image;
  }
}
