
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/backend/storage_service.dart';
import '../../core/contract.dart';

/// Verification Service
/// 
/// Consolidates verification operations from:
/// - profile_document_submission_service.dart
/// - verification_service.dart
class VerificationService {
  static final VerificationService _instance = VerificationService._internal();
  factory VerificationService() => _instance;
  VerificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storage = StorageService();

  bool _isInitialized = false;

  /// Initialize verification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _storage.initialize();
      _isInitialized = true;
      debugPrint('✅ VerificationService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ VerificationService initialization failed: $e');
      rethrow;
    }
  }

  /// Submit verification document
  Future<Map<String, dynamic>> submitVerificationDocument({
    required String userId,
    required String documentType,
    required String filePath,
    Map<String, String>? additionalData,
  }) async {
    try {
      await _ensureInitialized();
      
      // Validate document type
      if (!_isValidDocumentType(documentType)) {
        return {
          'success': false,
          'message': 'Invalid document type: $documentType',
        };
      }

      // Upload document
      final uploadResult = await _storage.uploadDocument(
        userId: userId,
        documentType: documentType,
        filePath: filePath,
        additionalMetadata: {
          // 🔥 FIX: Use snake_case field names
          'user_id': userId,
          'document_type': documentType,
          'status': 'pending',
          'submitted_at': DateTime.now().toIso8601String(),
          ...?additionalData,
        },
      );

      if (uploadResult['success'] != true) {
        return uploadResult;
      }

      // Create verification record
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final verificationData = {
        'user_id': userId,
        'document_type': documentType,
        'document_url': uploadResult['downloadUrl'],
        'storage_path': uploadResult['fullPath'],
        'status': 'pending',
        'submitted_at': FieldValue.serverTimestamp(),
        'submitted_by': _auth.currentUser?.uid,
        ...?additionalData,
      };

      await _db.collection('profile_verifications').add(verificationData);

      // Update user verification status
      await _updateUserVerificationStatus(userId, documentType, 'pending');

      debugPrint('✅ Verification document submitted: $documentType for user: $userId');
      
      return {
        'success': true,
        'message': 'Document submitted successfully',
        'documentUrl': uploadResult['downloadUrl'],
        'verificationId': verificationData['verificationId'],
      };
    } catch (e) {
      debugPrint('❌ Failed to submit verification document: $e');
      return {'success': false, 'message': 'Failed to submit document: $e'};
    }
  }

  /// Submit identity verification
  Future<Map<String, dynamic>> submitIdentityVerification({
    required String userId,
    required String idCardPath,
    required String selfiePath,
    Map<String, String>? additionalData,
  }) async {
    try {
      await _ensureInitialized();
      
      // Upload ID card
      final idCardResult = await _storage.uploadDocument(
        userId: userId,
        documentType: 'id_card',
        filePath: idCardPath,
        additionalMetadata: {
          // 🔥 FIX: Use snake_case field names
          'user_id': userId,
          'document_type': 'id_card',
          'status': 'pending',
          'submitted_at': DateTime.now().toIso8601String(),
          ...?additionalData,
        },
      );

      if (idCardResult['success'] != true) {
        return idCardResult;
      }

      // Upload selfie
      final selfieResult = await _storage.uploadDocument(
        userId: userId,
        documentType: 'selfie',
        filePath: selfiePath,
        additionalMetadata: {
          // 🔥 FIX: Use snake_case field names
          'user_id': userId,
          'document_type': 'selfie',
          'status': 'pending',
          'submitted_at': DateTime.now().toIso8601String(),
          ...?additionalData,
        },
      );

      if (selfieResult['success'] != true) {
        return selfieResult;
      }

      // Create verification record
      // 🔥 FIX: Use snake_case field names matching Firestore rules
      final verificationData = {
        'user_id': userId,
        'verification_type': 'identity',
        'documents': [
          {
            'type': 'id_card',
            'url': idCardResult['downloadUrl'],
            'path': idCardResult['fullPath'],
          },
          {
            'type': 'selfie',
            'url': selfieResult['downloadUrl'],
            'path': selfieResult['fullPath'],
          },
        ],
        'status': 'pending',
        'submitted_at': FieldValue.serverTimestamp(),
        'submitted_by': _auth.currentUser?.uid,
        ...?additionalData,
      };

      await _db.collection('profile_verifications').add(verificationData);

      // Update user verification status
      await _updateUserVerificationStatus(userId, 'identity', 'pending');

      debugPrint('✅ Identity verification submitted for user: $userId');
      
      return {
        'success': true,
        'message': 'Identity verification submitted successfully',
        'documents': verificationData['documents'],
      };
    } catch (e) {
      debugPrint('❌ Failed to submit identity verification: $e');
      return {'success': false, 'message': 'Failed to submit identity verification: $e'};
    }
  }

  /// Get verification status
  Future<Map<String, dynamic>> getVerificationStatus(String userId) async {
    try {
      // 🔥 FIX: Use snake_case field names in queries and reads
      final snapshot = await _db
          .collection('profile_verifications')
          .where('user_id', isEqualTo: userId)
          .orderBy('submitted_at', descending: true)
          .limit(10)
          .get();

      final verifications = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          // 🔥 FIX: Read with fallback for both conventions
          'verificationType': data['verification_type'] ?? data['verificationType'] ?? data['document_type'] ?? data['documentType'],
          'status': data['status'],
          'submittedAt': data['submitted_at'] ?? data['submittedAt'],
          'reviewedAt': data['reviewed_at'] ?? data['reviewedAt'],
          'reviewedBy': data['reviewed_by'] ?? data['reviewedBy'],
          'rejectionReason': data['rejection_reason'] ?? data['rejectionReason'],
          'documents': data['documents'] ?? [],
        };
      }).toList();

      debugPrint('✅ Verification status retrieved for user: $userId');
      
      return {
        'success': true,
        'verifications': verifications,
        'message': 'Verification status retrieved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to get verification status: $e');
      return {'success': false, 'message': 'Failed to get verification status: $e'};
    }
  }

  /// Approve verification
  Future<Map<String, dynamic>> approveVerification({
    required String verificationId,
    required String reviewedBy,
    String? notes,
  }) async {
    try {
      final verificationRef = _db.collection('profile_verifications').doc(verificationId);
      final verificationDoc = await verificationRef.get();

      if (!verificationDoc.exists) {
        return {'success': false, 'message': 'Verification not found'};
      }

      final verificationData = verificationDoc.data()!;
      // 🔥 FIX: Read with fallback for both conventions
      final userId = (verificationData['user_id'] ?? verificationData['user_id']) as String;
      final verificationType = verificationData['verification_type'] ?? verificationData['verificationType'] ?? verificationData['document_type'] ?? verificationData['documentType'];

      // Update verification status
      // 🔥 FIX: Use snake_case field names
      await verificationRef.update({
        'status': 'approved',
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': reviewedBy,
        'notes': notes,
      });

      // Update user verification status
      await _updateUserVerificationStatus(userId, verificationType, 'approved');

      debugPrint('✅ Verification approved: $verificationId');
      
      return {
        'success': true,
        'message': 'Verification approved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to approve verification: $e');
      return {'success': false, 'message': 'Failed to approve verification: $e'};
    }
  }

  /// Reject verification
  Future<Map<String, dynamic>> rejectVerification({
    required String verificationId,
    required String reviewedBy,
    required String rejectionReason,
    String? notes,
  }) async {
    try {
      final verificationRef = _db.collection('profile_verifications').doc(verificationId);
      final verificationDoc = await verificationRef.get();

      if (!verificationDoc.exists) {
        return {'success': false, 'message': 'Verification not found'};
      }

      final verificationData = verificationDoc.data()!;
      // 🔥 FIX: Read with fallback for both conventions
      final userId = (verificationData['user_id'] ?? verificationData['user_id']) as String;
      final verificationType = verificationData['verification_type'] ?? verificationData['verificationType'] ?? verificationData['document_type'] ?? verificationData['documentType'];

      // Update verification status
      // 🔥 FIX: Use snake_case field names
      await verificationRef.update({
        'status': 'rejected',
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': reviewedBy,
        'rejection_reason': rejectionReason,
        'notes': notes,
      });

      // Update user verification status
      await _updateUserVerificationStatus(userId, verificationType, 'rejected');

      debugPrint('✅ Verification rejected: $verificationId');
      
      return {
        'success': true,
        'message': 'Verification rejected successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to reject verification: $e');
      return {'success': false, 'message': 'Failed to reject verification: $e'};
    }
  }

  /// Get pending verifications (for admin)
  Future<Map<String, dynamic>> getPendingVerifications({int limit = 50}) async {
    try {
      final snapshot = await _db
          .collection('profile_verifications')
          .where('status', isEqualTo: 'pending')
          .orderBy('submitted_at', descending: true)
          .limit(limit)
          .get();

      final verifications = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'user_id': data['user_id'],
          'verification_type': data['verification_type'] ?? data['document_type'],
          'document_type': data['document_type'],
          'submitted_at': data['submitted_at'],
          'documents': data['documents'] ?? [],
          'document_url': data['document_url'],
        };
      }).toList();

      debugPrint('✅ Pending verifications retrieved: ${verifications.length}');
      
      return {
        'success': true,
        'verifications': verifications,
        'message': 'Pending verifications retrieved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to get pending verifications: $e');
      return {'success': false, 'message': 'Failed to get pending verifications: $e'};
    }
  }

  /// Get user verification summary
  Future<Map<String, dynamic>> getUserVerificationSummary(String userId) async {
    try {
      final userDoc = await _db.collection(Collections.users).doc(userId).get();
      if (!userDoc.exists) {
        return {'success': false, 'message': 'User not found'};
      }

      final userData = userDoc.data()!;
      
      return {
        'success': true,
        'verificationStatus': userData['verification_status'] ?? {},
        'isVerified': userData['is_verified'] ?? false,
        'verificationLevel': userData['verification_level'] ?? 'none',
        'message': 'Verification summary retrieved successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to get user verification summary: $e');
      return {'success': false, 'message': 'Failed to get verification summary: $e'};
    }
  }

  /// Update user verification status
  Future<void> _updateUserVerificationStatus(String userId, String verificationType, String status) async {
    try {
      final userRef = _db.collection(Collections.users).doc(userId);
      final userDoc = await userRef.get();

      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final verificationStatus = Map<String, dynamic>.from(userData['verification_status'] ?? {});
      
      verificationStatus[verificationType] = {
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Determine overall verification level
      String verificationLevel = 'none';
      bool isFullyVerified = false;

      if (verificationStatus['identity']?['status'] == 'approved') {
        verificationLevel = 'identity';
      }

      if (verificationStatus['address']?['status'] == 'approved') {
        verificationLevel = 'address';
      }

      if (verificationStatus['income']?['status'] == 'approved') {
        verificationLevel = 'income';
      }

      // Check if all required verifications are approved
      final requiredVerifications = ['identity', 'address'];
      isFullyVerified = requiredVerifications.every(
        (type) => verificationStatus[type]?['status'] == 'approved',
      );

      await userRef.update({
        'verification_status': verificationStatus,
        'verification_level': verificationLevel,
        'is_verified': isFullyVerified,
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ User verification status updated: $userId -> $verificationType: $status');
    } catch (e) {
      debugPrint('❌ Failed to update user verification status: $e');
    }
  }

  /// Validate document type
  bool _isValidDocumentType(String documentType) {
    final validTypes = [
      'id_card',
      'passport',
      'driving_license',
      'voter_id',
      'pan_card',
      'aadhaar_card',
      'address_proof',
      'income_proof',
      'education_certificate',
      'birth_certificate',
      'selfie',
    ];

    return validTypes.contains(documentType);
  }

  /// Delete verification document
  Future<Map<String, dynamic>> deleteVerificationDocument({
    required String verificationId,
    required String userId,
  }) async {
    try {
      final verificationRef = _db.collection('profile_verifications').doc(verificationId);
      final verificationDoc = await verificationRef.get();

      if (!verificationDoc.exists) {
        return {'success': false, 'message': 'Verification not found'};
      }

      final verificationData = verificationDoc.data()!;
      final storagePath = verificationData['storagePath'] as String?;

      // Delete from storage if path exists
      if (storagePath != null) {
        await _storage.deleteFile(storagePath);
      }

      // Delete verification record
      await verificationRef.delete();

      debugPrint('✅ Verification document deleted: $verificationId');
      
      return {
        'success': true,
        'message': 'Verification document deleted successfully',
      };
    } catch (e) {
      debugPrint('❌ Failed to delete verification document: $e');
      return {'success': false, 'message': 'Failed to delete verification document: $e'};
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
