import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';

class PrivacyEnforcementService {
  final FirebaseFirestore _db;

  PrivacyEnforcementService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static bool readBoolFromDoc(Map<String, dynamic>? doc, String key, {bool fallback = false}) {
    if (doc == null) return fallback;
    if (doc[key] is bool) return doc[key] as bool;
    final nested = doc['profile'];
    if (nested is Map<String, dynamic> && nested[key] is bool) {
      return nested[key] as bool;
    }
    return fallback;
  }

  static bool isPremiumOnlyVisibility(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_premium_only_visibility');

  static bool isVerifiedOnlyVisibility(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_only_verified_users');

  static bool hideFromSearch(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_hide_from_search');

  static bool hideContactDetails(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_hide_contact_details');

  static bool blurPhotosForStrangers(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_blur_photos_for_strangers');

  static bool hidePhotosUntilAccepted(Map<String, dynamic>? doc) =>
      readBoolFromDoc(doc, 'privacy_photo_visible_after_acceptance');

  /// Photo hidden from others (privacy settings "Photo hidden" / [UserProfile.isPhotoPrivate]).
  static bool isPhotoHiddenFromOthers(
    Map<String, dynamic>? doc, {
    bool? fromParsedProfile,
  }) {
    if (fromParsedProfile ?? false) return true;
    return readBoolFromDoc(doc, 'is_photo_private') ||
        readBoolFromDoc(doc, 'isPhotoPrivate') ||
        readBoolFromDoc(doc, 'photo_private');
  }

  /// Same as [isPhotoHiddenFromOthers] using a parsed [UserProfile] + optional doc.
  static bool isPhotoHiddenForProfile({
    required UserProfile? profile,
    Map<String, dynamic>? userDoc,
  }) {
    return isPhotoHiddenFromOthers(
      userDoc,
      fromParsedProfile: profile?.isPhotoPrivate ?? false,
    );
  }

  bool canViewerSeeProfile({
    required User viewer,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    if (viewer.id == candidate.id) return true;
    if (hideFromSearch(candidateDoc)) return false;
    if (isPremiumOnlyVisibility(candidateDoc) && !viewer.membership.isPremium) return false;
    if (isVerifiedOnlyVisibility(candidateDoc) && !viewer.isVerified) return false;
    return true;
  }

  bool canShowContactDetails({
    required User viewer,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    if (!canViewerSeeProfile(viewer: viewer, candidate: candidate, candidateDoc: candidateDoc)) {
      return false;
    }
    if (hideContactDetails(candidateDoc)) return false;
    return true;
  }

  bool canShowPhotoInDiscover({
    required User viewer,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    if (!canViewerSeeProfile(viewer: viewer, candidate: candidate, candidateDoc: candidateDoc)) {
      return false;
    }
    // Discover is a stranger surface. Respect photo privacy for all viewers.
    if (isPhotoHiddenFromOthers(
      candidateDoc,
      fromParsedProfile: candidate.profileForDiscovery.isPhotoPrivate ?? false,
    )) {
      return false;
    }
    if (hidePhotosUntilAccepted(candidateDoc)) return false;
    if (blurPhotosForStrangers(candidateDoc)) return false;
    return true;
  }

  /// Whether Premium Discover / 3D carousel may attach a real photo URL.
  ///
  /// Uses the same rules as [canShowPhotoInDiscover] so hidden/blurred photos
  /// are not leaked to premium viewers on the carousel.
  bool canIncludePhotoUrlInPremiumDiscoverCarousel({
    required User viewer,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
  }) {
    return canShowPhotoInDiscover(
      viewer: viewer,
      candidate: candidate,
      candidateDoc: candidateDoc,
    );
  }

  Future<bool> canShowPhotoInProfileDetail({
    required User viewer,
    required User candidate,
    required Map<String, dynamic>? candidateDoc,
    required bool isAlreadyAccepted,
    required bool hasPrivatePhotoApproval,
  }) async {
    if (!canViewerSeeProfile(viewer: viewer, candidate: candidate, candidateDoc: candidateDoc)) {
      return false;
    }

    final isPrivatePhoto = isPhotoHiddenFromOthers(
      candidateDoc,
      fromParsedProfile: candidate.profile?.isPhotoPrivate ?? false,
    );
    if (isPrivatePhoto && !hasPrivatePhotoApproval) return false;

    if (hidePhotosUntilAccepted(candidateDoc) && !isAlreadyAccepted) {
      return false;
    }
    if (blurPhotosForStrangers(candidateDoc) && !isAlreadyAccepted) {
      return false;
    }
    return true;
  }

  Future<bool> hasAcceptedInterestBetween({
    required String viewerUserId,
    required String candidateUserId,
  }) async {
    final first = await _db
        .collection('interests')
        .where('from_user_id', isEqualTo: viewerUserId)
        .where('to_user_id', isEqualTo: candidateUserId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (first.docs.isNotEmpty) return true;

    final second = await _db
        .collection('interests')
        .where('from_user_id', isEqualTo: candidateUserId)
        .where('to_user_id', isEqualTo: viewerUserId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    return second.docs.isNotEmpty;
  }
}
