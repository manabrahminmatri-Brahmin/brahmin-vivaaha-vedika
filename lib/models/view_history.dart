import 'package:uuid/uuid.dart';

/// Recently viewed profile model
class RecentlyViewed {
  final String id;
  final String viewerId;
  final String viewedProfileId;
  final DateTime viewedAt;
  final int viewCount;

  RecentlyViewed({
    String? id,
    required this.viewerId,
    required this.viewedProfileId,
    DateTime? viewedAt,
    this.viewCount = 1,
  })  : id = id ?? const Uuid().v4(),
        viewedAt = viewedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'viewer_id': viewerId,
        'viewed_profile_id': viewedProfileId,
        'viewed_at': viewedAt.toIso8601String(),
        'view_count': viewCount,
      };

  factory RecentlyViewed.fromJson(Map<String, dynamic> json) =>
      RecentlyViewed(
        id: json['id'],
        viewerId: (json['viewer_id'] ?? json['viewerId']) as String? ?? '',
        viewedProfileId:
            (json['viewed_profile_id'] ?? json['viewedProfileId']) as String? ?? '',
        viewedAt: DateTime.tryParse(
              (json['viewed_at'] ?? json['viewedAt']) as String? ?? '',
            ) ??
            DateTime.now(),
        viewCount: (json['view_count'] ?? json['viewCount']) as int? ?? 1,
      );
}

/// Activity log model
class ActivityLog {
  final String id;
  final String userId;
  final ActivityType type;
  final String targetUserId;
  final String? description;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ActivityLog({
    String? id,
    required this.userId,
    required this.type,
    required this.targetUserId,
    this.description,
    DateTime? timestamp,
    this.metadata,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'target_user_id': targetUserId,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        id: json['id'],
        userId: json['user_id'],
        type: ActivityType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => ActivityType.view,
        ),
        targetUserId: (json['target_user_id'] ?? json['targetUserId']) as String? ?? '',
        description: json['description'],
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        metadata: json['metadata'],
      );
}

enum ActivityType {
  view,
  interest,
  contactRequest,
  message,
  like,
  block,
  unblock,
  profileUpdate,
}
