/// 🎯 APP CONSTANTS
/// Centralized configuration values
class AppConstants {
  // App Info
  static const String appName = 'mana Vivaaha Vedika';
  /// Keep in sync with pubspec.yaml `version:` (user-facing, no build number).
  static const String appVersion = '1.1.0';
  
  // Collections
  static const String usersCollection = 'users';
  static const String likesCollection = 'likes';
  static const String notificationsCollection = 'notifications';
  static const String chatsCollection = 'chats';
  static const String supportThreadsCollection = 'support_threads';
  
  // Limits
  static const int maxNotificationsLoad = 50;
  static const int maxLikesLoad = 100;
  static const int maxChatsLoad = 50;
  
  // Timeouts
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Duration authTimeout = Duration(seconds: 15);
  
  // Cache Duration
  static const Duration cacheExpiration = Duration(hours: 1);
}

/// 🔥 FIREBASE CONSTANTS
class FirebaseConstants {
  // Field Names
  static const String userIdField = 'user_id';
  static const String timestampField = 'created_at';
  static const String createdField = 'created_at';
  static const String updatedField = 'updated_at';
  static const String isReadField = 'is_read';
  
  // Like Fields
  static const String fromField = 'from';
  static const String toField = 'to';
  
  // User Fields
  static const String mobileField = 'mobile_number';
  static const String nameField = 'first_name';
  static const String emailField = 'email';
  static const String onlineField = 'is_online';
  static const String activeField = 'last_active';
}
