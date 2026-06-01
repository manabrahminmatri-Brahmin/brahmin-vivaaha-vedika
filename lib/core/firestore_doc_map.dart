import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts Firestore snapshot data to a plain Dart [Map] (web-safe).
///
/// On Flutter web, [DocumentSnapshot.data] may return a JS interop object where
/// `Map.from` and map spread (`{...data}`) throw `row[$_get]` / `other[$forEach]`.
Map<String, dynamic> normalizeFirestoreMap(dynamic raw) {
  if (raw == null) return <String, dynamic>{};
  if (raw is Map<String, dynamic>) {
    return _copyMap(raw);
  }
  if (raw is Map) {
    return _copyMap(Map<String, dynamic>.from(raw));
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _copyMap(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    out[key] = _normalizeFirestoreValue(value);
  });
  return out;
}

dynamic _normalizeFirestoreValue(dynamic value) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is Timestamp ||
      value is DateTime) {
    return value;
  }
  if (value is Map) {
    return normalizeFirestoreMap(value);
  }
  if (value is List) {
    return value.map(_normalizeFirestoreValue).toList();
  }
  return value;
}

/// Row map with document id (safe on web).
Map<String, dynamic> firestoreRowFromDoc(DocumentSnapshot doc) {
  final data = normalizeFirestoreMap(doc.data());
  return <String, dynamic>{'id': doc.id, ...data};
}

/// Birth / community access request row (composite doc id fallback).
Map<String, dynamic> accessRequestRowFromDoc(QueryDocumentSnapshot doc) {
  final row = firestoreRowFromDoc(doc);
  final requester = (row['requester_id'] as String? ?? '').trim();
  final owner = (row['owner_id'] as String? ?? '').trim();
  if ((requester.isEmpty || owner.isEmpty) && doc.id.contains('_')) {
    final parts = doc.id.split('_');
    if (parts.length >= 2) {
      row['requester_id'] =
          requester.isEmpty ? parts.first.trim() : requester;
      row['owner_id'] =
          owner.isEmpty ? parts.sublist(1).join('_').trim() : owner;
    }
  }
  return row;
}

/// Photo access request row (`from_user_id` / `to_user_id` + composite id).
Map<String, dynamic> photoRequestRowFromDoc(QueryDocumentSnapshot doc) {
  final row = firestoreRowFromDoc(doc);
  final from = (row['from_user_id'] as String? ?? '').trim();
  final to = (row['to_user_id'] as String? ?? '').trim();
  if ((from.isEmpty || to.isEmpty) && doc.id.contains('_')) {
    final parts = doc.id.split('_');
    if (parts.length >= 2) {
      row['from_user_id'] = from.isEmpty ? parts.first.trim() : from;
      row['to_user_id'] =
          to.isEmpty ? parts.sublist(1).join('_').trim() : to;
    }
  }
  return row;
}

/// Tags a row for [AccessRequestVisibility] without map spread on web.
Map<String, dynamic> tagPrivacyKind(
  Map<String, dynamic> row,
  String kind,
) {
  final copy = Map<String, dynamic>.from(normalizeFirestoreMap(row));
  copy['_privacy_kind'] = kind;
  return copy;
}
