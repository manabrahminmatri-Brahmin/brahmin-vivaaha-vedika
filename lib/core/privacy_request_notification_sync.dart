import 'package:brahmin_vivaaha_vedika/core/access_request_status.dart';

/// Aligns in-app notification unread state with live privacy-request documents
/// (birth, community reference, photo) — same lifecycle as [InterestBadgeAggregator].
class PrivacyRequestNotificationSync {
  PrivacyRequestNotificationSync._();

  /// Incoming request — owner must act (mirrored by pending doc listeners).
  static const Set<String> incomingTypes = {
    'birth_request',
    'birth_details_request',
    'community_reference_request',
    'photo_request',
  };

  /// Outcome — requester was granted, denied, or revoked.
  static const Set<String> outcomeTypes = {
    'birth_request_granted',
    'birth_request_denied',
    'birth_request_revoked',
    'birth_details_granted',
    'birth_details_denied',
    'community_reference_granted',
    'community_reference_denied',
    'community_reference_revoked',
    'photo_request_granted',
    'photo_request_denied',
    'photo_request_revoked',
    'photo_request_approved',
    'photo_request_rejected',
    'photo_granted',
    'photo_denied',
  };

  /// Excluded from consolidated bell — counted via pending request doc listeners.
  static const Set<String> hubMirroredBellTypes = {
    ...incomingTypes,
    ...outcomeTypes,
  };

  static String normalizeStatus(dynamic raw) =>
      AccessRequestStatus.normalize(raw);

  static bool statusIsSettled(String normalized) =>
      AccessRequestStatus.isSettled(normalized);

  static String? requestDocIdFromNotification(Map<String, dynamic> n) {
    final data = n['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final id = (n['request_doc_id'] as String? ??
            n['requestDocId'] as String? ??
            map['request_doc_id'] as String? ??
            map['requestDocId'] as String? ??
            '')
        .trim();
    return id.isEmpty ? null : id;
  }

  /// Whether an unread notification row should be cleared for badge/list counts.
  static bool shouldMarkNotificationRead({
    required String type,
    required String requestDocId,
    required Set<String> pendingIncomingRequestDocIds,
    required Map<String, String> requestDocStatuses,
  }) {
    final normalizedType = type.trim();
    final status = requestDocStatuses[requestDocId] ?? 'pending';

    if (incomingTypes.contains(normalizedType)) {
      return !pendingIncomingRequestDocIds.contains(requestDocId);
    }

    if (outcomeTypes.contains(normalizedType)) {
      return statusIsSettled(status);
    }

    return false;
  }
}
