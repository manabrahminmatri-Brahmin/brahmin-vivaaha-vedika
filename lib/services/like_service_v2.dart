// 🔥 LIKE SERVICE V2 - Uses Repository Pattern
// NO direct Firestore calls
// Returns Result<T> for all operations
// Uses AppContract for all field names

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import '../core/app_firebase_functions.dart';
import '../core/contract.dart';
import '../core/result.dart' as app_result;
import '../core/app_identity.dart';
import '../core/app_initializer.dart';
import '../core/firestore_repository.dart';
import '../core/error_firewall.dart';
import '../models/cleanup_result.dart';
import 'engagement_gateway_service.dart';
import 'profile_deletion_service.dart';

/// LikeServiceV2 - Professional service using repository pattern
class LikeServiceV2 {
  static final LikeServiceV2 _instance = LikeServiceV2._internal();
  factory LikeServiceV2() => _instance;
  LikeServiceV2._internal();

  /// Cached profile preview rows keyed by user doc id (speeds Matches tab).
  final Map<String, Map<String, dynamic>> _profilePreviewById = {};

  String? _sentEnrichPeerKey;
  List<Map<String, dynamic>>? _sentEnrichCache;
  String? _recvEnrichPeerKey;
  List<Map<String, dynamic>>? _recvEnrichCache;

  String? _likesStreamIdentityKey;
  Stream<app_result.Result<List<Map<String, dynamic>>>>? _sentLikesBroadcast;
  Stream<app_result.Result<List<Map<String, dynamic>>>>? _recvLikesBroadcast;

  void resetLikeStreamCache() {
    _likesStreamIdentityKey = null;
    _sentLikesBroadcast = null;
    _recvLikesBroadcast = null;
    _sentEnrichPeerKey = null;
    _sentEnrichCache = null;
    _recvEnrichPeerKey = null;
    _recvEnrichCache = null;
  }

  /// Warm profile cache for Matches list tiles (fire-and-forget).
  Future<void> prefetchProfilesForLikes(Iterable<String> userIds) async {
    final ids = userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await fetchProfilesBatch(ids.toList());
  }

  Map<String, dynamic>? cachedProfilePreview(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final hit = _profilePreviewById[id];
    return hit == null ? null : Map<String, dynamic>.from(hit);
  }

  /// 🔥 Backward compatibility: boundFirestoreUserId for old Provider patterns
  String? get boundFirestoreUserId {
    return IdentityProvider.userDocId.isEmpty
        ? null
        : IdentityProvider.userDocId;
  }

  Future<String> _currentUserDocIdOrInitialize() async {
    var userId = IdentityProvider.userDocId.trim();
    if (userId.isNotEmpty) return userId;

    final initResult = await AppInitializer.ensureInitialized();
    if (initResult.isSuccess) {
      userId = IdentityProvider.userDocId.trim();
    }
    return userId;
  }

  /// Firestore rules match user doc id + auth uid only (not profile_id codes).
  Set<String> _currentIdentityAliases() {
    final sessionUid =
        fb_auth.FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    return <String>{
      IdentityProvider.userDocId.trim(),
      IdentityProvider.authUid.trim(),
      if (sessionUid.isNotEmpty) sessionUid,
    }..removeWhere((id) => id.isEmpty);
  }

  int _sortMillis(dynamic ts) {
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is String) {
      return DateTime.tryParse(ts)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  /// Older like docs may only have camelCase keys; queries are per-field.
  static String? _legacyLikeFieldAlias(String identityField) {
    switch (identityField) {
      case Fields.fromUserId:
        return 'fromUserId';
      case Fields.toUserId:
        return 'toUserId';
      default:
        return null;
    }
  }

  Stream<app_result.Result<List<Map<String, dynamic>>>> _streamLikesByAliases({
    required String identityField,
    required Set<String> identityAliases,
  }) {
    // Best-effort per-alias listeners instead of one whereIn query.
    // If one alias is denied by rules, other aliases can still stream.
    final aliases = identityAliases
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toSet()
        .take(10)
        .toList(growable: false);
    if (aliases.isEmpty) {
      return Stream.value(
        app_result.Result.error(
            ErrorCodes.notAuthenticated, 'Not authenticated'),
      );
    }

    final legacyField = _legacyLikeFieldAlias(identityField);
    final controller =
        StreamController<app_result.Result<List<Map<String, dynamic>>>>();
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final latestByKey = <String, QuerySnapshot<Map<String, dynamic>>>{};

    void emitMerged() {
      final byDocId = <String, Map<String, dynamic>>{};
      void addSnap(QuerySnapshot<Map<String, dynamic>> snap) {
        for (final doc in snap.docs) {
          byDocId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
        }
      }
      for (final snap in latestByKey.values) {
        addSnap(snap);
      }

      final list = byDocId.values.toList()
        ..sort(
          (a, b) =>
              _sortMillis(b[Fields.createdAt] ?? b[Fields.updatedAt]).compareTo(
            _sortMillis(a[Fields.createdAt] ?? a[Fields.updatedAt]),
          ),
        );
      if (!controller.isClosed) {
        controller.add(app_result.Result.success(list));
      }
    }

    void onListenError(Object e, String streamKey) {
      debugPrint(
        '❌ likes stream failed for $identityField/$streamKey aliases=$aliases: $e',
      );
      // Permission denied on one alias should not kill Likes tab.
      final msg = e.toString().toLowerCase();
      final isPermissionDenied =
          msg.contains('permission-denied') || msg.contains('insufficient permissions');
      if (isPermissionDenied) {
        latestByKey.remove(streamKey);
        emitMerged();
        return;
      }
      if (!controller.isClosed && latestByKey.isEmpty) {
        controller.add(
          app_result.Result.error(ErrorCodes.unknown, e.toString()),
        );
      }
    }

    controller.onListen = () {
      // Emit early empty state so UI doesn't block while streams attach.
      emitMerged();
      for (final alias in aliases) {
        final primaryKey = '$identityField:$alias';
        final subPrimary = FirebaseFirestore.instance
            .collection(Collections.likes)
            .where(identityField, isEqualTo: alias)
            .snapshots()
            .listen(
              (snap) {
                latestByKey[primaryKey] = snap;
                emitMerged();
              },
              onError: (e) => onListenError(e, primaryKey),
            );
        subs.add(subPrimary);

        if (legacyField != null) {
          final legacyKey = '$legacyField:$alias';
          final subLegacy = FirebaseFirestore.instance
              .collection(Collections.likes)
              .where(legacyField, isEqualTo: alias)
              .snapshots()
              .listen(
                (snap) {
                  latestByKey[legacyKey] = snap;
                  emitMerged();
                },
                onError: (e) => onListenError(e, legacyKey),
              );
          subs.add(subLegacy);
        }
      }
    };

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      subs.clear();
      latestByKey.clear();
    };

    return controller.stream;
  }

  /// Like a user profile
  Future<app_result.Result<Map<String, dynamic>>> likeUser(
    String targetUserDocId,
  ) async {
    try {
      final currentUserId = await _currentUserDocIdOrInitialize();

      if (currentUserId.isEmpty) {
        return app_result.Result.error(
          ErrorCodes.notAuthenticated,
          'Please sign in to like profiles',
        );
      }

      if (targetUserDocId.isEmpty) {
        return app_result.Result.error(
          ErrorCodes.invalidArgument,
          'Invalid target user',
        );
      }

      if (currentUserId == targetUserDocId) {
        return app_result.Result.error(
          ErrorCodes.invalidOperation,
          'You cannot like your own profile',
        );
      }

      final gateway = await EngagementGatewayService.recordLike(
        targetUserId: targetUserDocId,
      );
      if (gateway['success'] != true) {
        final code = (gateway['errorCode'] as String?) ?? ErrorCodes.unknown;
        return app_result.Result.error(
          code,
          (gateway['error'] as String?) ?? 'Failed to like profile',
        );
      }

      final likeDocId =
          (gateway['likeId'] as String?) ?? '${currentUserId}_$targetUserDocId';
      _sentEnrichPeerKey = null;
      _sentEnrichCache = null;
      _recvEnrichPeerKey = null;
      _recvEnrichCache = null;
      return app_result.Result.success({
        'likeId': likeDocId,
        'liked': true,
        'duplicateIgnored': gateway['duplicateIgnored'] == true,
      }, message: 'Profile liked successfully');
    } catch (e) {
      ErrorFirewall.logError(e, context: 'LikeServiceV2.likeUser');
      return app_result.Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Unlike a user
  Future<app_result.Result<void>> unlikeUser(String targetUserDocId) async {
    try {
      final currentUserId = await _currentUserDocIdOrInitialize();

      if (currentUserId.isEmpty) {
        return app_result.Result.error(
          ErrorCodes.notAuthenticated,
          'Please sign in',
        );
      }

      final gateway = await EngagementGatewayService.recordUnlike(
        targetUserId: targetUserDocId,
      );
      if (gateway['success'] != true) {
        return app_result.Result.error(
          (gateway['errorCode'] as String?) ?? ErrorCodes.unknown,
          (gateway['error'] as String?) ?? 'Failed to unlike profile',
        );
      }

      _sentEnrichPeerKey = null;
      _sentEnrichCache = null;
      _recvEnrichPeerKey = null;
      _recvEnrichCache = null;
      return app_result.Result.success(null, message: 'Unliked');
    } catch (e) {
      ErrorFirewall.logError(e, context: 'LikeServiceV2.unlikeUser');
      return app_result.Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  /// Check if current user liked target
  Future<app_result.Result<bool>> hasLiked(String targetUserDocId) async {
    try {
      final currentUserId = IdentityProvider.userDocId;

      if (currentUserId.isEmpty) {
        return app_result.Result.error(
          ErrorCodes.notAuthenticated,
          'Not authenticated',
        );
      }

      final likeDocId = '${currentUserId}_$targetUserDocId';

      final result = await FirestoreRepository.getDocument(
        Collections.likes,
        likeDocId,
      );

      if (result.isError) {
        return result.map((_) => false);
      }

      return app_result.Result.success(result.data != null);
    } catch (e) {
      ErrorFirewall.logError(e, context: 'LikeServiceV2.hasLiked');
      return app_result.Result.error(
        ErrorCodes.unknown,
        ErrorFirewall.toUserMessage(e),
        rawError: e,
      );
    }
  }

  String _likesStreamKey(Set<String> aliases) =>
      aliases.map((a) => a.trim()).where((a) => a.isNotEmpty).join('|');

  Stream<app_result.Result<List<Map<String, dynamic>>>> _sharedLikesStream({
    required bool sent,
    required Set<String> identityAliases,
    required Stream<app_result.Result<List<Map<String, dynamic>>>> Function()
        build,
  }) {
    final identityKey = _likesStreamKey(identityAliases);
    if (_likesStreamIdentityKey != identityKey) {
      _likesStreamIdentityKey = identityKey;
      _sentLikesBroadcast = null;
      _recvLikesBroadcast = null;
    }
    if (sent) {
      return _sentLikesBroadcast ??= build().asBroadcastStream();
    }
    return _recvLikesBroadcast ??= build().asBroadcastStream();
  }

  /// Stream of users who liked current user (received likes)
  Stream<app_result.Result<List<Map<String, dynamic>>>> streamLikesReceived() {
    final currentUserIds = _currentIdentityAliases();

    if (currentUserIds.isEmpty) {
      return Stream.value(
        app_result.Result.error(
          ErrorCodes.notAuthenticated,
          'Not authenticated',
        ),
      );
    }

    return _sharedLikesStream(
      sent: false,
      identityAliases: currentUserIds,
      build: () => _streamLikesByAliases(
        identityField: Fields.toUserId,
        identityAliases: currentUserIds,
      ).asyncMap((result) async {
      if (result.isError || result.data == null) {
        return result;
      }

      final likes = List<Map<String, dynamic>>.from(result.data!)
        ..sort(
          (a, b) => _sortMillis(b[Fields.createdAt] ?? b[Fields.updatedAt])
              .compareTo(
                  _sortMillis(a[Fields.createdAt] ?? a[Fields.updatedAt])),
        );
      if (likes.isEmpty) {
        return app_result.Result.success(<Map<String, dynamic>>[]);
      }

      final enriched = likes.map((like) {
        final fromUserId = (like[Fields.fromUserId] as String? ??
                like['fromUserId'] as String? ??
                '')
            .trim();

        return {
          ...like,
          'likeId': like['id'],
          'likedAt': like[Fields.createdAt],
          Fields.userId: fromUserId,
          Fields.docId: fromUserId,
          Fields.fromUserId: fromUserId,
          Fields.toUserId: like[Fields.toUserId] ?? like['toUserId'],
        };
      }).toList();

      final visible = await _filterLikesWithActiveProfiles(
        enriched,
        peerField: Fields.fromUserId,
        cacheScope: 'received',
      );
      return app_result.Result.success(visible);
    }),
    );
  }

  /// Stream of users current user liked (sent likes)
  /// 🔥 FIX (Bug 2): This method is now stored in State.initState() by
  /// LikedScreenV2 so the same stream instance is reused across rebuilds.
  Stream<app_result.Result<List<Map<String, dynamic>>>> streamLikesSent() {
    final currentUserIds = _currentIdentityAliases();

    if (currentUserIds.isEmpty) {
      return Stream.value(
        app_result.Result.error(
          ErrorCodes.notAuthenticated,
          'Not authenticated',
        ),
      );
    }

    return _sharedLikesStream(
      sent: true,
      identityAliases: currentUserIds,
      build: () => _streamLikesByAliases(
        identityField: Fields.fromUserId,
        identityAliases: currentUserIds,
      ).asyncMap((result) async {
      if (result.isError || result.data == null) {
        return result;
      }

      final likes = List<Map<String, dynamic>>.from(result.data!)
        ..sort(
          (a, b) => _sortMillis(b[Fields.createdAt] ?? b[Fields.updatedAt])
              .compareTo(
                  _sortMillis(a[Fields.createdAt] ?? a[Fields.updatedAt])),
        );
      if (likes.isEmpty) {
        return app_result.Result.success(<Map<String, dynamic>>[]);
      }

      final enriched = likes.map((like) {
        final toUserId = (like[Fields.toUserId] as String? ??
                like['toUserId'] as String? ??
                '')
            .trim();

        return {
          ...like,
          'likeId': like['id'],
          'likedAt': like[Fields.createdAt],
          // 🔥 FIX (Bug 3): Always include the raw user_id from the like
          // document as a guaranteed non-null fallback for navigation and
          // display, even when profile enrichment partially fails.
          Fields.userId: toUserId,
          Fields.docId: toUserId,
          Fields.fromUserId:
              like[Fields.fromUserId] ?? like['fromUserId'],
          Fields.toUserId: toUserId,
        };
      }).toList();

      final visible = await _filterLikesWithActiveProfiles(
        enriched,
        peerField: Fields.toUserId,
        cacheScope: 'sent',
      );
      return app_result.Result.success(visible);
    }),
    );
  }

  String _peerIdFromLike(
    Map<String, dynamic> like, {
    required String peerField,
    required String legacyPeer,
  }) {
    return (like[peerField] ?? like[legacyPeer] ?? '').toString().trim();
  }

  List<Map<String, dynamic>> _mergeProfilePreviewsIntoLikes(
    List<Map<String, dynamic>> likes,
    Map<String, Map<String, dynamic>> profiles, {
    required String peerField,
    required String legacyPeer,
  }) {
    return likes.map((like) {
      final id = _peerIdFromLike(like, peerField: peerField, legacyPeer: legacyPeer);
      final preview = profiles[id];
      if (preview == null || preview.isEmpty) return like;
      return {...like, ...preview};
    }).toList();
  }

  /// Drop deleted peers, merge cached profile previews (name, photo, city).
  Future<List<Map<String, dynamic>>> _filterLikesWithActiveProfiles(
    List<Map<String, dynamic>> likes, {
    required String peerField,
    required String cacheScope,
  }) async {
    if (likes.isEmpty) return likes;
    final legacyPeer = peerField == Fields.fromUserId ? 'fromUserId' : 'toUserId';
    final peerIds = <String>{};
    for (final like in likes) {
      final id = _peerIdFromLike(like, peerField: peerField, legacyPeer: legacyPeer);
      if (id.isNotEmpty) peerIds.add(id);
    }
    if (peerIds.isEmpty) return likes;

    final peerKey = peerIds.toList()..sort();
    final peerFingerprint = '$cacheScope:${peerKey.join('|')}';
    if (cacheScope == 'sent' &&
        _sentEnrichPeerKey == peerFingerprint &&
        _sentEnrichCache != null) {
      return List<Map<String, dynamic>>.from(_sentEnrichCache!);
    }
    if (cacheScope == 'received' &&
        _recvEnrichPeerKey == peerFingerprint &&
        _recvEnrichCache != null) {
      return List<Map<String, dynamic>>.from(_recvEnrichCache!);
    }

    final profiles = await fetchProfilesBatch(peerIds.toList());
    // On total failure, keep likes so the tab does not look empty/broken.
    if (profiles.isError || profiles.data == null) {
      return likes;
    }

    final active = profiles.data!;
    final filtered = likes.where((like) {
      final id = _peerIdFromLike(like, peerField: peerField, legacyPeer: legacyPeer);
      return id.isNotEmpty && active.containsKey(id);
    }).toList();

    final merged = _mergeProfilePreviewsIntoLikes(
      filtered,
      active,
      peerField: peerField,
      legacyPeer: legacyPeer,
    );

    if (cacheScope == 'sent') {
      _sentEnrichPeerKey = peerFingerprint;
      _sentEnrichCache = merged;
    } else if (cacheScope == 'received') {
      _recvEnrichPeerKey = peerFingerprint;
      _recvEnrichCache = merged;
    }
    return merged;
  }

  /// Batch fetch profiles using repository with retry logic
  Future<app_result.Result<Map<String, Map<String, dynamic>>>>
      fetchProfilesBatch(List<String> userIds) async {
    if (userIds.isEmpty) {
      return app_result.Result.success({});
    }

    try {
      final results = <String, Map<String, dynamic>>{};
      final missing = <String>[];
      for (final raw in userIds) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        final cached = _profilePreviewById[id];
        if (cached != null) {
          results[id] = Map<String, dynamic>.from(cached);
        } else {
          missing.add(id);
        }
      }

      const batchSize = 30;

      if (missing.isNotEmpty && kDebugMode) {
        debugPrint(
          '🔍 Fetching ${missing.length}/${userIds.length} profiles (cache hit ${results.length})',
        );
      }

      for (var i = 0; i < missing.length; i += batchSize) {
        final batch = missing.sublist(
          i,
          i + batchSize > missing.length ? missing.length : i + batchSize,
        );

        int retries = 2;
        var batchSuccess = false;

        while (retries > 0 && !batchSuccess) {
          try {
            final queryResult = await FirestoreRepository.query(
              Collections.users,
              conditions: [QueryCondition.whereIn(FieldPath.documentId, batch)],
            );

            if (queryResult.isError) {
              if (queryResult.message.contains('permission-denied') == true) {
                debugPrint(
                  '🔴 PERMISSION DENIED on users collection read. Check Firestore rules!',
                );
                break;
              }
              if (retries > 1) {
                retries--;
                debugPrint(
                  '⚠️ Batch query error (${queryResult.message}), retrying... ($retries left)',
                );
                await Future.delayed(const Duration(milliseconds: 500));
                continue;
              }
              debugPrint(
                '❌ Batch query failed after retries: ${queryResult.message}',
              );
              break;
            }

            for (final doc in queryResult.data ?? []) {
              final id = doc['id'] as String?;
              if (id == null || id.isEmpty) {
                continue;
              }

              try {
                final profile = _extractProfileData(id, doc);
                if (profile != null) {
                  results[id] = profile;
                  _profilePreviewById[id] = profile;
                }
              } catch (e) {
                debugPrint('❌ Error extracting profile $id: $e');
                continue;
              }
            }

            batchSuccess = true;
          } catch (e) {
            retries--;
            if (retries > 0) {
              await Future.delayed(const Duration(milliseconds: 500));
            } else {
              debugPrint('❌ Failed to fetch batch: $e');
            }
          }
        }
      }

      if (kDebugMode && results.isNotEmpty) {
        debugPrint(
          '✅ Profile batch ready ${results.length}/${userIds.length}',
        );
      }
      return app_result.Result.success(results);
    } catch (e, stack) {
      debugPrint('❌ Fatal error in _fetchProfilesBatch: $e');
      debugPrint('Stack: $stack');

      ErrorFirewall.logError(e, context: 'LikeServiceV2._fetchProfilesBatch');
      return app_result.Result.error(
        ErrorCodes.unknown,
        'Failed to load profiles. Please try again.',
        rawError: e,
      );
    }
  }

  /// Check if current user has liked target user
  Future<bool> hasLikedUser(String targetUserId) async {
    try {
      final currentUserId = IdentityProvider.userDocId;

      if (currentUserId.isEmpty) {
        debugPrint('⚠️ LikeServiceV2.hasLikedUser: User not authenticated');
        return false;
      }

      if (targetUserId.isEmpty) {
        debugPrint('⚠️ LikeServiceV2.hasLikedUser: Invalid target user ID');
        return false;
      }

      // Use the canonical like doc key used by likeUser/unlikeUser:
      // likes/{fromUserId}_{toUserId}
      final likeDocId = '${currentUserId}_$targetUserId';
      final doc = await FirebaseFirestore.instance
          .collection(Collections.likes)
          .doc(likeDocId)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('❌ LikeServiceV2.hasLikedUser error: $e');
      return false;
    }
  }

  /// Extract profile data from document with enhanced null safety.
  ///
  /// 🔥 FIX (Bug 3): The original code returned null when firstName, lastName,
  /// AND profileId were all empty. This caused the ...?profile spread in
  /// streamLikesSent() to add nothing to the enriched map, so the liked
  /// profile tile showed blank name, no photo, and no location.
  ///
  /// Now we always return a partial map for any active (non-deleted) user,
  /// using the userId as the last-resort display fallback. Only truly
  /// deleted/inactive accounts return null.
  Map<String, dynamic>? _extractProfileData(
    String userId,
    Map<String, dynamic> data,
  ) {
    String firstName = '';
    String lastName = '';
    String profileId = '';
    String photoUrl = '';
    String location = '';
    String status = '';
    int? age;
    Map<String, dynamic>? profile;

    try {
      if (userId.isEmpty) {
        debugPrint('⚠️ Empty userId provided');
        return null;
      }

      if (data.isEmpty) {
        debugPrint('⚠️ Empty data for userId: $userId');
        return null;
      }

      if (ProfileDeletionService.isUserHiddenFromEngagement(data)) {
        debugPrint('⚠️ User $userId hidden (deleted, grace deletion, or inactive)');
        return null;
      }
      status = (data[Fields.status] as String? ?? '').toLowerCase();

      profile = data[Fields.profile] as Map<String, dynamic>?;

      if (profile != null && profile.isNotEmpty) {
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
            '';
        if (photoUrl.isEmpty) {
          photoUrl = (profile[Fields.photoUrl] as String?)?.trim() ??
              (profile['photoUrl'] as String?)?.trim() ??
              '';
        }

        location = (profile[Fields.location] as String?)?.trim() ??
            (profile['location'] as String?)?.trim() ??
            '';
        if (location.isEmpty) {
          location = (profile[Fields.city] as String?)?.trim() ??
              (profile['city'] as String?)?.trim() ??
              '';
        }

        final dob = profile[Fields.dateOfBirth] ?? profile['dateOfBirth'];
        if (dob != null) {
          try {
            DateTime? dobDate;
            if (dob is Timestamp) {
              dobDate = dob.toDate();
            } else if (dob is String && dob.isNotEmpty) {
              dobDate = DateTime.tryParse(dob);
            }

            if (dobDate != null) {
              final now = DateTime.now();
              age = now.year - dobDate.year;
              if (now.month < dobDate.month ||
                  (now.month == dobDate.month && now.day < dobDate.day)) {
                age = age - 1;
              }

              if (age < 18 || age > 100) {
                debugPrint('⚠️ Invalid age calculated: $age for user $userId');
                age = null;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error calculating age for $userId: $e');
            age = null;
          }
        }
      } else {
        // Flat root-level fallback
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
        location = (data[Fields.city] as String?)?.trim() ??
            (data['city'] as String?)?.trim() ??
            '';
      }
    } catch (e, stack) {
      debugPrint('❌ Error in _extractProfileData for $userId: $e');
      debugPrint('Stack: $stack');
      // Return null only on unrecoverable exception — don't silently drop data.
      return null;
    }

    // 🔥 FIX (Bug 3): Always return a map for active users. If name fields are
    // empty, use profileId then userId as the display name — the tile will
    // show something meaningful rather than nothing.
    final displayName = firstName.isNotEmpty
        ? '$firstName ${lastName.isNotEmpty ? lastName : ''}'.trim()
        : profileId.isNotEmpty
            ? profileId
            : userId; // last resort — at least something is shown

    return {
      Fields.userId: userId,
      Fields.docId: userId,
      Fields.profileId: profileId,
      Fields.firstName: firstName,
      Fields.lastName: lastName,
      'name': displayName,
      Fields.photoUrl: photoUrl,
      Fields.city: location,
      Fields.age: age,
      Fields.status: status,
    };
  }
}

/// Provider-facing LikeService API backed by [LikeServiceV2].
class LikeService extends ChangeNotifier {
  static final LikeService _instance = LikeService._internal();
  factory LikeService() => _instance;
  LikeService._internal() {
    // [boundFirestoreUserId] reads [IdentityProvider] but is not a stored field.
    // Without this, `context.select<LikeService, String>(boundFirestoreUserId)`
    // never rebuilds when identity loads after cold start.
    IdentityProvider.addListener(_onIdentityChanged);
  }

  void _onIdentityChanged(AppIdentity? _) {
    _v2Service.resetLikeStreamCache();
    _lastLikesCacheKey = null;
    _youLikedFingerprint = '';
    _likedYouFingerprint = '';
    Future.microtask(notifyListeners);
  }

  final _v2Service = LikeServiceV2();
  String? _lastLikesCacheKey;
  List<Map<String, dynamic>> _lastYouLiked = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _lastLikedYou = <Map<String, dynamic>>[];
  String _youLikedFingerprint = '';
  String _likedYouFingerprint = '';

  static String _likesListFingerprint(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    final ids = <String>[];
    for (final row in rows) {
      ids.add(
        (row['id'] ??
                row['user_id'] ??
                row['doc_id'] ??
                row['to_user_id'] ??
                row['from_user_id'] ??
                '')
            .toString(),
      );
    }
    ids.sort();
    return '${rows.length}:${ids.join('|')}';
  }

  void _notifyIfLikesChanged({
    required bool sent,
    required List<Map<String, dynamic>> next,
    String? queryError,
  }) {
    final fp = _likesListFingerprint(next);
    final errChanged = sent
        ? _youLikedQueryError != queryError
        : _likedYouQueryError != queryError;
    final prevFp = sent ? _youLikedFingerprint : _likedYouFingerprint;
    if (!errChanged && fp == prevFp) return;
    if (sent) {
      _youLikedFingerprint = fp;
      _youLikedQueryError = queryError;
      _lastYouLiked = List<Map<String, dynamic>>.from(next);
    } else {
      _likedYouFingerprint = fp;
      _likedYouQueryError = queryError;
      _lastLikedYou = List<Map<String, dynamic>>.from(next);
    }
    notifyListeners();
  }

  /// Last Firestore/query failure for sent-likes stream (UI may show retry).
  String? _youLikedQueryError;
  String? _likedYouQueryError;
  String? get youLikedQueryError => _youLikedQueryError;
  String? get likedYouQueryError => _likedYouQueryError;

  String get boundFirestoreUserId => IdentityProvider.userDocId;

  void _ensureLikesCacheForCurrentIdentity() {
    final key = [
      IdentityProvider.userDocId.trim(),
      IdentityProvider.authUid.trim(),
      IdentityProvider.profileId.trim(),
    ].where((id) => id.isNotEmpty).join('|');
    if (key.isEmpty || _lastLikesCacheKey == key) return;
    _lastLikesCacheKey = key;
    _lastYouLiked = <Map<String, dynamic>>[];
    _lastLikedYou = <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> likeProfile({
    required String targetUserId,
  }) async {
    try {
      final result = await _v2Service.likeUser(targetUserId);

      if (result.isSuccess) {
        return result.data ?? {'success': true};
      } else {
        return {
          'success': false,
          'error': result.message,
          'errorCode': result.errorCode,
        };
      }
    } catch (e) {
      debugPrint('❌ LikeService.likeProfile error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> unlikeProfile({
    required String targetUserId,
  }) async {
    try {
      final result = await _v2Service.unlikeUser(targetUserId);

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
      debugPrint('❌ LikeService.unlikeProfile error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getProfilesLiked({
    required String userId,
    int limit = 20,
    DocumentSnapshot? lastDoc,
  }) async {
    try {
      final result = await _v2Service.streamLikesSent().first;
      if (result.isError) {
        debugPrint('❌ getProfilesLiked error: ${result.message}');
        return [];
      }
      return result.data ?? [];
    } catch (e) {
      debugPrint('❌ getProfilesLiked exception: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> streamLikes({
    required String userId,
    required bool sent,
  }) {
    try {
      if (sent) {
        return _v2Service.streamLikesSent().map((result) {
          if (result.isSuccess) {
            _notifyIfLikesChanged(
              sent: true,
              next: result.data ?? <Map<String, dynamic>>[],
              queryError: null,
            );
            return result.data ?? [];
          }
          final msg = '${result.errorCode}: ${result.message}';
          _notifyIfLikesChanged(
            sent: true,
            next: _lastYouLiked,
            queryError: msg,
          );
          debugPrint('LIKE STREAM ERROR sent streamLikes: $msg');
          return <Map<String, dynamic>>[];
        });
      } else {
        return _v2Service.streamLikesReceived().map((result) {
          if (result.isSuccess) {
            _notifyIfLikesChanged(
              sent: false,
              next: result.data ?? <Map<String, dynamic>>[],
              queryError: null,
            );
            return result.data ?? [];
          }
          final msg = '${result.errorCode}: ${result.message}';
          _notifyIfLikesChanged(
            sent: false,
            next: _lastLikedYou,
            queryError: msg,
          );
          debugPrint('LIKE STREAM ERROR received streamLikes: $msg');
          return <Map<String, dynamic>>[];
        });
      }
    } catch (e) {
      debugPrint('❌ LikeService.streamLikes error: $e');
      return Stream.value([]);
    }
  }

  Future<bool> isProfileLiked(String targetUserId) async {
    try {
      final result = await _v2Service.streamLikesSent().first;
      if (result.isError) {
        debugPrint('❌ isProfileLiked error: ${result.message}');
        return false;
      }
      final likes = result.data ?? <Map<String, dynamic>>[];
      return likes.any((like) {
        final id = (like['user_id'] ??
                like['doc_id'] ??
                like['to_user_id'] ??
                like['target_user_id'] ??
                '')
            .toString();
        return id == targetUserId;
      });
    } catch (e) {
      debugPrint('❌ isProfileLiked exception: $e');
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> getYouLiked() async* {
    try {
      await _v2Service._currentUserDocIdOrInitialize();
      _ensureLikesCacheForCurrentIdentity();
      notifyListeners();
      if (_lastYouLiked.isNotEmpty) {
        yield List<Map<String, dynamic>>.from(_lastYouLiked);
      }
      yield* _v2Service.streamLikesSent().map((result) {
        if (result.isError) {
          final msg = '${result.errorCode}: ${result.message}';
          _notifyIfLikesChanged(
            sent: true,
            next: _lastYouLiked,
            queryError: msg,
          );
          debugPrint('LIKE STREAM ERROR getYouLiked: $msg');
          return List<Map<String, dynamic>>.from(_lastYouLiked);
        }
        final next = List<Map<String, dynamic>>.from(
          result.data ?? <Map<String, dynamic>>[],
        );
        _notifyIfLikesChanged(sent: true, next: next, queryError: null);
        debugPrint('LIKE STREAM READY sent=${_lastYouLiked.length}');
        return _lastYouLiked;
      });
    } catch (e) {
      debugPrint('❌ getYouLiked exception: $e');
      yield _lastYouLiked;
    }
  }

  Stream<List<Map<String, dynamic>>> getLikedYou() async* {
    try {
      await _v2Service._currentUserDocIdOrInitialize();
      _ensureLikesCacheForCurrentIdentity();
      notifyListeners();
      if (_lastLikedYou.isNotEmpty) {
        yield List<Map<String, dynamic>>.from(_lastLikedYou);
      }
      yield* _v2Service.streamLikesReceived().map((result) {
        if (result.isError) {
          final msg = '${result.errorCode}: ${result.message}';
          _notifyIfLikesChanged(
            sent: false,
            next: _lastLikedYou,
            queryError: msg,
          );
          debugPrint('LIKE STREAM ERROR getLikedYou: $msg');
          return List<Map<String, dynamic>>.from(_lastLikedYou);
        }
        final next = List<Map<String, dynamic>>.from(
          result.data ?? <Map<String, dynamic>>[],
        );
        _notifyIfLikesChanged(sent: false, next: next, queryError: null);
        debugPrint('LIKE STREAM READY received=${_lastLikedYou.length}');
        return _lastLikedYou;
      });
    } catch (e) {
      debugPrint('❌ getLikedYou exception: $e');
      yield _lastLikedYou;
    }
  }

  /// Mutual matches = intersection of profiles you liked and who liked you.
  /// Not the same as sent-likes only (previous bug). Emits when either list updates.
  /// Note: creates two Firestore listeners — prefer deriving mutual in UI from
  /// [getYouLiked] + [getLikedYou] to avoid duplicate reads when those run anyway.
  Stream<List<Map<String, dynamic>>> getMatches() {
    final controller = StreamController<List<Map<String, dynamic>>>();
    StreamSubscription<app_result.Result<List<Map<String, dynamic>>>>? subSent;
    StreamSubscription<app_result.Result<List<Map<String, dynamic>>>>? subRecv;
    var sent = <Map<String, dynamic>>[];
    var recv = <Map<String, dynamic>>[];

    void emit() {
      final mutual = LikeService.mutualLikeRows(sent: sent, received: recv);
      if (!controller.isClosed) {
        controller.add(mutual);
        debugPrint('LIKE STREAM getMatches mutual count=${mutual.length}');
      }
    }

    controller.onListen = () {
      subSent = _v2Service.streamLikesSent().listen((r) {
        if (r.isSuccess) {
          sent = List<Map<String, dynamic>>.from(r.data ?? []);
          emit();
        } else {
          debugPrint('LIKE STREAM ERROR getMatches sent: ${r.message}');
        }
      }, onError: (e, _) => debugPrint('LIKE STREAM ERROR getMatches sent: $e'));
      subRecv = _v2Service.streamLikesReceived().listen((r) {
        if (r.isSuccess) {
          recv = List<Map<String, dynamic>>.from(r.data ?? []);
          emit();
        } else {
          debugPrint('LIKE STREAM ERROR getMatches recv: ${r.message}');
        }
      }, onError: (e, _) => debugPrint('LIKE STREAM ERROR getMatches recv: $e'));
    };
    controller.onCancel = () {
      subSent?.cancel();
      subRecv?.cancel();
    };
    return controller.stream;
  }

  /// Normalized mutual rows: `otherUserId` → enriched map from sent list if present else received.
  static List<Map<String, dynamic>> mutualLikeRows({
    required List<Map<String, dynamic>> sent,
    required List<Map<String, dynamic>> received,
  }) {
    String norm(String? v) => (v ?? '').trim().toLowerCase();

    String otherFromSent(Map<String, dynamic> m) => (m['user_id'] ??
            m['doc_id'] ??
            m['to_user_id'] ??
            m['toUserId'] ??
            m['uid'] ??
            m['id'] ??
            '')
        .toString();

    String otherFromRecv(Map<String, dynamic> m) => (m['user_id'] ??
            m['doc_id'] ??
            m['from_user_id'] ??
            m['fromUserId'] ??
            m['uid'] ??
            m['id'] ??
            '')
        .toString();

    final sentByNorm = <String, Map<String, dynamic>>{};
    for (final m in sent) {
      final id = otherFromSent(m);
      if (id.isEmpty) continue;
      sentByNorm[norm(id)] = m;
    }
    final out = <Map<String, dynamic>>[];
    for (final m in received) {
      final id = otherFromRecv(m);
      if (id.isEmpty) continue;
      final k = norm(id);
      if (sentByNorm.containsKey(k)) {
        out.add(sentByNorm[k]!);
      }
    }
    return out;
  }

  Future<void> unlikeUser({required String targetUserId}) async {
    try {
      await unlikeProfile(targetUserId: targetUserId);
    } catch (e) {
      debugPrint('❌ LikeService.unlikeUser error: $e');
    }
  }

  Future<bool> hasLikedUser(String targetUserId) async {
    return await _v2Service.hasLikedUser(targetUserId);
  }

  Future<void> toggleLike(String targetUserId) async {
    try {
      final isLiked = await hasLikedUser(targetUserId);
      if (isLiked) {
        await unlikeProfile(targetUserId: targetUserId);
      } else {
        await likeProfile(targetUserId: targetUserId);
      }
    } catch (e) {
      debugPrint('❌ LikeService.toggleLike error: $e');
    }
  }

  bool _isCorruptedLikeDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final fromUserId = (data[Fields.fromUserId] as String? ?? '').trim();
    final toUserId = (data[Fields.toUserId] as String? ?? '').trim();
    if (fromUserId.isEmpty || toUserId.isEmpty) return true;

    return doc.id != '${fromUserId}_$toUserId';
  }

  Future<DataIntegrityReport> validateCurrentUserLikeData() async {
    final identities = <String>{
      IdentityProvider.userDocId.trim(),
      IdentityProvider.authUid.trim(),
      IdentityProvider.profileId.trim(),
    }..removeWhere((id) => id.isEmpty);

    if (identities.isEmpty) {
      return DataIntegrityReport(
        isValid: false,
        issue: 'No authenticated user identity available',
        corruptedDocuments: 0,
        validDocuments: 0,
        affectedDocIds: const [],
      );
    }

    final snapshot =
        await FirebaseFirestore.instance.collection(Collections.likes).get();
    var validDocuments = 0;
    final affectedDocIds = <String>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fromUserId = (data[Fields.fromUserId] as String? ?? '').trim();
      final toUserId = (data[Fields.toUserId] as String? ?? '').trim();
      if (!identities.contains(fromUserId) && !identities.contains(toUserId)) {
        continue;
      }

      if (_isCorruptedLikeDoc(doc)) {
        affectedDocIds.add(doc.id);
      } else {
        validDocuments++;
      }
    }

    return DataIntegrityReport(
      isValid: affectedDocIds.isEmpty,
      issue: affectedDocIds.isEmpty ? null : 'Corrupted like documents found',
      corruptedDocuments: affectedDocIds.length,
      validDocuments: validDocuments,
      affectedDocIds: affectedDocIds,
    );
  }

  Future<CleanupResult> cleanupCorruptedLikeData() async {
    final snapshot =
        await FirebaseFirestore.instance.collection(Collections.likes).get();
    var validDocuments = 0;
    var corruptedDocuments = 0;
    var deletedDocuments = 0;

    WriteBatch? batch = FirebaseFirestore.instance.batch();
    var pendingDeletes = 0;

    Future<void> commitBatch() async {
      if (pendingDeletes == 0 || batch == null) return;
      await batch!.commit();
      deletedDocuments += pendingDeletes;
      batch = FirebaseFirestore.instance.batch();
      pendingDeletes = 0;
    }

    for (final doc in snapshot.docs) {
      if (_isCorruptedLikeDoc(doc)) {
        corruptedDocuments++;
        batch!.delete(doc.reference);
        pendingDeletes++;
        if (pendingDeletes >= 450) {
          await commitBatch();
        }
      } else {
        validDocuments++;
      }
    }

    await commitBatch();

    return CleanupResult(
      totalDocuments: snapshot.docs.length,
      validDocuments: validDocuments,
      corruptedDocuments: corruptedDocuments,
      deletedDocuments: deletedDocuments,
    );
  }
}
