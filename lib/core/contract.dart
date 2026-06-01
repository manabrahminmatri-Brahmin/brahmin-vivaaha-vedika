// 🔥 APP CONTRACT - Single Source of Truth
// EVERY layer must use these constants
// NO random strings anywhere in the project

/// Firestore collection names — use these constants instead of string literals.
///
/// For who reads/writes **users** today, see `FirestoreUsersAccessMap` in
/// `package:brahmin_vivaaha_vedika/core/firestore_users_access_map.dart`.
class Collections {
  static const String users = 'users';
  static const String likes = 'likes';
  static const String interests = 'interests';
  static const String profileViews = 'profile_views';
  static const String notifications = 'notifications';
  static const String references = 'references';
  static const String birthDetails = 'birth_details';
  static const String chats = 'chats';
  static const String messages = 'messages';
  static const String supportThreads = 'support_threads';
  static const String adminAuthLinks = 'admin_auth_links';
  
  // Photo requests
  static const String photoRequests = 'photo_requests';
  
  // Community reference system
  static const String communityReferenceRequests = 'community_reference_requests';
  static const String communityReferenceAccess = 'community_reference_access';
}

/// Field Names - snake_case for Firestore
class Fields {
  // Identity
  static const String authUid = 'auth_uid';
  static const String userId = 'user_id';
  static const String profileId = 'profile_id';
  static const String memberId = 'member_id';
  static const String docId = 'id';
  
  // Relations
  static const String fromUserId = 'from_user_id';
  static const String toUserId = 'to_user_id';
  static const String senderId = 'sender_id';
  static const String receiverId = 'receiver_id';
  static const String viewerUserId = 'viewer_user_id';
  static const String viewedProfileId = 'viewed_profile_id';
  
  // Community reference relations
  static const String requesterId = 'requester_id';
  static const String ownerId = 'owner_id';
  
  // Photo request profile references
  static const String fromProfileId = 'from_profile_id';
  static const String toProfileId = 'to_profile_id';
  
  // Timestamps
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
  static const String viewedAt = 'viewed_at';
  static const String sentAt = 'sent_at';
  static const String respondedAt = 'responded_at';
  
  // Status
  static const String status = 'status';
  static const String isRead = 'is_read';
  static const String isDeleted = 'is_deleted';
  static const String schemaVersion = 'schema_version';
  
  // Profile
  static const String profile = 'profile';
  static const String firstName = 'first_name';
  static const String lastName = 'last_name';
  static const String photoUrl = 'photo_url';
  static const String profilePicture = 'profile_picture';
  static const String isPhotoPrivate = 'is_photo_private';
  static const String photoPrivacyUpdatedAt = 'photo_privacy_updated_at';
  static const String city = 'city';
  static const String location = 'location';
  static const String dateOfBirth = 'date_of_birth';
  static const String age = 'age';
  static const String gender = 'gender';
  
  // Analytics
  static const String likesSent = 'likes_sent';
  static const String likesReceived = 'likes_received';
  static const String interestsSent = 'interests_sent';
  static const String interestsReceived = 'interests_received';
  static const String profileViewsSent = 'profile_views_sent';
  static const String profileViewsReceived = 'profile_views_received';
  
  // Notification
  static const String title = 'title';
  static const String body = 'body';
  static const String type = 'type';
  static const String data = 'data';
}

/// Error Codes
class ErrorCodes {
  // Firebase
  static const String permissionDenied = 'permission-denied';
  static const String notFound = 'not-found';
  static const String alreadyExists = 'already-exists';
  static const String invalidArgument = 'invalid-argument';
  static const String unauthenticated = 'unauthenticated';
  static const String unavailable = 'unavailable';
  static const String cancelled = 'cancelled';
  static const String deadlineExceeded = 'deadline-exceeded';
  
  // App
  static const String userNotFound = 'user-not-found';
  static const String notAuthenticated = 'not-authenticated';
  static const String invalidOperation = 'invalid-operation';
  static const String networkError = 'network-error';
  static const String timeout = 'timeout';
  static const String unknown = 'unknown';
}

/// Status Values
class StatusValues {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';
  static const String withdrawn = 'withdrawn';
  static const String active = 'active';
  static const String inactive = 'inactive';
  static const String deleted = 'deleted';
}

/// Notification Types
class NotificationTypes {
  static const String like = 'like';
  static const String interest = 'interest';
  static const String interestAccepted = 'interest_accepted';
  static const String interestRejected = 'interest_rejected';
  static const String profileView = 'profile_view';
  static const String message = 'message';
  static const String birthRequest = 'birth_request';
  static const String communityRequest = 'community_request';
}

/// UI Messages - User-friendly error messages
class UiMessages {
  static const String permissionDenied = 'Action unavailable. Please try again later.';
  static const String notFound = 'Resource not found.';
  static const String notAuthenticated = 'Please sign in to continue.';
  static const String networkError = 'Network issue. Please check your connection.';
  static const String timeout = 'Request timed out. Please try again.';
  static const String unknown = 'Something went wrong. Please try again.';
  static const String success = 'Success!';
}
