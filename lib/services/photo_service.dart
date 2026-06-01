import 'dart:async';
import 'dart:io';

// 🔥 FIX: TimeoutException is defined in dart:async
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/backend/storage_service.dart';
import '../core/contract.dart';
import '../core/app_identity.dart';
import '../core/request_ui_contract.dart';
import '../models/user.dart' as app_models;
import '../theme/app_theme.dart';
import 'access_request_broadcast.dart';
import 'interests_hub_analytics.dart';
import 'block_enforcement_policy.dart';
import 'birth_details_service.dart';
import 'matrimony_gateway_service.dart';
import 'privacy_request_auth_sync.dart';

/// Photo Service
/// 
/// Handles photo operations including upload, delete, and management
class PhotoService {
  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  // 🔥 FIX: Timeout constants for all operations
  static const Duration _uploadTimeout = Duration(seconds: 60);
  static const Duration _deleteTimeout = Duration(seconds: 30);
  static const Duration _firestoreTimeout = Duration(seconds: 10);

  /// Pick image from camera or gallery
  /// 🔥 FIX: Supports Windows desktop via file_picker
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      // 🔥 Windows/Desktop: Use file_picker instead of image_picker
      if (!kIsWeb && Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.single.path != null) {
          return File(result.files.single.path!);
        }
        return null;
      }

      // Mobile platforms: Use image_picker
      // Check permissions
      if (source == ImageSource.camera) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          debugPrint('Camera permission denied');
          return null;
        }
      } else {
        final storageStatus = await Permission.photos.request();
        if (!storageStatus.isGranted) {
          debugPrint('Photos permission denied');
          return null;
        }
      }

      final XFile? pickedFile = await _imagePicker.pickImage(source: source);
      if (pickedFile != null) {
        return File(pickedFile.path);
      }
      return null;
    } catch (e) {
      debugPrint('Failed to pick image: $e');
      return null;
    }
  }

  /// Upload profile photo with timeout protection
  /// 🔥 FIX: Added timeout to prevent hanging
  Future<String?> uploadProfilePhoto(File imageFile, String userId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ User not authenticated');
        return null;
      }

      debugPrint('📤 Uploading profile photo for user: $userId');

      // 🔥 FIX: Add timeout to storage upload
      final result = await _storage.uploadProfilePhoto(
        userId: userId,
        filePath: imageFile.path,
        isPrimary: true,
      ).timeout(
        _uploadTimeout,
        onTimeout: () {
          debugPrint('❌ Upload timed out after ${_uploadTimeout.inSeconds}s');
          throw TimeoutException('Photo upload timed out');
        },
      );
      
      final photoUrl = result['downloadUrl'] as String?;
      
      if (photoUrl != null) {
        debugPrint('✅ Photo uploaded: $photoUrl');
        
        // 🔥 FIX: Add timeout to Firestore update
        await _db.collection(Collections.users).doc(userId).update({
          'photo_url': photoUrl,
          'profile.profile_picture': photoUrl,
          'updated_at': FieldValue.serverTimestamp(),
        }).timeout(
          _firestoreTimeout,
          onTimeout: () {
            debugPrint('❌ Firestore update timed out');
            throw TimeoutException('Failed to update user document');
          },
        );
        
        debugPrint('✅ Profile photo uploaded and saved successfully');
      } else {
        debugPrint('❌ Upload completed but no URL returned');
      }

      return photoUrl;
    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to upload profile photo: $e');
      return null;
    }
  }

  /// Delete profile photo with timeout protection
  /// 🔥 FIX: Added timeout and better error handling
  Future<bool> deleteProfilePhoto(String userId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ User not authenticated');
        return false;
      }

      debugPrint('🗑️  Deleting profile photo for user: $userId');

      // 🔥 FIX: Add timeout to storage deletion (non-critical)
      try {
        await _storage.deleteFile('users/$userId/photos/profile_primary.jpg')
            .timeout(
              _deleteTimeout,
              onTimeout: () {
                debugPrint('⚠️ Storage deletion timed out (non-critical)');
                throw TimeoutException('Storage deletion timed out');
              },
            );
      } catch (e) {
        debugPrint('⚠️ Storage deletion error (non-critical): $e');
      }
      
      // 🔥 FIX: Add timeout to Firestore update (critical)
      await _db.collection(Collections.users).doc(userId).update({
        'photo_url': FieldValue.delete(),
        'profile.profile_picture': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      }).timeout(
        _firestoreTimeout,
        onTimeout: () {
          debugPrint('❌ Firestore update timed out');
          throw TimeoutException('Failed to update user document');
        },
      );

      debugPrint('✅ Profile photo deleted successfully');
      return true;
    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout: $e');
      return false;
    } catch (e) {
      debugPrint('❌ Failed to delete profile photo: $e');
      return false;
    }
  }

  /// Get user's photos
  Future<List<String>> getUserPhotos(String userId) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) return [];

      final data = doc.data()!;
      final photos = data['photos'] as List<dynamic>? ?? [];
      
      return photos.cast<String>();
    } catch (e) {
      debugPrint('Failed to get user photos: $e');
      return [];
    }
  }

  /// Add photo to user's photo collection
  Future<bool> addPhoto(String userId, File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Upload photo
      final bytes = await imageFile.readAsBytes();
      final result = await _storage.uploadPhoto(userId, imageFile.path, bytes, 'image/jpeg');
      final photoUrl = result as String?;
      
      if (photoUrl != null) {
        // Add to user's photos array
        await _db.collection(Collections.users).doc(userId).update({
          'photos': FieldValue.arrayUnion([photoUrl]),
          'updated_at': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to add photo: $e');
      return false;
    }
  }

  /// Remove photo from user's photo collection with timeout protection
  /// 🔥 FIX: Added timeout and better error handling
  Future<bool> removePhoto(String userId, String photoUrl) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ User not authenticated');
        return false;
      }

      debugPrint('🗑️  Removing photo for user: $userId');

      // 🔥 FIX: Add timeout to Firestore update first (critical)
      await _db.collection(Collections.users).doc(userId).update({
        'photos': FieldValue.arrayRemove([photoUrl]),
        'updated_at': FieldValue.serverTimestamp(),
      }).timeout(
        _firestoreTimeout,
        onTimeout: () {
          debugPrint('❌ Firestore update timed out');
          throw TimeoutException('Failed to update user document');
        },
      );

      // 🔥 FIX: Add timeout to storage deletion (non-critical)
      try {
        await _storage.deletePhoto(photoUrl, userId: userId)
            .timeout(
              _deleteTimeout,
              onTimeout: () {
                debugPrint('⚠️ Storage deletion timed out (non-critical)');
              },
            );
      } catch (e) {
        debugPrint('⚠️ Storage deletion error (non-critical): $e');
      }
      
      debugPrint('✅ Photo removed successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to remove photo: $e');
      return false;
    }
  }

  /// Set profile photo from existing photos
  Future<bool> setProfilePhoto(String userId, String photoUrl) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      await _db.collection(Collections.users).doc(userId).update({
        Fields.photoUrl: photoUrl,
        Fields.updatedAt: FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Failed to set profile photo: $e');
      return false;
    }
  }

  /// Get pending photo requests
  Stream<QuerySnapshot> getPendingPhotoRequests() {
    final userId = IdentityProvider.userDocId;
    if (userId.isEmpty) {
      debugPrint('❌ Cannot get pending requests: IdentityProvider.userDocId is empty');
      return Stream.empty();
    }

    debugPrint('🔍 QUERY: photo_requests where to_user_id=$userId status=pending');

    // 🔥 CONTRACT FIX: Use Collections, Fields constants, snake_case
    return _db
        .collection(Collections.photoRequests)
        .where(Fields.toUserId, isEqualTo: userId)
        .where(Fields.status, isEqualTo: StatusValues.pending)
        .orderBy(Fields.createdAt, descending: true)
        .snapshots();
  }

  /// Request photo access
  Future<bool> requestPhotoAccess(String targetUserId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userId = IdentityProvider.userDocId;
      if (userId.isEmpty) {
        debugPrint('❌ Cannot request photo access: IdentityProvider.userDocId is empty');
        return false;
      }

      if (await BlockEnforcementPolicy.verifyBlockedForPhotoRequest(
        actorUserDocId: userId,
        peerUserDocId: targetUserId,
      )) {
        debugPrint('❌ Photo request blocked: block relationship');
        return false;
      }

      final resolver = BirthDetailsService();
      final fromDocId = await resolver.resolveUserDocId(userId);
      final toDocId = await resolver.resolveUserDocId(targetUserId);
      if (fromDocId.isEmpty || toDocId.isEmpty) {
        debugPrint('❌ Photo request: could not resolve user doc ids');
        return false;
      }

      await PrivacyRequestAuthSync.syncAuthUidForUserDoc(fromDocId);

      final result = await MatrimonyGatewayService.createPhotoRequest(
        toUserId: toDocId,
        fromUserId: fromDocId,
      );
      if (result['success'] != true) {
        debugPrint('❌ Photo request failed: ${result['error']}');
        return false;
      }

      unawaited(InterestsHubAnalytics.photoRequestSent(toUserId: toDocId));
      AccessRequestBroadcast.notifyChanged();
      debugPrint('✅ Photo request created: ${result['requestId']}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to request photo access: $e');
      return false;
    }
  }

  /// Send a photo request to another user. Returns error text when [success] is false.
  static Future<({bool success, String? error})> sendPhotoRequest({
    required String requesterUserId,
    required String targetUserId,
    required String requesterProfileId,
    required String targetProfileId,
  }) async {
    try {
      final resolver = BirthDetailsService();
      final fromDocId = await resolver.resolveUserDocId(requesterUserId);
      final toDocId = await resolver.resolveUserDocId(targetUserId);
      if (fromDocId.isEmpty || toDocId.isEmpty) {
        const msg = 'Could not resolve member profile. Try again.';
        debugPrint('❌ Photo request: empty doc id from=$fromDocId to=$toDocId');
        return (success: false, error: msg);
      }

      await PrivacyRequestAuthSync.syncAuthUidForUserDoc(fromDocId);

      if (await BlockEnforcementPolicy.verifyBlockedForPhotoRequest(
        actorUserDocId: fromDocId,
        peerUserDocId: toDocId,
        peerProfileId: targetProfileId,
      )) {
        debugPrint('❌ Photo request blocked: block relationship');
        return (success: false, error: 'This member is blocked.');
      }

      final result = await MatrimonyGatewayService.createPhotoRequest(
        toUserId: toDocId,
        fromUserId: fromDocId,
        requesterProfileId: requesterProfileId,
        targetProfileId: targetProfileId,
      );
      if (result['success'] != true) {
        final err = _mapPhotoRequestCallableError(
          (result['error'] as String? ?? '').trim(),
          (result['errorCode'] as String? ?? '').trim(),
        );
        debugPrint('❌ Photo request failed: $err (${result['errorCode'] ?? ''})');
        return (success: false, error: err);
      }

      final duplicate = result['duplicateIgnored'] == true;
      final status = (result['status'] as String? ?? '').trim().toLowerCase();
      unawaited(InterestsHubAnalytics.photoRequestSent(toUserId: toDocId));
      AccessRequestBroadcast.notifyChanged();
      debugPrint(
        duplicate
            ? '✅ Photo request up to date (${status.isNotEmpty ? status : "pending"}): ${result['requestId']}'
            : '✅ Photo request created: ${result['requestId']}',
      );
      return (success: true, error: null);
    } catch (e) {
      debugPrint('❌ Failed to send photo request: $e');
      return (success: false, error: e.toString());
    }
  }

  static String _mapPhotoRequestCallableError(String message, String code) {
    if (code == 'not-found' || message.contains('NOT_FOUND')) {
      return 'Photo request service is not available. Ask admin to deploy Cloud Functions (createPhotoRequest).';
    }
    if (code == 'unauthenticated') {
      return 'Please sign in again, then retry the photo request.';
    }
    if (code == 'permission-denied') {
      return 'Could not verify your account for photo requests. Try logging out and in again.';
    }
    if (code == 'resource-exhausted') {
      return message.isNotEmpty
          ? message
          : 'Too many photo requests. Please wait and try again.';
    }
    if (message.isNotEmpty) return message;
    return RequestUiContract.sendRequestFailed;
  }

  /// Confirm, send, and show success/error feedback for a private photo request.
  static Future<bool> showPhotoRequestDialog({
    required BuildContext context,
    required app_models.User requestingUser,
    required app_models.User targetUser,
  }) async {
    final ownerName =
        (targetUser.profile?.fullName ?? targetUser.profileId).trim();
    final displayName = ownerName.isNotEmpty ? ownerName : 'this member';

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request photo access'),
        content: Text(
          'Send a request to view $displayName\'s private photo?\n\n'
          'They can accept or decline. You can track the status under '
          'Interests → Sent → Photo requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
            ),
            child: const Text('Send request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    if (!context.mounted) return false;

    // Avoid a second overlay dialog + Navigator.pop here — on web that can pop the
    // wrong route or schedule frames after the view is disposed.
    ({bool success, String? error}) sent;
    try {
      sent = await sendPhotoRequest(
        requesterUserId: requestingUser.id,
        targetUserId: targetUser.id,
        requesterProfileId: requestingUser.profileId,
        targetProfileId: targetUser.profileId,
      );
    } catch (e) {
      sent = (success: false, error: e.toString());
    }

    if (!context.mounted) return sent.success;

    _showPhotoRequestFeedback(
      context,
      success: sent.success,
      error: sent.error,
    );

    return sent.success;
  }

  static void _showPhotoRequestFeedback(
    BuildContext context, {
    required bool success,
    String? error,
  }) {
    void show() {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        debugPrint(
          'Photo request ${success ? "sent" : "failed"}: ${error ?? ""}',
        );
        return;
      }
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? RequestUiContract.photoRequestSent
                : (error ?? RequestUiContract.sendRequestFailed),
          ),
          backgroundColor:
              success ? AppTheme.sacredGreen : AppTheme.kumkumRed,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }
}
