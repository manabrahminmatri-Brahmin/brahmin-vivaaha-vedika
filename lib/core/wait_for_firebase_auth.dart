import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Cold start: [FirebaseAuth.currentUser] can be null briefly while the SDK
/// restores a persisted session or while [signInAnonymously] completes.
/// Waits until [auth.currentUser] is non-null or [timeout] elapses.
Future<void> waitForFirebaseAuthUser(
  FirebaseAuth auth, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (auth.currentUser != null) return;
  try {
    await auth
        .authStateChanges()
        .where((u) => u != null)
        .first
        .timeout(timeout);
  } catch (_) {}
}
