import 'package:uuid/uuid.dart';

/// Message model for in-app messaging
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;
  final DateTime? readAt;
  final String? attachmentUrl;
  final String? attachmentType;

  Message({
    String? id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = MessageType.text,
    DateTime? timestamp,
    this.isRead = false,
    this.readAt,
    this.attachmentUrl,
    this.attachmentType,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'content': content,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'is_read': isRead,
        'read_at': readAt?.toIso8601String(),
        'attachment_url': attachmentUrl,
        'attachment_type': attachmentType,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'],
        conversationId: json['conversation_id'],
        senderId: json['sender_id'],
        receiverId: json['receiver_id'],
        content: json['content'],
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
        ),
        timestamp: DateTime.parse(json['timestamp']),
        isRead: json['is_read'] ?? false,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
        attachmentUrl: json['attachment_url'],
        attachmentType: json['attachment_type'],
      );
}

enum MessageType {
  text,
  image,
  file,
  system,
}

/// Conversation model
class Conversation {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final DateTime lastMessageAt;
  final String? lastMessage;
  final int unreadCount;
  final bool isDeleted;
  final DateTime createdAt;

  Conversation({
    String? id,
    required this.participant1Id,
    required this.participant2Id,
    DateTime? lastMessageAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.isDeleted = false,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        lastMessageAt = lastMessageAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'participant1_id': participant1Id,
        'participant2_id': participant2Id,
        'last_message_at': lastMessageAt.toIso8601String(),
        'last_message': lastMessage,
        'unread_count': unreadCount,
        'is_deleted': isDeleted,
        'created_at': createdAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'],
        participant1Id: json['participant1_id'],
        participant2Id: json['participant2_id'],
        lastMessageAt: DateTime.parse(json['last_message_at']),
        lastMessage: json['last_message'],
        unreadCount: json['unread_count'] ?? 0,
        isDeleted: json['is_deleted'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}
