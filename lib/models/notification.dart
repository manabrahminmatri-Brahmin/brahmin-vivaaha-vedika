/// Push/in-app notification *type strings* (`type` field) used across the app.
///
/// Persisted payloads, unread badges, and list screens should go through a single
/// repository/service layer (`NotificationRepository`, `NotificationService`); do not
/// add a second parallel document model for the same rows.
class NotificationType {
  // Interest related
  static const String interestReceived = 'interest_received';
  static const String interestAccepted = 'interest_accepted';
  static const String interestDeclined = 'interest_declined';
  
  // Like related
  static const String liked = 'liked';
  static const String likedYou = 'liked_you';
  
  // Match related
  static const String match = 'match';
  
  // Contact related
  static const String contactShared = 'contact_shared';
  
  // Photo related
  static const String photoRequest = 'photo_request';
  static const String photoGranted = 'photo_granted';
  static const String photoDenied = 'photo_denied';
  
  // Birth details related
  static const String birthDetailsRequest = 'birth_details_request';
  static const String birthDetailsGranted = 'birth_details_granted';
  static const String birthDetailsDenied = 'birth_details_denied';
  
  // Community reference related
  static const String communityReferenceRequest = 'community_reference_request';
  static const String communityReferenceGranted = 'community_reference_granted';
  static const String communityReferenceDenied = 'community_reference_denied';
  
  // Profile related
  static const String profileView = 'profile_view';
  static const String profileUpdate = 'profile_update';
  
  // System related
  static const String system = 'system';
  static const String admin = 'admin';
  static const String announcement = 'announcement';
  
  // Reminder related
  static const String membershipReminder = 'membership_reminder';
  static const String incompleteProfile = 'incomplete_profile';
}
