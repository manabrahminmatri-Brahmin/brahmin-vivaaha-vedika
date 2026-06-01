import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';

/// Storage Service
/// 
/// Consolidates file storage operations from:
/// - cloudinary_service.dart
/// - cloudinary_upload_service.dart
/// - photo_service.dart (storage parts)
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  bool _isInitialized = false;

  // Getters
  bool get isInitialized => _isInitialized;

  /// Initialize storage service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('✅ StorageService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ StorageService initialization failed: $e');
      rethrow;
    }
  }

  /// Upload file from path
  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required String storagePath,
    Map<String, String>? metadata,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      final fileBytes = await file.readAsBytes();
      final fileName = path.basename(filePath);
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      return await uploadBytes(
        bytes: fileBytes,
        storagePath: storagePath,
        fileName: fileName,
        contentType: mimeType,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('❌ Failed to upload file: $e');
      return {'success': false, 'message': 'Failed to upload file: $e'};
    }
  }

  /// Upload file from bytes
  Future<Map<String, dynamic>> uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    String? fileName,
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    try {
      var ref = _storage.ref().child(storagePath);
      if (fileName != null) {
        // Use the provided filename as part of the path
        ref = ref.child(fileName);
      }
      
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          customMetadata: metadata,
        ),
      );
      
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return {
        'success': true,
        'downloadUrl': downloadUrl,
        'fullPath': snapshot.ref.fullPath,
        'size': bytes.length,
        'contentType': contentType,
      };
    } catch (e) {
      debugPrint('❌ Failed to upload bytes: $e');
      return {'success': false, 'message': 'Failed to upload file: $e'};
    }
  }

  /// Upload user file (convenience method for profile photos/documents)
  Future<Map<String, dynamic>> uploadUserFile({
    required String userId,
    required String filePath,
    required String fileType,
    Map<String, String>? metadata,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {'success': false, 'message': 'File does not exist: $filePath'};
      }

      final storagePath = 'users/$userId/$fileType';
      final result = await uploadFile(
        filePath: filePath,
        storagePath: storagePath,
        metadata: {
          'userId': userId,
          'fileType': fileType,
          'uploadedAt': DateTime.now().toIso8601String(),
          ...?metadata,
        },
      );

      return result;
    } catch (e) {
      debugPrint('❌ Failed to upload user file: $e');
      return {'success': false, 'message': 'Failed to upload user file: $e'};
    }
  }

  /// Upload image from URL
  Future<Map<String, dynamic>> uploadImageFromUrl({
    required String imageUrl,
    required String storagePath,
    String? fileName,
  }) async {
    try {
      // Download image from URL
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final finalFileName = fileName ?? path.basename(imageUrl);
      final contentType = lookupMimeType(imageUrl) ?? 'image/jpeg';

      return await uploadBytes(
        bytes: bytes,
        storagePath: storagePath,
        fileName: finalFileName,
        contentType: contentType,
      );
    } catch (e) {
      debugPrint('❌ Failed to upload image from URL: $e');
      return {'success': false, 'message': 'Failed to upload image: $e'};
    }
  }

  /// Upload multiple files
  Future<List<Map<String, dynamic>>> uploadMultipleFiles({
    required List<String> filePaths,
    required String storagePath,
    Map<String, String>? metadata,
  }) async {
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < filePaths.length; i++) {
      final filePath = filePaths[i];
      final fileName = path.basename(filePath);
      
      debugPrint('Uploading file ${i + 1}/${filePaths.length}: $fileName');
      
      final result = await uploadFile(
        filePath: filePath,
        storagePath: storagePath,
        metadata: metadata,
      );
      
      results.add(result);
    }

    return results;
  }

  /// Delete file
  Future<Map<String, dynamic>> deleteFile(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.delete();

      debugPrint('✅ File deleted successfully: $storagePath');
      
      return {
        'success': true,
        'message': 'File deleted successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to delete file: $e');
      return {'success': false, 'message': 'Failed to delete file: $e'};
    }
  }

  /// Get file download URL
  Future<String?> getDownloadUrl(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('❌ Failed to get download URL: $e');
      return null;
    }
  }

  /// Get file metadata
  Future<Map<String, dynamic>?> getFileMetadata(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      final metadata = await ref.getMetadata();
      
      return {
        'name': metadata.name,
        'bucket': metadata.bucket,
        'generation': metadata.generation,
        'metadata': metadata.customMetadata,
        'size': metadata.size,
        'contentType': metadata.contentType,
        'timeCreated': metadata.timeCreated,
        'updated': metadata.updated,
      };
    } catch (e) {
      debugPrint('❌ Failed to get file metadata: $e');
      return null;
    }
  }

  /// List files in directory
  Future<List<Map<String, dynamic>>> listFiles(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      final result = await ref.listAll();
      
      final files = <Map<String, dynamic>>[];
      
      // Add files
      for (final item in result.items) {
        final metadata = await item.getMetadata();
        files.add({
          'name': metadata.name,
          'fullPath': metadata.fullPath,
          'bucket': metadata.bucket,
          'size': metadata.size,
          'contentType': metadata.contentType,
          'timeCreated': metadata.timeCreated,
          'isDirectory': false,
        });
      }
      
      // Add directories
      for (final prefix in result.prefixes) {
        files.add({
          'name': prefix.name,
          'fullPath': prefix.fullPath,
          'bucket': prefix.bucket,
          'isDirectory': true,
        });
      }
      
      return files;
    } catch (e) {
      debugPrint('❌ Failed to list files: $e');
      return [];
    }
  }

  /// Upload user profile photo
  Future<Map<String, dynamic>> uploadProfilePhoto({
    required String userId,
    required String filePath,
    bool isPrimary = false,
  }) async {
    try {
      final storagePath = 'users/$userId/photos';
      
      final result = await uploadFile(
        filePath: filePath,
        storagePath: storagePath,
        metadata: {
          'user_id': userId,
          'type': 'profile_photo',
          'isPrimary': isPrimary.toString(),
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      if (result['success'] == true) {
        debugPrint('✅ Profile photo uploaded for user: $userId');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Failed to upload profile photo: $e');
      return {'success': false, 'message': 'Failed to upload profile photo: $e'};
    }
  }

  /// Upload document
  Future<Map<String, dynamic>> uploadDocument({
    required String userId,
    required String documentType,
    required String filePath,
    Map<String, String>? additionalMetadata,
  }) async {
    try {
      final storagePath = 'users/$userId/documents';
      
      final metadata = {
        'user_id': userId,
        'documentType': documentType,
        'uploadedAt': DateTime.now().toIso8601String(),
        ...?additionalMetadata,
      };
      
      final result = await uploadFile(
        filePath: filePath,
        storagePath: storagePath,
        metadata: metadata,
      );

      if (result['success'] == true) {
        debugPrint('✅ Document uploaded for user: $userId, type: $documentType');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Failed to upload document: $e');
      return {'success': false, 'message': 'Failed to upload document: $e'};
    }
  }

  /// Delete user file
  Future<Map<String, dynamic>> deleteUserFile({
    required String userId,
    required String fileName,
    required String fileType, // 'photos' or 'documents'
  }) async {
    try {
      final storagePath = 'users/$userId/$fileType/$fileName';
      return await deleteFile(storagePath);
    } catch (e) {
      debugPrint('❌ Failed to delete user file: $e');
      return {'success': false, 'message': 'Failed to delete file: $e'};
    }
  }

  /// Get user files
  Future<List<Map<String, dynamic>>> getUserFiles({
    required String userId,
    required String fileType, // 'photos' or 'documents'
    String? documentType,
  }) async {
    try {
      final storagePath = 'users/$userId/$fileType';
      final files = await listFiles(storagePath);
      
      // Filter by document type if specified
      if (documentType != null && fileType == 'documents') {
        return files.where((file) {
          final metadata = file['metadata'] as Map<String, String>?;
          return metadata?['documentType'] == documentType;
        }).toList();
      }
      
      return files;
    } catch (e) {
      debugPrint('❌ Failed to get user files: $e');
      return [];
    }
  }

  /// Copy file
  Future<Map<String, dynamic>> copyFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    try {
      final sourceRef = _storage.ref().child(sourcePath);
      
      // Get download URL of source
      final downloadUrl = await sourceRef.getDownloadURL();
      
      // Download and re-upload
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download source file');
      }
      
      final bytes = response.bodyBytes;
      final metadata = await sourceRef.getMetadata();
      
      return await uploadBytes(
        bytes: bytes,
        storagePath: path.dirname(destinationPath),
        fileName: path.basename(destinationPath),
        contentType: metadata.contentType,
        metadata: metadata.customMetadata,
      );
    } catch (e) {
      debugPrint('❌ Failed to copy file: $e');
      return {'success': false, 'message': 'Failed to copy file: $e'};
    }
  }

  /// Check if file exists
  Future<bool> fileExists(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.getMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get storage usage for user
  Future<Map<String, dynamic>> getUserStorageUsage(String userId) async {
    try {
      final photos = await getUserFiles(userId: userId, fileType: 'photos');
      final documents = await getUserFiles(userId: userId, fileType: 'documents');
      
      int totalSize = 0;
      int photoSize = 0;
      int documentSize = 0;
      
      for (final file in photos) {
        final size = file['size'] as int? ?? 0;
        totalSize += size;
        photoSize += size;
      }
      
      for (final file in documents) {
        final size = file['size'] as int? ?? 0;
        totalSize += size;
        documentSize += size;
      }
      
      return {
        'totalSize': totalSize,
        'photoSize': photoSize,
        'documentSize': documentSize,
        'photoCount': photos.length,
        'documentCount': documents.length,
        'totalFiles': photos.length + documents.length,
      };
    } catch (e) {
      debugPrint('❌ Failed to get storage usage: $e');
      return {
        'totalSize': 0,
        'photoSize': 0,
        'documentSize': 0,
        'photoCount': 0,
        'documentCount': 0,
        'totalFiles': 0,
      };
    }
  }

  /// Upload photo (convenience method for profile photos)
  Future<String> uploadPhoto(
    String userId,
    String filePath,
    Uint8List fileBytes,
    String mimeType,
  ) async {
    try {
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'users/$userId/photos/$fileName';
      
      final result = await uploadFile(
        filePath: filePath,
        storagePath: storagePath,
        metadata: {
          'user_id': userId,
          'type': 'profile_photo',
          'contentType': mimeType,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );
      
      return result['downloadUrl'] as String;
    } catch (e) {
      debugPrint('❌ Failed to upload photo: $e');
      rethrow;
    }
  }

  /// Delete photo (convenience method for profile photos)
  Future<void> deletePhoto(String photoUrl, {required String userId}) async {
    try {
      // Extract file path from URL
      final ref = _storage.refFromURL(photoUrl);
      await ref.delete();
      
      debugPrint('✅ Photo deleted successfully: $photoUrl');
    } catch (e) {
      debugPrint('❌ Failed to delete photo: $e');
      rethrow;
    }
  }
}
