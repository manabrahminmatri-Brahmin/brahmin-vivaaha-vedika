import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import '../core/interest_identity_resolver.dart';
import '../core/firestore_repository.dart';

/// Client-side repair for interest docs missing peer snapshot fields.
abstract final class LegacyInterestRepairService {
  LegacyInterestRepairService._();

  static bool needsSnapshotRepair(Map<String, dynamic> row) {
    final normalized = InterestIdentityResolver.normalizeInterestRow(row);
    final hasFrom = _hasSenderSnapshot(normalized);
    final hasTo = _hasTargetSnapshot(normalized);
    return !hasFrom || !hasTo;
  }

  static bool _hasSenderSnapshot(Map<String, dynamic> row) {
    return InterestIdentityResolver.peerFirstName(row, isReceived: true).isNotEmpty ||
        InterestIdentityResolver.peerProfileId(row, isReceived: true).isNotEmpty;
  }

  static bool _hasTargetSnapshot(Map<String, dynamic> row) {
    return InterestIdentityResolver.peerFirstName(row, isReceived: false).isNotEmpty ||
        InterestIdentityResolver.peerProfileId(row, isReceived: false).isNotEmpty;
  }

  /// Builds Firestore patch fields from live profile maps (does not touch status).
  static Map<String, dynamic> patchFromProfiles({
    required Map<String, dynamic> row,
    required Map<String, Map<String, dynamic>> profilesByUserId,
  }) {
    final normalized = InterestIdentityResolver.normalizeInterestRow(row);
    final fromId = (normalized[Fields.fromUserId] as String? ?? '').trim();
    final toId = (normalized[Fields.toUserId] as String? ?? '').trim();
    final patch = <String, dynamic>{};
    if (fromId.isNotEmpty) {
      patch.addAll(_senderFields(profilesByUserId[fromId] ?? const {}));
    }
    if (toId.isNotEmpty) {
      patch.addAll(_targetFields(profilesByUserId[toId] ?? const {}));
    }
    return patch;
  }

  /// Merges patch into an in-memory interest row for UI.
  static Map<String, dynamic> mergeIntoRow(
    Map<String, dynamic> row,
    Map<String, dynamic> patch,
  ) {
    if (patch.isEmpty) return row;
    return {...row, ...patch};
  }

  /// Best-effort background persist (non-blocking).
  static void schedulePersist({
    required String interestDocId,
    required Map<String, dynamic> patch,
  }) {
    if (interestDocId.trim().isEmpty || patch.isEmpty) return;
    // ignore: discarded_futures
    _persist(interestDocId: interestDocId, patch: patch);
  }

  static Future<void> _persist({
    required String interestDocId,
    required Map<String, dynamic> patch,
  }) async {
    try {
      await FirestoreRepository.updateDocument(
        Collections.interests,
        interestDocId,
        patch,
      );
      debugPrint('✅ LegacyInterestRepair: patched $interestDocId');
    } catch (e) {
      debugPrint('⚠️ LegacyInterestRepair persist skipped: $e');
    }
  }

  static Map<String, dynamic> _senderFields(Map<String, dynamic> profile) {
    if (profile.isEmpty) return const {};
    final firstName = (profile[Fields.firstName] as String? ?? '').trim();
    final lastName = (profile[Fields.lastName] as String? ?? '').trim();
    final profileId = (profile[Fields.profileId] as String? ?? '').trim();
    final photoUrl = (profile[Fields.photoUrl] as String? ?? '').trim();
    final city = (profile['city'] as String? ?? '').trim();
    final state = (profile['state'] as String? ?? '').trim();
    final age = profile[Fields.age] as int?;
    return {
      if (firstName.isNotEmpty) 'from_first_name': firstName,
      if (lastName.isNotEmpty) 'from_last_name': lastName,
      if (profileId.isNotEmpty) 'from_profile_id': profileId,
      if (photoUrl.isNotEmpty) 'from_photo_url': photoUrl,
      if (city.isNotEmpty) 'from_city': city,
      if (state.isNotEmpty) 'from_state': state,
      if (age != null && age > 0) 'from_age': age,
    };
  }

  static Map<String, dynamic> _targetFields(Map<String, dynamic> profile) {
    if (profile.isEmpty) return const {};
    final firstName = (profile[Fields.firstName] as String? ?? '').trim();
    final lastName = (profile[Fields.lastName] as String? ?? '').trim();
    final profileId = (profile[Fields.profileId] as String? ?? '').trim();
    final photoUrl = (profile[Fields.photoUrl] as String? ?? '').trim();
    final city = (profile['city'] as String? ?? '').trim();
    final state = (profile['state'] as String? ?? '').trim();
    final age = profile[Fields.age] as int?;
    return {
      if (firstName.isNotEmpty) 'to_first_name': firstName,
      if (lastName.isNotEmpty) 'to_last_name': lastName,
      if (profileId.isNotEmpty) 'to_profile_id': profileId,
      if (photoUrl.isNotEmpty) 'to_photo_url': photoUrl,
      if (city.isNotEmpty) 'to_city': city,
      if (state.isNotEmpty) 'to_state': state,
      if (age != null && age > 0) 'to_age': age,
    };
  }

  /// One-shot repair for up to [limit] docs owned by [userDocId] (admin/debug).
  static Future<int> repairInterestsForUser({
    required String userDocId,
    int limit = 25,
  }) async {
    final db = FirebaseFirestore.instance;
    final sent = await db
        .collection(Collections.interests)
        .where(Fields.fromUserId, isEqualTo: userDocId)
        .limit(limit)
        .get();
    final received = await db
        .collection(Collections.interests)
        .where(Fields.toUserId, isEqualTo: userDocId)
        .limit(limit)
        .get();

    final docs = <String, Map<String, dynamic>>{};
    for (final d in [...sent.docs, ...received.docs]) {
      docs[d.id] = {'id': d.id, ...d.data()};
    }

    var repaired = 0;
    for (final entry in docs.entries) {
      final row = entry.value;
      if (!needsSnapshotRepair(row)) continue;
      final fromId = (row[Fields.fromUserId] as String? ?? '').trim();
      final toId = (row[Fields.toUserId] as String? ?? '').trim();
      final ids = <String>{fromId, toId}..removeWhere((e) => e.isEmpty);
      final profiles = <String, Map<String, dynamic>>{};
      for (final id in ids) {
        final snap = await db.collection(Collections.users).doc(id).get();
        if (snap.exists) profiles[id] = snap.data() ?? {};
      }
      final patch = patchFromProfiles(row: row, profilesByUserId: profiles);
      if (patch.isEmpty) continue;
      await _persist(interestDocId: entry.key, patch: patch);
      repaired++;
    }
    return repaired;
  }
}
