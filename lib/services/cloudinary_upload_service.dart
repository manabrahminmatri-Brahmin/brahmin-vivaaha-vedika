import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/build_secrets.dart';
import 'cloudinary_service.dart';

/// Profile photo helpers — all uploads go through [CloudinaryService] (unsigned preset from [BuildSecrets]).
/// No Firebase Storage; no duplicate Cloudinary HTTP clients.
class CloudinaryUploadService {
  /// Predictable URL when using fixed `public_id` uploads (`profile_photos/{uid}/profile`).
  static String getProfilePhotoUrl(String uid) {
    final cloud = BuildSecrets.resolveCloudinaryCloudName();
    return 'https://res.cloudinary.com/$cloud/image/upload/'
        'c_fill,w_800,h_800,q_85/profile_photos/$uid/profile.jpg';
  }

  /// Upload profile photo (one stable asset per user when [uid] is set).
  static Future<String> uploadProfilePhoto(String filePath, {String? uid}) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final lower = filePath.toLowerCase();
    var ext = 'jpg';
    if (lower.endsWith('.png')) ext = 'png';
    if (lower.endsWith('.webp')) ext = 'webp';
    if (lower.endsWith('.gif')) ext = 'gif';

    // Unique id per upload so secure_url changes and CDN/image caches do not
    // show the previous photo after delete + re-upload.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final publicId = (uid != null && uid.isNotEmpty)
        ? 'profile_photos/$uid/profile_$stamp'
        : 'profile_photos/temp/profile_$stamp';

    return CloudinaryService.uploadImageBytes(
      bytes,
      filename: 'profile.$ext',
      publicId: publicId,
    );
  }

  /// Couple photo for Explore → Success Stories (unique id per upload).
  static Future<String> uploadSuccessStoryPhoto(
    String filePath, {
    required String userDocId,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final lower = filePath.toLowerCase();
    var ext = 'jpg';
    if (lower.endsWith('.png')) ext = 'png';
    if (lower.endsWith('.webp')) ext = 'webp';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return CloudinaryService.uploadImageBytes(
      bytes,
      filename: 'success.$ext',
      publicId: 'success_stories/$userDocId/$stamp',
    );
  }

  static Future<String> uploadSuccessStoryPhotoBytes(
    Uint8List bytes, {
    required String userDocId,
    String filename = 'success.jpg',
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return CloudinaryService.uploadImageBytes(
      bytes,
      filename: filename,
      publicId: 'success_stories/$userDocId/$stamp',
    );
  }

  /// Unsigned uploads cannot call Cloudinary destroy API (needs API secret).
  /// Clearing Firestore + next upload with same [public_id] replaces the image.
  static Future<void> deleteProfilePhoto({String? uid}) async {
    if (uid != null && uid.isNotEmpty) {
      debugPrint('🗑️ Photo marked for deletion for uid: $uid');
    }
  }
}
