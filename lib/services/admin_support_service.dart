import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/contract.dart';
import 'matrimony_gateway_service.dart';

/// In-app support desk: one Firestore thread per member (`support_threads/{userDocId}`).
abstract final class AdminSupportService {
  AdminSupportService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> watchAdminInbox() {
    return _db
        .collection(Collections.supportThreads)
        .orderBy('updated_at', descending: true)
        .limit(200)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['thread_id'] = d.id;
            return data;
          }).toList(),
        );
  }

  static Stream<List<Map<String, dynamic>>> watchMessages(String threadId) {
    return _db
        .collection(Collections.supportThreads)
        .doc(threadId)
        .collection('messages')
        .orderBy('created_at')
        .limit(500)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['id'] = d.id;
            return data;
          }).toList(),
        );
  }

  static Future<String?> ensureUserThread({String? requesterId}) async {
    final res = await MatrimonyGatewayService.ensureSupportThread(
      requesterId: requesterId,
    );
    if (res['success'] == true) {
      return (res['threadId'] as String?)?.trim();
    }
    return null;
  }

  static Future<bool> sendMessage({
    required String threadId,
    required String body,
    bool asAdmin = false,
    String? requesterId,
  }) async {
    final res = await MatrimonyGatewayService.sendSupportMessage(
      threadId: threadId,
      body: body,
      asAdmin: asAdmin,
      requesterId: requesterId,
    );
    return res['success'] == true;
  }

  static Future<void> markRead({
    required String threadId,
    required bool asAdmin,
    String? requesterId,
  }) async {
    await MatrimonyGatewayService.markSupportThreadRead(
      threadId: threadId,
      asAdmin: asAdmin,
      requesterId: requesterId,
    );
  }
}
