// Single place to tune profile completion rules for discovery and app access.
//
// All discovery list UIs must use [isEligibleForDiscovery] only — no duplicate
// completion / firstName / profile==null gates at call sites.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gender.dart';
import '../models/user.dart';

import 'contract.dart';

abstract final class ProfileCompletionPolicy {
  static const int completeThresholdPercent = 80;
  static const int minCompletionPercentForDiscovery = 80;
  static const int minCompletionPercentForFullApp = 80;

  /// Meaningful row heuristic: enough signals that the member is real even when
  /// completion % was never backfilled (legacy docs).
  static bool hasMeaningfulProfileData(User user) {
    if (user.isDeleted) return false;
    final p = user.profile;
    int hits = 0;
    void hit(bool ok) {
      if (ok) hits++;
    }

    hit((p?.firstName ?? user.firstName).trim().isNotEmpty);
    hit((p?.lastName ?? user.lastName).trim().isNotEmpty);
    hit((p?.occupation ?? '').trim().isNotEmpty);
    hit((p?.education ?? '').trim().isNotEmpty);
    hit((p?.city ?? '').trim().isNotEmpty || (p?.state ?? '').trim().isNotEmpty);
    hit((p?.profilePicture ?? '').trim().isNotEmpty);
    hit((p?.aboutMe ?? '').trim().isNotEmpty);
    hit(user.profileId.trim().isNotEmpty);
    hit(user.mobileNumber.trim().isNotEmpty);

    return hits >= 3;
  }

  /// Stored / computed completion, with legacy fallback for undervalued rows.
  ///
  /// If **stored** % is &gt; 0, it is authoritative (matches Firestore backfills and
  /// admin overrides) — no heuristic bump above it.
  ///
  /// If stored is 0, use **computed** when &gt; 0; if that is still below the
  /// discovery threshold, apply completion **flags** and [hasMeaningfulProfileData]
  /// so legacy rows are not hidden solely because `computedCompletionPercentage`
  /// undervalues them.
  ///
  /// When both stored and computed are 0, flags and meaningful data can still
  /// yield the discovery threshold.
  static int effectiveCompletionPercent(User user) {
    final stored = user.profileCompletionPercentage;
    final computed = user.profile?.computedCompletionPercentage ?? 0;

    if (stored > 0) {
      return stored.clamp(0, 100);
    }
    if (computed > 0) {
      final c = computed.clamp(0, 100);
      if (c >= minCompletionPercentForDiscovery) {
        return c;
      }
      if (user.isProfileComplete ||
          (user.profile?.isProfileComplete ?? false)) {
        return minCompletionPercentForDiscovery;
      }
      if (hasMeaningfulProfileData(user)) {
        return minCompletionPercentForDiscovery;
      }
      return c;
    }
    if (user.isProfileComplete ||
        (user.profile?.isProfileComplete ?? false)) {
      return minCompletionPercentForDiscovery;
    }
    if (hasMeaningfulProfileData(user)) {
      return minCompletionPercentForDiscovery;
    }
    return 0;
  }

  /// Single gate for Home, Matches, Recently Added, recommendations, Firestore helpers.
  /// Staff / admin accounts (`User.isAdmin`) are never discoverable.
  static bool isEligibleForDiscovery(User user) {
    if (user.isDeleted) {
      logDiscoveryExclude(user, 'deleted');
      return false;
    }
    if (user.isAdmin) {
      logDiscoveryExclude(user, 'admin');
      return false;
    }
    final eff = effectiveCompletionPercent(user);
    if (eff >= minCompletionPercentForDiscovery) return true;
    logDiscoveryExclude(user, 'completion', extra: 'effective=$eff');
    return false;
  }

  /// Debug: why a user was excluded (debug builds only).
  static void logDiscoveryExclude(
    User user,
    String reason, {
    String? extra,
  }) {
    if (!kDebugMode) return;
    final p = user.profile;
    final rawG = p?.gender;
    debugPrint(
      'DISCOVERY EXCLUDE user=${user.id} profile=${user.profileId} '
      'reason=$reason stored=${user.profileCompletionPercentage} '
      'computed=${p?.computedCompletionPercentage ?? 'n/a'} '
      'effective=${effectiveCompletionPercent(user)} profileNull=${p == null} '
      'gender=$rawG ${extra ?? ''}',
    );
  }

  /// Gender mismatch logging (client-side sanity checks).
  static void logDiscoveryGenderExclude(
    User user, {
    required String rawLabel,
    required Gender myGender,
    required String targetGenderCanonical,
  }) {
    if (!kDebugMode) return;
    final theirs = user.profile?.gender;
    debugPrint(
      'DISCOVERY EXCLUDE user=${user.id} profile=${user.profileId} reason=gender '
      'raw=$rawLabel normalized=${theirs?.genderName ?? 'unknown'} '
      'target=$targetGenderCanonical my=${myGender.genderName}',
    );
  }

  static bool meetsFullAppAccessThreshold({
    required int storedPercent,
    required bool isProfileCompleteFlag,
  }) {
    return storedPercent >= minCompletionPercentForFullApp || isProfileCompleteFlag;
  }

  static Future<bool> isProfileDoneForUserDoc(String userDocId) async {
    if (userDocId.isEmpty) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(userDocId)
          .get()
          .timeout(const Duration(seconds: 6));
      if (!doc.exists) return false;
      final d = doc.data()!;
      final pct = (d['profile_completion_percentage'] as num?)?.toInt() ?? 0;
      final flag = d['is_profile_complete'] == true;
      return meetsFullAppAccessThreshold(
        storedPercent: pct,
        isProfileCompleteFlag: flag,
      );
    } catch (e, st) {
      debugPrint(
        '⚠️ isProfileDoneForUserDoc($userDocId): $e — fail-open (avoid wizard loop)\n$st',
      );
      return true;
    }
  }
}
