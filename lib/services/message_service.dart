import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/safe_data_extractor.dart';

/// Service to handle all types of messages (photo requests, birthday wishes, etc.)
class MessageService extends ChangeNotifier {
  List<Map<String, dynamic>> _messagesReceived = [];
  List<Map<String, dynamic>> _messagesSent = [];
  bool _isLoading = false;

  // Real-time listeners
  StreamSubscription<QuerySnapshot>? _receivedPhotoSubscription;
  StreamSubscription<QuerySnapshot>? _sentPhotoSubscription;
  StreamSubscription<QuerySnapshot>? _receivedMessageSubscription;
  StreamSubscription<QuerySnapshot>? _sentMessageSubscription;
  String? _listenedUserId;
  List<Map<String, dynamic>> _livePhotoReceived = [];
  List<Map<String, dynamic>> _livePhotoSent = [];
  List<Map<String, dynamic>> _liveMessageReceived = [];
  List<Map<String, dynamic>> _liveMessageSent = [];

  MessageService();

  static String _displayText(dynamic value, String fallback) {
    final t = value?.toString().trim() ?? '';
    if (t.isEmpty || t.toLowerCase() == 'null') return fallback;
    return t;
  }

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get messagesReceived => List.unmodifiable(_messagesReceived);
  List<Map<String, dynamic>> get messagesSent => List.unmodifiable(_messagesSent);

  String? _lastLoadedUserId;

  static bool _notSoftDeletedForUser(Map<String, dynamic> msg, String userId) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    List<dynamic> deletedFor = [
      ...(msg['deleted_for'] as List<dynamic>? ?? []),
      ...(msg['deletedFor'] as List<dynamic>? ?? []),
    ];
    if (deletedFor.contains(userId)) return false;
    if (authUid != null && authUid.isNotEmpty && deletedFor.contains(authUid)) {
      return false;
    }
    return true;
  }

  /// Load all messages for a user (photo requests, birthday wishes, etc.)
  Future<void> loadMessages(String userId, {bool forceReload = false}) async {
    if (userId.isEmpty) return;
    
    final userSwitched = _lastLoadedUserId != userId;
    if (_isLoading && !forceReload && !userSwitched) return;

    _lastLoadedUserId = userId;
    final showLoadingSpinner = userSwitched ||
        _messagesReceived.isEmpty && _messagesSent.isEmpty;
    if (showLoadingSpinner) {
      _updateAndNotify(() => _isLoading = true);
    }

    try {
      debugPrint('🔄 Loading messages for user: $userId (force: $forceReload)');

      // Bound total wait so Notifications / inbox never hangs indefinitely on slow Firestore.
      // Direct Firestore calls since FirebaseService methods don't exist
      final photoRequestsReceived = FirebaseFirestore.instance
          .collection('photo_requests')
          .where('to_user_id', isEqualTo: userId)
          .get();
      final photoRequestsSent = FirebaseFirestore.instance
          .collection('photo_requests')
          .where('from_user_id', isEqualTo: userId)
          .get();
      final birthdayWishes = FirebaseFirestore.instance
          .collection('messages')
          .where('type', isEqualTo: 'birthday_wish')
          .where('to_user_id', isEqualTo: userId)
          .get();
      final anniversaryMessages = FirebaseFirestore.instance
          .collection('messages')
          .where('type', isEqualTo: 'anniversary_message')
          .where('to_user_id', isEqualTo: userId)
          .get();
      
      // Helper functions defined before use
      Map<String, dynamic> tagInboxType(Map<String, dynamic> m) {
        final mt = m['message_type'] as String? ?? 'message';
        return {...m, 'type': mt};
      }

      List<Map<String, dynamic>> asMaps(dynamic data) {
        if (data == null) return [];
        if (data is QuerySnapshot) {
          return data.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data() as Map<dynamic, dynamic>);
            m['id'] = d.id;
            return m;
          }).toList();
        }
        if (data is List) {
          return data.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>)).toList();
        }
        return [];
      }

      final results = await Future.wait<QuerySnapshot>([
        photoRequestsReceived,
        photoRequestsSent,
        birthdayWishes,
        anniversaryMessages,
      ]);

      final photoRx = asMaps(results[0])
          .where((msg) => _notSoftDeletedForUser(msg, userId))
          .map(
            (m) => {
              ...m,
              'type': 'photo_request',
              'direction': 'received',
            },
          )
          .toList();
      final photoSent = asMaps(results[1])
          .where((msg) => _notSoftDeletedForUser(msg, userId))
          .map(
            (m) => {
              ...m,
              'type': 'photo_request',
              'direction': 'sent',
            },
          )
          .toList();

      final inboxExtras = <Map<String, dynamic>>[
        ...asMaps(results[2]),
        ...asMaps(results[3]),
      ]
          .where((msg) => _notSoftDeletedForUser(msg, userId))
          .map(tagInboxType)
          .toList();

      _messagesReceived = [...photoRx, ...inboxExtras];
      _messagesSent = photoSent;

      // Sort by date (newest first)
      _messagesReceived.sort(_compareByCreatedAtDesc);
      _messagesSent.sort(_compareByCreatedAtDesc);

      debugPrint(
          '✅ Loaded ${_messagesReceived.length} received, ${_messagesSent.length} sent messages');
    } on FirebaseException catch (e) {
      // 🔥 FIX: Gracefully handle permission denied - return empty lists
      if (e.code == 'permission-denied') {
        debugPrint('🔒 MessageService: permission denied, returning empty lists');
        _messagesReceived = [];
        _messagesSent = [];
      } else {
        debugPrint('❌ Failed to load messages: $e');
      }
    } catch (e) {
      debugPrint('❌ Failed to load messages: $e');
    } finally {
      if (showLoadingSpinner) {
        _updateAndNotify(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
    notifyListeners();
  }

  /// Get display name for a message
  String getMessageDisplayName(Map<String, dynamic> message) {
    if (message['type'] == 'photo_request') {
      final direction =
          (message['direction'] as String? ?? 'received').toLowerCase();
      if (direction == 'received') {
        return _displayText(message['from_first_name'], 'Someone');
      }
      return _displayText(message['to_first_name'], 'Someone');
    }
    final mt =
        message['type'] as String? ?? message['message_type'] as String? ?? '';
    switch (mt) {
      case 'birthday_wish':
        return 'Birthday wish';
      case 'anniversary_wish':
        return 'Anniversary';
      case 'system':
      case 'announcement':
      case 'reminder':
        return 'Notice';
      default:
        return 'Message';
    }
  }

  /// Get message text for display
  String getMessageText(Map<String, dynamic> message) {
    if (message['type'] == 'photo_request') {
      final direction = (message['direction'] as String? ?? '').toLowerCase();
      final status = (message['status'] as String? ?? 'pending').toLowerCase();
      if (direction == 'received') {
        switch (status) {
          case 'approved':
          case 'granted':
          case 'accepted':
            return 'You accepted this photo request';
          case 'rejected':
          case 'denied':
          case 'revoked':
            return 'You rejected this photo request';
          default:
            return 'Photo request received';
        }
      } else {
        switch (status) {
          case 'approved':
          case 'granted':
          case 'accepted':
            return 'Your photo request was accepted. You can view the photo now.';
          case 'rejected':
          case 'denied':
          case 'revoked':
            return 'Your photo request was rejected';
          default:
            return 'Photo request sent';
        }
      }
    }
    final body = _displayText(
      message['message'] ?? message['body'],
      '',
    );
    if (body.isNotEmpty) return body;
    final mt =
        message['type'] as String? ?? message['message_type'] as String? ?? '';
    switch (mt) {
      case 'birthday_wish':
        return 'Someone sent you birthday wishes';
      case 'anniversary_wish':
        return 'Anniversary message';
      case 'system':
      case 'announcement':
      case 'reminder':
        return message['title'] as String? ?? 'System message';
      default:
        return 'Message';
    }
  }

  /// Get message status for display
  String getMessageStatus(Map<String, dynamic> message) {
    if (message['type'] == 'photo_request') {
      final status = message['status'] as String? ?? 'pending';
      switch (status.toLowerCase()) {
        case 'pending':
          return 'Pending';
        case 'accepted':
        case 'granted':
          return 'Approved';
        case 'approved':
          return 'Approved';
        case 'revoked':
        case 'rejected':
        case 'denied':
          return 'Rejected';
        default:
          return 'Unknown';
      }
    }
    final read = message['is_read'] as bool? ?? false;
    return read ? 'Read' : 'New';
  }

  /// Get message status color
  String getMessageStatusColor(Map<String, dynamic> message) {
    if (message['type'] == 'photo_request') {
      final status = message['status'] as String? ?? 'pending';
      switch (status.toLowerCase()) {
        case 'pending':
          return '#FFA500'; // Orange
        case 'accepted':
        case 'granted':
        case 'approved':
          return '#28A745'; // Green
        case 'revoked':
        case 'rejected':
        case 'denied':
          return '#DC3545'; // Red
        default:
          return '#6C757D'; // Gray
      }
    }
    final read = message['is_read'] as bool? ?? false;
    return read ? '#28A745' : '#FFA500';
  }

  /// Get message icon
  String getMessageIcon(Map<String, dynamic> message) {
    if (message['type'] == 'photo_request') {
      return 'photo_camera';
    }
    return 'message';
  }

  /// Format message timestamp
  String formatMessageTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'Just now';
          }
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      debugPrint('❌ Error formatting timestamp: $e');
      return '';
    }
  }

  void _updateAndNotify(void Function() fn) {
    fn();
    notifyListeners();
  }

  /// Delete a single inbox row for the current user.
  /// Use [messageType] `'photo_request'` for `photo_requests` docs; otherwise `messages` is updated.
  Future<void> deleteMessage({
    required String messageId,
    required String currentUserId,
    String? messageType,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final deleteFor = <String>{
      currentUserId,
      if (authUid != null && authUid.isNotEmpty) authUid,
    }.toList();

    if (messageType == 'photo_request') {
      await FirebaseFirestore.instance
          .collection('photo_requests')
          .doc(messageId)
          .set({
        'deleted_for': FieldValue.arrayUnion(deleteFor),
      }, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .set({
        'deleted_for': FieldValue.arrayUnion(deleteFor),
      }, SetOptions(merge: true));
    }

    _messagesReceived.removeWhere((m) => m['id'] == messageId);
    _messagesSent.removeWhere((m) => m['id'] == messageId);

    notifyListeners();

    debugPrint('🗑️ Inbox row removed: $messageId (${messageType ?? 'message'})');
  }

  /// Clear all messages for the current user using soft delete
  Future<void> clearAllMessages(String userId) async {
    _updateAndNotify(() => _isLoading = true);

    try {
      final allMessages = getAllMessages();

      for (var msg in allMessages) {
        final messageId = msg['id'];
        if (messageId == null) continue;
        final id = messageId.toString();
        if (id.isEmpty) continue;
        final type = msg['type'] as String?;
        try {
          await deleteMessage(
            messageId: id,
            currentUserId: userId,
            messageType: type == 'photo_request' ? 'photo_request' : null,
          );
        } catch (e) {
          debugPrint('⚠️ clearAllMessages: skip id=$id ($e)');
        }
      }

      _messagesReceived.clear();
      _messagesSent.clear();
      _lastLoadedUserId = null;

      debugPrint('🧹 All messages cleared from Firebase + local');
    } finally {
      _updateAndNotify(() => _isLoading = false);
    }
  }

  /// Pending incoming inbox row (messages + photo requests) for badge counts.
  static bool isIncomingUnread(Map<String, dynamic> msg) {
    final status = (msg['status'] as String? ?? 'pending').toLowerCase();
    if (status == 'approved' ||
        status == 'accepted' ||
        status == 'granted' ||
        status == 'rejected' ||
        status == 'declined' ||
        status == 'denied') {
      return false;
    }
    final isRead =
        (msg['is_read'] as bool?) ?? (msg['isRead'] as bool?) ?? false;
    return !isRead;
  }

  /// Unread inbox rows (photo requests, wishes) for notifications / bell — not the Messages chat tab.
  List<Map<String, dynamic>> incomingUnreadInbox({String? userId}) {
    if (userId != null &&
        (_lastLoadedUserId == null || userId != _lastLoadedUserId)) {
      return const [];
    }
    return _messagesReceived.where((msg) {
      final id = (msg['id'] as String?)?.trim() ?? '';
      return id.isNotEmpty && isIncomingUnread(msg);
    }).toList();
  }

  int getReceivedMessagesCount({String? userId}) =>
      incomingUnreadInbox(userId: userId).length;

  Future<void> markMessageAsRead({
    required String messageId,
    String? messageType,
  }) async {
    if (messageId.isEmpty) return;
    final isPhoto = (messageType ?? '').toLowerCase() == 'photo_request';
    final collection = isPhoto ? 'photo_requests' : 'messages';
    try {
      await FirebaseFirestore.instance.collection(collection).doc(messageId).set(
        {'is_read': true},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ markMessageAsRead failed for $collection/$messageId: $e');
    }
    final rxIdx = _messagesReceived.indexWhere((m) => (m['id'] as String?) == messageId);
    if (rxIdx >= 0) {
      _messagesReceived[rxIdx] = {
        ..._messagesReceived[rxIdx],
        'is_read': true,
      };
      notifyListeners();
    }
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _createdAtToDate(dynamic raw) =>
      SafeDataExtractor.parseFirestoreDate(raw) ?? _epoch;

  int _compareByCreatedAtDesc(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) =>
      _createdAtToDate(b['created_at']).compareTo(_createdAtToDate(a['created_at']));

  void _rebuildFromLiveBuckets(String userId) {
    _messagesReceived = [
      ..._livePhotoReceived.where((m) => _notSoftDeletedForUser(m, userId)),
      ..._liveMessageReceived.where((m) => _notSoftDeletedForUser(m, userId)),
    ]..sort(_compareByCreatedAtDesc);

    _messagesSent = [
      ..._livePhotoSent.where((m) => _notSoftDeletedForUser(m, userId)),
      ..._liveMessageSent.where((m) => _notSoftDeletedForUser(m, userId)),
    ]..sort(_compareByCreatedAtDesc);
  }

  int getSentMessagesCount({String? userId}) {
    if (userId != null && userId != _lastLoadedUserId) {
      return 0;
    }
    return _messagesSent.length;
  }

  int getMessagesCount({String? userId}) {
    if (userId != null && userId != _lastLoadedUserId) {
      return 0;
    }
    return _messagesReceived.length + _messagesSent.length;
  }

  bool hasAnyMessages({String? userId}) {
    return getMessagesCount(userId: userId) > 0;
  }

  /// Get all messages (received + sent) combined
  List<Map<String, dynamic>> getAllMessages() {
    final allMessages = [..._messagesReceived, ..._messagesSent];
    allMessages.sort(_compareByCreatedAtDesc);
    return allMessages;
  }

  bool isDataLoadedForUser(String userId) {
    return _lastLoadedUserId == userId && !_isLoading;
  }

  Future<void> refreshMessages() async {
    if (_lastLoadedUserId != null) {
      await loadMessages(_lastLoadedUserId!, forceReload: true);
    }
  }

  // Start real-time listeners for messages
  Future<void> startListening(String userId) async {
    if (_listenedUserId == userId && 
        _receivedPhotoSubscription != null &&
        _sentPhotoSubscription != null &&
        _receivedMessageSubscription != null &&
        _sentMessageSubscription != null) {
      return; // Already listening for this user
    }

    stopListening();
    _listenedUserId = userId;

    try {
      final listenUid = userId.trim();
      if (listenUid.isEmpty) return;

      debugPrint('MessageService: Starting real-time listeners for $listenUid');

      _receivedPhotoSubscription = FirebaseFirestore.instance
          .collection('photo_requests')
          .where('to_user_id', isEqualTo: listenUid)
          .snapshots()
          .listen((snapshot) {
            _livePhotoReceived = snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              data['type'] = 'photo_request';
              data['direction'] = 'received';
              return data;
            }).toList();
            _rebuildFromLiveBuckets(userId);
            notifyListeners();
          }, onError: (error) {
            debugPrint('MessageService: Received messages listener error: $error');
          });

      _sentPhotoSubscription = FirebaseFirestore.instance
          .collection('photo_requests')
          .where('from_user_id', isEqualTo: listenUid)
          .snapshots()
          .listen((snapshot) {
            _livePhotoSent = snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              data['type'] = 'photo_request';
              data['direction'] = 'sent';
              return data;
            }).toList();
            _rebuildFromLiveBuckets(userId);
            notifyListeners();
          }, onError: (error) {
            debugPrint('MessageService: Sent messages listener error: $error');
          });

      _receivedMessageSubscription = FirebaseFirestore.instance
          .collection('messages')
          .where('to_user_id', isEqualTo: listenUid)
          .snapshots()
          .listen((snapshot) {
            _liveMessageReceived = snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              data['type'] = data['message_type'] ?? data['type'] ?? 'message';
              return data;
            }).toList();
            _rebuildFromLiveBuckets(userId);
            notifyListeners();
          }, onError: (error) {
            debugPrint('MessageService: Received message listener error: $error');
          });

      _sentMessageSubscription = FirebaseFirestore.instance
          .collection('messages')
          .where('from_user_id', isEqualTo: listenUid)
          .snapshots()
          .listen((snapshot) {
            _liveMessageSent = snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              data['type'] = data['message_type'] ?? data['type'] ?? 'message';
              return data;
            }).toList();
            _rebuildFromLiveBuckets(userId);
            notifyListeners();
          }, onError: (error) {
            debugPrint('MessageService: Sent message listener error: $error');
          });

    } catch (e) {
      debugPrint('MessageService: Failed to start listeners: $e');
    }
  }

  // Stop real-time listeners
  void stopListening() {
    _receivedPhotoSubscription?.cancel();
    _sentPhotoSubscription?.cancel();
    _receivedMessageSubscription?.cancel();
    _sentMessageSubscription?.cancel();
    _receivedPhotoSubscription = null;
    _sentPhotoSubscription = null;
    _receivedMessageSubscription = null;
    _sentMessageSubscription = null;
    _listenedUserId = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
