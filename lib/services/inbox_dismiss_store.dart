import 'package:shared_preferences/shared_preferences.dart';

/// Persists inbox row keys the user removed (Interests → Messages tab).
/// Covers: (1) mutual "conversation" rows — not stored in `messages` / `photo_requests`;
/// (2) rows whose Firestore soft-delete failed or has not synced yet.
class InboxDismissStore {
  InboxDismissStore._();

  static String _key(String userId) => 'inbox_dismissed_row_keys_$userId';

  static Future<Set<String>> load(String userId) async {
    if (userId.isEmpty) return {};
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_key(userId))?.toSet() ?? {};
  }

  static Future<void> addAll(String userId, Iterable<String> keys) async {
    if (userId.isEmpty) return;
    final list = keys.where((k) => k.isNotEmpty).toList();
    if (list.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final cur = p.getStringList(_key(userId))?.toSet() ?? {};
    cur.addAll(list);
    await p.setStringList(_key(userId), cur.toList());
  }
}
