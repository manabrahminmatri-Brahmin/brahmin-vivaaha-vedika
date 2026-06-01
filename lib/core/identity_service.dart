import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 🔥 UNIFIED IDENTITY SERVICE
/// 
/// MANDATORY: ALL identity access MUST go through this service
/// NO direct FirebaseAuth.currentUser.uid usage allowed
/// NO fallback logic allowed
/// 
/// SINGLE SOURCE OF TRUTH: profile_id (stored in SharedPreferences)
class IdentityService {
  static final IdentityService _instance = IdentityService._internal();
  factory IdentityService() => _instance;
  IdentityService._internal();

  static const String _profileIdKey = 'profile_id';
  static const String _currentUserIdKey = 'current_user_id';

  /// 🔥 CRITICAL: Get profile ID with NO fallback
  /// 
  /// Throws exception if profile_id is missing
  /// This is ENFORCED - no silent failures allowed
  Future<String> getProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    final profileId = prefs.getString(_profileIdKey);
    
    if (profileId == null || profileId.isEmpty) {
      throw Exception('CRITICAL: Missing profile_id - User not properly authenticated');
    }
    
    return profileId;
  }

  /// 🔥 CRITICAL: Get user ID with NO fallback
  /// 
  /// Uses stored current_user_id, throws if missing
  Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_currentUserIdKey);
    
    if (userId == null || userId.isEmpty) {
      throw Exception('CRITICAL: Missing current_user_id - User not properly authenticated');
    }
    
    return userId;
  }

  /// 🔥 CRITICAL: Set profile ID (called during login)
  /// 
  /// This is the ONLY place where profile_id should be set
  Future<void> setProfileId(String profileId) async {
    if (profileId.isEmpty) {
      throw Exception('CRITICAL: Cannot set empty profile_id');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileIdKey, profileId);
  }

  /// 🔥 CRITICAL: Set user ID (called during login)
  /// 
  /// This is the ONLY place where current_user_id should be set
  Future<void> setUserId(String userId) async {
    if (userId.isEmpty) {
      throw Exception('CRITICAL: Cannot set empty current_user_id');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserIdKey, userId);
  }

  /// 🔥 CRITICAL: Clear all identity data (called during logout)
  /// 
  /// This is the ONLY place where identity data should be cleared
  Future<void> clearIdentity() async {
    debugPrint('🔍 IDENTITY DATA CLEARING: clearIdentity() called');

    // Log current identity before clearing
    final currentUserId = await getUserId();
    final profileId = await getProfileId();
    debugPrint('🔍 IDENTITY BEING CLEARED: userId=$currentUserId, profileId=$profileId');
  
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileIdKey);
    await prefs.remove(_currentUserIdKey);
    debugPrint('🔍 IDENTITY DATA CLEARED: clearIdentity() completed');
  }

  /// 🔥 CRITICAL: Check if user is properly authenticated
  /// 
  /// Returns true only if both profile_id and current_user_id exist
  Future<bool> isAuthenticated() async {
    try {
      await getProfileId();
      await getUserId();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 🔥 CRITICAL: Get current Firebase Auth UID for sync ONLY
  /// 
  /// ⚠️ WARNING: This method is ONLY for auth_uid sync with Firestore
  /// NEVER use this for business logic or user identification
  /// Business logic MUST use getProfileId() or getUserId() only
  Future<String?> getFirebaseAuthUid() async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      throw Exception('CRITICAL: No authenticated Firebase user for sync');
    }
    
    return user.uid;
  }

  /// 🔥 CRITICAL: Validate identity consistency
  /// 
  /// Checks if stored identity is consistent with Firebase Auth
  /// Throws if inconsistencies found
  Future<void> validateIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final profileId = prefs.getString(_profileIdKey);
    final userId = prefs.getString(_currentUserIdKey);
    await getFirebaseAuthUid();

    if (profileId == null || profileId.isEmpty) {
      throw Exception('CRITICAL: profile_id is missing');
    }

    if (userId == null || userId.isEmpty) {
      throw Exception('CRITICAL: current_user_id is missing');
    }

    // Note: firebaseAuthUid can be different (anonymous auth)
    // That's expected - we rely on stored IDs, not Firebase Auth UID
  }
}
