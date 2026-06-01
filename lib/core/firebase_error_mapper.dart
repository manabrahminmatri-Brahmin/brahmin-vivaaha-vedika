import 'package:firebase_auth/firebase_auth.dart';

/// Centralized mapping from Firebase exceptions to user-safe messages.
class FirebaseErrorMapper {
  static String toUserMessage(Object error) {
    if (error is FirebaseAuthException) {
      return _authMessage(error);
    }
    if (error is FirebaseException) {
      return _firebaseMessage(error);
    }
    return 'Something went wrong. Please try again.';
  }

  static String _authMessage(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    switch (code) {
      case 'session-required':
      case 'invalid-credential':
        return 'Session expired. Please sign in again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Authentication error. Please try again.';
    }
  }

  static String _firebaseMessage(FirebaseException e) {
    final code = e.code.toLowerCase();
    switch (code) {
      case 'permission-denied':
        return 'Permission denied. Please sign in again or contact support.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Service temporarily unavailable. Please try again.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Server error. Please try again.';
    }
  }
}

