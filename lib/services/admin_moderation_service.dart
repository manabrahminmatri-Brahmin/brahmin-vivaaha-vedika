import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'admin_service.dart';

/// Admin moderation: reports, suspensions, audit logs, verification queue.
class AdminModerationService {
  AdminModerationService._();
  static final AdminModerationService instance = AdminModerationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> watchOpenReports({int limit = 100}) {
    return _db
        .collection('reports')
        .limit(limit)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> watchSecurityAuditLogs({int limit = 80}) {
    return _db
        .collection('security_audit_logs')
        .limit(limit)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList(),
        );
  }

  Future<void> submitFakeProfileReport({
    required String reporterUserId,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    if (reporterUserId.isEmpty || reportedUserId.isEmpty) {
      throw ArgumentError('reporter and reported user ids required');
    }
    await _db.collection('reports').add({
      'reporter_id': reporterUserId,
      'reported_user_id': reportedUserId,
      'type': 'fake_profile',
      'reason': reason,
      'details': (details ?? '').trim(),
      'status': 'open',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> suspendUser(String userDocId, String reason) async {
    await AdminService.instance.suspendUser(userDocId, reason);
  }

  Future<void> markReportReviewed({
    required String reportId,
    required String resolution,
  }) async {
    await _db.collection('reports').doc(reportId).set(
      {
        'status': 'reviewed',
        'resolution': resolution,
        'reviewed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> queuePhotoModeration({
    required String userDocId,
    required String photoUrl,
    String? note,
  }) async {
    await _db.collection('moderation_queue').add({
      'type': 'photo',
      'user_id': userDocId,
      'photo_url': photoUrl,
      'note': (note ?? '').trim(),
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
    debugPrint('AdminModerationService: photo queued for $userDocId');
  }
}
