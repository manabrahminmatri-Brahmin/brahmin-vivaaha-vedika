import 'package:uuid/uuid.dart';

/// Interest model for express interest feature
class Interest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final DateTime createdAt;
  final InterestStatus status;
  final DateTime? respondedAt;
  final bool isMutual;

  Interest({
    String? id,
    required this.fromUserId,
    required this.toUserId,
    DateTime? createdAt,
    this.status = InterestStatus.pending,
    this.respondedAt,
    this.isMutual = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'responded_at': respondedAt?.toIso8601String(),
        'is_mutual': isMutual,
      };

  factory Interest.fromJson(Map<String, dynamic> json) => Interest(
        id: json['id'],
        fromUserId: (json['from_user_id'] ?? json['fromUserId']) as String? ?? '',
        toUserId: (json['to_user_id'] ?? json['toUserId']) as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        status: InterestStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => InterestStatus.pending,
        ),
        respondedAt: (json['responded_at'] ?? json['respondedAt']) != null
            ? DateTime.tryParse(
                (json['responded_at'] ?? json['respondedAt']) as String? ?? '',
              )
            : null,
        isMutual: (json['is_mutual'] ?? json['isMutual']) as bool? ?? false,
      );
}

enum InterestStatus {
  pending,
  accepted,
  rejected,
  ignored,
}
