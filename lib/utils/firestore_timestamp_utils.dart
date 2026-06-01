import 'package:cloud_firestore/cloud_firestore.dart';

/// Milliseconds since epoch for Firestore [Timestamp], ISO [String], or [DateTime].
int firestoreFieldMillis(dynamic value) {
  if (value == null) return 0;
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  if (value is String) {
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}

/// Newest activity first: prefers [updated_at], then [created_at].
int requestRowActivityMillis(Map<String, dynamic> row) {
  final updated = firestoreFieldMillis(row['updated_at']);
  if (updated > 0) return updated;
  return firestoreFieldMillis(row['created_at']);
}

int compareRequestRowsNewestFirst(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) =>
    requestRowActivityMillis(b).compareTo(requestRowActivityMillis(a));
