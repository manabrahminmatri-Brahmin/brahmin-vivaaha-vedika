import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/security/session_security_service.dart';

/// Viewer identity + session token for protected profile photos.
abstract final class ProfilePhotoSecurityContext {
  ProfilePhotoSecurityContext._();

  static String viewerProfileId(BuildContext context) {
    try {
      final auth = context.read<AuthService>();
      final pid = auth.currentUser?.profileId.trim() ?? '';
      if (pid.isNotEmpty) return pid;
      final uid = auth.currentUser?.id.trim() ?? '';
      if (uid.isNotEmpty) return uid;
    } catch (_) {
      // No Provider above — tests / isolated widgets
    }
    return 'GUEST';
  }

  static String sessionToken() =>
      SessionSecurityService.currentWatermarkToken();
}
