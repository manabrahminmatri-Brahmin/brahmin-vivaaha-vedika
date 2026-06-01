import 'package:cloud_firestore/cloud_firestore.dart';

/// A single page of Firestore query results.
class FirestorePage<T> {
  FirestorePage({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });

  final List<T> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;
}

