import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:shared_preferences/shared_preferences.dart';

import 'contract.dart';

/// Firebase UID used as **participant** in `interests`, `birth_requests`,
/// `community_reference_requests`, etc.
///
/// Likes use the Firestore profile doc id (`LikeService`) and keep working
/// after prefs restore. Those collections instead key rows by the member's
/// real Firebase Auth UID. After [restoreSessionFromPrefs] the live session
/// may be **anonymous** while `users/{prefsDoc}.auth_uid` still holds the real
/// UID — this helper returns the real UID for queries so lists match server
/// data (see also `anonymous_bridge_uid` in Firestore rules).
Future<String> sessionQueryAuthUid() async {
  final user = fb.FirebaseAuth.instance.currentUser;
  if (user == null) return '';
  if (!user.isAnonymous) return user.uid;

  final prefs = await SharedPreferences.getInstance();
  final docId = (prefs.getString('current_user_id') ?? '').trim();
  if (docId.isEmpty) return user.uid;
  try {
    final snap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(docId)
        .get()
        .timeout(const Duration(seconds: 6));
    final stored = (snap.data()?['auth_uid'] as String? ?? '').trim();
    if (stored.isNotEmpty) return stored;
  } catch (_) {}
  return user.uid;
}
