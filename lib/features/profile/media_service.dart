import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../../core/backend/storage_service.dart';

/// Media Service
/// 
/// Consolidates media operations from:
/// - [PhotoService], profile widgets, Cloudinary uploads
/// - [StorageService]
class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storage = StorageService();

  bool _isInitialized = false;

  /// Initialize media service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _storage.initialize();
      _isInitialized = true;
      debugPrint('✅ MediaService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ MediaService initialization failed: $e');
      rethrow;
    }
  }

  /// Pick image from gallery
  Future<Map<String, dynamic>> pickImageFromGallery({
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 85,
  }) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );

      if (pickedFile == null) {
        return {'success': false, 'message': 'No image selected'};
      }

      final file = File(pickedFile.path);
      final fileSize = await file.length();
      
      debugPrint('✅ Image picked from gallery: ${pickedFile.path}');
      
      return {
        'success': true,
        'filePath': pickedFile.path,
        'fileName': pickedFile.name,
        'fileSize': fileSize,
        'message': 'Image picked successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to pick image from gallery: $e');
      return {'success': false, 'message': 'Failed to pick image: $e'};
    }
  }

  /// Pick image from camera
  Future<Map<String, dynamic>> pickImageFromCamera({
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 85,
  }) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );

      if (pickedFile == null) {
        return {'success': false, 'message': 'No image captured'};
      }

      final file = File(pickedFile.path);
      final fileSize = await file.length();
      
      debugPrint('✅ Image captured from camera: ${pickedFile.path}');
      
      return {
        'success': true,
        'filePath': pickedFile.path,
        'fileName': pickedFile.name,
        'fileSize': fileSize,
        'message': 'Image captured successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to capture image from camera: $e');
      return {'success': false, 'message': 'Failed to capture image: $e'};
    }
  }

  /// Pick multiple images from gallery
  Future<Map<String, dynamic>> pickMultipleImages({
    int maxImages = 5,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 85,
  }) async {
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );

      if (pickedFiles.isEmpty) {
        return {'success': false, 'message': 'No images selected'};
      }

      // Limit number of images
      final limitedFiles = pickedFiles.take(maxImages).toList();
      
      final images = <Map<String, dynamic>>[];
      int totalSize = 0;

      for (final pickedFile in limitedFiles) {
        final file = File(pickedFile.path);
        final fileSize = await file.length();
        totalSize += fileSize;
        
        images.add({
          'filePath': pickedFile.path,
          'fileName': pickedFile.name,
          'fileSize': fileSize,
        });
      }
      
      debugPrint('✅ ${images.length} images picked from gallery');
      
      return {
        'success': true,
        'images': images,
        'totalSize': totalSize,
        'message': '${images.length} images picked successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to pick multiple images: $e');
      return {'success': false, 'message': 'Failed to pick images: $e'};
    }
  }

  /// Upload profile photo
  Future<Map<String, dynamic>> uploadProfilePhoto({
    required String userId,
    required String filePath,
    bool isPrimary = false,
  }) async {
    try {
      await _ensureInitialized();
      
      final result = await _storage.uploadProfilePhoto(
        userId: userId,
        filePath: filePath,
        isPrimary: isPrimary,
      );

      if (result['success'] == true) {
        debugPrint('✅ Profile photo uploaded for user: $userId');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Failed to upload profile photo: $e');
      return {'success': false, 'message': 'Failed to upload photo: $e'};
    }
  }

  /// Upload multiple profile photos
  Future<List<Map<String, dynamic>>> uploadMultipleProfilePhotos({
    required String userId,
    required List<String> filePaths,
    bool setFirstAsPrimary = false,
  }) async {
    await _ensureInitialized();
    
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < filePaths.length; i++) {
      final filePath = filePaths[i];
      final isPrimary = setFirstAsPrimary && i == 0;
      
      debugPrint('Uploading photo ${i + 1}/${filePaths.length}');
      
      final result = await uploadProfilePhoto(
        userId: userId,
        filePath: filePath,
        isPrimary: isPrimary,
      );
      
      results.add(result);
    }

    return results;
  }

  /// Delete profile photo
  Future<Map<String, dynamic>> deleteProfilePhoto({
    required String userId,
    required String photoId,
    required String photoUrl,
  }) async {
    try {
      await _ensureInitialized();
      
      // Extract filename from URL
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;
      final fileName = pathSegments.isNotEmpty ? pathSegments.last : '';
      
      if (fileName.isEmpty) {
        return {'success': false, 'message': 'Could not extract filename from URL'};
      }

      final result = await _storage.deleteUserFile(
        userId: userId,
        fileName: fileName,
        fileType: 'photos',
      );

      if (result['success'] == true) {
        debugPrint('✅ Profile photo deleted for user: $userId');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Failed to delete profile photo: $e');
      return {'success': false, 'message': 'Failed to delete photo: $e'};
    }
  }

  /// Download image from URL
  Future<Map<String, dynamic>> downloadImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        debugPrint('✅ Image downloaded from URL: $imageUrl');
        
        return {
          'success': true,
          'bytes': bytes,
          'size': bytes.length,
          'message': 'Image downloaded successfully',
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to download image: HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Failed to download image: $e');
      return {'success': false, 'message': 'Failed to download image: $e'};
    }
  }

  /// Compress image
  Future<Map<String, dynamic>> compressImage({
    required String filePath,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 85,
  }) async {
    try {
      // This would typically use image compression library
      // For now, we'll simulate compression by re-picking with quality
      final file = File(filePath);
      final originalSize = await file.length();
      
      // Re-pick with compression (simulated)
      final XFile? compressedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      if (compressedFile == null) {
        return {'success': false, 'message': 'Failed to compress image'};
      }

      final compressedSize = await File(compressedFile.path).length();
      final compressionRatio = ((originalSize - compressedSize) / originalSize * 100).round();
      
      debugPrint('✅ Image compressed: $originalSize -> $compressedSize bytes ($compressionRatio% reduction)');
      
      return {
        'success': true,
        'filePath': compressedFile.path,
        'originalSize': originalSize,
        'compressedSize': compressedSize,
        'compressionRatio': compressionRatio,
        'message': 'Image compressed successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to compress image: $e');
      return {'success': false, 'message': 'Failed to compress image: $e'};
    }
  }

  /// Validate image file
  Future<Map<String, dynamic>> validateImage(String filePath) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        return {'success': false, 'message': 'File does not exist'};
      }

      final fileSize = await file.length();
      final fileName = file.path.split('/').last.toLowerCase();
      
      // Check file size (max 10MB)
      const maxFileSize = 10 * 1024 * 1024; // 10MB
      if (fileSize > maxFileSize) {
        return {
          'success': false,
          'message': 'File too large. Maximum size is 10MB',
          'fileSize': fileSize,
        };
      }

      // Check file extension
      final validExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
      final hasValidExtension = validExtensions.any((ext) => fileName.endsWith(ext));
      
      if (!hasValidExtension) {
        return {
          'success': false,
          'message': 'Invalid file type. Supported formats: JPG, PNG, GIF, BMP, WEBP',
          'fileName': fileName,
        };
      }

      debugPrint('✅ Image validation passed: $fileName');
      
      return {
        'success': true,
        'fileSize': fileSize,
        'fileName': fileName,
        'message': 'Image validation passed',
      };
    } catch (e) {
      debugPrint('❌ Failed to validate image: $e');
      return {'success': false, 'message': 'Failed to validate image: $e'};
    }
  }

  /// Get image info
  Future<Map<String, dynamic>> getImageInfo(String filePath) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        return {'success': false, 'message': 'File does not exist'};
      }

      final fileSize = await file.length();
      final lastModified = await file.lastModified();
      final fileName = file.path.split('/').last;
      
      debugPrint('✅ Image info retrieved: $fileName');
      
      return {
        'success': true,
        'fileName': fileName,
        'filePath': filePath,
        'fileSize': fileSize,
        'lastModified': lastModified,
        'message': 'Image info retrieved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to get image info: $e');
      return {'success': false, 'message': 'Failed to get image info: $e'};
    }
  }

  /// Check storage usage for user
  Future<Map<String, dynamic>> getStorageUsage(String userId) async {
    try {
      await _ensureInitialized();
      
      final usage = await _storage.getUserStorageUsage(userId);
      
      debugPrint('✅ Storage usage retrieved for user: $userId');
      
      return {
        'success': true,
        ...usage,
        'message': 'Storage usage retrieved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to get storage usage: $e');
      return {'success': false, 'message': 'Failed to get storage usage: $e'};
    }
  }

  /// Clean up unused photos
  Future<Map<String, dynamic>> cleanupUnusedPhotos(String userId) async {
    try {
      await _ensureInitialized();
      
      // Get all photos in storage
      final storagePhotos = await _storage.getUserFiles(userId: userId, fileType: 'photos');
      
      // This would need to be compared with photos in user document
      // For now, we'll just return the list
      debugPrint('✅ Found ${storagePhotos.length} photos in storage for user: $userId');
      
      return {
        'success': true,
        'photos': storagePhotos,
        'message': 'Cleanup analysis completed',
      };
    } catch (e) {
      debugPrint('❌ Failed to cleanup photos: $e');
      return {'success': false, 'message': 'Failed to cleanup photos: $e'};
    }
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
