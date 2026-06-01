import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/app_firebase_functions.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart' as app_models;
import '../../models/auth_result.dart';
import '../../models/gender.dart';
import '../../screens/search/filter_screen.dart' show FilterPreferences;
import 'local_auth_service.dart';
import '../../services/two_factor_service.dart';
import '../../core/backend/firestore_service.dart';
import '../../utils/firestore_cache_read.dart';
import '../../core/contract.dart';
import '../../core/firestore_doc_map.dart';
import '../../core/firestore_repository.dart';
import '../../core/app_identity.dart';
import '../../core/identity_service.dart';
import '../../services/profile_deletion_service.dart';
import '../../core/profile_completion_policy.dart';
import '../../services/navigation_service.dart';
import '../../services/plan_service.dart';
import '../../services/presence_service.dart';
import '../../services/security/device_security_service.dart';
import '../../services/security/protected_image_cache_service.dart';
import '../../services/security/session_security_service.dart';
import '../../services/access_request_broadcast.dart';
import '../profile/profile_repository.dart';
import 'session_manager.dart';

/// MPIN salt constant - must match ZIP1 for backward compatibility
const String _kMpinSalt = 'mana_matrimony_mpin_salt';

/// One page of match results (cursor + flag for infinite scroll).
class MatchingProfilesPage {
  final List<app_models.User> users;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;
  const MatchingProfilesPage({
    required this.users,
    required this.lastDoc,
    required this.hasMore,
  });
}

/// Hash MPIN using SHA256 with salt (matches ZIP1 implementation)
String _hashMpin(String mpin) {
  final salted = '$_kMpinSalt$mpin';
  final bytes = utf8.encode(salted);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

@visibleForTesting
String hashMpinForTesting(String mpin) => _hashMpin(mpin);

/// Main Authentication Controller
///
/// Consolidates auth logic from:
/// - auth_service.dart
/// - session_service.dart
/// - user_init_service.dart
/// - biometric_auth_service.dart
/// - mpin_service.dart
class AuthController extends ChangeNotifier {
  static final AuthController _instance = AuthController._internal();
  factory AuthController() => _instance;
  AuthController._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  final LocalAuthService _localAuth = LocalAuthService();
  final SessionManager _sessionManager = SessionManager();
  final TwoFactorService _twoFactor = TwoFactorService();

  // State
  app_models.User? _currentUser;
  bool _isInitialized = false;
  String? _errorMessage;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;

  /// Matches from the last broad fetch that did not fit the requested page size.
  final List<app_models.User> _matchProfileOverflow = [];

  static const int _kDiscoveryOverfetchFactor = 4;
  static const int _kDiscoveryFetchMin = 40;
  static const int _kDiscoveryFetchMax = 400;

  int _discoveryFetchSize(int pageLimit) =>
      (pageLimit * _kDiscoveryOverfetchFactor)
          .clamp(_kDiscoveryFetchMin, _kDiscoveryFetchMax);

  /// Broad listing: `is_deleted == false` + `created_at` desc. Falls back to
  /// `created_at` only if the composite index / field is unavailable (filter
  /// deleted users in Dart on that path).
  Future<QuerySnapshot<Map<String, dynamic>>> _broadActiveUsersPage({
    required DocumentSnapshot? startAfter,
    required int fetchSize,
  }) async {
    Query<Map<String, dynamic>> activeQuery() {
      var q = _db
          .collection(Collections.users)
          .where('is_deleted', isEqualTo: false)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      return q;
    }

    Query<Map<String, dynamic>> anyQuery() {
      var q = _db
          .collection(Collections.users)
          .orderBy('created_at', descending: true)
          .limit(fetchSize);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      return q;
    }

    try {
      return await activeQuery().get();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' ||
          e.code == 'permission-denied') {
        debugPrint(
          '⚠️ _broadActiveUsersPage: ${e.code} — retrying without is_deleted '
          '(${e.message})',
        );
        return await anyQuery().get();
      }
      rethrow;
    }
  }

  // Getters
  app_models.User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  // Streams
  Stream<app_models.User?> get userStream => _sessionManager.userStream;

  /// Initialize authentication system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _localAuth.initialize();
      await _sessionManager.initialize();

      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
      } else {
        // Hot restart / cleared prefs: Firebase Auth may still have anonymous session
        // with an existing `users/{uid}` doc from registration.
        await _ensureCurrentUserFromAuthSession();
      }

      if (_currentUser != null) {
        _activateWatermarkSession();
        _attachUserDocumentListener(_currentUser!.id);
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Auth initialization failed: $e';
      rethrow;
    }
  }

  /// Resolve Firestore user for this Firebase Auth UID (doc id or [auth_uid] field).
  Future<app_models.User?> _tryLoadUserDocForFirebaseUid(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final direct = await _db.collection(Collections.users).doc(uid).get();
      if (direct.exists && direct.data() != null) {
        return app_models.User.fromFirestore(direct.data()!, direct.id);
      }
      final q = await _db
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      final d = q.docs.first;
      return app_models.User.fromFirestore(d.data(), d.id);
    } catch (e) {
      debugPrint('⚠️ _tryLoadUserDocForFirebaseUid: $e');
      return null;
    }
  }

  /// When [FirebaseAuth] has a user but prefs / [_currentUser] are empty, bind session.
  Future<bool> _ensureCurrentUserFromAuthSession() async {
    if (_currentUser != null) return true;
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return false;

    final user = await _tryLoadUserDocForFirebaseUid(firebaseUser.uid);
    if (user == null) {
      debugPrint(
        '⚠️ No Firestore user for auth uid ${firebaseUser.uid}; cannot bind session',
      );
      return false;
    }

    final identityService = IdentityService();
    await identityService.setUserId(user.id);
    final pid = user.profileId;
    await identityService.setProfileId(pid.isNotEmpty ? pid : user.id);

    _currentUser = user;
    _activateWatermarkSession();
    await _sessionManager.startSession(user);
    _attachUserDocumentListener(user.id);
    notifyListeners();
    debugPrint('✅ Session bound from Firebase Auth: ${user.id}');
    return true;
  }

  /// Writes [IdentityService] prefs from [_currentUser] (non-empty profile_id fallback).
  Future<void> _syncIdentityPrefsFromCurrentUser() async {
    final u = _currentUser;
    if (u == null) return;
    final identityService = IdentityService();
    await identityService.setProfileId(
      u.profileId.isNotEmpty ? u.profileId : u.id,
    );
    await identityService.setUserId(u.id);
  }

  /// Keeps [currentUser] in sync when Firestore is updated (e.g. admin grants premium).
  void _attachUserDocumentListener(String userId) {
    _userDocSubscription?.cancel();
    _userDocSubscription = null;
    final id = userId.trim();
    if (id.isEmpty) return;
    _userDocSubscription = _db.collection(Collections.users).doc(id).snapshots().listen(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!snap.exists) return;
        final data = snap.data();
        if (data == null) return;
        try {
          final incoming = app_models.User.fromFirestore(data, snap.id);
          final local = _currentUser;
          if (local != null &&
              local.id == incoming.id &&
              local.profile != null &&
              incoming.profile != null) {
            final localAt = local.profile!.photoLastUpdated;
            final incomingAt = incoming.profile!.photoLastUpdated;
            // Ignore stale snapshot that would restore an old photo after upload.
            if (localAt != null &&
                (incomingAt == null || incomingAt.isBefore(localAt))) {
              _currentUser = incoming.copyWith(
                profile: incoming.profile!.copyWith(
                  profilePicture: local.profile!.profilePicture,
                  photoLastUpdated: localAt,
                ),
              );
              _sessionManager.updateSession(_currentUser!).catchError((Object e) {
                debugPrint('⚠️ updateSession after user doc snapshot: $e');
              });
              notifyListeners();
              return;
            }
          }
          _currentUser = incoming;
          _sessionManager.updateSession(incoming).catchError((Object e) {
            debugPrint('⚠️ updateSession after user doc snapshot: $e');
          });
          notifyListeners();
        } catch (e, st) {
          debugPrint('⚠️ user doc listener parse failed: $e\n$st');
        }
      },
      onError: (Object e) => debugPrint('⚠️ user doc listener: $e'),
    );
  }

  void _detachUserDocumentListener() {
    _userDocSubscription?.cancel();
    _userDocSubscription = null;
  }

  /// Public hook for screens (e.g. MPIN setup) after restart: bind Firestore user from Firebase Auth.
  Future<bool> restoreSessionFromFirebaseAuth() =>
      _ensureCurrentUserFromAuthSession();

  void _logRestoreSanity(app_models.User user, {required String source}) {
    if (!kDebugMode) return;
    final p = user.profile;
    final checks = <String, bool>{
      'id': user.id.trim().isNotEmpty,
      'profile_id': user.profileId.trim().isNotEmpty,
      'mobile_number': user.mobileNumber.trim().isNotEmpty,
      'auth_uid': (user.authUid ?? '').trim().isNotEmpty,
      'first_name': (p?.firstName ?? '').trim().isNotEmpty,
      'last_name': (p?.lastName ?? '').trim().isNotEmpty,
      'gender': p != null,
      'date_of_birth': p?.dateOfBirth != null,
      'education': (p?.education ?? '').trim().isNotEmpty,
      'occupation': (p?.occupation ?? '').trim().isNotEmpty,
      'city': (p?.city ?? '').trim().isNotEmpty,
      'state': (p?.state ?? '').trim().isNotEmpty,
      'about_me': (p?.aboutMe ?? '').trim().isNotEmpty,
      'partner_preferences': (p?.partnerPreferences ?? '').trim().isNotEmpty,
      'profile_picture': (p?.profilePicture ?? '').trim().isNotEmpty,
    };
    final total = checks.length;
    final filled = checks.values.where((v) => v).length;
    final pct = total == 0 ? 0 : ((filled * 100) / total).round();
    final missing = checks.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .take(8)
        .join(', ');
    debugPrint(
      '🧪 Restore sanity [$source]: $filled/$total ($pct%) '
      'profile=${user.profileId} user=${user.id} '
      '${missing.isEmpty ? '' : 'missing=[$missing]'}',
    );
  }

  /// Load current user from Firestore
  ///
  /// 1) Prefers [IdentityService] doc id when prefs exist and the doc is present.
  /// 2) Falls back to Firebase Auth UID → `users/{uid}` or `auth_uid` query so
  ///    login/registration works before prefs are populated, and stale prefs /
  ///    missing docs do not strand the session.
  Future<app_models.User?> _loadCurrentUser() async {
    final identityService = IdentityService();
    String? prefsUserId;

    try {
      prefsUserId = await identityService.getUserId();
    } catch (e) {
      debugPrint('🔍 _loadCurrentUser: no prefs user id yet ($e)');
      prefsUserId = null;
    }

    if (prefsUserId != null && prefsUserId.isNotEmpty) {
      try {
        final doc = await getDocumentCachedFirst(
          _db.collection(Collections.users).doc(prefsUserId),
        );
        if (doc.exists && doc.data() != null) {
          final firestoreData = doc.data() as Map<String, dynamic>;
          if (kDebugMode) {
            debugPrint('🔍 Firestore data keys: ${firestoreData.keys}');
          }
          if (kDebugMode) {
            final sample = firestoreData.toString();
            debugPrint(
              '🔍 Firestore data sample: ${sample.length > 200 ? sample.substring(0, 200) : sample}',
            );
          }
          final user = app_models.User.fromFirestore(firestoreData, doc.id);
          _logRestoreSanity(user, source: '_loadCurrentUser');
          return user;
        }
        debugPrint(
          '⚠️ _loadCurrentUser: users/$prefsUserId missing — trying Firebase Auth',
        );
      } catch (e) {
        debugPrint('⚠️ _loadCurrentUser doc read error: $e');
      }
    }

    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      final recovered = await _tryLoadUserDocForFirebaseUid(firebaseUser.uid);
      if (recovered != null) {
        try {
          await identityService.setUserId(recovered.id);
          final pid = recovered.profileId;
          await identityService.setProfileId(pid.isNotEmpty ? pid : recovered.id);
        } catch (e) {
          debugPrint('⚠️ _loadCurrentUser: could not persist identity prefs: $e');
        }
        _logRestoreSanity(recovered, source: '_loadCurrentUser.firebaseUid');
        return recovered;
      }
    }

    return null;
  }

  /// Login with email and password
  Future<AuthResult> login(String email, String password) async {
    try {
      _errorMessage = null;

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Sync auth_uid with Firestore
      await _db.collection(Collections.users).doc(credential.user!.uid).set({
        'auth_uid': credential.user!.uid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
        _activateWatermarkSession();
        await _sessionManager.startSession(user);
        _attachUserDocumentListener(user.id);
        notifyListeners();
        return AuthResult.success('Login successful');
      }
      // [_ensureCurrentUserFromAuthSession] already starts session + attaches listener.
      if (await _ensureCurrentUserFromAuthSession()) {
        return AuthResult.success('Login successful');
      }

      return AuthResult.failure('User not found');
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Login with MPIN
  Future<AuthResult> loginWithMpin(String mpin) async {
    try {
      _errorMessage = null;

      final success = await _localAuth.verifyMpin(mpin);
      if (!success) {
        return AuthResult.failure('Invalid MPIN');
      }

      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
        _activateWatermarkSession();
        await _syncIdentityPrefsFromCurrentUser();
        await _sessionManager.startSession(user);
        _attachUserDocumentListener(user.id);
        notifyListeners();
        return AuthResult.success('MPIN login successful');
      }
      if (await _ensureCurrentUserFromAuthSession()) {
        await _syncIdentityPrefsFromCurrentUser();
        return AuthResult.success('MPIN login successful');
      }

      return AuthResult.failure('User not found');
    } catch (e) {
      _errorMessage = 'MPIN login failed: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Login with biometrics
  Future<AuthResult> loginWithBiometrics() async {
    try {
      _errorMessage = null;

      final success = await _localAuth.authenticateWithBiometrics();
      if (!success) {
        return AuthResult.failure('Biometric authentication failed');
      }

      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
        _activateWatermarkSession();
        await _sessionManager.startSession(user);
        _attachUserDocumentListener(user.id);
        notifyListeners();
        return AuthResult.success('Biometric login successful');
      }
      if (await _ensureCurrentUserFromAuthSession()) {
        return AuthResult.success('Biometric login successful');
      }

      return AuthResult.failure('User not found');
    } catch (e) {
      _errorMessage = 'Biometric login failed: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Register new user
  Future<AuthResult> register(
      String email, String password, Map<String, dynamic> userData) async {
    try {
      _errorMessage = null;

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document
      await _db.collection(Collections.users).doc(credential.user!.uid).set({
        ...userData,
        'auth_uid': credential.user!.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
        _activateWatermarkSession();
        await _sessionManager.startSession(user);
        _attachUserDocumentListener(user.id);
        notifyListeners();
        return AuthResult.success('Registration successful');
      }
      if (await _ensureCurrentUserFromAuthSession()) {
        return AuthResult.success('Registration successful');
      }

      return AuthResult.failure('Failed to load user after registration');
    } catch (e) {
      _errorMessage = 'Registration failed: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  void _activateWatermarkSession() {
    SessionSecurityService.beginSession();
    DeviceSecurityService.resetSessionFlags();
    unawaited(DeviceSecurityService.isCompromisedDevice());
  }

  void _clearWatermarkSession() {
    SessionSecurityService.clearSession();
    DeviceSecurityService.resetSessionFlags();
    unawaited(ProtectedImageCacheService.clearProtectedImageCache());
  }

  /// Logout user
  Future<void> logout() async {
    try {
      debugPrint('🔍 LOGOUT PROCESS STARTING: logout() called');
      _clearWatermarkSession();
      final rememberedUser = _currentUser;
      _detachUserDocumentListener();
      _currentUser = null;
      _errorMessage = null;
      notifyListeners();

      // Set logout timestamp to enable profile data clearing safeguards
      final prefs = await SharedPreferences.getInstance();
      final rememberedUserId =
          rememberedUser?.id ?? prefs.getString('current_user_id') ?? '';
      final rememberedName =
          rememberedUser?.profile?.fullName ?? prefs.getString('current_user_name') ?? '';
      final rememberedMobile =
          rememberedUser?.mobileNumber ?? prefs.getString('last_login_mobile') ?? '';
      final rememberedProfileComplete = prefs.getBool('profile_complete') ?? false;

      await prefs.setInt(
          'logout_timestamp', DateTime.now().millisecondsSinceEpoch);
      debugPrint('🔍 LOGOUT TIMESTAMP SET: ${DateTime.now()}');

      // Normal logout should lock the remembered account, not erase it.
      // Write these BEFORE Firebase sign-out/session listeners can react;
      // otherwise startup routing can briefly see stale profile flags and open
      // Profile Wizard behind/over the login screen.
      if (rememberedUserId.isNotEmpty) {
        await prefs.setString('current_user_id', rememberedUserId);
        await prefs.setBool('user_logged_in', true);
        await prefs.setBool('mpin_setup_complete', true);
        await prefs.setBool('mpin_verified', false);
        await prefs.setBool('app_locked', true);
        await prefs.setBool('profile_complete', rememberedProfileComplete);
        await prefs.remove('user_explicitly_logged_out');
        if (rememberedName.trim().isNotEmpty) {
          await prefs.setString('current_user_name', rememberedName.trim());
        }
        if (rememberedMobile.trim().isNotEmpty) {
          await prefs.setString('last_login_mobile', rememberedMobile.trim());
        }
      }
      NavigationService().invalidateCaches();
      unawaited(() async {
        // Stop presence tracking so "Live now" badges don't remain after logout.
        await PresenceService().stopTracking();
      }());
      unawaited(_auth.signOut());
      unawaited(_sessionManager.endSession());
    } catch (e) {
      _errorMessage = 'Logout failed: $e';
    }
  }

  /// Refresh user data
  Future<void> refreshUserData() async {
    try {
      final user = await _loadCurrentUser();
      if (user != null) {
        _currentUser = user;
        await _sessionManager.updateSession(user);
        _attachUserDocumentListener(user.id);
        notifyListeners();
      } else if (await _ensureCurrentUserFromAuthSession()) {
        await _sessionManager.updateSession(_currentUser!);
      }
    } catch (e) {
      _errorMessage = 'Failed to refresh user data: $e';
    }
  }

  /// Fields clients must not write (Firestore rules + server-owned membership).
  static const Set<String> _profileWriteBlockedKeys = {
    'id',
    'is_admin',
    'is_premium',
    'subscription_tier',
    'premium_expiry',
    'membership_level',
    'membership_tier',
    'membership_status',
    'membership_json',
    'membership_expiry_date',
    'auth_uid',
    'admin_role',
    'admin_permissions',
    'created_at',
    'membership',
  };

  Map<String, dynamic> _sanitizeProfileWritePayload(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final key in _profileWriteBlockedKeys) {
      out.remove(key);
    }
    return out;
  }

  /// Update user profile
  Future<AuthResult> updateUserProfile(Map<String, dynamic> userData) async {
    try {
      if (_currentUser == null) {
        throw Exception('No user logged in');
      }

      final userId = _currentUser!.id;
      // Rules require users/{docId}.auth_uid == Firebase Auth UID before profile writes.
      await syncAuthUid(userId);

      final payload = _sanitizeProfileWritePayload(userData);
      await _db.collection(Collections.users).doc(userId).update({
        ...payload,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Refresh user data
      await refreshUserData();
      notifyListeners();
      return AuthResult.success('Profile updated');
    } on FirebaseException catch (e) {
      _errorMessage = 'Failed to update profile: $e';
      if (e.code == 'permission-denied') {
        return AuthResult.failure(
          'Permission denied. Please log out, log in again, and retry.',
        );
      }
      return AuthResult.failure(e.toString());
    } catch (e) {
      _errorMessage = 'Failed to update profile: $e';
      return AuthResult.failure(e.toString());
    }
  }

  /// Update specific user profile field with proper synchronization
  Future<AuthResult> updateUserProfileField(
      String userId, String field, dynamic value) async {
    try {
      debugPrint('🔄 UPDATING USER FIELD: $field = $value for user $userId');

      await syncAuthUid(userId);
      final result = await FirestoreRepository.setDocument(
        Collections.users,
        userId,
        {field: value},
        merge: true,
      );
      if (result.isError) {
        throw Exception(result.message);
      }

      // If updating current user, refresh their data
      if (_currentUser?.id == userId) {
        await refreshUserData();
        notifyListeners();
      }

      return AuthResult.success('Field updated');
    } catch (e) {
      debugPrint('❌ FAILED TO UPDATE USER FIELD: $field = $value - $e');
      return AuthResult.failure(e.toString());
    }
  }

  /// Set MPIN for user using secure Cloud Function
  Future<AuthResult> setMpin(String mpin) async {
    try {
      _errorMessage = null;

      if (_currentUser == null) {
        final bound = await _ensureCurrentUserFromAuthSession();
        if (!bound) {
          return AuthResult.failure(
            'No user logged in. Go back and complete registration, or log in again.',
          );
        }
      }

      final hashedMpin = _hashMpin(mpin);

      // CRITICAL: Sync auth_uid before MPIN update to satisfy security rules
      await _syncAuthUid(_currentUser!.id);

      // Use secure Cloud Function to write mpin_hash to Firestore
      final HttpsCallable callable =
          appFirebaseFunctions.httpsCallable('setUserMpinSecure');
      // Callable `setUserMpinSecure` expects camelCase `userId` / `mobileNumber` (see functions/index.js).
      final result = await callable.call({
        'userId': _currentUser!.id,
        'mpin_hash': hashedMpin,
        'mobileNumber': _currentUser!.mobileNumber,
        'auth_uid': _auth.currentUser?.uid,
      });

      if (result.data['success'] == true) {
        // Also save to local auth for device-specific MPIN
        await _localAuth.saveMpin(hashedMpin);
        return AuthResult.success('MPIN set successfully');
      } else {
        return AuthResult.failure('Failed to set MPIN');
      }
    } on FirebaseFunctionsException catch (e) {
      _errorMessage = 'Failed to set MPIN: ${e.message}';
      return AuthResult.failure(_errorMessage!);
    } catch (e) {
      _errorMessage = 'Failed to set MPIN: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Same controls as My Profile and Privacy Settings: public vs hidden.
  /// Uses [syncPhotoPrivacyBundle] so legacy blur / hide-until-interest flags
  /// are cleared; hidden relies on [is_photo_private]. Others see your photo
  /// after you accept their photo-view request.
  Future<AuthResult> updatePhotoPrivacy(bool isPrivate) async {
    debugPrint(
        '🔄 updatePhotoPrivacy (bundle): hidden=$isPrivate → blur/off, afterAccept/off');
    return syncPhotoPrivacyBundle(
      isPhotoPrivate: isPrivate,
      blurPhotosForStrangers: false,
      photoVisibleAfterAcceptance: false,
    );
  }

  /// One Firestore merge + single [refreshUserData] — keeps private / blur /
  /// after-acceptance flags mutually consistent (replaces three separate toggles).
  Future<AuthResult> syncPhotoPrivacyBundle({
    required bool isPhotoPrivate,
    required bool blurPhotosForStrangers,
    required bool photoVisibleAfterAcceptance,
  }) async {
    try {
      if (_currentUser == null) {
        return AuthResult.failure('No user logged in');
      }
      debugPrint(
        '🔄 syncPhotoPrivacyBundle: private=$isPhotoPrivate blur=$blurPhotosForStrangers '
        'afterAccept=$photoVisibleAfterAcceptance',
      );
      await syncAuthUid(_currentUser!.id);
      final result = await FirestoreRepository.setDocument(
        Collections.users,
        _currentUser!.id,
        {
          Fields.isPhotoPrivate: isPhotoPrivate,
          'isPhotoPrivate': isPhotoPrivate,
          'privacy_blur_photos_for_strangers': blurPhotosForStrangers,
          'privacy_photo_visible_after_acceptance': photoVisibleAfterAcceptance,
          Fields.photoPrivacyUpdatedAt: FieldValue.serverTimestamp(),
          // Legacy nested `profile` map (shallow merge — other profile keys kept).
          'profile': {
            'is_photo_private': isPhotoPrivate,
            'isPhotoPrivate': isPhotoPrivate,
          },
        },
        merge: true,
      );
      if (result.isError) {
        throw Exception(result.message);
      }
      await refreshUserData();
      ProfileRepository().invalidateProfileCache(_currentUser!.id);
      notifyListeners();
      // Notify any requester/profile UI on this device to recompute photo access
      // and evict proxied-photo caches (prevents stale "allowed" images).
      AccessRequestBroadcast.notifyChanged();
      unawaited(ProtectedImageCacheService.clearProtectedImageCache());
      debugPrint('✅ syncPhotoPrivacyBundle saved');
      return AuthResult.success('Photo privacy updated');
    } catch (e) {
      debugPrint('❌ syncPhotoPrivacyBundle failed: $e');
      return AuthResult.failure(e.toString());
    }
  }

  /// Sync auth_uid field with Firebase Auth UID for security rules
  Future<void> _syncAuthUid(String userId) async {
    try {
      debugPrint('🔐 SYNCING AUTH_UID for user: $userId');

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('⚠️ No Firebase Auth user found for auth_uid sync');
        return;
      }

      await FirebaseFirestore.instance.collection(Collections.users).doc(userId).set({
        'auth_uid': currentUser.uid,
        'auth_uid_synced_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ AUTH_UID SYNCED: ${currentUser.uid} for user $userId');
    } catch (e) {
      debugPrint('❌ FAILED TO SYNC AUTH_UID: $e');
    }
  }

  /// Enable biometric authentication
  Future<AuthResult> enableBiometrics() async {
    try {
      _errorMessage = null;

      if (_currentUser == null) {
        return AuthResult.failure('No user logged in');
      }

      final success = await _localAuth.setupBiometrics();
      if (success) {
        return AuthResult.success('Biometrics enabled');
      }

      return AuthResult.failure('Failed to enable biometrics');
    } catch (e) {
      _errorMessage = 'Failed to enable biometrics: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Reset password
  Future<AuthResult> resetPassword(String email) async {
    try {
      _errorMessage = null;

      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success('Password reset email sent');
    } catch (e) {
      _errorMessage = 'Failed to send password reset email: $e';
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Waits until session + gender are available for discovery (Matches / Home feeds).
  Future<bool> ensureReadyForDiscovery({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_currentUser == null) {
        if (!_isInitialized) {
          try {
            await initialize();
          } catch (_) {}
        } else {
          await _ensureCurrentUserFromAuthSession();
        }
      }
      final gender = await _resolveMyGenderForMatchingOnce();
      if (gender != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return (await _resolveMyGenderForMatchingOnce()) != null;
  }

  Future<String?> _resolveMyUserDocIdForMatching() async {
    final fromUser = _currentUser?.id.trim() ?? '';
    if (fromUser.isNotEmpty) return fromUser;
    final fromIdentity = IdentityProvider.userDocId.trim();
    if (fromIdentity.isNotEmpty) return fromIdentity;
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return null;
    final user = await _tryLoadUserDocForFirebaseUid(uid);
    if (user != null) {
      if (_currentUser == null) {
        _currentUser = user;
        await _syncIdentityPrefsFromCurrentUser();
        notifyListeners();
      }
      return user.id;
    }
    return null;
  }

  Future<Gender?> _resolveMyGenderForMatchingOnce() async {
    final fromProfile = _currentUser?.profile?.gender;
    if (fromProfile != null) return fromProfile;
    final id = await _resolveMyUserDocIdForMatching();
    if (id == null || id.isEmpty) return null;
    try {
      final snap = await _db.collection(Collections.users).doc(id).get();
      if (!snap.exists) return null;
      final data = normalizeFirestoreMap(snap.data());
      return genderFromUserDocumentData(data);
    } catch (e) {
      debugPrint('⚠️ _resolveMyGenderForMatchingOnce: $e');
    }
    return null;
  }

  Future<Gender?> _resolveMyGenderForMatching() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (_currentUser == null) {
        if (!_isInitialized) {
          try {
            await initialize();
          } catch (_) {}
        } else {
          await _ensureCurrentUserFromAuthSession();
        }
      }
      final gender = await _resolveMyGenderForMatchingOnce();
      if (gender != null) return gender;
      if (attempt < 5) {
        await Future<void>.delayed(
          Duration(milliseconds: 60 * (attempt + 1)),
        );
      }
    }
    return null;
  }

  /// Get matching profiles
  Future<MatchingProfilesPage> getMatchingProfiles({
    FilterPreferences? filters,
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    try {
      if (_currentUser == null) {
        await _ensureCurrentUserFromAuthSession();
      }
      if (_currentUser == null) {
        return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
      }

      final out = <app_models.User>[];
      while (out.length < limit && _matchProfileOverflow.isNotEmpty) {
        out.add(_matchProfileOverflow.removeAt(0));
      }
      if (out.length >= limit) {
        return MatchingProfilesPage(
          users: out,
          lastDoc: lastDoc,
          hasMore: true,
        );
      }

      final myGender = await _resolveMyGenderForMatching();
      if (myGender == null) {
        debugPrint(
            '⚠️ getMatchingProfiles: user gender unknown — cannot load opposite-gender profiles');
        return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
      }
      final targetGender = myGender == Gender.male ? 'female' : 'male';
      debugPrint(
          '🔍 getMatchingProfiles: myGender=${myGender.name}, client filter '
          'opposite=$targetGender (broad Firestore fetch + Dart filters)');

      final fetchSize = _discoveryFetchSize(limit);
      DocumentSnapshot? cursor = lastDoc;
      var nSelf = 0,
          nDeleted = 0,
          nCompletion = 0,
          nGender = 0,
          nParse = 0,
          nUnknown = 0;
      var rawTotal = 0;
      var serverHasMore = false;

      while (out.length < limit) {
        final snap =
            await _broadActiveUsersPage(startAfter: cursor, fetchSize: fetchSize);
        if (snap.docs.isEmpty) {
          serverHasMore = false;
          break;
        }
        rawTotal += snap.docs.length;
        serverHasMore = snap.docs.length >= fetchSize;
        cursor = snap.docs.last;

        for (final doc in snap.docs) {
          late final app_models.User user;
          try {
            user = app_models.User.fromFirestore(doc.data(), doc.id);
          } catch (e, st) {
            nParse++;
            if (kDebugMode) {
              debugPrint(
                'DISCOVERY EXCLUDE user=${doc.id} reason=profile_parse_failed $e\n$st',
              );
            }
            continue;
          }
          if (user.id == _currentUser!.id) {
            nSelf++;
            continue;
          }
          if (user.isDeleted) {
            nDeleted++;
            continue;
          }
          if (!ProfileCompletionPolicy.isEligibleForDiscovery(user)) {
            nCompletion++;
            continue;
          }
          final peerGender = user.profile?.gender ??
              genderFromUserDocumentData(doc.data());
          if (peerGender == null) {
            nUnknown++;
            continue;
          }
          if (peerGender == myGender) {
            nGender++;
            if (kDebugMode) {
              final raw = (doc.data()['profile'] is Map<String, dynamic>
                      ? (doc.data()['profile'] as Map<String, dynamic>)['gender']
                      : null) ??
                  doc.data()['gender'] ??
                  doc.data()['sex'] ??
                  peerGender.genderName;
              ProfileCompletionPolicy.logDiscoveryGenderExclude(
                user,
                rawLabel: '$raw',
                myGender: myGender,
                targetGenderCanonical: targetGender,
              );
            }
            continue;
          }
          if (out.length < limit) {
            out.add(user);
          } else {
            _matchProfileOverflow.add(user);
          }
        }

        if (!serverHasMore) break;
      }

      if (kDebugMode && out.isEmpty && rawTotal > 0) {
        debugPrint(
          'DISCOVERY FUNNEL getMatchingProfiles raw=$rawTotal '
          'self=$nSelf deleted=$nDeleted completion=$nCompletion gender=$nGender '
          'unknownGender=$nUnknown parse=$nParse duplicate=0',
        );
      }

      return MatchingProfilesPage(
        users: out,
        lastDoc: cursor,
        hasMore: serverHasMore || _matchProfileOverflow.isNotEmpty,
      );
    } catch (e) {
      _errorMessage = 'Failed to get matching profiles: $e';
      debugPrint('❌ getMatchingProfiles error: $e');
      return MatchingProfilesPage(users: [], lastDoc: null, hasMore: false);
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
  }

  // ─── User lookup helpers (delegating to FirestoreService) ───────────

  final FirestoreService _firestoreService = FirestoreService();

  Future<app_models.User?> getUserById(String userId) =>
      _firestoreService.getUserById(userId);

  Future<app_models.User?> getUserByProfileId(String profileId) async {
    final snap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .where('profile_id', isEqualTo: profileId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return app_models.User.fromFirestore(doc.data(), doc.id);
  }

  Future<app_models.User?> getUserByMobile(String mobile) async {
    final snap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .where('mobile_number', isEqualTo: mobile)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return app_models.User.fromFirestore(doc.data(), doc.id);
  }

  // Tries profileId, then Firestore doc id, then Firebase Auth uid — in that order
  Future<app_models.User?> getUserByAnyId(String id) async {
    return await getUserByProfileId(id) ??
        await getUserById(id) ??
        await _getUserByAuthUid(id);
  }

  Future<app_models.User?> getUserByUidField(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .where('auth_uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return app_models.User.fromFirestore(doc.data(), doc.id);
  }

  Future<app_models.User?> _getUserByAuthUid(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .where('auth_uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return app_models.User.fromFirestore(doc.data(), doc.id);
  }

  // ─── Profile-level helpers ───────────────────────────────────

  Future<void> setCurrentUser(app_models.User user) async {
    _currentUser = user;
    _attachUserDocumentListener(user.id);
    notifyListeners();
  }

  // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
  String? getCurrentUid() {
    // 🔥 DEPRECATED: This method should NOT be used for business logic
    // Only for auth_uid sync with Firestore
    return _auth.currentUser?.uid;
  }

  void updateCurrentUserProfileLocally(app_models.User updatedUser) {
    _currentUser = updatedUser;
    notifyListeners();
  }

  Future<String?> updateProfileIdGenderPrefix(
      String firestoreDocId, String currentProfileId, String gender) async {
    final prefix = gender.toLowerCase() == 'female' ? 'BVV-F-' : 'BVV-M-';
    if (currentProfileId.startsWith(prefix)) return currentProfileId;
    final newId =
        '$prefix${currentProfileId.replaceAll(RegExp(r'^BVV-[MF]-'), '')}';
    await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(firestoreDocId)
        .update({'profile_id': newId});
    return newId;
  }

  /// Generate and save profile_id if missing (for legacy users created before profile_id was required)
  Future<String> ensureProfileId(String userId, String gender) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) return '';

      final data = doc.data()!;
      final existingProfileId = data['profile_id'] as String? ?? '';

      if (existingProfileId.isNotEmpty) {
        return existingProfileId;
      }

      // Generate new profile ID
      final newProfileId = app_models.User.generateProfileIdForGender(
          gender.toLowerCase() == 'female' ? Gender.female : Gender.male);

      // Save to Firestore
      await _db.collection(Collections.users).doc(userId).update({
        'profile_id': newProfileId,
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint(
          '✅ Generated missing profile_id for user $userId: $newProfileId');
      return newProfileId;
    } catch (e) {
      debugPrint('⚠️ Failed to ensure profile_id: $e');
      return '';
    }
  }

  // ─── Pagination helpers ──────────────────────────────────────

  DocumentSnapshot? _lastProfileDoc;

  void resetProfilePagination() {
    _lastProfileDoc = null;
    _matchProfileOverflow.clear();
  }

  Future<MatchingProfilesPage> fetchMatchingProfilesPage(
      FilterPreferences filters,
      {int limit = 20}) async {
    final page = await getMatchingProfiles(
      filters: filters,
      limit: limit,
      lastDoc: _lastProfileDoc,
    );
    _lastProfileDoc = page.lastDoc;
    return page;
  }

  Future<List<app_models.User>> getRecentlyAddedProfiles(
      {int limit = 20}) async {
    // Recent tab retention policy:
    // 1) only profiles created within the last 7 days
    // 2) keep at most the latest 10 profiles (oldest drops first)
    const maxRecentWindow = 10;
    const recentDays = 7;
    final effectiveLimit = limit.clamp(1, maxRecentWindow);
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: recentDays));
    final fetchSize = _discoveryFetchSize(effectiveLimit);
    final out = <app_models.User>[];
    final registrationByUserId = <String, DateTime>{};
    DocumentSnapshot? cursor;
    var nSelf = 0,
        nDeleted = 0,
        nCompletion = 0,
        nGender = 0,
        nParse = 0,
        nUnknown = 0;
    var rawTotal = 0;
    var pagesScanned = 0;
    const maxPagesToScan = 12;

    DateTime? registeredAtFromDoc(Map<String, dynamic> data) {
      final raw =
          data['created_at'] ??
          data['createdAt'] ??
          data['registered_at'] ??
          data['registeredAt'] ??
          data['joined_at'] ??
          data['joinedAt'];
      if (raw is Timestamp) return raw.toDate().toUtc();
      if (raw is DateTime) return raw.toUtc();
      if (raw is String) return DateTime.tryParse(raw)?.toUtc();
      return null;
    }

    while (out.length < effectiveLimit && pagesScanned < maxPagesToScan) {
      pagesScanned++;
      final snap =
          await _broadActiveUsersPage(startAfter: cursor, fetchSize: fetchSize);
      if (snap.docs.isEmpty) break;
      rawTotal += snap.docs.length;
      cursor = snap.docs.last;

      for (final d in snap.docs) {
        final data = d.data();
        late final app_models.User u;
        try {
          u = app_models.User.fromFirestore(data, d.id);
        } catch (e, st) {
          nParse++;
          if (kDebugMode) {
            debugPrint(
              'DISCOVERY EXCLUDE user=${d.id} reason=profile_parse_failed $e\n$st',
            );
          }
          continue;
        }
        if (u.id == _currentUser?.id) {
          nSelf++;
          continue;
        }
        if (u.isDeleted) {
          nDeleted++;
          continue;
        }
        if (!ProfileCompletionPolicy.isEligibleForDiscovery(u)) {
          nCompletion++;
          continue;
        }
        // Recently Added is a recency feed, not a gender-matching feed.
        // Keep profile eligibility gates, but do not exclude by gender here.
        final registeredAt = registeredAtFromDoc(data) ?? u.createdAt.toUtc();
        if (registeredAt.isBefore(cutoff)) {
          // Do not short-circuit here: legacy datasets may mix timestamp/string
          // types so strict monotonic ordering is not guaranteed.
          continue;
        }
        out.add(u);
        registrationByUserId[u.id] = registeredAt;
        if (out.length >= effectiveLimit) break;
      }

      if (snap.docs.length < fetchSize) break;
    }

    if (kDebugMode && out.isEmpty && rawTotal > 0) {
      debugPrint(
        'DISCOVERY FUNNEL getRecentlyAddedProfiles raw=$rawTotal '
        'self=$nSelf deleted=$nDeleted completion=$nCompletion gender=$nGender '
        'unknownGender=$nUnknown parse=$nParse duplicate=0',
      );
    }
    out.sort((a, b) {
      final tb = registrationByUserId[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta = registrationByUserId[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    if (out.isNotEmpty) {
      return out.take(maxRecentWindow).toList();
    }

    // Fallback: if 7-day window yields nothing but data exists, return the
    // latest profiles without date-window filtering. This handles mixed legacy
    // timestamp formats where strict date parsing can under-include.
    final relaxed = <app_models.User>[];
    final relaxedRegistration = <String, DateTime>{};
    cursor = null;
    pagesScanned = 0;
    while (relaxed.length < effectiveLimit && pagesScanned < maxPagesToScan) {
      pagesScanned++;
      final snap =
          await _broadActiveUsersPage(startAfter: cursor, fetchSize: fetchSize);
      if (snap.docs.isEmpty) break;
      cursor = snap.docs.last;
      for (final d in snap.docs) {
        final data = d.data();
        late final app_models.User u;
        try {
          u = app_models.User.fromFirestore(data, d.id);
        } catch (_) {
          continue;
        }
        if (u.id == _currentUser?.id) continue;
        if (u.isDeleted) continue;
        if (!ProfileCompletionPolicy.isEligibleForDiscovery(u)) continue;
        final registeredAt = registeredAtFromDoc(data) ?? u.createdAt.toUtc();
        relaxed.add(u);
        relaxedRegistration[u.id] = registeredAt;
        if (relaxed.length >= effectiveLimit) break;
      }
      if (snap.docs.length < fetchSize) break;
    }

    relaxed.sort((a, b) {
      final tb =
          relaxedRegistration[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta =
          relaxedRegistration[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return relaxed.take(maxRecentWindow).toList();
  }

  // ─── Membership helpers ────────────────────────────────────

  Future<void> refreshMembershipData() async => await refreshUserData();

  Future<List<Map<String, dynamic>>> getMembershipPlans() async {
    final ps = PlanService.instance;
    if (ps.activePlans.isEmpty) {
      await ps.loadPlans(force: true);
    }
    int daysForMonths(int m) {
      switch (m) {
        case 1:
          return 30;
        case 3:
          return 90;
        case 6:
          return 180;
        case 12:
          return 365;
        default:
          return (m * 30).clamp(1, 9999);
      }
    }

    return ps.activePlans
        .map(
          (p) => <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'tier': 'platinum',
            'days': daysForMonths(p.durationMonths),
            'price': p.discountedFee,
            'original_price':
                p.actualFee > p.discountedFee ? p.actualFee : null,
            'description': p.description,
            'is_popular': p.isPopular,
            'features': p.features,
            'is_active': p.isActive,
            'duration_months': p.durationMonths,
            'actual_fee': p.actualFee,
            'discounted_fee': p.discountedFee,
          },
        )
        .toList();
  }

  // ─── MPIN helpers ────────────────────────────────────────────────────

  Future<bool> checkMpin(String mpin) async {
    try {
      final result = await loginWithMpin(mpin);
      return result.success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeMpin(String oldMpin, String newMpin) async {
    final valid = await checkMpin(oldMpin);
    if (!valid) return false;
    final result = await setMpin(newMpin);
    return result.success;
  }

  // ─── Profile deletion ────────────────────────────────────────────────

  Future<bool> initiateProfileDeletion(String reason) async {
    try {
      final identityService = IdentityService();
      final userId = await identityService.getUserId();
      if (userId.isEmpty) return false;

      final scheduledAt = DateTime.now().add(
        const Duration(days: ProfileDeletionService.gracePeriodDays),
      );
      await FirebaseFirestore.instance.collection(Collections.users).doc(userId).update({
        'deletion_requested': true,
        'deletion_reason': reason,
        'deletion_requested_at': FieldValue.serverTimestamp(),
        'deletion_scheduled_at': Timestamp.fromDate(scheduledAt),
        // Hide from discover/matches immediately during grace period.
        'is_deleted': true,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('initiateProfileDeletion failed: $e');
      return false;
    }
  }

  /// Days until scheduled purge, or null if not in grace period.
  /// Returns 0 when the grace window has expired (purge pending/done).
  static int? pendingDeletionDaysFromData(Map<String, dynamic> data) {
    final raw = data['deletion_scheduled_at'];
    if (raw == null) return null;
    DateTime? scheduled;
    if (raw is Timestamp) scheduled = raw.toDate();
    if (raw is DateTime) scheduled = raw;
    if (scheduled == null) return null;
    final remaining = scheduled.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    final days = (remaining.inHours / 24).ceil();
    return days.clamp(0, ProfileDeletionService.gracePeriodDays);
  }

  // ─── Profile viewers stream ──────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> profileViewersStream(String profileId) {
    return FirebaseFirestore.instance
        .collection('profile_views')
        .where('viewedUserId', isEqualTo: profileId)
        .orderBy('viewedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ─── Auth Screen Helper Methods ─────────────────────────────────────────

  Future<AuthResult> loginByMpinOnly(
      {required String mobile, required String mpin}) async {
    try {
      final snap = await _db
          .collection(Collections.users)
          .where('mobile_number', isEqualTo: mobile)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return AuthResult.failure('User not found');
      final data = snap.docs.first.data();
      final hashedInput = _hashMpin(mpin);
      if (data['mpin_hash'] == hashedInput) {
        _currentUser = app_models.User.fromFirestore(data, snap.docs.first.id);
        await _syncIdentityPrefsFromCurrentUser();

        _attachUserDocumentListener(_currentUser!.id);
        notifyListeners();
        return AuthResult.success('Login successful');
      }
      return AuthResult.failure('Invalid MPIN');
    } catch (e) {
      return AuthResult.failure(e.toString());
    }
  }

  Future<bool> verifyMpinForUser(String userId, String mpin) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (!doc.exists) {
        _errorMessage = 'User not found';
        return false;
      }
      final data = doc.data()!;

      final hashedInput = _hashMpin(mpin);
      final storedHash = data['mpin_hash'] as String?;

      // No MPIN stored — new device scenario
      if (storedHash == null || storedHash.isEmpty) {
        _errorMessage = 'NEW_DEVICE_NO_MPIN';
        return false;
      }

      if (kDebugMode) {
        debugPrint('🔐 verifyMpinForUser: userId=$userId');
        debugPrint('🔐   input MPIN hash: $hashedInput');
        debugPrint('🔐   stored hash: $storedHash');
        debugPrint('🔐   match: ${storedHash == hashedInput}');
      }

      if (storedHash != hashedInput) {
        _errorMessage = 'Invalid MPIN. Please try again.';
        return false;
      }

      final pendingDays = pendingDeletionDaysFromData(data);
      if (pendingDays != null) {
        _errorMessage = 'PENDING_DELETION:$pendingDays';
        return false;
      }

      _errorMessage = null;
      return true;
    } catch (e) {
      debugPrint('🔐 verifyMpinForUser error: $e');
      _errorMessage = 'Verification error: $e';
      return false;
    }
  }

  Future<void> markSessionMpinVerified() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mpin_verified', true);
    await prefs.setBool('app_locked', false);
    await prefs.remove('logout_timestamp');
  }

  /// 🔥 CRITICAL: Sync auth_uid to user document for security rule compliance
  /// This is the ONLY place where direct Firebase Auth usage is allowed
  Future<void> syncAuthUid(String userId) async {
    try {
      // 🔥 EXCEPTION: Direct Firebase Auth usage allowed ONLY for auth_uid sync
      final firebaseAuthUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
      if (firebaseAuthUid == null || firebaseAuthUid.isEmpty) {
        debugPrint('⚠️ syncAuthUid: No Firebase Auth user');
        return;
      }

      await _db.collection(Collections.users).doc(userId).set({
        'auth_uid': firebaseAuthUid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ syncAuthUid: auth_uid synced for $userId');

      // 🔍 DEBUG: Verify the sync worked
      await _verifyAuthUidSync(userId, firebaseAuthUid);
    } catch (e) {
      debugPrint('⚠️ syncAuthUid failed: $e');
    }
  }

  /// 🔍 DEBUG: Verify auth_uid sync status
  Future<void> _verifyAuthUidSync(String userId, String expectedAuthUid) async {
    try {
      final doc = await _db.collection(Collections.users).doc(userId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final storedAuthUid = data['auth_uid'] as String? ?? 'NOT_FOUND';
        debugPrint('🔍 AUTH_UID DEBUG: User=$userId');
        debugPrint('🔍   Expected: $expectedAuthUid');
        debugPrint('🔍   Stored: $storedAuthUid');
        debugPrint(
            '🔍   Match: ${storedAuthUid == expectedAuthUid ? '✅ YES' : '❌ NO'}');
      } else {
        debugPrint('🔍 AUTH_UID DEBUG: User document not found for $userId');
      }
    } catch (e) {
      debugPrint('🔍 AUTH_UID DEBUG: Failed to verify - $e');
    }
  }

  Future<AuthResult> loginWithBiometric() async {
    try {
      final localAuth = LocalAuthentication();
      final didAuth = await localAuth.authenticate(
        localizedReason: 'Verify your identity',
        options:
            const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (didAuth) {
        return AuthResult.success('Biometric authentication successful');
      }
      return AuthResult.failure('Biometric authentication failed');
    } catch (e) {
      return AuthResult.failure(e.toString());
    }
  }

  Future<bool> cancelProfileDeletion(String userId) async {
    try {
      await _db.collection(Collections.users).doc(userId).update({
        'deletion_requested': false,
        'deletion_reason': FieldValue.delete(),
        'deletion_scheduled_at': null,
        'deletion_requested_at': null,
        'is_deleted': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Failed to cancel profile deletion: $e');
      return false;
    }
  }

  Future<AuthResult> restoreExistingSession(String mobile) async {
    try {
      debugPrint(
          '🔍 restoreExistingSession: Looking up user by mobile: $mobile');
      final snap = await _db
          .collection(Collections.users)
          .where('mobile_number', isEqualTo: mobile)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        debugPrint(
            '❌ restoreExistingSession: User not found for mobile: $mobile');
        return AuthResult.failure('No existing session found');
      }
      final data = snap.docs.first.data();
      final docId = snap.docs.first.id;
      debugPrint('✅ restoreExistingSession: Found user doc: $docId');
      debugPrint('   Raw data keys: ${data.keys.toList()}');
      debugPrint('   mobile_number: ${data['mobile_number'] ?? 'NOT FOUND'}');
      debugPrint('   profile_id: ${data['profile_id'] ?? 'NOT FOUND'}');
      debugPrint('   email: ${data['email'] ?? 'NOT FOUND'}');

      _currentUser = app_models.User.fromFirestore(data, docId);
      debugPrint(
          '✅ restoreExistingSession: User loaded - profileId=${_currentUser?.profileId}, mobile=${_currentUser?.mobileNumber}');
      if (_currentUser != null) {
        _logRestoreSanity(_currentUser!, source: 'restoreExistingSession');
      }

      await _syncIdentityPrefsFromCurrentUser();
      _activateWatermarkSession();

      _attachUserDocumentListener(_currentUser!.id);
      notifyListeners();
      return AuthResult.success('Session restored');
    } catch (e) {
      debugPrint('❌ restoreExistingSession error: $e');
      return AuthResult.failure(e.toString());
    }
  }

  String? _lastVerificationId;
  String? get lastVerificationId => _lastVerificationId;

  // Debug flag - set to true to bypass OTP in development
  // NOTE: For production, set to false and configure test phone numbers in Firebase Console
  static const bool _kDebugOtpBypass = false;
  static const String _kDebugOtpCode = '123456';

  /// Send OTP via 2Factor.in (NO reCAPTCHA required)
  Future<AuthResult> sendPhoneOtp(String phoneNumber) async {
    try {
      // DEBUG BYPASS: Only active if explicitly enabled
      if (kDebugMode && _kDebugOtpBypass) {
        debugPrint('⚠️ DEBUG MODE: Bypassing real OTP');
        return AuthResult.success('OTP sent (DEBUG: use 123456)');
      }

      debugPrint('📱 Sending OTP to: $phoneNumber');

      // Use 2Factor.in OTP service (no CAPTCHA needed)
      final result = await _twoFactor.sendOtp(phoneNumber);

      if (result.success) {
        debugPrint('✅ OTP sent successfully');
        return AuthResult.success(result.message);
      } else {
        _errorMessage = result.message;
        debugPrint('❌ Failed to send OTP: ${result.message}');
        return AuthResult.failure(result.message);
      }
    } catch (e) {
      _errorMessage = 'Failed to send OTP: $e';
      debugPrint('❌ Send OTP exception: $e');
      return AuthResult.failure(_errorMessage!);
    }
  }

  /// Verify OTP via 2Factor.in - uses anonymous Firebase auth (NO phone credential)
  Future<AuthResult> verifyOTPWithMobile(
      String mobile, String otp, String? verificationId) async {
    try {
      // DEBUG BYPASS: Accept debug code
      if (kDebugMode && _kDebugOtpBypass && otp == _kDebugOtpCode) {
        debugPrint('⚠️ DEBUG MODE: Accepting debug OTP $_kDebugOtpCode');

        // Sign in anonymously for debug mode
        if (_auth.currentUser == null) {
          await _auth.signInAnonymously();
        }
        return AuthResult.success('OTP verified (DEBUG)');
      }

      debugPrint('📱 Verifying OTP for: $mobile');

      // Verify OTP via 2Factor.in
      final result = await _twoFactor.verifyOtp(mobile, otp);

      if (result.success) {
        // OTP valid - use anonymous Firebase auth (no phone credential needed)
        if (_auth.currentUser == null) {
          final userCred = await _auth.signInAnonymously();
          debugPrint('✅ Signed in anonymously: ${userCred.user?.uid}');
        }

        debugPrint('✅ OTP verified successfully');
        return AuthResult.success('OTP verified');
      } else {
        _errorMessage = result.message;
        debugPrint('❌ OTP verification failed: ${result.message}');
        return AuthResult.failure(result.message);
      }
    } catch (e) {
      _errorMessage = 'Verification failed: $e';
      debugPrint('❌ Verify OTP exception: $e');
      return AuthResult.failure(_errorMessage!);
    }
  }

  Future<AuthResult> setMpinForUser(String mobile, String mpin) async {
    try {
      final snap = await _db
          .collection(Collections.users)
          .where('mobile_number', isEqualTo: mobile)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        return AuthResult.failure('User not found');
      }
      final userId = snap.docs.first.id;
      final hashedMpin = _hashMpin(mpin);

      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      await _syncAuthUid(userId);

      // Use set with merge to include auth_uid in the update (required by security rules)
      await _db.collection(Collections.users).doc(userId).set({
        'mpin_hash': hashedMpin,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also save to local auth for device-specific MPIN (matches setMpin behavior)
      await _localAuth.saveMpin(hashedMpin);
      return AuthResult.success('MPIN set successfully');
    } catch (e) {
      return AuthResult.failure(e.toString());
    }
  }

  /// Create Firestore user after mobile OTP + anonymous Firebase Auth session.
  /// MPIN is set on [Routes.mpinSetup].
  Future<AuthResult> registerWithMobileOtp(
    String mobile, {
    String? alternateMobile,
  }) async {
    try {
      _errorMessage = null;

      final fbUser = _auth.currentUser;
      if (fbUser == null) {
        return AuthResult.failure(
          'Session expired. Please go back and verify OTP again.',
        );
      }

      final snap = await _db
          .collection(Collections.users)
          .where('mobile_number', isEqualTo: mobile)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return AuthResult.failure('User already exists');
      }

      final uid = fbUser.uid;
      final email = '$mobile@mobile.manamatrimony.com';

      final userData = <String, dynamic>{
        'mobile_number': mobile,
        'auth_uid': uid,
        'email': email,
        'status': 'active',
        'is_deleted': false,
        'is_profile_complete': false,
        'profile_completion_percentage': 0,
        'is_phone_verified': true,
        'is_email_verified': false,
        'mpin_verified': false,
        'first_name': '',
        'last_name': '',
        'membership': {
          'tier': 'free',
          'startDate': null,
          'expiryDate': null,
        },
        'membership_json': {
          'tier': 'free',
          'startDate': null,
          'expiryDate': null,
        },
        'profile': {
          'first_name': '',
          'last_name': '',
        },
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        Fields.schemaVersion: 1,
      };

      if (alternateMobile != null && alternateMobile.trim().isNotEmpty) {
        userData['alternative_mobile_number'] = alternateMobile.trim();
      }

      await _db.collection(Collections.users).doc(uid).set(userData);

      final identityService = IdentityService();
      await identityService.setUserId(uid);
      // The public profile_id is gendered, so it is generated only after the
      // profile wizard confirms gender. Use the doc id as provisional local
      // identity so MPIN setup can route the user into the wizard.
      await identityService.setProfileId(uid);

      final doc = await _db.collection(Collections.users).doc(uid).get();
      if (!doc.exists || doc.data() == null) {
        return AuthResult.failure(
            'Failed to create account. Please try again.');
      }

      final user = app_models.User.fromFirestore(doc.data()!, uid);
      _currentUser = user;
      _activateWatermarkSession();
      await _sessionManager.startSession(user);
      _attachUserDocumentListener(user.id);
      notifyListeners();

      return AuthResult.success('Registration successful');
    } catch (e) {
      debugPrint('❌ registerWithMobileOtp: $e');
      _errorMessage = e.toString();
      return AuthResult.failure(e.toString());
    }
  }
}
