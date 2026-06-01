import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/backend/storage_service.dart';
import '../core/identity_service.dart';
import '../core/contract.dart';

/// Document submission result
class DocumentSubmissionResult {
  final bool success;
  final bool cancelled;
  final String? errorMessage;

  const DocumentSubmissionResult({
    required this.success,
    this.cancelled = false,
    this.errorMessage,
  });
}

/// Profile Document Submission Service
///
/// Handles document submission for profile verification including ID proof
class ProfileDocumentSubmissionService {
  static final ProfileDocumentSubmissionService _instance = ProfileDocumentSubmissionService._internal();
  factory ProfileDocumentSubmissionService() => _instance;
  ProfileDocumentSubmissionService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  /// Pick and submit ID proof document
  Future<DocumentSubmissionResult> pickAndSubmitIdProof(String userId) async {
    try {
      // Check permissions
      final storageStatus = await Permission.photos.request();
      if (!storageStatus.isGranted) {
        debugPrint('Photos permission denied');
        return const DocumentSubmissionResult(success: false, errorMessage: 'Photos permission denied');
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        debugPrint('No document selected');
        return const DocumentSubmissionResult(success: false, cancelled: true);
      }

      final imageFile = File(pickedFile.path);
      
      // Upload document to storage
      final result = await _storage.uploadDocument(
        userId: userId,
        documentType: 'id_proof',
        filePath: imageFile.path,
      );
      final documentUrl = result['downloadUrl'] as String?;

      if (documentUrl != null) {
        // Update user document with ID proof URL
        await _db.collection(Collections.users).doc(userId).update({
          'id_proof_url': documentUrl,
          'id_proof_submitted_at': FieldValue.serverTimestamp(),
          'id_proof_status': 'pending',
          'updated_at': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ ID proof submitted for user: $userId');
        return const DocumentSubmissionResult(success: true);
      }

      return const DocumentSubmissionResult(success: false, errorMessage: 'Failed to upload document');
    } catch (e) {
      debugPrint('❌ Failed to submit ID proof: $e');
      return DocumentSubmissionResult(success: false, errorMessage: e.toString());
    }
  }

  /// Pick and submit address proof document
  Future<bool> pickAndSubmitAddressProof(String userId) async {
    try {
      // Check permissions
      final storageStatus = await Permission.photos.request();
      if (!storageStatus.isGranted) {
        debugPrint('Photos permission denied');
        return false;
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        debugPrint('No document selected');
        return false;
      }

      final imageFile = File(pickedFile.path);
      
      // Upload document to storage
      final result = await _storage.uploadDocument(
        userId: userId,
        documentType: 'address_proof',
        filePath: imageFile.path,
      );
      final documentUrl = result['downloadUrl'] as String?;

      if (documentUrl != null) {
        // Update user document with address proof URL
        await _db.collection(Collections.users).doc(userId).update({
          'address_proof_url': documentUrl,
          'address_proof_submitted_at': FieldValue.serverTimestamp(),
          'address_proof_status': 'pending',
          'updated_at': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ Address proof submitted for user: $userId');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Failed to submit address proof: $e');
      return false;
    }
  }

  /// Get document submission status
  Future<Map<String, dynamic>> getDocumentStatus(String userId) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) {
        return {
          'id_proof_status': 'not_submitted',
          'address_proof_status': 'not_submitted',
          'id_proof_url': null,
          'address_proof_url': null,
        };
      }

      final data = doc.data()!;
      return {
        'id_proof_status': data['id_proof_status'] ?? 'not_submitted',
        'address_proof_status': data['address_proof_status'] ?? 'not_submitted',
        'id_proof_url': data['id_proof_url'],
        'address_proof_url': data['address_proof_url'],
        'id_proof_submitted_at': data['id_proof_submitted_at'],
        'address_proof_submitted_at': data['address_proof_submitted_at'],
      };
    } catch (e) {
      debugPrint('Failed to get document status: $e');
      return {
        'id_proof_status': 'error',
        'address_proof_status': 'error',
        'id_proof_url': null,
        'address_proof_url': null,
      };
    }
  }

  /// Delete submitted document
  Future<bool> deleteDocument(String userId, String documentType) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      final documentField = documentType == 'id_proof' ? 'id_proof_url' : 'address_proof_url';
      final documentUrl = data[documentField] as String?;

      if (documentUrl != null) {
        // Delete from storage
        await _storage.deleteFile(documentUrl);
        
        // Update user document
        await _db.collection(Collections.users).doc(userId).update({
          documentField: null,
          '${documentType}_status': 'not_submitted',
          '${documentType}_submitted_at': null,
          'updated_at': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ $documentType deleted for user: $userId');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Failed to delete $documentType: $e');
      return false;
    }
  }

  /// Check if user has submitted all required documents
  Future<bool> hasAllDocuments(String userId) async {
    try {
      final status = await getDocumentStatus(userId);
      return status['id_proof_status'] == 'approved' && 
             status['address_proof_status'] == 'approved';
    } catch (e) {
      debugPrint('Failed to check document status: $e');
      return false;
    }
  }

  /// Update document verification status (admin only)
  Future<bool> updateDocumentStatus(String userId, String documentType, String status) async {
    try {
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final adminUserId = await identityService.getUserId();
      
      final userDoc = await _db.collection(Collections.users).doc(adminUserId).get();
      if (!userDoc.exists || !(userDoc.data()!['is_admin'] == true)) {
        debugPrint('User is not authorized to update document status');
        return false;
      }

      await _db.collection(Collections.users).doc(userId).update({
        '${documentType}_status': status,
        '${documentType}_verified_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ $documentType status updated to $status for user: $userId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to update $documentType status: $e');
      return false;
    }
  }
}
