import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import 'cloudinary_upload_service.dart';

/// Result from the marriage-fixed survey dialog.
class MarriageSurveyResult {
  final String matchSource;
  final String? photoLocalPath;
  final Uint8List? photoBytes;
  final String photoFileName;

  const MarriageSurveyResult({
    required this.matchSource,
    this.photoLocalPath,
    this.photoBytes,
    this.photoFileName = 'success.jpg',
  });

  bool get hasPhoto =>
      (photoLocalPath != null && photoLocalPath!.isNotEmpty) ||
      (photoBytes != null && photoBytes!.isNotEmpty);
}

/// Writes and reads public success stories (marriage on mana Vivaaha Vedika).
abstract final class SuccessStoryService {
  SuccessStoryService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? partnerProfileIdFromMatchSource(String matchSource) {
    final raw = matchSource.trim();
    if (!raw.toLowerCase().contains('vedika') &&
        !raw.toLowerCase().contains('mana')) {
      return null;
    }
    final colon = raw.indexOf(':');
    if (colon < 0) return null;
    final id = raw.substring(colon + 1).trim();
    return id.isEmpty ? null : id;
  }

  static bool isAppMatchSource(String matchSource) =>
      partnerProfileIdFromMatchSource(matchSource) != null;

  static String _displayName(Map<String, dynamic> data) {
    final profile = data['profile'];
    final profileMap =
        profile is Map ? Map<String, dynamic>.from(profile) : <String, dynamic>{};
    final first = (data['first_name'] ?? profileMap['first_name'] ?? '')
        .toString()
        .trim();
    final last =
        (data['last_name'] ?? profileMap['last_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return (data['profile_id'] ?? 'Member').toString().trim();
  }

  static String _gender(Map<String, dynamic> data) {
    final profile = data['profile'];
    final profileMap =
        profile is Map ? Map<String, dynamic>.from(profile) : <String, dynamic>{};
    return (data['gender'] ?? profileMap['gender'] ?? '').toString().toLowerCase();
  }

  /// Upload optional couple photo (Cloudinary) before profile deletion.
  static Future<String?> uploadSuccessPhoto({
    required String callerUserDocId,
    String? photoLocalPath,
    Uint8List? photoBytes,
    String photoFileName = 'success.jpg',
  }) async {
    try {
      if (photoLocalPath != null && photoLocalPath.isNotEmpty) {
        return await CloudinaryUploadService.uploadSuccessStoryPhoto(
          photoLocalPath,
          userDocId: callerUserDocId,
        );
      }
      if (photoBytes != null && photoBytes.isNotEmpty) {
        return await CloudinaryUploadService.uploadSuccessStoryPhotoBytes(
          photoBytes,
          userDocId: callerUserDocId,
          filename: photoFileName,
        );
      }
      return null;
    } catch (e) {
      debugPrint('SuccessStoryService.uploadSuccessPhoto: $e');
      return null;
    }
  }

  /// Record story **before** Cloud Function deletes user docs (rules + reliability).
  static Future<bool> recordAppMarriageIfNeeded({
    required String matchSource,
    required String callerUserDocId,
    String? imageUrl,
  }) async {
    final partnerProfileId = partnerProfileIdFromMatchSource(matchSource);
    if (partnerProfileId == null) return true;

    try {
      final callerSnap =
          await _db.collection(Collections.users).doc(callerUserDocId).get();
      if (!callerSnap.exists) {
        debugPrint('SuccessStoryService: caller doc missing');
        return false;
      }
      final callerData = callerSnap.data() ?? {};
      final callerProfileId =
          (callerData['profile_id'] ?? '').toString().trim();

      final partnerQuery = await _db
          .collection(Collections.users)
          .where('profile_id', isEqualTo: partnerProfileId)
          .limit(1)
          .get();
      if (partnerQuery.docs.isEmpty) {
        debugPrint('SuccessStoryService: partner profile_id not found');
        return false;
      }
      final partnerDoc = partnerQuery.docs.first;
      final partnerData = partnerDoc.data();

      final callerGender = _gender(callerData);
      final partnerGender = _gender(partnerData);
      final partnerPublicId =
          (partnerData['profile_id'] ?? partnerProfileId).toString().trim();

      var groomProfileId = callerProfileId.isNotEmpty
          ? callerProfileId
          : callerUserDocId;
      var brideProfileId =
          partnerPublicId.isNotEmpty ? partnerPublicId : partnerDoc.id;
      if (callerGender == 'female' && partnerGender != 'female') {
        groomProfileId =
            partnerPublicId.isNotEmpty ? partnerPublicId : partnerDoc.id;
        brideProfileId = callerProfileId.isNotEmpty
            ? callerProfileId
            : callerUserDocId;
      } else if (partnerGender == 'female' && callerGender != 'female') {
        groomProfileId = callerProfileId.isNotEmpty
            ? callerProfileId
            : callerUserDocId;
        brideProfileId =
            partnerPublicId.isNotEmpty ? partnerPublicId : partnerDoc.id;
      }

      final callerName = _displayName(callerData);
      final partnerName = _displayName(partnerData);
      final marriedAt = DateTime.now().toIso8601String();

      final storyData = <String, dynamic>{
        'user_id': callerUserDocId,
        'created_by_user_id': callerUserDocId,
        'partner_user_id': partnerDoc.id,
        'groom_profile_id': groomProfileId,
        'bride_profile_id': brideProfileId,
        'couple_names': '$callerName & $partnerName',
        'title': 'Matched on mana Vivaaha Vedika',
        'description':
            '$callerName and $partnerName tied the knot after connecting on mana Vivaaha Vedika.',
        'match_source': 'mana_Vivaaha Vedika',
        'married_at': marriedAt,
        'created_at': FieldValue.serverTimestamp(),
        'is_published': true,
      };
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        storyData['image_url'] = imageUrl.trim();
      }
      await _db.collection('success_stories').add(storyData);
      debugPrint('SuccessStoryService: marriage story recorded');
      return true;
    } catch (e) {
      debugPrint('SuccessStoryService.recordAppMarriageIfNeeded: $e');
      return false;
    }
  }

  /// Public list for Success Stories screen — always prefer server data.
  static Future<List<Map<String, dynamic>>> fetchPublishedStories({
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('success_stories')
        .where('is_published', isEqualTo: true)
        .orderBy('created_at', descending: true)
        .limit(limit);

    try {
      final snap = await query.get(
        const GetOptions(source: Source.server),
      );
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      // Missing composite index — fallback without is_published filter.
      debugPrint(
        'SuccessStoryService: index fallback (${e.message})',
      );
      final snap = await _db
          .collection('success_stories')
          .orderBy('created_at', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.server));
      return snap.docs
          .where((d) => d.data()['is_published'] != false)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    }
  }
}
