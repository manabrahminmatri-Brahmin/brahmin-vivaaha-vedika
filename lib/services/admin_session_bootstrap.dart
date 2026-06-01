import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/contract.dart';

/// Writes Firestore admin session docs keyed by Firebase Auth UID so
/// [isElevatedAdmin] rules pass (app user doc id ≠ auth uid).
abstract final class AdminSessionBootstrap {
  AdminSessionBootstrap._();

  static Future<void> ensureAccess({required String userDocId}) async {
    final docId = userDocId.trim();
    final fbUid = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    if (docId.isEmpty || fbUid.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    try {
      await db.collection(Collections.adminAuthLinks).doc(fbUid).set({
        'user_doc_id': docId,
        'auth_uid': fbUid,
        'is_admin': true,
        'updated_at': now,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ admin_auth_links write failed (non-fatal): $e');
    }

    try {
      await db.collection('admin_sessions').doc(fbUid).set({
        'is_admin': true,
        'uid': fbUid,
        'user_doc_id': docId,
        'updated_at': now,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ admin_sessions write failed (non-fatal): $e');
    }
  }
}
