import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/contract.dart';
import '../services/profile_views_privacy.dart';

/// Owns **`profile_views`** query wiring for activity hub UIs (counts, etc.).
///
/// Keeps screens off direct [FirebaseFirestore.instance] for these reads.
class ActivityFeedRepository {
  static final ActivityFeedRepository _instance = ActivityFeedRepository._();
  factory ActivityFeedRepository() => _instance;
  ActivityFeedRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Rows where the signed-in user is the viewer ("Profiles I Viewed" style).
  Stream<int> watchProfileViewsCountAsViewer(String viewerUserId) {
    final id = viewerUserId.trim();
    if (id.isEmpty) return Stream.value(0);
    return _db
        .collection(Collections.profileViews)
        .where('viewer_user_id', isEqualTo: id)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Rows where [viewedProfileId] matches **`viewed_profile_id`** (views on your profile).
  Stream<int> watchProfileViewsCountForViewedProfile(String viewedProfileId) {
    final id = viewedProfileId.trim();
    if (id.isEmpty) return Stream.value(0);
    return _db
        .collection(Collections.profileViews)
        .where('viewed_profile_id', isEqualTo: id)
        .snapshots()
        .asyncMap((s) async => _countActiveUniqueViewers(s.docs));
  }

  Future<int> _countActiveUniqueViewers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final latestByViewer = <String, Map<String, dynamic>>{};
    for (final d in docs) {
      final row = <String, dynamic>{'id': d.id, ...d.data()};
      if (ProfileViewsPrivacy.shouldHideViewerRow(row)) continue;
      final viewerId = ProfileViewsPrivacy.viewerIdFromRow(row);
      if (viewerId.isEmpty) continue;
      latestByViewer[viewerId] = row;
    }
    final active = await ProfileViewsPrivacy.filterActiveViewerProfiles(
      latestByViewer.values.toList(),
      pruneOrphanDocuments: false,
    );
    return active.length;
  }
}
