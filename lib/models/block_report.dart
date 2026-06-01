import 'package:cloud_firestore/cloud_firestore.dart';

/// Reason for reporting a user
enum ReportReason {
  fakeProfile('Fake Profile', 'User is using false information or photos'),
  inappropriate('Inappropriate Content', 'Sharing offensive or explicit content'),
  harassment('Harassment', 'Sending unwanted messages or threats'),
  scam('Scam/Fraud', 'Attempting to defraud or scam other users'),
  underage('Underage', 'User appears to be under 18 years old'),
  other('Other', 'Other reasons not listed above');

  final String label;
  final String description;
  
  const ReportReason(this.label, this.description);
}

/// Status of a report
enum ReportStatus {
  pending('Pending Review'),
  investigating('Under Investigation'),
  resolved('Resolved'),
  dismissed('Dismissed');

  final String label;
  const ReportStatus(this.label);
}

/// Model for user blocks
class UserBlock {
  final String id;
  final String blockerId;
  final String blockedId;
  final DateTime blockedAt;
  final String? reason;

  UserBlock({
    required this.id,
    required this.blockerId,
    required this.blockedId,
    required this.blockedAt,
    this.reason,
  });

  factory UserBlock.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserBlock(
      id: doc.id,
      blockerId: data['blocker_id'] ?? '',
      blockedId: data['blocked_id'] ?? '',
      blockedAt: (data['blocked_at'] as Timestamp).toDate(),
      reason: data['reason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'blocker_id': blockerId,
      'blocked_id': blockedId,
      'blocked_at': Timestamp.fromDate(blockedAt),
      'reason': reason,
    };
  }
}

/// Model for user reports
class UserReport {
  final String id;
  final String reporterId;
  final String reportedId;
  final ReportReason reason;
  final String? details;
  final DateTime reportedAt;
  final ReportStatus status;
  final String? adminNotes;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  UserReport({
    required this.id,
    required this.reporterId,
    required this.reportedId,
    required this.reason,
    this.details,
    required this.reportedAt,
    this.status = ReportStatus.pending,
    this.adminNotes,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory UserReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserReport(
      id: doc.id,
      reporterId: data['reporter_id'] ?? '',
      reportedId: data['reported_id'] ?? '',
      reason: ReportReason.values.firstWhere(
        (r) => r.name == data['reason'],
        orElse: () => ReportReason.other,
      ),
      details: data['details'],
      reportedAt: (data['reported_at'] as Timestamp).toDate(),
      status: ReportStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => ReportStatus.pending,
      ),
      adminNotes: data['admin_notes'],
      resolvedAt: data['resolved_at'] != null 
          ? (data['resolved_at'] as Timestamp).toDate() 
          : null,
      resolvedBy: data['resolved_by'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason.name,
      'details': details,
      'reported_at': Timestamp.fromDate(reportedAt),
      'status': status.name,
      'admin_notes': adminNotes,
      'resolved_at': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'resolved_by': resolvedBy,
    };
  }
}

/// Extension to check if a user is blocked
extension BlockCheckExtension on List<UserBlock> {
  bool isBlocked(String userId) {
    return any((block) => block.blockedId == userId);
  }

  bool hasBlocked(String userId) {
    return any((block) => block.blockerId == userId);
  }
}
