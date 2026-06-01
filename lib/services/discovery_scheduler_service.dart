import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

enum DiscoveryTimeSlot {
  slot00to03,
  slot04to07,
  slot08to11,
  slot12to15,
  slot16to19,
  slot20to23,
}

class DiscoverySchedulerService {
  static const int defaultBatchSize = 8; // premium curated feel: 5..10
  static const Duration manualRefreshCooldown = Duration(minutes: 20);

  DiscoveryTimeSlot currentSlot(DateTime now) {
    final h = now.hour;
    if (h < 4) return DiscoveryTimeSlot.slot00to03;
    if (h < 8) return DiscoveryTimeSlot.slot04to07;
    if (h < 12) return DiscoveryTimeSlot.slot08to11;
    if (h < 16) return DiscoveryTimeSlot.slot12to15;
    if (h < 20) return DiscoveryTimeSlot.slot16to19;
    return DiscoveryTimeSlot.slot20to23;
  }

  String slotKey(DateTime now) {
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final s = switch (currentSlot(now)) {
      DiscoveryTimeSlot.slot00to03 => '00_03',
      DiscoveryTimeSlot.slot04to07 => '04_07',
      DiscoveryTimeSlot.slot08to11 => '08_11',
      DiscoveryTimeSlot.slot12to15 => '12_15',
      DiscoveryTimeSlot.slot16to19 => '16_19',
      DiscoveryTimeSlot.slot20to23 => '20_23',
    };
    return '$d-$s';
  }

  Future<bool> canManualRefresh(String userId) async {
    if (userId.isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_refreshTsKey(userId));
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last) >= manualRefreshCooldown;
  }

  Future<void> markManualRefresh(String userId) async {
    if (userId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_refreshTsKey(userId), DateTime.now().toIso8601String());
  }

  Future<Set<String>> getServedIdsForSlot(String userId, DateTime now) async {
    if (userId.isEmpty) return {};
    final p = await SharedPreferences.getInstance();
    final key = _servedKey(userId, slotKey(now));
    return p.getStringList(key)?.toSet() ?? {};
  }

  Future<void> markServed(String userId, DateTime now, Iterable<String> ids) async {
    if (userId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final key = _servedKey(userId, slotKey(now));
    final curr = p.getStringList(key)?.toSet() ?? {};
    curr.addAll(ids.where((e) => e.isNotEmpty));
    await p.setStringList(key, curr.toList());
  }

  Future<List<User>> curateForSession({
    required String userId,
    required List<User> rankedUsers,
    int batchSize = defaultBatchSize,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final served = await getServedIdsForSlot(userId, ts);
    final target = batchSize.clamp(5, 10);

    final fresh = rankedUsers.where((u) => !served.contains(u.id)).toList();
    final diversified = _diversify(fresh);
    return diversified.take(target).toList();
  }

  List<User> _diversify(List<User> users) {
    // Lightweight diversity by city/occupation buckets while preserving quality order.
    final citySeen = <String>{};
    final occSeen = <String>{};
    final curated = <User>[];
    final deferred = <User>[];

    for (final u in users) {
      final city = (u.profile?.city ?? '').trim().toLowerCase();
      final occ = (u.profile?.occupation ?? '').trim().toLowerCase();
      final cityNew = city.isNotEmpty && !citySeen.contains(city);
      final occNew = occ.isNotEmpty && !occSeen.contains(occ);
      if (cityNew || occNew || curated.length < 3) {
        curated.add(u);
        if (city.isNotEmpty) citySeen.add(city);
        if (occ.isNotEmpty) occSeen.add(occ);
      } else {
        deferred.add(u);
      }
    }
    curated.addAll(deferred);
    return curated;
  }

  String _servedKey(String userId, String slot) => 'discover_served_${userId}_$slot';
  String _refreshTsKey(String userId) => 'discover_manual_refresh_$userId';
}
