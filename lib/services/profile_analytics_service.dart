import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../core/contract.dart';

class ProfileViewer {
  final String userId;
  final String name;
  final String? profileId;
  final String? city;
  final String? photoUrl;
  final DateTime viewedAt;

  const ProfileViewer({
    required this.userId,
    required this.name,
    required this.viewedAt,
    this.profileId,
    this.city,
    this.photoUrl,
  });
}

class ProfileAnalyticsSummary {
  final int totalViews;
  final int weeklyViews;
  final double popularityScore; // 0..100
  final double acceptancePercent; // 0..100
  final double rankingPercentile; // 0..100
  final List<ProfileViewer> whoViewedMe;
  /// People whose profiles you opened (deduped, most recent view per person).
  final List<ProfileViewer> profilesIViewedRecently;

  const ProfileAnalyticsSummary({
    required this.totalViews,
    required this.weeklyViews,
    required this.popularityScore,
    required this.acceptancePercent,
    required this.rankingPercentile,
    required this.whoViewedMe,
    this.profilesIViewedRecently = const [],
  });
}

class ProfileAnalyticsService {
  final FirebaseFirestore _db;
  final AuthService _authService;

  ProfileAnalyticsService({
    FirebaseFirestore? firestore,
    required AuthService authService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _authService = authService;

  Future<ProfileAnalyticsSummary> loadAnalytics() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      return const ProfileAnalyticsSummary(
        totalViews: 0,
        weeklyViews: 0,
        popularityScore: 0,
        acceptancePercent: 0,
        rankingPercentile: 0,
        whoViewedMe: <ProfileViewer>[],
        profilesIViewedRecently: <ProfileViewer>[],
      );
    }
    final userId = currentUser.id;
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));

    final profileViewsSnap = await _db
        .collection('profile_views')
        .where('viewed_profile_id', isEqualTo: userId)
        .limit(500)
        .get();

    final allViewRows = profileViewsSnap.docs
        .map((d) => d.data())
        .toList();
    final totalViews = allViewRows.length;
    final weeklyViews = allViewRows.where((row) {
      final ts = row['viewed_at'];
      if (ts is Timestamp) return ts.toDate().isAfter(oneWeekAgo);
      return false;
    }).length;

    final whoViewed = await _loadWhoViewedMe(allViewRows);
    var profilesIViewed = const <ProfileViewer>[];
    try {
      final myViewingSnap = await _db
          .collection('profile_views')
          .where('viewer_user_id', isEqualTo: userId)
          .orderBy('viewed_at', descending: true)
          .limit(200)
          .get();
      profilesIViewed = await _loadProfilesIVewed(
        myViewingSnap.docs.map((d) => d.data()).toList(),
      );
    } catch (e) {
      debugPrint('ProfileAnalytics: profiles I viewed query skipped: $e');
    }
    final acceptancePercent = await _loadInterestAcceptance(userId: userId);
    final popularityScore = _popularityScore(
      totalViews: totalViews,
      weeklyViews: weeklyViews,
      acceptancePercent: acceptancePercent,
    );
    final rankingPercentile = await _rankingPercentile(
      me: currentUser,
      myScore: popularityScore,
      totalViews: totalViews,
    );

    return ProfileAnalyticsSummary(
      totalViews: totalViews,
      weeklyViews: weeklyViews,
      popularityScore: popularityScore,
      acceptancePercent: acceptancePercent,
      rankingPercentile: rankingPercentile,
      whoViewedMe: whoViewed,
      profilesIViewedRecently: profilesIViewed,
    );
  }

  Future<List<ProfileViewer>> _loadWhoViewedMe(List<Map<String, dynamic>> rows) async {
    final latestByViewer = <String, DateTime>{};
    for (final row in rows) {
      final viewerId = (row['viewer_user_id'] as String? ?? '').trim();
      final ts = row['viewed_at'];
      final viewedAt = ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      if (viewerId.isEmpty) continue;
      final current = latestByViewer[viewerId];
      if (current == null || viewedAt.isAfter(current)) {
        latestByViewer[viewerId] = viewedAt;
      }
    }

    final ids = latestByViewer.keys.toList();
    if (ids.isEmpty) return const <ProfileViewer>[];

    final usersById = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final snap = await _db
          .collection(Collections.users)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        usersById[doc.id] = doc.data();
      }
    }

    final viewers = <ProfileViewer>[];
    for (final id in ids) {
      final data = usersById[id];
      final first = (data?['first_name'] as String?) ??
          (data?['profile']?['first_name'] as String?) ??
          '';
      final last = (data?['last_name'] as String?) ??
          (data?['profile']?['last_name'] as String?) ??
          '';
      final name = '$first $last'.trim();
      viewers.add(ProfileViewer(
        userId: id,
        name: name.isEmpty ? 'Member' : name,
        profileId: data?['profile_id'] as String?,
        city: (data?['city'] as String?) ?? (data?['profile']?['city'] as String?),
        photoUrl: (data?['profile_picture'] as String?) ??
            (data?['profilePicture'] as String?) ??
            (data?['profile']?['profile_picture'] as String?),
        viewedAt: latestByViewer[id]!,
      ));
    }

    viewers.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return viewers.take(30).toList();
  }

  Future<List<ProfileViewer>> _loadProfilesIVewed(
    List<Map<String, dynamic>> rows,
  ) async {
    final latestByPeer = <String, DateTime>{};
    for (final row in rows) {
      final peer = ((row['viewed_profile_id'] ??
                  row['viewed_user_id'] ??
                  row['viewedUserId']) as String?)
              ?.trim() ??
          '';
      if (peer.isEmpty) continue;
      if (latestByPeer.containsKey(peer)) continue;
      final ts = row['viewed_at'];
      final viewedAt = ts is Timestamp
          ? ts.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      latestByPeer[peer] = viewedAt;
    }

    final ids = latestByPeer.keys.toList();
    if (ids.isEmpty) return const <ProfileViewer>[];

    final usersById = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final snap = await _db
          .collection(Collections.users)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        usersById[doc.id] = doc.data();
      }
    }

    final viewers = <ProfileViewer>[];
    for (final id in ids) {
      final data = usersById[id];
      final first = (data?['first_name'] as String?) ??
          (data?['profile']?['first_name'] as String?) ??
          '';
      final last = (data?['last_name'] as String?) ??
          (data?['profile']?['last_name'] as String?) ??
          '';
      final name = '$first $last'.trim();
      viewers.add(ProfileViewer(
        userId: id,
        name: name.isEmpty ? 'Member' : name,
        profileId: data?['profile_id'] as String?,
        city: (data?['city'] as String?) ?? (data?['profile']?['city'] as String?),
        photoUrl: (data?['profile_picture'] as String?) ??
            (data?['profilePicture'] as String?) ??
            (data?['profile']?['profile_picture'] as String?),
        viewedAt: latestByPeer[id]!,
      ));
    }

    viewers.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return viewers.take(40).toList();
  }

  Future<double> _loadInterestAcceptance({required String userId}) async {
    final snap = await _db
        .collection('interests')
        .where('to_user_id', isEqualTo: userId)
        .limit(500)
        .get();
    if (snap.docs.isEmpty) return 0;

    int accepted = 0;
    int decided = 0;
    for (final d in snap.docs) {
      final s = (d.data()['status'] as String? ?? '').trim().toLowerCase();
      if (s == 'accepted') {
        accepted++;
        decided++;
      } else if (s == 'rejected') {
        decided++;
      }
    }
    if (decided == 0) return 0;
    return ((accepted / decided) * 100).clamp(0, 100);
  }

  double _popularityScore({
    required int totalViews,
    required int weeklyViews,
    required double acceptancePercent,
  }) {
    final viewsComponent = (totalViews / 300).clamp(0.0, 1.0) * 45;
    final weeklyComponent = (weeklyViews / 80).clamp(0.0, 1.0) * 30;
    final acceptComponent = (acceptancePercent / 100).clamp(0.0, 1.0) * 25;
    return (viewsComponent + weeklyComponent + acceptComponent).clamp(0, 100);
  }

  Future<double> _rankingPercentile({
    required User me,
    required double myScore,
    required int totalViews,
  }) async {
    final snap = await _db
        .collection(Collections.users)
        .where('is_deleted', isEqualTo: false)
        .limit(200)
        .get();
    if (snap.docs.isEmpty) return 50;

    final peerScores = <double>[];
    for (final d in snap.docs) {
      if (d.id == me.id) continue;
      final data = d.data();
      final views = (data['profile_view_count'] as num?)?.toInt() ?? 0;
      final completion = (data['profile_completion_percentage'] as num?)?.toInt() ?? 0;
      final activeBoost = data['is_online'] == true ? 8.0 : 0.0;
      final score = ((views / 300).clamp(0.0, 1.0) * 70) +
          ((completion / 100).clamp(0.0, 1.0) * 30) +
          activeBoost;
      peerScores.add(score);
    }
    if (peerScores.isEmpty) return 50;

    final myComparable = ((totalViews / 300).clamp(0.0, 1.0) * 70) +
        (((me.profileCompletionPercentage) / 100).clamp(0.0, 1.0) * 30) +
        (me.isOnline ? 8.0 : 0.0);
    final effectiveMy = (myComparable + myScore) / 2;
    final lessThanMine = peerScores.where((s) => s <= effectiveMy).length;
    return ((lessThanMine / peerScores.length) * 100).clamp(0, 100);
  }
}
