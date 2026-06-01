import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';

/// Ensures Firestore `users/{docId}.auth_uid` matches Firebase Auth before
/// privacy callables or owner-only profile writes (photo/birth/community).
abstract final class PrivacyRequestAuthSync {
  PrivacyRequestAuthSync._();

  static Future<void> syncAuthUidForUserDoc(String userDocId) async {
    final docId = userDocId.trim();
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (docId.isEmpty || authUid.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection(Collections.users).doc(docId).set(
        {
          'auth_uid': authUid,
          'auth_uid_synced_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('✅ PrivacyRequestAuthSync: auth_uid synced for $docId');
    } catch (e) {
      debugPrint('⚠️ PrivacyRequestAuthSync: auth_uid sync failed for $docId: $e');
    }
  }
}
