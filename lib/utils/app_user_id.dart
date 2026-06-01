import 'package:firebase_auth/firebase_auth.dart';

/// Global helper for accessing the current Firebase Auth UID.
/// Use this instead of repeating FirebaseAuth calls throughout the codebase.
/// 
/// For user model Auth UID access, prefer: user.firebaseAuthUid
class AppUserId {
  /// Returns the current Firebase Auth UID, or null if not authenticated.
  static String? get current => FirebaseAuth.instance.currentUser?.uid;
  
  /// Returns the current Firebase Auth UID, throwing if not authenticated.
  static String get currentOrThrow {
    final uid = current;
    if (uid == null) {
      throw StateError('No authenticated user');
    }
    return uid;
  }
}
