import 'package:flutter/material.dart';
import '../models/user.dart';
import 'profile_photo.dart';

class ProfileImage extends StatelessWidget {
  final String? url;
  final double size;
  final String? ownerUserId;
  final String? profileId;

  const ProfileImage({
    super.key,
    this.url,
    this.size = 50,
    this.ownerUserId,
    this.profileId,
  });

  @override
  Widget build(BuildContext context) {
    final safeUrl = (url ?? '').trim();
    final ownerId = (ownerUserId ?? '').trim();
    final pid = (profileId ?? '').trim();
    return ProfilePhoto(
      profile: UserProfile.fallbackForDiscovery(
        User(
          id: ownerId.isNotEmpty ? ownerId : (pid.isNotEmpty ? pid : 'member'),
          profileId: pid.isNotEmpty ? pid : null,
          email: '',
          password: '',
          mobileNumber: '',
        ),
      ),
      ownerUserId: ownerId.isNotEmpty ? ownerId : null,
      ownerUserDoc: {
        if (safeUrl.isNotEmpty) ...{
          'photo_url': safeUrl,
          'profile_picture': safeUrl,
        },
      },
      size: size,
      circle: true,
      isPremiumViewer: true,
    );
  }
}
