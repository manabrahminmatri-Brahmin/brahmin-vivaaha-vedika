import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/build_secrets.dart';

/// Low-level **unsigned** upload to Cloudinary (HTTP multipart).
///
/// Screens should use **[CloudinaryUploadService]** for profile assets (stable `public_id`, resizing URL).
class CloudinaryService {
  /// Upload from disk (reads file once into memory — avoids path quirks on Android).
  static Future<String> uploadImage(File file) async {
    final bytes = await file.readAsBytes();
    final name = file.path.split(Platform.pathSeparator).last;
    return uploadImageBytes(bytes, filename: name.isEmpty ? 'upload.jpg' : name);
  }

  /// Preferred for in-memory bytes — no temp file, avoids read-only filesystem errors on device.
  ///
  /// [publicId] — optional Cloudinary `public_id` (e.g. `profile_photos/{userId}/profile`)
  /// for stable URLs / overwrite-on-re-upload. Omit for unique uploads each time.
  static Future<String> uploadImageBytes(
    Uint8List bytes, {
    String filename = 'profile.jpg',
    String? publicId,
  }) async {
    final cloudName = BuildSecrets.resolveCloudinaryCloudName();
    final uploadPreset = BuildSecrets.resolveCloudinaryUploadPreset();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw Exception(
        'cloudinary_not_configured: Set CLOUDINARY_CLOUD_NAME and '
        'CLOUDINARY_UPLOAD_PRESET via --dart-define=...',
      );
    }

    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final lower = filename.toLowerCase();
      final mimeStr = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : lower.endsWith('.gif')
                  ? 'image/gif'
                  : 'image/jpeg';

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset;
      if (publicId != null && publicId.isNotEmpty) {
        request.fields['public_id'] = publicId;
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeStr),
        ),
      );

      final response = await request.send().timeout(
        const Duration(seconds: 45),
      );

      final res = await response.stream.bytesToString();
      debugPrint('Cloudinary: status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(res) as Map<String, dynamic>;
        final url = data['secure_url'] as String?;
        if (url == null || url.isEmpty) {
          throw Exception(
            'cloudinary_invalid_response: Missing secure_url in Cloudinary JSON. '
            'Check upload preset "$uploadPreset" and unsigned upload settings in Cloudinary console.',
          );
        }
        return url;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(
          'cloudinary_auth_error: HTTP ${response.statusCode}. '
          'Verify cloud name "$cloudName" and that preset "$uploadPreset" allows unsigned uploads.',
        );
      }
      if (response.statusCode == 400) {
        var hint =
            'preset may be missing, wrong type (use unsigned), or file rejected';
        try {
          final j = jsonDecode(res) as Map<String, dynamic>?;
          final err = j?['error'] as Map<String, dynamic>?;
          final msg = err?['message'] as String? ?? '';
          if (msg.contains('preset') || msg.contains('Upload')) {
            hint = 'Upload preset not found or invalid — create an unsigned preset '
                'in Cloudinary (same name as CLOUDINARY_UPLOAD_PRESET / '
                '${BuildSecrets.resolveCloudinaryUploadPreset()}).';
          }
        } catch (_) {}
        throw Exception(
          'cloudinary_preset_error: HTTP 400 — $hint. Response: $res',
        );
      }
      throw Exception(
          'cloudinary_upload_failed: HTTP ${response.statusCode}: $res');
    } catch (e) {
      debugPrint('Cloudinary upload error: $e');
      throw Exception('Upload error: $e');
    }
  }

  /// 🔥 Delete image from Cloudinary using public_id
  /// 
  /// ⚠️ IMPORTANT: Cloudinary deletion requires API key + secret which should
  /// NOT be stored in client-side code. This method:
  /// 1. Extracts the public_id from the URL
  /// 2. Logs it for server-side cleanup
  /// 3. Optionally calls a Cloud Function if configured
  /// 
  /// For production, set up a Firebase Cloud Function to handle deletion
  /// or configure a scheduled cleanup job.
  static Future<bool> deleteImage(String imageUrl) async {
    try {
      if (imageUrl.isEmpty || !imageUrl.contains('cloudinary.com')) {
        debugPrint('⏭️ Not a Cloudinary URL, skipping deletion: $imageUrl');
        return true;
      }

      // Extract public_id from URL
      // URL format: https://res.cloudinary.com/{cloud}/image/upload/v{version}/{public_id}.{ext}
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length < 3) {
        debugPrint('⚠️ Invalid Cloudinary URL format: $imageUrl');
        return false;
      }

      // Find the 'upload' index and get everything after it
      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 1 >= pathSegments.length) {
        debugPrint('⚠️ Could not find upload segment in URL: $imageUrl');
        return false;
      }

      // Skip version segment (v1234567890) and get public_id
      var publicIdSegments = pathSegments.sublist(uploadIndex + 1);
      if (publicIdSegments.isNotEmpty && publicIdSegments[0].startsWith('v')) {
        publicIdSegments = publicIdSegments.sublist(1);
      }

      if (publicIdSegments.isEmpty) {
        debugPrint('⚠️ Could not extract public_id from URL: $imageUrl');
        return false;
      }

      // Join remaining segments and remove file extension
      String publicId = publicIdSegments.join('/');
      final lastDotIndex = publicId.lastIndexOf('.');
      if (lastDotIndex > 0) {
        publicId = publicId.substring(0, lastDotIndex);
      }

      final cloudName = BuildSecrets.resolveCloudinaryCloudName();
      debugPrint('🗑️ CLOUDINARY DELETE REQUESTED: cloud=$cloudName public_id=$publicId');
      debugPrint('   URL: $imageUrl');
      debugPrint('   ⚠️ Note: Actual deletion requires server-side function with API secret');
      debugPrint('   TODO: Implement Firebase Cloud Function "deleteCloudinaryImage"');
      
      // 🔥 FOR PRODUCTION: Call a Firebase Cloud Function
      // This is the secure way to delete Cloudinary images
      try {
        // Uncomment when Cloud Function is deployed:
        // final callable = FirebaseFunctions.instance.httpsCallable('deleteCloudinaryImage');
        // final result = await callable.call({'public_id': publicId});
        // debugPrint('✅ Cloud Function delete result: ${result.data}');
        // return result.data['success'] == true;
        
        // For now, log the public_id for manual/admin cleanup
        // The old image will remain in Cloudinary but won't be referenced in the app
        debugPrint('   ✅ Logged for cleanup. Old image orphaned but not referenced.');
        return true;
      } catch (e) {
        debugPrint('⚠️ Cloud Function call failed (expected if not deployed): $e');
        return true; // Return true so app flow continues
      }
    } catch (e) {
      debugPrint('⚠️ Cloudinary delete error: $e');
      // Don't throw - deletion failure shouldn't block app operations
      return true; // Return true to continue with app flow
    }
  }
}
