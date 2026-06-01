// FirestoreClient — thin wrapper around FirebaseFirestore.
// Used by NotificationRepository and other data-layer classes.
// Deprecated: prefer FirestoreRepository for new code.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

@Deprecated('Use FirestoreRepository instead')
class FirestoreClient {
  static final FirestoreClient _instance = FirestoreClient._internal();
  factory FirestoreClient() => _instance;
  FirestoreClient._internal();

  /// The underlying Firestore instance (public so callers can call
  /// `_client.db.batch()`, `_client.db.collection()`, etc.).
  final FirebaseFirestore db = FirebaseFirestore.instance;

  CollectionReference collection(String path) => db.collection(path);
  DocumentReference  doc(String path)        => db.doc(path);

  // ── Auth guard ─────────────────────────────────────────────────────────────

  /// Waits until Firebase Auth has a signed-in user, then returns.
  /// If a user is already signed in this returns immediately.
  /// Throws a [TimeoutException] after 15 s if no auth arrives.
  Future<void> ensureAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance
        .authStateChanges()
        .firstWhere((u) => u != null)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'FirestoreClient.ensureAuth: timed out waiting for auth.',
          ),
        );
  }

  // ── Timeout helper ─────────────────────────────────────────────────────────

  /// Wraps [future] with a [timeout] duration.
  /// Re-throws the original error on failure; throws [TimeoutException] on
  /// timeout (the caller can decide whether to catch it).
  Future<T> withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
  }) =>
      future.timeout(timeout);
}
