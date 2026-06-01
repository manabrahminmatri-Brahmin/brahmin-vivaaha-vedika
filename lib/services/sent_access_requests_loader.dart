import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/backend/firestore_service.dart';
import '../core/firestore_doc_map.dart';
import 'access_request_visibility.dart';
import 'birth_details_service.dart';
import 'community_reference_service.dart';

/// Loads sent birth / community / photo access requests across user id aliases.
abstract final class SentAccessRequestsLoader {
  SentAccessRequestsLoader._();

  static const Duration _cacheTtl = Duration(seconds: 45);

  static String? _cacheKey;
  static DateTime? _cachedAt;
  static Map<String, List<Map<String, dynamic>>>? _cachedResult;
  static Future<Map<String, List<Map<String, dynamic>>>>? _inFlight;
  static String? _inFlightKey;

  static Future<Map<String, List<Map<String, dynamic>>>> loadAll({
    required List<String> requesterAliasIds,
    bool force = false,
  }) async {
    final aliases = requesterAliasIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (aliases.isEmpty) {
      return _emptyResult();
    }

    final key = aliases.join('\u0001');
    final now = DateTime.now();
    if (!force &&
        _cacheKey == key &&
        _cachedResult != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return _cachedResult!;
    }

    if (!force && _inFlight != null && _inFlightKey == key) {
      return _inFlight!;
    }

    _inFlightKey = key;
    _inFlight = () async {
      try {
        final data = await _loadAllUncached(aliases);
        _cacheKey = key;
        _cachedAt = DateTime.now();
        _cachedResult = data;
        return data;
      } catch (e, st) {
        debugPrint('❌ SentAccessRequestsLoader.loadAll: $e\n$st');
        // Do not cache failures — a later refresh after auth/session ready must refetch.
        rethrow;
      } finally {
        _inFlight = null;
        _inFlightKey = null;
      }
    }();

    return _inFlight!;
  }

  static void invalidateCache() {
    _cacheKey = null;
    _cachedAt = null;
    _cachedResult = null;
    AccessRequestVisibility.invalidateCache();
  }

  static Map<String, List<Map<String, dynamic>>> _emptyResult() => {
        'birth': <Map<String, dynamic>>[],
        'community': <Map<String, dynamic>>[],
        'photo': <Map<String, dynamic>>[],
      };

  static Future<Map<String, List<Map<String, dynamic>>>> _loadAllUncached(
    List<String> aliases,
  ) async {
    final birth = await _mergeByDocId(
      aliases,
      (id) => BirthDetailsService().getSentRequestsForRequester(id),
      'birth',
    );
    final community = await _mergeByDocId(
      aliases,
      (id) => CommunityReferenceService().getSentRequestsForRequester(id),
      'community',
    );
    final photo = await _mergeByDocId(
      aliases,
      (id) => FirestoreService().getPhotoRequestsSent(id),
      'photo',
    );
    final birthVisible = await AccessRequestVisibility.filterOutgoingRows(
      birth.map((r) => tagPrivacyKind(r, 'birth')).toList(),
    );
    final communityVisible = await AccessRequestVisibility.filterOutgoingRows(
      community.map((r) => tagPrivacyKind(r, 'community')).toList(),
    );
    final photoVisible = await AccessRequestVisibility.filterOutgoingRows(
      photo.map((r) => tagPrivacyKind(r, 'photo')).toList(),
    );
    return {
      'birth': birthVisible,
      'community': communityVisible,
      'photo': photoVisible,
    };
  }

  static Future<List<Map<String, dynamic>>> _mergeByDocId(
    List<String> aliasIds,
    Future<List<Map<String, dynamic>>> Function(String id) load,
    String label,
  ) async {
    final byId = <String, Map<String, dynamic>>{};
    for (final id in aliasIds) {
      try {
        final rows = await load(id);
        for (final row in rows) {
          final safe = normalizeFirestoreMap(row);
          final docId = (safe['id'] as String? ?? '').trim();
          if (docId.isEmpty) continue;
          byId[docId] = safe;
        }
      } catch (e) {
        debugPrint('⚠️ SentAccessRequestsLoader.$label alias=$id: $e');
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      int ms(Map<String, dynamic> m) {
        for (final key in ['updated_at', 'created_at']) {
          final v = m[key];
          if (v == null) continue;
          if (v is Timestamp) return v.millisecondsSinceEpoch;
          if (v is DateTime) return v.millisecondsSinceEpoch;
          if (v is String) {
            return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
          }
        }
        return 0;
      }

      return ms(b).compareTo(ms(a));
    });
    return list;
  }
}
