// lib/services/firebase_service.dart
// Re-exports FirebaseService from the legacy compatibility layer so that
// realtime_sync_service.dart and user_activity_service.dart can import it
// without a path change.

export '../legacy/compatibility.dart' show FirebaseService;