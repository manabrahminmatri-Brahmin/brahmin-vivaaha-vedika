import 'dart:math';

import '../models/user.dart';

/// FNV-1a 32-bit hash for stable integer seeds from strings.
int fnv1a32(String s) {
  const p = 0x01000193;
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * p) & 0x7fffffff;
  }
  return h == 0 ? 0x9e3779b9 : h;
}

/// Per-viewer, per-day, per-surface seed so feeds feel fresh daily without
/// jumping on every rebuild (common matrimonial-app pattern).
int discoveryFeedSeed({String? viewerUserId, required String salt}) {
  final day = DateTime.now().toUtc().toIso8601String().split('T').first;
  return fnv1a32('${viewerUserId ?? 'guest'}|$day|$salt');
}

List<T> shuffleSeeded<T>(List<T> items, int seed) {
  if (items.length <= 1) return List<T>.from(items);
  final rng = Random(seed);
  final out = List<T>.from(items);
  for (var i = out.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

List<User> shuffleUsersForDiscovery(
  List<User> users, {
  String? viewerUserId,
  required String salt,
}) {
  if (users.isEmpty) return const [];
  return shuffleSeeded(
    users,
    discoveryFeedSeed(viewerUserId: viewerUserId, salt: salt),
  );
}
