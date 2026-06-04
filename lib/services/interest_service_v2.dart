// 🔥 INTEREST SERVICE V2 - Uses Repository Pattern
// NO direct Firestore calls
// Returns Result<T> for all operations
// Uses AppContract for all field names

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';

import '../core/app_identity.dart';
import '../core/app_initializer.dart';
import '../core/contract.dart';
import '../core/error_firewall.dart';
import '../core/firestore_repository.dart';
import '../core/interest_badge_aggregator.dart';
import '../core/interest_hub_cache.dart';
import '../core/interest_identity_resolver.dart';
import 'legacy_interest_repair_service.dart';
import 'block_enforcement_policy.dart';
import '../core/result.dart';
import '../services/notification_service.dart';
import 'matrimony_gateway_service.dart';
import 'product_funnel_analytics.dart';
import 'profile_deletion_service.dart';

/// Reads snake_case or legacy camelCase keys from interest documents.
dynamic _interestRowField(Map<String, dynamic> row, String snake, String camel) {
  if (row.containsKey(snake)) return row[snake];
  return row[camel];
}

/// Merges multiple Firestore interest snapshot streams (e.g. `whereIn` chunks).
Stream<Result<List<Map<String, dynamic>>>> _mergeInterestSnapshotStreams(
  List<Stream<Result<List<Map<String, dynamic>>>>> streams,
) {
  if (streams.isEmpty) {
    return Stream.value(
      Result.error(ErrorCodes.invalidArgument, 'No interest query streams'),
    );
  }
  if (streams.length == 1) return streams.first;

  late final StreamController<Result<List<Map<String, dynamic>>>> controller;
  controller = StreamController<Result<List<Map<String, dynamic>>>>(
    onListen: () {
      final latest =
          List<List<Map<String, dynamic>>?>.filled(streams.length, null);
      final subscriptions =
          <StreamSubscription<Result<List<Map<String, dynamic>>>>>[];

      void emitMerged() {
        if (controller.isClosed) return;
        final merged = <String, Map<String, dynamic>>{};
        for (var i = 0; i < streams.length; i++) {
          final rows = latest[i];
          if (rows == null) continue;
          for (final row in rows) {
            final id = (row['id'] as String? ?? '').toString().trim();
            if (id.isEmpty) continue;
            merged[id] = row;
          }
        }
        controller.add(Result.success(merged.values.toList()));
      }

      for (var i = 0; i < streams.length; i++) {
        final idx = i;
        subscriptions.add(streams[i].listen(
          (res) {
            if (res.isError) {
              if (!controller.isClosed) controller.add(res);
              return;
            }
            latest[idx] = res.data ?? const <Map<String, dynamic>>[];
            emitMerged();
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) {
              controller.add(
                Result.error(ErrorCodes.unknown, e.toString(), rawError: e),
              );
            }
          },
        ));
      }

      controller.onCancel = () {
        for (final s in subscriptions) {
          s.cancel();
        }
      };
    },
  );

  return controller.stream;
}

/// InterestServiceV2 - Professional service using repository pattern
class InterestServiceV2 {
  static final InterestServiceV2 _instance = InterestServiceV2._internal();
  factory InterestServiceV2() => _instance;
  InterestServiceV2._internal();

  // Retry configuration for Issue 1 Fix
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  final Map<String, Map<String, dynamic>> _interestProfileById = {};

  Future<String> _currentUserDocIdOrInitialize() async {
    var userId = IdentityProvider.userDocId.trim();
    if (userId.isNotEmpty) return userId;

    final initResult = await AppInitializer.ensureInitialized();
    if (initResult.isSuccess) {
      userId = IdentityProvider.userDocId.trim();
    }
    return userId;
  }

  /// Send interest to a user with retry logic
  Future<Result<Map<String, dynamic>>> sendInterest(
    String targetUserDocId, {
    String? message,
  }) async {
    return _retryOperation(
      () => _sendInterestInternal(targetUserDocId, message: message),
      'sendInterest',
    );
  }

  /// [rawTarget] may be a `users/{docId}` id or a public [Fields.profileId].
  Future<Result<String>> _resolveReceiverFirestoreDocId(
    String rawTarget,
  ) async {
    final t = rawTarget.trim();
    if (t.isEmpty) {
      return Result.error(ErrorCodes.invalidArgument, 'Invalid target user');
    }

    final direct = await FirestoreRepository.getDocument(Collections.users, t);
    if (direct.isError) {
      return Result.error(
        direct.errorCode,
        direct.message,
        rawError: direct.rawError,
      );
    }
    if (direct.data != null) {
      return Result.success(t);
    }

    final byProfile = await FirestoreRepository.query(
      Collections.users,
      conditions: [QueryCondition.equal(Fields.profileId, t)],
      limit: 1,
    );
    if (byProfile.isError) {
      return Result.error(
        byProfile.errorCode,
        byProfile.message,
        rawError: byProfile.rawError,
      );
    }
    final rows = byProfile.data ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      return Result.error(ErrorCodes.invalidArgument, 'User not found');
    }
    final id = rows.first['id'] as String?;
    if (id == null || id.isEmpty) {
      return Result.error(ErrorCodes.invalidArgument, 'User not found');
    }
    return Result.success(id);
  }

  /// Internal send interest implementation
  Future<Result<Map<String, dynamic>>> _sendInterestInternal(
    String targetUserDocId, {
    String? message,
  }) async {
    try {
      final currentUserId = await _currentUserDocIdOrInitialize();

      // Issue 1 Fix: Add debug logging
      debugPrint('🔍 Current User ID: $currentUserId');
      debugPrint('🔍 Target User ID (raw): $targetUserDocId');

      if (currentUserId.isEmpty) {
        debugPrint('❌ Cannot send interest: User not authenticated');
        return Result.error(
          ErrorCodes.notAuthenticated,
          'Please sign in to send interest',
        );
      }

      if (targetUserDocId.isEmpty) {
        debugPrint('❌ Cannot send interest: Invalid target user ID');
        return Result.error(ErrorCodes.invalidArgument, 'Invalid target user');
      }

      final resolved = await _resolveReceiverFirestoreDocId(targetUserDocId);
      if (resolved.isError) {
        return Result.error(
          resolved.errorCode,
          resolved.message,
          rawError: resolved.rawError,
        );
      }
      final receiverDocId = resolved.data!;

      debugPrint('🔍 Target resolved to user doc: $receiverDocId');

      if (currentUserId == receiverDocId) {
        debugPrint('❌ Cannot send interest: Self-interest attempt');
        return Result.error(
          ErrorCodes.invalidOperation,
          'You cannot send interest to yourself',
        );
      }

      if (await BlockEnforcementPolicy.verifyBlockedForSendInterest(
        actorUserDocId: currentUserId,
        peerUserDocId: receiverDocId,
      )) {
        return Result.error(
          ErrorCodes.permissionDenied,
          'You cannot send interest to a blocked member.',
        );
      }

      // Check for existing interest using repository
      debugPrint('🔍 Checking for existing interest...');
      final existingResult = await _getExistingInterest(
        currentUserId,
        receiverDocId,
      );

      if (existingResult.isError) {
        return existingResult.map((_) => {});
      }

      if (existingResult.data != null) {
        final existing = existingResult.data!;
        final status = existing[Fields.status] as String?;

        if (status == StatusValues.pending) {
          return Result.error(
            ErrorCodes.alreadyExists,
            'Interest already pending',
          );
        } else if (status == StatusValues.accepted) {
          return Result.error(
            ErrorCodes.alreadyExists,
            'You are already connected',
          );
        }
        // If rejected/withdrawn, allow re-send
      }

      final gateway = await MatrimonyGatewayService.sendInterest(
        fromUserId: currentUserId,
        toUserId: receiverDocId,
        message: message,
        forceResend: existingResult.data != null,
      );

      if (gateway['success'] != true) {
        return Result.error(
          gateway['errorCode']?.toString() ?? ErrorCodes.permissionDenied,
          gateway['error']?.toString() ?? 'Failed to send interest',
        );
      }

      final duplicateIgnored = gateway['duplicateIgnored'] == true;
      final interestDocId =
          (gateway['interestId'] as String?) ?? '${currentUserId}_$receiverDocId';
      debugPrint('✅ Interest sent via gateway: $interestDocId');
      if (!duplicateIgnored) {
        unawaited(ProductFunnelAnalytics.interestSend(toUserId: receiverDocId));
      }
      return Result.success({
        'interestId': interestDocId,
        'receiverDocId':
            (gateway['receiverDocId'] as String?) ?? receiverDocId,
        'sent': true,
        'duplicateIgnored': duplicateIgnored,
      }, message: duplicateIgnored
          ? 'Interest already pending'
          : 'Interested');
    } catch (e) {
      ErrorFirewall.logError(e, context: 'InterestServiceV2.sendInterest');
      return Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Accept interest (server-authoritative).
  Future<Result<void>> acceptInterest(
    String interestDocId, {
    String? responseMessage,
  }) async {
    return _transitionInterestViaGateway(
      interestDocId,
      action: 'accept',
      responseMessage: responseMessage,
      contextLabel: 'InterestServiceV2.acceptInterest',
    );
  }

  /// Reject interest (server-authoritative).
  Future<Result<void>> rejectInterest(
    String interestDocId, {
    String? rejectionReason,
  }) async {
    return _transitionInterestViaGateway(
      interestDocId,
      action: 'reject',
      declineReason: rejectionReason,
      contextLabel: 'InterestServiceV2.rejectInterest',
    );
  }

  /// Withdraw interest (server-authoritative).
  Future<Result<void>> withdrawInterest(String interestDocId) async {
    return _transitionInterestViaGateway(
      interestDocId,
      action: 'withdraw',
      contextLabel: 'InterestServiceV2.withdrawInterest',
    );
  }

  Future<Result<void>> _transitionInterestViaGateway(
    String interestDocId, {
    required String action,
    String? declineReason,
    String? responseMessage,
    required String contextLabel,
  }) async {
    try {
      final currentUserId = await _currentUserDocIdOrInitialize();
      if (currentUserId.isEmpty) {
        return Result.error(ErrorCodes.notAuthenticated, 'Please sign in');
      }

      final gateway = await MatrimonyGatewayService.transitionInterest(
        interestId: interestDocId,
        action: action,
        declineReason: declineReason,
        responseMessage: responseMessage,
        requesterId: currentUserId,
      );

      if (gateway['success'] == true) {
        if (action == 'accept') {
          unawaited(ProductFunnelAnalytics.interestAccept(interestId: interestDocId));
        } else if (action == 'reject') {
          unawaited(ProductFunnelAnalytics.interestReject(interestId: interestDocId));
        } else if (action == 'withdraw') {
          unawaited(ProductFunnelAnalytics.interestWithdraw(interestId: interestDocId));
        }
        return Result.success(null);
      }

      return Result.error(
        gateway['errorCode']?.toString() ?? ErrorCodes.permissionDenied,
        gateway['error']?.toString() ?? 'Interest update failed',
      );
    } catch (e) {
      ErrorFirewall.logError(e, context: contextLabel);
      return Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Get existing interest between two users
  Future<Result<Map<String, dynamic>?>> _getExistingInterest(
    String fromUserId,
    String toUserId,
  ) async {
    final docId = '${fromUserId}_$toUserId';

    final result = await FirestoreRepository.getDocument(
      Collections.interests,
      docId,
    );

    return result;
  }

  /// Stream interests received by current user.
  ///
  /// [queryUserDocId] is the Firestore `users/{id}` document id from [AuthService]
  /// when [IdentityProvider] is not yet hydrated — keeps header bell / hub counts
  /// accurate on cold start.
  Stream<Result<List<Map<String, dynamic>>>> streamInterestsReceived({
    String? queryUserDocId,
  }) {
    final hinted = (queryUserDocId ?? '').trim();
    final aliasIds =
        InterestBadgeAggregator.resolveInterestParticipantQueryAliasIds(
      canonicalUserDocId: IdentityProvider.userDocId.trim(),
      queryUserDocIdHint: hinted.isNotEmpty ? hinted : null,
      firebaseAuthUid: fa.FirebaseAuth.instance.currentUser?.uid,
      identityAuthUid: IdentityProvider.authUid.trim().isNotEmpty
          ? IdentityProvider.authUid.trim()
          : null,
    );

    if (aliasIds.isEmpty) {
      return Stream.value(
        Result.error(ErrorCodes.notAuthenticated, 'Not authenticated'),
      );
    }

    final chunks = InterestBadgeAggregator.chunksForFirestoreWhereIn(aliasIds);
    final rawStreams = chunks
        .map(
          (c) => FirestoreRepository.streamQuery(
            Collections.interests,
            conditions: [
              c.length == 1
                  ? QueryCondition.equal(Fields.toUserId, c.first)
                  : QueryCondition.whereIn(Fields.toUserId, c),
            ],
            orderBy: Fields.createdAt,
            descending: true,
            includeMetadataChanges: false,
          ),
        )
        .toList();

    return _mergeInterestSnapshotStreams(rawStreams).asyncMap((result) async {
      if (result.isError || result.data == null) {
        return result;
      }

      final rawList = result.data!;
      if (rawList.isEmpty) {
        return Result.success(<Map<String, dynamic>>[]);
      }

      final byDoc = <String, Map<String, dynamic>>{};
      for (final row in rawList) {
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byDoc[id] = row;
      }
      final interests = byDoc.values.toList();

      // Collect peer IDs for received rows (sender + receiver snapshots).
      final userIds = <String>{};
      for (final i in interests) {
        final n = InterestIdentityResolver.normalizeInterestRow(i);
        final from = (n[Fields.fromUserId] as String? ?? '').trim();
        final to = (n[Fields.toUserId] as String? ?? '').trim();
        if (from.isNotEmpty) userIds.add(from);
        if (to.isNotEmpty) userIds.add(to);
      }

      // Batch fetch profiles
      final profilesResult = await _fetchProfilesBatch(userIds.toList());

      if (profilesResult.isError) {
        return Result.error(profilesResult.errorCode, profilesResult.message);
      }

      final profiles = profilesResult.data ?? {};

      // Enrich interests — skip rows whose sender no longer has an active profile.
      final enriched = interests.map((interest) {
        final normalized = InterestIdentityResolver.normalizeInterestRow(interest);
        final docId = InterestIdentityResolver.interestDocumentId(normalized);
        var repairPatch = <String, dynamic>{};
        if (LegacyInterestRepairService.needsSnapshotRepair(normalized)) {
          repairPatch = LegacyInterestRepairService.patchFromProfiles(
            row: normalized,
            profilesByUserId: profiles,
          );
          if (repairPatch.isNotEmpty) {
            LegacyInterestRepairService.schedulePersist(
              interestDocId: docId,
              patch: repairPatch,
            );
          }
        }
        final baseRow = LegacyInterestRepairService.mergeIntoRow(
          normalized,
          repairPatch,
        );
        final fromUserId = baseRow[Fields.fromUserId] as String? ?? '';
        final profile = profileForPeer(profiles, fromUserId);
        if (profile == null) return null;
        final firstName = _mergeInterestField(
          profile[Fields.firstName] as String?,
          baseRow['from_first_name'] as String?,
        );
        final lastName = _mergeInterestField(
          profile[Fields.lastName] as String?,
          baseRow['from_last_name'] as String?,
        );
        final profileId = _mergeInterestField(
          profile[Fields.profileId] as String?,
          baseRow['from_profile_id'] as String?,
        );
        final photoUrl = _mergeInterestField(
          profile[Fields.photoUrl] as String?,
          baseRow['from_photo_url'] as String?,
        );
        final fromCity = _mergeInterestField(
          profile['city'] as String?,
          baseRow['from_city'] as String?,
        );
        final fromState = _mergeInterestField(
          profile['state'] as String?,
          baseRow['from_state'] as String?,
        );
        final fromAge =
            profile[Fields.age] as int? ?? baseRow['from_age'] as int?;
        final createdAt = baseRow[Fields.createdAt];
        final respondedAt = baseRow[Fields.respondedAt];
        final optimisticUpdatedAt = respondedAt ?? createdAt;

        return {
          ...profile,
          // Legacy fields expected by interests screen/widgets.
          'id': baseRow['id'],
          'interestId': baseRow['id'],
          'from_user_id': fromUserId,
          'from_first_name': firstName,
          'from_last_name': lastName,
          'from_profile_id': profileId,
          'from_photo_url': photoUrl,
          'from_city': fromCity,
          'from_state': fromState,
          if (fromAge != null) 'from_age': fromAge,
          'to_user_id': (baseRow[Fields.toUserId] as String? ?? ''),
          Fields.status: baseRow[Fields.status],
          'message': baseRow['message'],
          'viewed_by_recipient': baseRow['viewed_by_recipient'],
          'viewedByRecipient': baseRow['viewedByRecipient'],
          'created_at': createdAt,
          'updated_at': optimisticUpdatedAt,
          Fields.sentAt: baseRow[Fields.createdAt],
          'response_message':
              _interestRowField(baseRow, 'response_message', 'responseMessage'),
          'responseMessage':
              _interestRowField(baseRow, 'response_message', 'responseMessage'),
          'withdrawn_at':
              _interestRowField(baseRow, 'withdrawn_at', 'withdrawnAt'),
          'withdrawnAt':
              _interestRowField(baseRow, 'withdrawn_at', 'withdrawnAt'),
          Fields.respondedAt: baseRow[Fields.respondedAt],
        };
      }).whereType<Map<String, dynamic>>().toList();

      final visible = enriched
          .where(
            (row) =>
                InterestBadgeAggregator.isInterestRowVisible(row['status']),
          )
          .where((row) {
            final n = InterestBadgeAggregator.normalizeInterestStatus(
              row['status'],
            );
            return n != 'rejected' && n != 'cancelled';
          })
          .toList();

      return Result.success(visible);
    });
  }

  /// Stream interests sent by current user.
  ///
  /// See [streamInterestsReceived] for [queryUserDocId].
  Stream<Result<List<Map<String, dynamic>>>> streamInterestsSent({
    String? queryUserDocId,
  }) {
    final hinted = (queryUserDocId ?? '').trim();
    final aliasIds =
        InterestBadgeAggregator.resolveInterestParticipantQueryAliasIds(
      canonicalUserDocId: IdentityProvider.userDocId.trim(),
      queryUserDocIdHint: hinted.isNotEmpty ? hinted : null,
      firebaseAuthUid: fa.FirebaseAuth.instance.currentUser?.uid,
      identityAuthUid: IdentityProvider.authUid.trim().isNotEmpty
          ? IdentityProvider.authUid.trim()
          : null,
    );

    if (aliasIds.isEmpty) {
      return Stream.value(
        Result.error(ErrorCodes.notAuthenticated, 'Not authenticated'),
      );
    }

    final chunks = InterestBadgeAggregator.chunksForFirestoreWhereIn(aliasIds);
    final rawStreams = chunks
        .map(
          (c) => FirestoreRepository.streamQuery(
            Collections.interests,
            conditions: [
              c.length == 1
                  ? QueryCondition.equal(Fields.fromUserId, c.first)
                  : QueryCondition.whereIn(Fields.fromUserId, c),
            ],
            orderBy: Fields.createdAt,
            descending: true,
            includeMetadataChanges: false,
          ),
        )
        .toList();

    return _mergeInterestSnapshotStreams(rawStreams).asyncMap((result) async {
      if (result.isError || result.data == null) {
        return result;
      }

      final rawList = result.data!;
      if (rawList.isEmpty) {
        return Result.success(<Map<String, dynamic>>[]);
      }

      final byDoc = <String, Map<String, dynamic>>{};
      for (final row in rawList) {
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byDoc[id] = row;
      }
      final interests = byDoc.values.toList();

      final userIds = <String>{};
      for (final i in interests) {
        final n = InterestIdentityResolver.normalizeInterestRow(i);
        final from = (n[Fields.fromUserId] as String? ?? '').trim();
        final to = (n[Fields.toUserId] as String? ?? '').trim();
        if (from.isNotEmpty) userIds.add(from);
        if (to.isNotEmpty) userIds.add(to);
      }

      final profilesResult = await _fetchProfilesBatch(userIds.toList());

      if (profilesResult.isError) {
        return Result.error(profilesResult.errorCode, profilesResult.message);
      }

      final profiles = profilesResult.data ?? {};

      final enriched = interests.map((interest) {
        final normalized = InterestIdentityResolver.normalizeInterestRow(interest);
        final docId = InterestIdentityResolver.interestDocumentId(normalized);
        var repairPatch = <String, dynamic>{};
        if (LegacyInterestRepairService.needsSnapshotRepair(normalized)) {
          repairPatch = LegacyInterestRepairService.patchFromProfiles(
            row: normalized,
            profilesByUserId: profiles,
          );
          if (repairPatch.isNotEmpty) {
            LegacyInterestRepairService.schedulePersist(
              interestDocId: docId,
              patch: repairPatch,
            );
          }
        }
        final baseRow = LegacyInterestRepairService.mergeIntoRow(
          normalized,
          repairPatch,
        );
        final toUserId = baseRow[Fields.toUserId] as String? ?? '';
        final profile = profileForPeer(profiles, toUserId);
        if (profile == null) return null;
        final firstName = _mergeInterestField(
          profile[Fields.firstName] as String?,
          baseRow['to_first_name'] as String?,
        );
        final lastName = _mergeInterestField(
          profile[Fields.lastName] as String?,
          baseRow['to_last_name'] as String?,
        );
        final profileId = _mergeInterestField(
          profile[Fields.profileId] as String?,
          baseRow['to_profile_id'] as String?,
        );
        final photoUrl = _mergeInterestField(
          profile[Fields.photoUrl] as String?,
          baseRow['to_photo_url'] as String?,
        );
        final toCity = _mergeInterestField(
          profile['city'] as String?,
          baseRow['to_city'] as String?,
        );
        final toState = _mergeInterestField(
          profile['state'] as String?,
          baseRow['to_state'] as String?,
        );
        final toAge =
            profile[Fields.age] as int? ?? baseRow['to_age'] as int?;
        final createdAt = baseRow[Fields.createdAt];
        final respondedAt = baseRow[Fields.respondedAt];
        final optimisticUpdatedAt = respondedAt ?? createdAt;

        return {
          ...profile,
          'id': baseRow['id'],
          'interestId': baseRow['id'],
          'from_user_id': (baseRow[Fields.fromUserId] as String? ?? ''),
          'to_user_id': toUserId,
          'to_first_name': firstName,
          'to_last_name': lastName,
          'to_profile_id': profileId,
          'to_photo_url': photoUrl,
          'to_city': toCity,
          'to_state': toState,
          if (toAge != null) 'to_age': toAge,
          Fields.status: baseRow[Fields.status],
          'message': baseRow['message'],
          'viewed_by_recipient': baseRow['viewed_by_recipient'],
          'viewedByRecipient': baseRow['viewedByRecipient'],
          'created_at': createdAt,
          'updated_at': optimisticUpdatedAt,
          Fields.sentAt: baseRow[Fields.createdAt],
          'response_message':
              _interestRowField(baseRow, 'response_message', 'responseMessage'),
          'responseMessage':
              _interestRowField(baseRow, 'response_message', 'responseMessage'),
          'withdrawn_at':
              _interestRowField(baseRow, 'withdrawn_at', 'withdrawnAt'),
          'withdrawnAt':
              _interestRowField(baseRow, 'withdrawn_at', 'withdrawnAt'),
          Fields.respondedAt: baseRow[Fields.respondedAt],
        };
      }).whereType<Map<String, dynamic>>().toList();

      final visible = enriched
          .where(
            (row) =>
                InterestBadgeAggregator.isInterestRowVisible(row['status']),
          )
          .toList();

      return Result.success(visible);
    });
  }

  /// Batch fetch profiles using repository
  Future<Result<Map<String, Map<String, dynamic>>>> _fetchProfilesBatch(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return Result.success({});
    }

    try {
      final results = <String, Map<String, dynamic>>{};
      for (final id in userIds) {
        final cached = _interestProfileById[id];
        if (cached != null) {
          results[id] = Map<String, dynamic>.from(cached);
        }
      }
      final missing =
          userIds.where((id) => !results.containsKey(id)).toList();
      if (missing.isEmpty) {
        return Result.success(results);
      }

      final batchSize = InterestBadgeAggregator.firestoreWhereInMax;

      for (var i = 0; i < missing.length; i += batchSize) {
        final batch = missing.sublist(
          i,
          i + batchSize > missing.length ? missing.length : i + batchSize,
        );

        final queryResult = await FirestoreRepository.query(
          Collections.users,
          conditions: [QueryCondition.whereIn(FieldPath.documentId, batch)],
        );

        if (queryResult.isError) {
          return queryResult.map((_) => {});
        }

        for (final doc in queryResult.data ?? []) {
          final id = doc['id'] as String?;
          if (id == null) continue;

          final profile = _extractProfileData(id, doc);
          if (profile != null) {
            results[id] = profile;
            _interestProfileById[id] = profile;
          }
        }

        // Fallback: some rows store auth_uid/profile_id instead of doc id.
        final unresolved =
            batch.where((id) => !results.containsKey(id)).toList();
        for (var j = 0; j < unresolved.length; j += batchSize) {
          final end = j + batchSize > unresolved.length
              ? unresolved.length
              : j + batchSize;
          final slice = unresolved.sublist(j, end);
          final byAuth = await FirestoreRepository.query(
            Collections.users,
            conditions: [QueryCondition.whereIn(Fields.authUid, slice)],
          );
          if (byAuth.isSuccess) {
            for (final doc in byAuth.data ?? []) {
              final id = doc['id'] as String?;
              if (id == null) continue;
              final profile = _extractProfileData(id, doc);
              if (profile == null) continue;
              final authUid = (doc[Fields.authUid] as String? ?? '').trim();
              if (authUid.isNotEmpty) {
                results[authUid] = profile;
                _interestProfileById[authUid] = profile;
              }
              results[id] = profile;
              _interestProfileById[id] = profile;
            }
          }
          final byProfile = await FirestoreRepository.query(
            Collections.users,
            conditions: [QueryCondition.whereIn(Fields.profileId, slice)],
          );
          if (byProfile.isSuccess) {
            for (final doc in byProfile.data ?? []) {
              final id = doc['id'] as String?;
              if (id == null) continue;
              final profile = _extractProfileData(id, doc);
              if (profile == null) continue;
              final profileId = (doc[Fields.profileId] as String? ?? '').trim();
              if (profileId.isNotEmpty) {
                results[profileId] = profile;
                _interestProfileById[profileId] = profile;
              }
              results[id] = profile;
              _interestProfileById[id] = profile;
            }
          }
        }
      }

      return Result.success(results);
    } catch (e) {
      ErrorFirewall.logError(
        e,
        context: 'InterestServiceV2._fetchProfilesBatch',
      );
      return Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Extract profile data from document
  Map<String, dynamic>? _extractProfileData(
    String userId,
    Map<String, dynamic> data,
  ) {
    if (ProfileDeletionService.isUserHiddenFromEngagement(data)) {
      return null;
    }

    final status = (data[Fields.status] as String? ?? '').toLowerCase();
    final profile = data[Fields.profile] as Map<String, dynamic>?;

    String firstName = '';
    String lastName = '';
    String profileId = '';
    String photoUrl = '';
    String city = '';
    String state = '';
    String location = '';
    int? age;

    if (profile != null) {
      firstName = (profile[Fields.firstName] as String?)?.trim() ??
          (profile['firstName'] as String?)?.trim() ??
          '';
      lastName = (profile[Fields.lastName] as String?)?.trim() ??
          (profile['lastName'] as String?)?.trim() ??
          '';
      profileId = (data[Fields.profileId] as String?)?.trim() ??
          (data['profileId'] as String?)?.trim() ??
          '';

      photoUrl = (profile[Fields.profilePicture] as String?)?.trim() ??
          (profile['profilePicture'] as String?)?.trim() ??
          (profile[Fields.photoUrl] as String?)?.trim() ??
          (profile['photoUrl'] as String?)?.trim() ??
          '';

      city = (profile[Fields.city] as String?)?.trim() ??
          (profile['city'] as String?)?.trim() ??
          '';
      state = (profile['state'] as String?)?.trim() ?? '';
      location = city;
      if (location.isEmpty) {
        location = (profile[Fields.location] as String?)?.trim() ??
            (profile['location'] as String?)?.trim() ??
            '';
      }

      final dob = profile[Fields.dateOfBirth] ?? profile['dateOfBirth'];
      if (dob != null) {
        DateTime? dobDate;
        if (dob is Timestamp) {
          dobDate = dob.toDate();
        } else if (dob is String) {
          try {
            dobDate = DateTime.parse(dob);
          } catch (_) {}
        }

        if (dobDate != null) {
          age = DateTime.now().year - dobDate.year;
        }
      }
    } else {
      firstName = (data[Fields.firstName] as String?)?.trim() ??
          (data['firstName'] as String?)?.trim() ??
          '';
      lastName = (data[Fields.lastName] as String?)?.trim() ??
          (data['lastName'] as String?)?.trim() ??
          '';
      profileId = (data[Fields.profileId] as String?)?.trim() ??
          (data['profileId'] as String?)?.trim() ??
          '';
      photoUrl = (data[Fields.photoUrl] as String?)?.trim() ??
          (data['photoUrl'] as String?)?.trim() ??
          '';
      city = (data[Fields.city] as String?)?.trim() ??
          (data['city'] as String?)?.trim() ??
          '';
      state = (data['state'] as String?)?.trim() ?? '';
      location = city;
    }

    return {
      Fields.userId: userId,
      Fields.docId: userId,
      Fields.profileId: profileId,
      Fields.firstName: firstName,
      Fields.lastName: lastName,
      'name': firstName.isNotEmpty
          ? '$firstName ${lastName.isNotEmpty ? lastName : ''}'
          : profileId,
      Fields.photoUrl: photoUrl,
      'city': city,
      'state': state,
      Fields.location: location,
      Fields.age: age,
      Fields.status: status,
    };
  }

  /// Resolve live profile for an interest peer id (doc id, auth uid, or profile_id).
  static Map<String, dynamic>? profileForPeer(
    Map<String, Map<String, dynamic>> profiles,
    String peerId,
  ) {
    final peer = peerId.trim();
    if (peer.isEmpty) return null;
    final direct = profiles[peer];
    if (direct != null) return direct;
    for (final p in profiles.values) {
      final docId =
          (p[Fields.userId] ?? p[Fields.docId] ?? '').toString().trim();
      final profileId = (p[Fields.profileId] ?? '').toString().trim();
      final authUid = (p[Fields.authUid] ?? '').toString().trim();
      if (peer == docId || peer == profileId || peer == authUid) return p;
    }
    return null;
  }

  static String _mergeInterestField(String? live, String? stored) {
    final fromLive = (live ?? '').trim();
    if (fromLive.isNotEmpty) return fromLive;
    return (stored ?? '').trim();
  }

  static Map<String, dynamic> _interestSenderSnapshotFields(
    Map<String, dynamic> profile,
  ) {
    if (profile.isEmpty) return const {};
    final firstName = (profile[Fields.firstName] as String? ?? '').trim();
    final lastName = (profile[Fields.lastName] as String? ?? '').trim();
    final profileId = (profile[Fields.profileId] as String? ?? '').trim();
    final photoUrl = (profile[Fields.photoUrl] as String? ?? '').trim();
    final city = (profile['city'] as String? ?? '').trim();
    final state = (profile['state'] as String? ?? '').trim();
    final age = profile[Fields.age] as int?;
    return {
      if (firstName.isNotEmpty) 'from_first_name': firstName,
      if (lastName.isNotEmpty) 'from_last_name': lastName,
      if (profileId.isNotEmpty) 'from_profile_id': profileId,
      if (photoUrl.isNotEmpty) 'from_photo_url': photoUrl,
      if (city.isNotEmpty) 'from_city': city,
      if (state.isNotEmpty) 'from_state': state,
      if (age != null && age > 0) 'from_age': age,
    };
  }

  static Map<String, dynamic> _interestTargetSnapshotFields(
    Map<String, dynamic> profile,
  ) {
    if (profile.isEmpty) return const {};
    final firstName = (profile[Fields.firstName] as String? ?? '').trim();
    final lastName = (profile[Fields.lastName] as String? ?? '').trim();
    final profileId = (profile[Fields.profileId] as String? ?? '').trim();
    final photoUrl = (profile[Fields.photoUrl] as String? ?? '').trim();
    final city = (profile['city'] as String? ?? '').trim();
    final state = (profile['state'] as String? ?? '').trim();
    final age = profile[Fields.age] as int?;
    return {
      if (firstName.isNotEmpty) 'to_first_name': firstName,
      if (lastName.isNotEmpty) 'to_last_name': lastName,
      if (profileId.isNotEmpty) 'to_profile_id': profileId,
      if (photoUrl.isNotEmpty) 'to_photo_url': photoUrl,
      if (city.isNotEmpty) 'to_city': city,
      if (state.isNotEmpty) 'to_state': state,
      if (age != null && age > 0) 'to_age': age,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Retry Operation Helper (Issue 1 Fix)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Retry an operation with exponential backoff
  Future<Result<T>> _retryOperation<T>(
    Future<Result<T>> Function() operation,
    String context,
  ) async {
    int attempts = 0;

    while (attempts < _maxRetries) {
      attempts++;

      try {
        final result = await operation();

        if (result.isSuccess || result.errorCode != ErrorCodes.networkError) {
          return result;
        }

        if (attempts < _maxRetries) {
          debugPrint('⚠️ Retry $attempts/$_maxRetries for $context');
          await Future.delayed(_retryDelay * attempts);
        }
      } catch (e) {
        if (attempts >= _maxRetries) {
          return Result.error(
            ErrorCodes.unknown,
            'Failed after $attempts attempts: $e',
            rawError: e,
          );
        }
      }
    }

    return Result.error(
      ErrorCodes.networkError,
      'Operation failed after $_maxRetries attempts',
    );
  }
}

/// Provider-facing InterestService API backed by [InterestServiceV2].
class InterestService extends ChangeNotifier {
  static final InterestService _instance = InterestService._internal();
  factory InterestService() => _instance;
  InterestService._internal();

  final _v2Service = InterestServiceV2();
  final InterestHubCache _cache = InterestHubCache();

  StreamSubscription? _sentSub;
  StreamSubscription? _receivedSub;
  StreamSubscription<fa.User?>? _firebaseAuthSub;
  String? _lastFirebaseAuthUidForStreams;
  String _boundIdentityKey = '';

  /// Last [loadInterests] Firestore user doc id — used when interest streams bind
  /// before [IdentityProvider.userDocId] is populated (bell badge / hub accuracy).
  String? _queryUserDocIdHint;

  bool _interestResponseMeansAccept(String raw) {
    final normalized = raw.trim().toLowerCase();
    return normalized == 'accepted' ||
        normalized == 'accept' ||
        normalized == 'approved' ||
        normalized == 'approve' ||
        normalized == 'granted' ||
        normalized == 'grant';
  }

  void _optimisticHideInterestDoc(
    String interestDocId, {
    Map<String, dynamic>? rowHint,
  }) {
    _cache.optimisticHide(interestDocId, rowHint: rowHint);
    notifyListeners();
  }

  void _restoreOptimisticHiddenInterestDoc(
    String interestDocId, {
    Map<String, dynamic>? rowHint,
  }) {
    _cache.restoreHide(interestDocId, rowHint: rowHint);
    notifyListeners();
  }

  void _notifyCacheChanged() {
    _cache.pruneOptimisticHidden();
    notifyListeners();
  }

  /// Immediately show a sent interest before Firestore streams catch up.
  void upsertSentInterestLocal({
    required String interestId,
    required String fromUserId,
    required String toUserId,
    String status = 'pending',
    Map<String, dynamic>? extra,
  }) {
    _cache.upsertSentLocal(
      interestId: interestId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      status: status,
      extra: extra,
    );
    notifyListeners();
  }

  /// Raw sent rows (optimistic hide applied; may include non-visible statuses).
  List<dynamic> get interestsSent => _cache.sent;

  /// Raw received rows (optimistic hide applied).
  List<dynamic> get interestsReceived => _cache.received;

  /// Hub Sent tab + sent badge source of truth.
  List<Map<String, dynamic>> get visibleInterestsSent => _cache.visibleSent;

  /// Hub Received tab + received badge source of truth.
  List<Map<String, dynamic>> get visibleInterestsReceived =>
      _cache.visibleReceived;

  /// Bumps when cache/snapshots/optimistic overlay changes (tab rebuild hint).
  int get hubRevision => _cache.revision;
  String get boundFirestoreUserId => IdentityProvider.userDocId;

  Future<String> _currentUserDocIdOrInitialize() async {
    var userId = IdentityProvider.userDocId.trim();
    if (userId.isNotEmpty) return userId;

    final initResult = await AppInitializer.ensureInitialized();
    if (initResult.isSuccess) {
      userId = IdentityProvider.userDocId.trim();
    }
    return userId;
  }

  Future<void> _notifyInterestReceived({
    required String senderUserId,
    required String receiverId,
  }) async {
    if (receiverId.isEmpty || senderUserId.isEmpty) return;
    try {
      String? fn, ln;
      final snap = await FirestoreRepository.getDocument(
        Collections.users,
        senderUserId,
      );
      if (snap.isSuccess && snap.data != null) {
        final d = snap.data!;
        fn = d[Fields.firstName] as String?;
        ln = d[Fields.lastName] as String?;
        final nested = d[Fields.profile] as Map<String, dynamic>?;
        if ((fn == null || fn.isEmpty) && nested != null) {
          fn = nested[Fields.firstName] as String? ??
              nested['firstName'] as String?;
          ln = nested[Fields.lastName] as String? ??
              nested['lastName'] as String?;
        }
      }
      await NotificationService().sendInterestReceivedNotification(
        toUserId: receiverId,
        fromUserId: senderUserId,
        fromFirstName: fn,
        fromLastName: ln,
      );
    } catch (e) {
      debugPrint('⚠️ _notifyInterestReceived: $e');
    }
  }

  String _identityKey() {
    final doc = IdentityProvider.userDocId.trim();
    final auth = IdentityProvider.authUid.trim();
    final profile = IdentityProvider.profileId.trim();
    final hint = (_queryUserDocIdHint ?? '').trim();
    final firebaseAuth =
        (fa.FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    return '$doc|$auth|$profile|$hint|$firebaseAuth';
  }

  void _bindFirebaseAuthReloader() {
    _firebaseAuthSub ??=
        fa.FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid == _lastFirebaseAuthUidForStreams) return;
      _lastFirebaseAuthUidForStreams = uid;
      _sentSub?.cancel();
      _receivedSub?.cancel();
      _sentSub = null;
      _receivedSub = null;
      _boundIdentityKey = '';
      _cache.clear();
      notifyListeners();
    });
  }

  /// Binds Firestore snapshot listeners (never throttled). Safe to call often.
  Future<void> ensureHubLiveSync(String userDocId) async {
    final trimmed = userDocId.trim();
    if (trimmed.isNotEmpty) {
      _queryUserDocIdHint = trimmed;
    }
    await _currentUserDocIdOrInitialize();
    _ensureLiveStreamsBound();
  }

  void _ensureLiveStreamsBound() {
    _bindFirebaseAuthReloader();
    final nextIdentity = _identityKey();
    final shouldRebind = _sentSub == null ||
        _receivedSub == null ||
        _boundIdentityKey != nextIdentity;
    if (!shouldRebind) return;

    _sentSub?.cancel();
    _receivedSub?.cancel();
    _boundIdentityKey = nextIdentity;

    debugPrint(
      'InterestService: binding live interest streams (hint=$_queryUserDocIdHint)',
    );

    // Seed cache only when empty — live listeners + [loadInterests] also refresh.
    if (_cache.sent.isEmpty && _cache.received.isEmpty) {
      unawaited(
        refreshInterestsFromFirestore(
          userDocId: _queryUserDocIdHint,
          force: true,
        ),
      );
    }

    _sentSub = _v2Service
        .streamInterestsSent(queryUserDocId: _queryUserDocIdHint)
        .listen(
      (result) {
        if (result.isError) {
          debugPrint('❌ interestsSent stream error: ${result.message}');
          return;
        }
        _cache.applySentSnapshot(
          (result.data ?? const <Map<String, dynamic>>[])
              .cast<Map<String, dynamic>>(),
        );
        _notifyCacheChanged();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('❌ interestsSent stream listener error: $e\n$st');
      },
    );

    _receivedSub = _v2Service
        .streamInterestsReceived(queryUserDocId: _queryUserDocIdHint)
        .listen(
      (result) {
        if (result.isError) {
          debugPrint('❌ interestsReceived stream error: ${result.message}');
          return;
        }
        _cache.applyReceivedSnapshot(
          (result.data ?? const <Map<String, dynamic>>[])
              .cast<Map<String, dynamic>>(),
        );
        _notifyCacheChanged();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('❌ interestsReceived stream listener error: $e\n$st');
      },
    );
  }

  Future<Map<String, dynamic>> sendInterest({
    String? userId,
    String? targetUserDocId,
    String? receiverId,
    String? message,
  }) async {
    try {
      final effectiveReceiverId = targetUserDocId ?? receiverId;
      if (effectiveReceiverId == null || effectiveReceiverId.isEmpty) {
        return {
          'success': false,
          'error': 'Missing target user id',
          'errorCode': 'invalid-argument',
        };
      }
      final result = await sendInterestWithResult(
        userId: userId,
        receiverId: effectiveReceiverId,
        message: message,
      );

      if (result['success']) {
        return result;
      } else {
        return {
          'success': false,
          'error': result['error'],
          'errorCode': result['errorCode'],
        };
      }
    } catch (e) {
      debugPrint('❌ InterestService.sendInterest error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sendInterestWithResult({
    String? userId,
    required String receiverId,
    String? message,
  }) async {
    try {
      final senderUserId = userId ?? await _currentUserDocIdOrInitialize();
      if (senderUserId.isEmpty) {
        return {
          'success': false,
          'error': 'Please sign in to send interest',
          'errorCode': 'not-authenticated',
        };
      }
      await ensureHubLiveSync(senderUserId);
      final result = await _v2Service.sendInterest(
        receiverId,
        message: message,
      );

      if (result.isSuccess) {
        final notifyReceiverId =
            (result.data?['receiverDocId'] as String?) ?? receiverId;
        final interestId =
            (result.data?['interestId'] as String?) ??
            '${senderUserId}_$notifyReceiverId';
        final duplicateIgnored = result.data?['duplicateIgnored'] == true;
        upsertSentInterestLocal(
          interestId: interestId,
          fromUserId: senderUserId,
          toUserId: notifyReceiverId,
        );
        // Refresh after a short delay so live streams can include the new doc
        // without wiping the optimistic row with an empty snapshot.
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 800), () {
            refreshInterestsFromFirestore(
              userDocId: senderUserId,
              force: true,
            );
          }),
        );
        // Receiver alert is written server-side in createOrResendInterest.
        return {
          'success': true,
          'interestId': interestId,
          'message': result.message,
          'duplicateIgnored': duplicateIgnored,
        };
      } else {
        return {
          'success': false,
          'error': result.message,
          'errorCode': result.errorCode,
        };
      }
    } catch (e) {
      debugPrint('❌ InterestService.sendInterestWithResult error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getInterestsSent({
    required String userId,
    int limit = 20,
  }) async {
    try {
      final result = await _v2Service
          .streamInterestsSent(queryUserDocId: _queryUserDocIdHint)
          .first;
      if (result.isError) {
        debugPrint('❌ getInterestsSent error: ${result.message}');
        return [];
      }
      return result.data ?? [];
    } catch (e) {
      debugPrint('❌ getInterestsSent exception: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getInterestsReceived({
    required String userId,
    int limit = 20,
  }) async {
    try {
      final result = await _v2Service
          .streamInterestsReceived(queryUserDocId: _queryUserDocIdHint)
          .first;
      if (result.isError) {
        debugPrint('❌ getInterestsReceived error: ${result.message}');
        return [];
      }
      return result.data ?? [];
    } catch (e) {
      debugPrint('❌ getInterestsReceived exception: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> streamInterests({
    required String userId,
    required bool sent,
  }) {
    try {
      final stream = sent
          ? _v2Service.streamInterestsSent(queryUserDocId: _queryUserDocIdHint)
          : _v2Service.streamInterestsReceived(
              queryUserDocId: _queryUserDocIdHint,
            );

      return stream.map((result) {
        if (result.isError) {
          debugPrint('❌ streamInterests error: ${result.message}');
          return <Map<String, dynamic>>[];
        }
        return result.data ?? <Map<String, dynamic>>[];
      });
    } catch (e) {
      debugPrint('❌ streamInterests exception: $e');
      return Stream.value(<Map<String, dynamic>>[]);
    }
  }

  Future<Map<String, dynamic>> withdrawInterest(String interestId) async {
    try {
      final result = await _v2Service.withdrawInterest(interestId);

      if (result.isSuccess) {
        return {'success': true};
      } else {
        return {
          'success': false,
          'error': result.message,
          'errorCode': result.errorCode,
        };
      }
    } catch (e) {
      debugPrint('❌ InterestService.withdrawInterest error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> respondToInterest({
    required String interestId,
    required String response,
    String? message,
  }) async {
    try {
      final normalized = response.trim().toLowerCase();
      final isAccept = normalized == 'accepted' ||
          normalized == 'accept' ||
          normalized == 'approved' ||
          normalized == 'approve' ||
          normalized == 'granted' ||
          normalized == 'grant';

      final result = isAccept
          ? await _v2Service.acceptInterest(
              interestId,
              responseMessage: message,
            )
          : await _v2Service.rejectInterest(
              interestId,
              rejectionReason: message,
            );

      if (result.isSuccess) {
        return {
          'success': true,
          'message': isAccept ? 'Interest accepted' : 'Interest rejected',
        };
      }

      return {
        'success': false,
        'error': result.message,
        'errorCode': result.errorCode,
      };
    } catch (e) {
      debugPrint('❌ InterestService.respondToInterest error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sets [viewed_by_recipient] on the interest document (notifications, hub).
  Future<void> markInterestViewedByRecipient(String interestDocumentId) async {
    final id = interestDocumentId.trim();
    if (id.isEmpty) return;
    try {
      final result = await FirestoreRepository.setDocument(
        Collections.interests,
        id,
        {'viewed_by_recipient': true},
        merge: true,
      );
      if (result.isError) {
        debugPrint(
          '⚠️ InterestService.markInterestViewedByRecipient: ${result.message}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ InterestService.markInterestViewedByRecipient: $e');
    }
  }

  /// Sets [viewed_by_sender] so Sent-tab and bell counts drop after open.
  Future<void> markInterestViewedBySender(String interestDocumentId) async {
    final id = interestDocumentId.trim();
    if (id.isEmpty) return;
    try {
      final result = await FirestoreRepository.setDocument(
        Collections.interests,
        id,
        {'viewed_by_sender': true},
        merge: true,
      );
      if (result.isError) {
        debugPrint(
          '⚠️ InterestService.markInterestViewedBySender: ${result.message}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ InterestService.markInterestViewedBySender: $e');
    }
  }

  String? _lastRefreshUserId;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshFromFirestoreInFlight;
  String? _refreshFromFirestoreInFlightKey;
  Future<void>? _loadInterestsInFlight;
  String? _loadInterestsInFlightKey;

  Future<void> loadInterests(String userId, {bool force = false}) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return;

    final flightKey = '$trimmed|force=$force';
    if (_loadInterestsInFlight != null &&
        _loadInterestsInFlightKey == flightKey) {
      return _loadInterestsInFlight!;
    }

    _loadInterestsInFlightKey = flightKey;
    _loadInterestsInFlight =
        _loadInterestsImpl(trimmed, force: force).whenComplete(() {
      _loadInterestsInFlight = null;
      _loadInterestsInFlightKey = null;
    });
    return _loadInterestsInFlight!;
  }

  Future<void> _loadInterestsImpl(String trimmed, {required bool force}) async {
    try {
      await ensureHubLiveSync(trimmed);

      final now = DateTime.now();
      final hasPoolData =
          _cache.sent.isNotEmpty || _cache.received.isNotEmpty;
      final recentlyRefreshed = _lastRefreshUserId == trimmed &&
          _lastRefreshAt != null &&
          now.difference(_lastRefreshAt!) < const Duration(seconds: 45);

      if (!force && hasPoolData && recentlyRefreshed) {
        return;
      }

      await refreshInterestsFromFirestore(userDocId: trimmed, force: force);
      _lastRefreshUserId = trimmed;
      _lastRefreshAt = now;
      debugPrint('✅ loadInterests completed for $trimmed');
    } catch (e) {
      debugPrint('❌ loadInterests error: $e');
    }
  }

  /// One-shot fetch so Sent/Received tabs and bell badges update even if a stream
  /// snapshot was empty or briefly denied.
  Future<void> refreshInterestsFromFirestore({
    String? userDocId,
    bool force = false,
  }) async {
    final hint = (userDocId ?? _queryUserDocIdHint ?? '').trim();
    final flightKey = '$hint|force=$force';
    if (_refreshFromFirestoreInFlight != null &&
        _refreshFromFirestoreInFlightKey == flightKey) {
      return _refreshFromFirestoreInFlight!;
    }

    _refreshFromFirestoreInFlightKey = flightKey;
    _refreshFromFirestoreInFlight =
        _refreshInterestsFromFirestoreImpl(hint: hint, force: force)
            .whenComplete(() {
      _refreshFromFirestoreInFlight = null;
      _refreshFromFirestoreInFlightKey = null;
    });
    return _refreshFromFirestoreInFlight!;
  }

  Future<void> _refreshInterestsFromFirestoreImpl({
    required String hint,
    required bool force,
  }) async {
    if (hint.isNotEmpty) {
      await ensureHubLiveSync(hint);
    } else {
      await _currentUserDocIdOrInitialize();
      _ensureLiveStreamsBound();
    }

    final trimmedHint = hint;
    final now = DateTime.now();
    if (!force &&
        _lastRefreshUserId == trimmedHint &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 20) &&
        (_cache.sent.isNotEmpty || _cache.received.isNotEmpty)) {
      return;
    }

    Future<Result<List<Map<String, dynamic>>>?> _firstSnapshot(
      Stream<Result<List<Map<String, dynamic>>>> stream,
      String label,
    ) async {
      try {
        return await stream.first.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        debugPrint(
          '⚠️ refreshInterestsFromFirestore: $label timed out (live streams may still update)',
        );
        return null;
      } catch (e) {
        debugPrint('⚠️ refreshInterestsFromFirestore: $label failed: $e');
        return null;
      }
    }

    try {
      final results = await Future.wait([
        _firstSnapshot(
          _v2Service.streamInterestsSent(queryUserDocId: hint),
          'sent',
        ),
        _firstSnapshot(
          _v2Service.streamInterestsReceived(queryUserDocId: hint),
          'received',
        ),
      ]);

      final sent = results[0];
      if (sent != null && !sent.isError && sent.data != null) {
        _cache.applySentSnapshot(sent.data!.cast<Map<String, dynamic>>());
      }

      final received = results[1];
      if (received != null && !received.isError && received.data != null) {
        _cache.applyReceivedSnapshot(
          received.data!.cast<Map<String, dynamic>>(),
        );
      }

      _notifyCacheChanged();
      _lastRefreshUserId =
          trimmedHint.isNotEmpty ? trimmedHint : _lastRefreshUserId;
      _lastRefreshAt = DateTime.now();
    } catch (e) {
      debugPrint('⚠️ refreshInterestsFromFirestore: $e');
    }
  }

  Future<Map<String, dynamic>> withdrawInterestWithResult({
    required String interestId,
  }) async {
    final trimmed = interestId.trim();
    if (trimmed.isEmpty) {
      return {'success': false, 'error': 'Missing interest id'};
    }
    final rowHint = _cache.findRow(trimmed);
    _optimisticHideInterestDoc(trimmed, rowHint: rowHint);
    try {
      final result = await withdrawInterest(trimmed);
      if (result['success'] != true) {
        _restoreOptimisticHiddenInterestDoc(trimmed, rowHint: rowHint);
      } else {
        unawaited(
          refreshInterestsFromFirestore(
            userDocId: _queryUserDocIdHint,
            force: true,
          ),
        );
      }
      return result;
    } catch (e) {
      debugPrint('❌ InterestService.withdrawInterestWithResult error: $e');
      _restoreOptimisticHiddenInterestDoc(trimmed, rowHint: rowHint);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> hideInterestWithResult({
    required String interestId,
  }) async {
    final id = interestId.trim();
    if (id.isEmpty) {
      return {'success': false, 'error': 'Missing interest id'};
    }
    final rowHint = _cache.findRow(id);
    _optimisticHideInterestDoc(id, rowHint: rowHint);
    try {
      final result = await FirestoreRepository.updateDocument(
        Collections.interests,
        id,
        {
          Fields.status: StatusValues.inactive,
          'hidden_at': FieldValue.serverTimestamp(),
          Fields.schemaVersion: 1,
        },
      );
      if (result.isError) {
        _restoreOptimisticHiddenInterestDoc(id, rowHint: rowHint);
        return {
          'success': false,
          'error': result.message,
          'errorCode': result.errorCode,
        };
      }
      return {'success': true};
    } catch (e) {
      _restoreOptimisticHiddenInterestDoc(id, rowHint: rowHint);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> sendInterestReminderForSentRow(String interestId) async {
    try {
      if (interestId.trim().isEmpty) {
        throw Exception('Missing interest ID');
      }

      final interestResult = await FirestoreRepository.getDocument(
        Collections.interests,
        interestId,
      );
      if (interestResult.isError || interestResult.data == null) {
        throw Exception(interestResult.message);
      }

      final row = interestResult.data!;
      final status = (row[Fields.status] as String? ?? '').toLowerCase();
      if (status != StatusValues.pending) {
        throw Exception('Reminder allowed only for pending requests');
      }

      final toUserId = (row[Fields.toUserId] as String? ?? '').trim();
      final fromUserId = (row[Fields.fromUserId] as String? ?? '').trim();
      if (toUserId.isEmpty || fromUserId.isEmpty) {
        throw Exception('Invalid reminder target');
      }

      await NotificationService().addNotification(
        userId: toUserId,
        type: 'interest_reminder',
        title: 'Interest Reminder',
        body: 'You have a pending interest request awaiting your response.',
        data: {
          'interest_id': interestId,
          Fields.fromUserId: fromUserId,
          Fields.toUserId: toUserId,
        },
      );
    } catch (e) {
      debugPrint('❌ InterestService.sendInterestReminderForSentRow error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> respondToInterestWithResult({
    required String interestId,
    required String response,
    String? message,
  }) async {
    final trimmed = interestId.trim();
    final hideOptimistic =
        trimmed.isNotEmpty && !_interestResponseMeansAccept(response);
    final rowHint = hideOptimistic ? _cache.findRow(trimmed) : null;
    if (hideOptimistic) {
      _optimisticHideInterestDoc(trimmed, rowHint: rowHint);
    }
    try {
      final result = await respondToInterest(
        interestId: trimmed,
        response: response,
        message: message,
      );
      if (result['success'] == true) {
        // Drop unread interest_received rows after respond (any outcome).
        unawaited(
          NotificationService()
              .markInterestNotificationsReadForInterest(trimmed),
        );
        unawaited(
          refreshInterestsFromFirestore(
            userDocId: _queryUserDocIdHint,
            force: true,
          ),
        );
      } else if (hideOptimistic) {
        _restoreOptimisticHiddenInterestDoc(trimmed, rowHint: rowHint);
      }
      return result;
    } catch (e) {
      debugPrint('❌ InterestService.respondToInterestWithResult error: $e');
      if (hideOptimistic) {
        _restoreOptimisticHiddenInterestDoc(trimmed, rowHint: rowHint);
      }
      return {'success': false, 'error': e.toString()};
    }
  }
}
