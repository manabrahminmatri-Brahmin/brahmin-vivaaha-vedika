import 'package:uuid/uuid.dart';

/// Profile verification model
class ProfileVerification {
  final String id;
  final String userId;
  final VerificationType type;
  final VerificationStatus status;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final String? rejectionReason;
  final String? documentUrl;

  ProfileVerification({
    String? id,
    required this.userId,
    required this.type,
    this.status = VerificationStatus.pending,
    DateTime? submittedAt,
    this.verifiedAt,
    this.verifiedBy,
    this.rejectionReason,
    this.documentUrl,
  })  : id = id ?? const Uuid().v4(),
        submittedAt = submittedAt ?? DateTime.now();

  bool get isVerified => status == VerificationStatus.verified;

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'status': status.name,
        'submittedAt': submittedAt?.toIso8601String(),
        'verifiedAt': verifiedAt?.toIso8601String(),
        'verifiedBy': verifiedBy,
        'rejectionReason': rejectionReason,
        'documentUrl': documentUrl,
      };

  factory ProfileVerification.fromJson(Map<String, dynamic> json) =>
      ProfileVerification(
        id: json['id'],
        userId: json['user_id'],
        type: VerificationType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => VerificationType.phone,
        ),
        status: VerificationStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => VerificationStatus.pending,
        ),
        submittedAt: json['submittedAt'] != null
            ? DateTime.tryParse(json['submittedAt'] as String? ?? '')
            : null,
        verifiedAt: json['verifiedAt'] != null
            ? DateTime.tryParse(json['verifiedAt'] as String? ?? '')
            : null,
        verifiedBy: json['verifiedBy'],
        rejectionReason: json['rejectionReason'],
        documentUrl: json['documentUrl'],
      );
}

enum VerificationType {
  phone,
  email,
  id,
}

enum VerificationStatus {
  pending,
  verified,
  rejected,
  expired,
}
