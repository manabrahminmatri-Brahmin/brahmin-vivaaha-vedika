import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads that prefer the local Firestore persistence cache, then fall back to
/// the network when the document is not available locally.
///
/// Use for **low-churn** data (own profile fields, membership summary, static
/// config). Keep normal [DocumentReference.get] / query `.get()` for feeds,
/// interests, messages, and anything that must be fresh on every open.
Future<DocumentSnapshot<Map<String, dynamic>>> getDocumentCachedFirst(
  DocumentReference<Map<String, dynamic>> ref,
) async {
  try {
    final cached =
        await ref.get(const GetOptions(source: Source.cache));
    if (cached.exists) return cached;
  } on FirebaseException {
    // e.g. unavailable, failed-precondition — no usable cache entry.
  } catch (_) {}
  return ref.get();
}

/// Same strategy for one-shot queries (e.g. subscription plans, membership list).
Future<QuerySnapshot<Map<String, dynamic>>> getQueryCachedFirst(
  Query<Map<String, dynamic>> query,
) async {
  try {
    return await query.get(const GetOptions(source: Source.cache));
  } on FirebaseException {
    // No cached index results yet.
  } catch (_) {}
  return query.get();
}
