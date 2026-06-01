import '../models/user.dart';

class MatchRankingSignals {
  final double compatibility; // 0..1
  final double activityFreshness; // 0..1
  final double popularity; // 0..1
  final double reciprocalInterestProbability; // 0..1

  const MatchRankingSignals({
    required this.compatibility,
    required this.activityFreshness,
    required this.popularity,
    required this.reciprocalInterestProbability,
  });
}

class MatchRankingService {
  static const double _wCompatibility = 0.40;
  static const double _wActivityFreshness = 0.20;
  static const double _wPopularity = 0.20;
  static const double _wReciprocal = 0.20;

  double calculateScore(MatchRankingSignals s) {
    return (s.compatibility * _wCompatibility) +
        (s.activityFreshness * _wActivityFreshness) +
        (s.popularity * _wPopularity) +
        (s.reciprocalInterestProbability * _wReciprocal);
  }

  MatchRankingSignals buildSignals({
    required User me,
    required User candidate,
  }) {
    final compatibility = _compatibility(me, candidate);
    final activityFreshness = _activityFreshness(candidate);
    final popularity = _popularity(candidate);
    final reciprocal = _reciprocalInterestProbability(me, candidate);
    return MatchRankingSignals(
      compatibility: compatibility,
      activityFreshness: activityFreshness,
      popularity: popularity,
      reciprocalInterestProbability: reciprocal,
    );
  }

  double _compatibility(User me, User candidate) {
    final cp = candidate.profile;
    final mp = me.profile;
    if (cp == null || mp == null) return 0.35;

    final scores = <double>[
      _agePreferenceScore(me, candidate),
      _locationScore(mp, cp),
      _stringMatch(mp.sect, cp.sect),
      _stringMatch(mp.subSect, cp.subSect),
      _softCategoryMatch(mp.education, cp.education),
      _softCategoryMatch(mp.occupation, cp.occupation),
      _maritalPreferenceScore(me, candidate),
      _lifestyleScore(mp, cp),
    ];
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  double _agePreferenceScore(User me, User candidate) {
    final prefMin = me.profile?.partnerAgeMin;
    final prefMax = me.profile?.partnerAgeMax;
    if (prefMin == null && prefMax == null) return 0.6;
    final age = candidate.age;
    if (prefMin != null && age < prefMin) return 0.15;
    if (prefMax != null && age > prefMax) return 0.15;
    return 1.0;
  }

  double _locationScore(UserProfile me, UserProfile candidate) {
    final c1 = me.city?.trim().toLowerCase();
    final c2 = candidate.city?.trim().toLowerCase();
    if ((c1 ?? '').isNotEmpty && c1 == c2) return 1.0;
    final s1 = me.state?.trim().toLowerCase();
    final s2 = candidate.state?.trim().toLowerCase();
    if ((s1 ?? '').isNotEmpty && s1 == s2) return 0.8;
    final k1 = me.country?.trim().toLowerCase();
    final k2 = candidate.country?.trim().toLowerCase();
    if ((k1 ?? '').isNotEmpty && k1 == k2) return 0.55;
    return 0.3;
  }

  double _maritalPreferenceScore(User me, User candidate) {
    final prefs = me.profile?.partnerMaritalStatus ?? const <String>[];
    if (prefs.isEmpty) return 0.65;
    final m = (candidate.profile?.maritalStatus ?? '').trim().toLowerCase();
    if (m.isEmpty) return 0.4;
    final normalized = prefs.map((e) => e.trim().toLowerCase()).toSet();
    return normalized.contains(m) ? 1.0 : 0.2;
  }

  double _lifestyleScore(UserProfile me, UserProfile candidate) {
    final parts = <double>[
      _stringMatch(me.foodHabit, candidate.foodHabit),
      _stringMatch(me.smokingHabit, candidate.smokingHabit),
      _stringMatch(me.drinkingHabit, candidate.drinkingHabit),
      _listOverlap(me.interests, candidate.interests),
    ];
    return parts.reduce((a, b) => a + b) / parts.length;
  }

  double _activityFreshness(User user) {
    final now = DateTime.now();
    final activityTs = user.lastActive ?? user.lastLoginAt;
    final profileTs = user.profileUpdatedAt;
    final photoTs = user.profile?.photoLastUpdated;

    double online = user.isOnline ? 1.0 : 0.0;
    double active = _recentDecay(now, activityTs, maxHours: 72);
    double profile = _recentDecay(now, profileTs, maxHours: 24 * 14);
    double photo = _recentDecay(now, photoTs, maxHours: 24 * 30);
    return ((online * 0.35) + (active * 0.35) + (profile * 0.2) + (photo * 0.1))
        .clamp(0.0, 1.0);
  }

  double _popularity(User user) {
    final data = user.toLocalCacheJson();
    final views = _extractNum(data, const ['profile_view_count', 'profile_views_count', 'views_count']);
    final likes = _extractNum(data, const ['likes_received_count', 'interests_received_count', 'received_likes_count']);
    final accepted = _extractNum(data, const ['accepted_interests_count', 'interests_accepted_count']);
    final totalReceived = likes > 0 ? likes : _extractNum(data, const ['interests_total_received']);
    final acceptanceRatio = totalReceived > 0 ? (accepted / totalReceived) : 0.5;

    final viewsScore = (views / 150).clamp(0.0, 1.0);
    final likesScore = (likes / 80).clamp(0.0, 1.0);
    final accScore = acceptanceRatio.clamp(0.0, 1.0);
    return ((viewsScore * 0.4) + (likesScore * 0.35) + (accScore * 0.25)).clamp(0.0, 1.0);
  }

  double _reciprocalInterestProbability(User me, User candidate) {
    final mp = me.profile;
    final cp = candidate.profile;
    if (mp == null || cp == null) return 0.45;

    final prefAgeMin = cp.partnerAgeMin;
    final prefAgeMax = cp.partnerAgeMax;
    final myAgeFits = ((prefAgeMin == null || me.age >= prefAgeMin) &&
        (prefAgeMax == null || me.age <= prefAgeMax))
        ? 1.0
        : 0.2;

    final sharedPrefs = <double>[
      _listOverlap(cp.partnerEducation, [mp.education ?? '']),
      _listOverlap(cp.partnerOccupation, [mp.occupation ?? '']),
      _listOverlap(cp.partnerLocations, [mp.city ?? '', mp.state ?? '']),
      _stringMatch(cp.partnerIncomeMin, mp.incomeRange),
    ];
    final sharedScore =
        sharedPrefs.reduce((a, b) => a + b) / sharedPrefs.length;

    final mutualSignals = _listOverlap(mp.interests, cp.interests);
    return ((myAgeFits * 0.45) + (sharedScore * 0.35) + (mutualSignals * 0.2))
        .clamp(0.0, 1.0);
  }

  double _recentDecay(DateTime now, DateTime? when, {required int maxHours}) {
    if (when == null) return 0.15;
    final diff = now.difference(when).inHours;
    if (diff <= 0) return 1.0;
    if (diff >= maxHours) return 0.0;
    return (1 - (diff / maxHours)).clamp(0.0, 1.0);
  }

  double _stringMatch(String? a, String? b) {
    final x = (a ?? '').trim().toLowerCase();
    final y = (b ?? '').trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return 0.5;
    if (x == y) return 1.0;
    if (x.contains(y) || y.contains(x)) return 0.75;
    return 0.2;
  }

  double _softCategoryMatch(String? a, String? b) {
    final s = _stringMatch(a, b);
    return s >= 0.75 ? s : 0.35;
  }

  double _listOverlap(List<String>? a, List<String>? b) {
    final left = (a ?? const <String>[])
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final right = (b ?? const <String>[])
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (left.isEmpty || right.isEmpty) return 0.45;
    final inter = left.intersection(right).length;
    final union = left.union(right).length;
    if (union == 0) return 0.45;
    return (inter / union).clamp(0.0, 1.0);
  }

  double _extractNum(Map<String, dynamic> source, List<String> keys) {
    for (final k in keys) {
      final v = source[k];
      if (v is num) return v.toDouble();
    }
    return 0.0;
  }
}
