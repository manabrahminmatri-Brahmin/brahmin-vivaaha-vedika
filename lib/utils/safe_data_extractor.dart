import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility class for safe data extraction from Firestore documents
class SafeDataExtractor {
  /// Safely extract a string value from a map
  static String getSafeString(Map<String, dynamic> data, String key) {
    return data[key]?.toString() ?? '';
  }

  /// Safely extract a list of strings from a map
  static List<String> getSafeStringList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return [];
    
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    
    return [];
  }

  /// Safely extract a boolean value from a map
  static bool getSafeBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return false;
    
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    
    return false;
  }

  /// Safely extract a timestamp from a map
  static DateTime? getSafeTimestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    
    if (value is Timestamp) {
      return value.toDate();
    }
    
    return null;
  }

  /// Safely extract a numeric value from a map
  static double getSafeDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return 0.0;
    
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    
    return 0.0;
  }

  /// Safely extract an integer value from a map
  static int getSafeInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return 0;
    
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    
    return 0;
  }

  /// Check if a user document has required fields
  static bool isValidUserDocument(Map<String, dynamic> data) {
    final uid = getSafeString(data, 'uid');
    final name = getSafeString(data, 'name');
    
    return uid.isNotEmpty && name.isNotEmpty;
  }

  /// Get a user's photo URL safely
  static String getUserPhotoUrl(Map<String, dynamic> user) {
    return getSafeString(user, 'photo_url').isNotEmpty 
        ? getSafeString(user, 'photo_url')
        : getSafeString(user, 'profilePicture');
  }

  /// Get a user's display name safely
  static String getUserDisplayName(Map<String, dynamic> user) {
    final name = getSafeString(user, 'name');
    if (name.isNotEmpty) return name;
    
    final firstName = getSafeString(user, 'first_name');
    final lastName = getSafeString(user, 'last_name');
    
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    }
    
    return firstName.isNotEmpty ? firstName : 'Unknown User';
  }

  /// Get user's liked users list safely
  static List<String> getUserLikedUsers(Map<String, dynamic> user) {
    return getSafeStringList(user, 'liked_users');
  }

  /// Get user's liked by list safely
  static List<String> getUserLikedBy(Map<String, dynamic> user) {
    return getSafeStringList(user, 'liked_by');
  }

  /// Public profile id (MB… / MG…) from `profile_id`, `profileId`, or nested `profile`.
  static String getProfileId(Map<String, dynamic> data) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final a = pick(data['profile_id']);
    if (a != null) return a;
    final p = data['profile'];
    if (p is Map) {
      final pm = Map<String, dynamic>.from(p);
      final c = pick(pm['profile_id']);
      if (c != null) return c;
    }
    return '';
  }

  /// Parse Firestore [Timestamp], ISO string, int ms, or [DateTime].
  static DateTime? parseFirestoreDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.tryParse(value.toString());
  }

  /// Booleans from Firestore (bool, 0/1, or string).
  static bool coerceBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return defaultValue;
  }

  /// Integers from Firestore (int, double, or string), clamped to [min]–[max].
  static int coerceInt(dynamic value, int defaultValue,
      {int min = 0, int max = 999999}) {
    if (value == null) return defaultValue;
    int? n;
    if (value is int) {
      n = value;
    } else if (value is double) {
      n = value.round();
    } else {
      n = int.tryParse(value.toString());
    }
    if (n == null) return defaultValue;
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }
}
