import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';
import 'profile_deletion_service.dart';

/// Filters profile view rows so incognito / deleted viewers are not exposed.
abstract final class ProfileViewsPrivacy {
  ProfileViewsPrivacy._();

  static bool shouldHideViewerRow(Map<String, dynamic> row) {
    if (row['viewer_incognito'] == true || row['viewer_hidden'] == true) {
      return true;
    }
    return false;
  }

  static String viewerIdFromRow(Map<String, dynamic> row) {
    return (row['viewer_user_id'] ??
            row['viewer_id'] ??
            row['from_user_id'] ??
            row['from_user'] ??
            row['user_id'] ??
            '')
        .toString()
        .trim();
  }

  static bool _userDataIsActive(Map<String, dynamic>? data) {
    return !ProfileDeletionService.isUserHiddenFromEngagement(data);
  }

  /// Resolves which raw viewer ids from [profile_views] still belong to active users.
  static Future<Set<String>> resolveActiveViewerIds(Set<String> rawIds) async {
    final active = <String>{};
    final pending =
        rawIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (pending.isEmpty) return active;

    final db = FirebaseFirestore.instance;
    final pendingList = pending.toList();

    for (var i = 0; i < pendingList.length; i += 30) {
      final end = i + 30 > pendingList.length ? pendingList.length : i + 30;
      final chunk = pendingList.sublist(i, end);
      try {
        final snap = await db
            .collection(Collections.users)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          if (!_userDataIsActive(d.data())) continue;
          final docId = d.id;
          final profileId =
              (d.data()[Fields.profileId] ?? '').toString().trim();
          final authUid = (d.data()[Fields.authUid] ?? '').toString().trim();
          for (final raw in chunk) {
            if (raw == docId || raw == profileId || raw == authUid) {
              active.add(raw);
            }
          }
        }
      } catch (e) {
        debugPrint('ProfileViewsPrivacy.resolveActiveViewerIds batch: $e');
      }
    }

    final stillPending = pending.where((id) => !active.contains(id)).toList();
    for (final raw in stillPending) {
      try {
        var snap = await db
            .collection(Collections.users)
            .where(Fields.profileId, isEqualTo: raw)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty && _userDataIsActive(snap.docs.first.data())) {
          active.add(raw);
          continue;
        }
        snap = await db
            .collection(Collections.users)
            .where(Fields.authUid, isEqualTo: raw)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty && _userDataIsActive(snap.docs.first.data())) {
          active.add(raw);
        }
      } catch (e) {
        debugPrint('ProfileViewsPrivacy.resolveActiveViewerIds lookup: $e');
      }
    }

    return active;
  }

  static Future<bool> viewerIsIncognito(
    String viewerUserId, {
    Map<String, bool>? cache,
  }) async {
    final id = viewerUserId.trim();
    if (id.isEmpty) return false;
    final c = cache ?? <String, bool>{};
    if (c.containsKey(id)) return c[id]!;

    try {
      final snap = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(id)
          .get();
      final data = snap.data();
      final incognito = data?['privacy_incognito'] == true;
      c[id] = incognito;
      return incognito;
    } catch (_) {
      c[id] = false;
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> filterVisibleViewers(
    List<Map<String, dynamic>> rows,
  ) async {
    final cache = <String, bool>{};
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (shouldHideViewerRow(row)) continue;
      final viewerId = viewerIdFromRow(row);
      if (viewerId.isNotEmpty &&
          await viewerIsIncognito(viewerId, cache: cache)) {
        continue;
      }
      out.add(row);
    }
    return out;
  }

  /// Drops viewers whose account was deleted; optionally removes orphan view docs.
  static Future<List<Map<String, dynamic>>> filterActiveViewerProfiles(
    List<Map<String, dynamic>> rows, {
    bool pruneOrphanDocuments = false,
  }) async {
    if (rows.isEmpty) return rows;

    final viewerIds = <String>{};
    for (final row in rows) {
      final id = viewerIdFromRow(row);
      if (id.isNotEmpty) viewerIds.add(id);
    }
    if (viewerIds.isEmpty) return const [];

    final active = await resolveActiveViewerIds(viewerIds);
    final db = FirebaseFirestore.instance;
    final out = <Map<String, dynamic>>[];

    for (final row in rows) {
      final viewerId = viewerIdFromRow(row);
      if (viewerId.isEmpty || !active.contains(viewerId)) {
        if (pruneOrphanDocuments) {
          final docId = (row['id'] ?? '').toString().trim();
          if (docId.isNotEmpty) {
            db
                .collection(Collections.profileViews)
                .doc(docId)
                .delete()
                .catchError(
                  (e) => debugPrint(
                    'ProfileViewsPrivacy: prune orphan view $docId: $e',
                  ),
                );
          }
        }
        continue;
      }
      out.add(row);
    }
    return out;
  }
}
