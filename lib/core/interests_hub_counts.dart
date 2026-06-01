// Back-compat wrappers — all logic lives in [interest_badge_aggregator.dart].
import 'interest_badge_aggregator.dart';

String interestsHubNormalizeStatus(dynamic raw) =>
    InterestBadgeAggregator.normalizeInterestStatus(raw);

bool interestsHubInterestRowVisible(dynamic rawStatus) =>
    InterestBadgeAggregator.isInterestRowVisible(rawStatus);

bool interestsHubRowPending(dynamic rawStatus) =>
    InterestBadgeAggregator.isPendingInterestStatus(rawStatus);

bool interestsHubRowViewedByRecipient(Map<String, dynamic> row) =>
    InterestBadgeAggregator.viewedByRecipientIsTruthy(row);

int interestsHubPendingReceivedUnviewedCount(
  List<Map<String, dynamic>> received,
) =>
    InterestBadgeAggregator.receivedInterestUnviewed(received);

int interestsHubPendingSentCount(List<Map<String, dynamic>> sent) =>
    InterestBadgeAggregator.sentInterestUnviewed(sent);

int interestsHubIncomingRequestDocCount({
  required Iterable<String> birthOwnerIds,
  required Iterable<String> birthOwnerAuthIds,
  required Iterable<String> communityOwnerIds,
  required Iterable<String> communityOwnerAuthIds,
  required Iterable<String> photoToUserIds,
  required Iterable<String> photoToProfileIds,
}) =>
    InterestBadgeAggregator.pendingIncomingRequestDocCount(
      birthOwnerIds: birthOwnerIds,
      birthOwnerAuthIds: birthOwnerAuthIds,
      communityOwnerIds: communityOwnerIds,
      communityOwnerAuthIds: communityOwnerAuthIds,
      photoToUserIds: photoToUserIds,
      photoToProfileIds: photoToProfileIds,
    );
