import 'dart:async';

import '../core/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/app_identity.dart';
import 'block_enforcement_policy.dart';
import 'matrimony_gateway_service.dart';
import 'product_funnel_analytics.dart';

/// Result of attempting to send a chat message (includes intro-quota enforcement).
enum ChatSendResult {
  success,
  notSignedIn,
  introQuotaUsed,
  failed,
}

class _IntroQuotaException implements Exception {}

/// 💬 CHAT SERVICE - ONLY CHAT LOGIC
/// Single responsibility: Handle all chat operations
class ChatService {
  final _db = FirebaseFirestore.instance;

  String get _senderDocId => IdentityProvider.userDocId.trim();
  String get _senderAuthUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  /// One introductory message per member per chat (billing-friendly). Uses a transaction.
  Future<ChatSendResult> sendMessage({
    required String chatId,
    required String message,
    required String messageType,
    String? recipientId,
    Map<String, dynamic>? data,
  }) async {
    final senderId = _senderDocId;
    if (senderId.isEmpty) return ChatSendResult.notSignedIn;

    final recipient = (recipientId ?? '').trim();
    if (recipient.isNotEmpty &&
        await BlockEnforcementPolicy.verifyBlockedForChat(
          actorUserDocId: senderId,
          peerUserDocId: recipient,
        )) {
      return ChatSendResult.failed;
    }

    final chatRef = _db.collection(AppConstants.chatsCollection).doc(chatId);

    try {
      await _db.runTransaction((txn) async {
        final chatSnap = await txn.get(chatRef);
        if (!chatSnap.exists) {
          throw StateError('Chat room missing');
        }
        final used = (chatSnap.data()?['intro_message_sent_by'] as List<dynamic>? ??
                const <dynamic>[])
            .map((e) => e.toString())
            .toSet();
        if (used.contains(senderId)) {
          throw _IntroQuotaException();
        }

        final msgRef = chatRef.collection('messages').doc();
        txn.set(msgRef, {
          'sender_id': senderId,
          'sender_auth_uid': _senderAuthUid,
          'recipient_id': recipientId,
          'message': message,
          'message_type': messageType,
          'is_read': false,
          'hidden_for': <String>[],
          'revoked_for_everyone': false,
          FirebaseConstants.timestampField: FieldValue.serverTimestamp(),
          if (data != null) ...data,
        });
        txn.update(chatRef, {
          'intro_message_sent_by': FieldValue.arrayUnion([senderId]),
          'lastMessage': message,
          FirebaseConstants.updatedField: FieldValue.serverTimestamp(),
        });
      });
      return ChatSendResult.success;
    } on _IntroQuotaException {
      return ChatSendResult.introQuotaUsed;
    } catch (e, st) {
      debugPrint('ChatService.sendMessage: $e\n$st');
      return ChatSendResult.failed;
    }
  }

  /// Idempotent: marks intro slot used for current user (e.g. legacy messages predating the flag).
  Future<void> ensureIntroQuotaRecorded(String chatId) async {
    final me = _senderDocId;
    if (me.isEmpty) return;
    await _db.collection(AppConstants.chatsCollection).doc(chatId).set({
      'intro_message_sent_by': FieldValue.arrayUnion([me]),
    }, SetOptions(merge: true));
  }

  /// Get chat messages stream
  Stream<List<Map<String, dynamic>>> getMessages(String chatId) {
    return _db
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection('messages')
        .orderBy(FirebaseConstants.timestampField, descending: true)
        .limit(AppConstants.maxChatsLoad)
        .snapshots()
        .map((snap) {
          final docId = _senderDocId;
          final authUid = _senderAuthUid;
          return snap.docs
              .map((doc) {
                final m = doc.data();
                return <String, dynamic>{'id': doc.id, ...m};
              })
              .where((m) => !_messageHiddenForViewer(m, docId, authUid))
              .toList();
        });
  }

  /// Backfill `participant_auth_uids` on legacy chat docs (required for list queries).
  Future<void> repairChatsForAcceptedInterests(
    Iterable<Map<String, dynamic>> interestRows,
  ) async {
    final me = _senderDocId;
    if (me.isEmpty) return;
    final seen = <String>{};
    for (final row in interestRows) {
      final status = (row['status'] as String? ?? '').toLowerCase();
      if (status != 'accepted' && status != 'granted') continue;
      final from = (row['from_user_id'] as String? ?? row['fromUserId'] as String? ?? '').trim();
      final to = (row['to_user_id'] as String? ?? row['toUserId'] as String? ?? '').trim();
      var other = '';
      if (from == me) {
        other = to;
      } else if (to == me) {
        other = from;
      }
      if (other.isEmpty || other == me || !seen.add(other)) continue;
      try {
        await MatrimonyGatewayService.createChatRoom(
          otherUserId: other,
          requesterId: me,
        );
      } catch (e) {
        debugPrint('ChatService.repairChatsForAcceptedInterests($other): $e');
      }
    }
  }

  /// Create or get chat room. Returns empty string if not signed in to Firebase Auth.
  Future<String> getOrCreateChatRoom(String otherUserId) async {
    final me = _senderDocId;
    if (me.isEmpty) return '';
    final other = otherUserId.trim();
    if (other.isEmpty) return '';

    if (await BlockEnforcementPolicy.verifyBlockedForChat(
      actorUserDocId: me,
      peerUserDocId: other,
    )) {
      return '';
    }

    final gateway = await MatrimonyGatewayService.createChatRoom(
      otherUserId: other,
      requesterId: me,
    );
    if (gateway['success'] == true) {
      final chatId = (gateway['chatId'] as String?)?.trim() ?? '';
      if (chatId.isNotEmpty) {
        unawaited(ProductFunnelAnalytics.chatCreate(peerUserId: other));
        return chatId;
      }
    }

    return '';
  }

  int _chatSortMillis(Map<String, dynamic> chat) {
    final ts = chat[FirebaseConstants.updatedField] ??
        chat['updatedAt'] ??
        chat['created_at'];
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    return 0;
  }

  List<Map<String, dynamic>> _sortChats(List<Map<String, dynamic>> chats) {
    final copy = List<Map<String, dynamic>>.from(chats);
    copy.sort((a, b) => _chatSortMillis(b).compareTo(_chatSortMillis(a)));
    return copy;
  }

  List<Map<String, dynamic>> _mergeChatLists(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in [...a, ...b]) {
      final id = (row['id'] as String? ?? '').trim();
      if (id.isEmpty) continue;
      merged[id] = row;
    }
    return _sortChats(merged.values.toList());
  }

  Stream<List<Map<String, dynamic>>> _chatsForAuthUid(String authUid) {
    return _db
        .collection(AppConstants.chatsCollection)
        .where('participant_auth_uids', arrayContains: authUid)
        .snapshots()
        .map((snap) => _mapChatDocs(snap))
        .handleError((Object e, StackTrace st) {
          debugPrint('ChatService._chatsForAuthUid($authUid): $e');
          return <Map<String, dynamic>>[];
        });
  }

  /// Get user's chat rooms (empty when no auth session).
  ///
  /// Firestore list rules require querying `participant_auth_uids` with the
  /// signed-in Firebase Auth UID (not profile doc id in `participants`).
  Stream<List<Map<String, dynamic>>> getUserChats() {
    final docId = _senderDocId;
    final authUid = _senderAuthUid;
    if (authUid.isEmpty) {
      return Stream.value(<Map<String, dynamic>>[]);
    }

    return _chatsForAuthUid(authUid).map(
      (rows) => _sortChats(_filterDeletedChats(rows, docId)),
    );
  }

  /// Update last message in chat
  Future<void> updateLastMessage(String chatId, String lastMessage) async {
    await _db.collection(AppConstants.chatsCollection).doc(chatId).update({
      'lastMessage': lastMessage,
      FirebaseConstants.updatedField: FieldValue.serverTimestamp(),
    });
  }

  /// Generate consistent chat ID from two user IDs
  String _generateChatId(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Unread incoming messages in one chat (for Messages tab badge).
  Future<int> countUnreadIncomingInChat(String chatId) async {
    final docId = _senderDocId;
    final authUid = _senderAuthUid;
    if (docId.isEmpty && authUid.isEmpty) return 0;

    const cap = 50;
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    if (docId.isNotEmpty) {
      queries.add(
        _db
            .collection(AppConstants.chatsCollection)
            .doc(chatId)
            .collection('messages')
            .where('recipient_id', isEqualTo: docId)
            .limit(cap)
            .get(),
      );
    }
    if (authUid.isNotEmpty && authUid != docId) {
      queries.add(
        _db
            .collection(AppConstants.chatsCollection)
            .doc(chatId)
            .collection('messages')
            .where('recipient_id', isEqualTo: authUid)
            .limit(cap)
            .get(),
      );
    }

    final snaps = await Future.wait(queries);
    final seenIds = <String>{};
    var unread = 0;
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        if (!seenIds.add(doc.id)) continue;
        if (doc.data()[FirebaseConstants.isReadField] == true) continue;
        unread++;
      }
    }
    return unread;
  }

  /// Live unread count across all chat rooms (Messages tab badge).
  Stream<int> watchUnreadIncomingChatCount() {
    return getUserChats().asyncMap((chats) async {
      if (chats.isEmpty) return 0;
      final counts = await Future.wait(
        chats.map((chat) {
          final id = (chat['id'] as String? ?? '').trim();
          if (id.isEmpty) return Future<int>.value(0);
          return countUnreadIncomingInChat(id);
        }),
      );
      return counts.fold<int>(0, (sum, n) => sum + n);
    });
  }

  /// Mark messages as read
  ///
  /// Does not use `where('is_read', isEqualTo: false)` because older docs may omit
  /// [is_read]; Firestore excludes missing fields from that query.
  Future<void> markMessagesAsRead(String chatId) async {
    final docId = _senderDocId;
    final authUid = _senderAuthUid;
    if (docId.isEmpty && authUid.isEmpty) return;

    const cap = 50;
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    if (docId.isNotEmpty) {
      queries.add(
        _db
            .collection(AppConstants.chatsCollection)
            .doc(chatId)
            .collection('messages')
            .where('recipient_id', isEqualTo: docId)
            .limit(cap)
            .get(),
      );
    }
    if (authUid.isNotEmpty && authUid != docId) {
      queries.add(
        _db
            .collection(AppConstants.chatsCollection)
            .doc(chatId)
            .collection('messages')
            .where('recipient_id', isEqualTo: authUid)
            .limit(cap)
            .get(),
      );
    }

    final snaps = await Future.wait(queries);
    final toMark = <DocumentReference<Map<String, dynamic>>>[];
    final seenIds = <String>{};
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        if (!seenIds.add(doc.id)) continue;
        final data = doc.data();
        if (data[FirebaseConstants.isReadField] == true) continue;
        toMark.add(doc.reference);
      }
    }
    if (toMark.isEmpty) return;

    var batch = _db.batch();
    var ops = 0;
    for (final ref in toMark) {
      batch.update(ref, {
        FirebaseConstants.isReadField: true,
        'read_at': FieldValue.serverTimestamp(),
      });
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
      await _db.collection(AppConstants.chatsCollection).doc(chatId).set({
        FirebaseConstants.updatedField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Hide a single message for the current user only (WhatsApp-style).
  Future<void> hideMessageForMe(String chatId, String messageId) async {
    final me = _senderDocId;
    if (me.isEmpty) return;
    await _db
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'hidden_for': FieldValue.arrayUnion([me]),
    }, SetOptions(merge: true));
  }

  /// Revoke message content for all participants (sender only, recent messages).
  Future<void> revokeMessageForEveryone(String chatId, String messageId) async {
    final me = _senderDocId;
    if (me.isEmpty) return;
    final ref = _db
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final sender = (data['sender_id'] as String? ?? '').trim();
    if (sender != me) {
      throw StateError('Only the sender can delete for everyone');
    }
    final ts = data[FirebaseConstants.timestampField];
    if (ts is! Timestamp) return;
    if (DateTime.now().difference(ts.toDate()) > const Duration(hours: 1)) {
      throw StateError('Delete for everyone is only available for recent messages');
    }
    await ref.update({
      'revoked_for_everyone': true,
      'message': '',
      'message_type': 'revoked',
    });
  }

  /// Delete chat only for current user (WhatsApp-style "Delete for me").
  Future<void> deleteChatForMe(String chatId) async {
    final me = _senderDocId;
    if (me.isEmpty) return;
    await _db.collection(AppConstants.chatsCollection).doc(chatId).set({
      'deleted_for': FieldValue.arrayUnion([me]),
      FirebaseConstants.updatedField: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Delete chat for everyone (WhatsApp-style "Delete for everyone").
  Future<void> deleteChatForEveryone(String chatId) async {
    final chatRef = _db.collection(AppConstants.chatsCollection).doc(chatId);
    while (true) {
      final msgSnap = await chatRef.collection('messages').limit(400).get();
      if (msgSnap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in msgSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await chatRef.delete();
  }

  // Backward-compat helper.
  Future<void> deleteChat(String chatId) => deleteChatForEveryone(chatId);

  List<Map<String, dynamic>> _mapChatDocs(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();
  }

  bool _messageHiddenForViewer(
    Map<String, dynamic> m,
    String docId,
    String authUid,
  ) {
    final hidden = (m['hidden_for'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e.toString())
        .toSet();
    if (docId.isNotEmpty && hidden.contains(docId)) return true;
    if (authUid.isNotEmpty && hidden.contains(authUid)) return true;
    return false;
  }

  List<Map<String, dynamic>> _filterDeletedChats(
    List<Map<String, dynamic>> chats,
    String currentDocId,
  ) {
    if (currentDocId.isEmpty) return chats;
    return chats.where((chat) {
      final deletedFor = (chat['deleted_for'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toSet();
      return !deletedFor.contains(currentDocId);
    }).toList();
  }
}
