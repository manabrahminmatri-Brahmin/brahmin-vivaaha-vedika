import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/privacy_enforcement_service.dart';
import '../utils/profile_field_mapping.dart';
import 'gender.dart';
import 'membership.dart';

/// User authentication and profile model
class User {
  final String id;
  final String profileId; // Unique profile ID: MB/MG + 5 digits (e.g. MB47218 / MG38492)
  final String email;
  final String password; // In production, this would be hashed
  final String mobileNumber;
  final String? alternativeMobileNumber; // Alternative contact number
  final String? mpin; // 4-digit MPIN (hashed in secure storage)
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final String? verificationCode;
  final DateTime? verificationCodeExpiry;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final UserProfile? profile;
  final Membership membership; // User membership status
  final bool isProfileLocked; // Profile locked after creation for free users
  final String? deletionReason; // Reason for profile deletion request
  final DateTime? deletionRequestedAt; // When deletion was requested
  final bool isDeleted; // Whether profile is marked for deletion
  final double? weight; // Weight in kg or lbs
  final bool isProfileComplete;
  final int profileCompletionPercentage;
  final DateTime? profileUpdatedAt;
  final bool isVerified;
  final bool isAdmin; // Admin user flag
  final String? adminRole; // Admin role descriptor
  final List<String>? adminPermissions; // Admin permission keys
  final String? mpinHash; // Hashed MPIN stored in Firestore
  // Live status fields — written by auth_service on login/active and read by
  // profile_detail_screen to show the green online dot.
  final bool isOnline;           // true while app is in foreground
  final DateTime? lastActive;    // Updated every ~5 min while app is open
  final String? authUid;         // Firebase Auth UID (may differ from Firestore doc ID for legacy accounts)

  /// Key for [PresenceService.watchUser] — Firestore `users/{id}` document id.
  String get presenceWatchId {
    final doc = id.trim();
    if (doc.isNotEmpty) return doc;
    final uid = authUid?.trim();
    if (uid != null && uid.isNotEmpty) return uid;
    return profileId.trim();
  }

  /// ALWAYS use this getter for Firebase Auth UID — never use `id` directly
  /// For modern accounts: returns Firebase Auth UID
  /// For legacy accounts: returns stored auth_uid or falls back to id (with warning)
  String get firebaseAuthUid {
    if (authUid == null || authUid!.isEmpty) {
      debugPrint('⚠️ WARNING: authUid missing for user $id, falling back to Firestore doc ID. Consider backfilling auth_uid field.');
    }
    return authUid ?? id;
  }

  static String _requireNonEmptyId(String? id) {
    final v = id?.trim() ?? '';
    if (v.isEmpty) {
      throw ArgumentError(
        'User requires a non-empty Firestore-backed id (no UUID fallback).',
      );
    }
    return v;
  }

  User({
    String? id,
    String? profileId,
    required this.email,
    required this.password,
    required this.mobileNumber,
    this.alternativeMobileNumber,
    this.mpin,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.verificationCode,
    this.verificationCodeExpiry,
    DateTime? createdAt,
    this.lastLoginAt,
    this.profile,
    Membership? membership,
    this.isProfileLocked = false,
    this.deletionReason,
    this.deletionRequestedAt,
    this.isDeleted = false,
    this.weight,
    this.isProfileComplete = false,
    this.profileCompletionPercentage = 0,
    this.profileUpdatedAt,
    this.isVerified = false,
    this.isAdmin = false,
    this.adminRole,
    this.adminPermissions,
    this.mpinHash,
    this.isOnline = false,
    this.lastActive,
    this.authUid,
  })  : id = _requireNonEmptyId(id),
        profileId = profileId ?? _generateProfileId(profile?.gender),
        createdAt = createdAt ?? DateTime.now(),
        membership = membership ?? Membership.free();

  /// Check if user is premium member
  bool get isPremium => membership.isPremium;

  /// Check if user can edit profile
  bool get canEditProfile => isPremium || !isProfileLocked;

  // ─────────────────────────────────────────────────────────────────────────────
  // PROFILE GETTERS (for repository compatibility)
  // These delegate to the UserProfile for easy access by repositories and services
  // ─────────────────────────────────────────────────────────────────────────────

  /// Get first name from profile
  String get firstName => profile?.firstName ?? '';
  
  /// Get last name from profile
  String get lastName => profile?.lastName ?? '';
  
  /// Get gender from profile
  Gender get gender => profile?.gender ?? Gender.male;
  
  /// Get date of birth from profile
  DateTime get dateOfBirth => profile?.dateOfBirth ?? DateTime(1990, 1, 1);
  
  /// Get age from profile (calculated from date of birth)
  int get age {
    final now = DateTime.now();
    final dob = dateOfBirth;
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }
  
  /// Get height from profile
  String? get height => profile?.height;
  
  /// Get religion/sect from profile
  String? get religion => profile?.sect;
  
  /// Get community/sub-sect from profile
  String? get community => profile?.subSect;
  
  /// Get mother tongue from profile
  String? get motherTongue => profile?.languages?.isNotEmpty == true ? profile!.languages!.first : null;
  
  /// Get country from profile
  String? get country => profile?.country;
  
  /// Get state from profile
  String? get state => profile?.state;
  
  /// Get city from profile
  String? get city => profile?.city;
  
  /// Get education from profile
  String? get education => profile?.education;
  
  /// Get occupation from profile
  String? get occupation => profile?.occupation;
  
  /// Get income range from profile
  String? get income => profile?.incomeRange;
  
  /// Get family type from profile
  String? get familyType => profile?.familyType;
  
  /// Get family values from profile
  String? get familyValues => profile?.familyValues;
  
  /// Get family status from profile
  String? get familyStatus => profile?.familyStatus;
  
  /// Get photos from profile
  List<String> get photos => profile?.photos ?? [];

  /// Generate a unique profile ID (6 characters total)
  /// MBXXXX for brides (female), MGXXXX for grooms (male)
  /// Uses 1111-9999 range to match SQL database generation
  static String _generateProfileId(Gender? gender) {
    final random = Random.secure();
    // ✅ Generate 5 random digits (10000–99999) to match firebase_service format
    final code = (10000 + random.nextInt(90000)).toString();

    if (gender == Gender.female) {
      return 'MB$code'; // Bride ID: MB + 5 digits  e.g. MB47218
    } else if (gender == Gender.male) {
      return 'MG$code'; // Groom ID: MG + 5 digits  e.g. MG38492
    } else {
      // Gender unknown at registration — defaults to MB prefix.
      // firebase_service.updateProfileIdGenderPrefix() fixes it after profile wizard.
      return 'MB$code';
    }
  }
  
  /// Generate a profile ID based on gender (used when profile is created/updated)
  /// Uses 10000-99999 range (5 digits) for consistency with _generateProfileId
  static String generateProfileIdForGender(Gender gender) {
    final random = Random.secure();
    final code = (10000 + random.nextInt(90000)).toString(); // 5 digits: 10000-99999
    return gender == Gender.female ? 'MB$code' : 'MG$code';
  }

  User copyWith({
    String? id,
    String? profileId,
    String? email,
    String? password,
    String? mobileNumber,
    String? alternativeMobileNumber,
    String? mpin,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    String? verificationCode,
    DateTime? verificationCodeExpiry,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    UserProfile? profile,
    Membership? membership,
    bool? isProfileLocked,
    String? deletionReason,
    DateTime? deletionRequestedAt,
    bool? isDeleted,
    double? weight,
    bool? isProfileComplete,
    int? profileCompletionPercentage,
    DateTime? profileUpdatedAt,
    bool? isVerified,
    bool? isAdmin,
    String? adminRole,
    List<String>? adminPermissions,
    String? mpinHash,
    bool? isOnline,
    DateTime? lastActive,
    String? authUid,
  }) {
    return User(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      email: email ?? this.email,
      password: password ?? this.password,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      alternativeMobileNumber: alternativeMobileNumber ?? this.alternativeMobileNumber,
      mpin: mpin ?? this.mpin,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      verificationCode: verificationCode ?? this.verificationCode,
      verificationCodeExpiry: verificationCodeExpiry ?? this.verificationCodeExpiry,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      profile: profile ?? this.profile,
      membership: membership ?? this.membership,
      isProfileLocked: isProfileLocked ?? this.isProfileLocked,
      deletionReason: deletionReason ?? this.deletionReason,
      deletionRequestedAt: deletionRequestedAt ?? this.deletionRequestedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      weight: weight ?? this.weight,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      profileCompletionPercentage: profileCompletionPercentage ?? this.profileCompletionPercentage,
      profileUpdatedAt: profileUpdatedAt ?? this.profileUpdatedAt,
      isVerified: isVerified ?? this.isVerified,
      isAdmin: isAdmin ?? this.isAdmin,
      adminRole: adminRole ?? this.adminRole,
      adminPermissions: adminPermissions ?? this.adminPermissions,
      mpinHash: mpinHash ?? this.mpinHash,
      isOnline: isOnline ?? this.isOnline,
      lastActive: lastActive ?? this.lastActive,
      authUid: authUid ?? this.authUid,
    );
  }

  /// Convert to Map for compatibility with AuthService
  Map<String, dynamic> toMap() => {
    'id': id,
    'auth_uid': authUid,
    'profile_id': profileId,
    'email': email,
    'mobile_number': mobileNumber,
    'alternative_mobile_number': alternativeMobileNumber,
    'mpin': mpin,
    'isEmailVerified': isEmailVerified,
    'isPhoneVerified': isPhoneVerified,
    'verificationCode': verificationCode,
    'verificationCodeExpiry': verificationCodeExpiry?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
    'profile': profile?.toMap(),
    'membership_tier': membership.tier.name,
    'membership_json': membership.toJson(),
    'isProfileLocked': isProfileLocked,
    'deletionReason': deletionReason,
    'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
    'isDeleted': isDeleted,
    'weight': weight,
    'isProfileComplete': isProfileComplete,
    'profileCompletionPercentage': profileCompletionPercentage,
    'profileUpdatedAt': profileUpdatedAt?.toIso8601String(),
    'isVerified': isVerified,
    'is_admin': isAdmin,
    'admin_role': adminRole,
    'admin_permissions': adminPermissions,
    'is_online': isOnline,
    'last_active': lastActive?.toIso8601String(),
  };
  /// 
  /// This method creates nested camelCase maps that Firestore queries cannot
  /// reach (e.g., profile.gender is nested, not queryable at root level).
  /// 
  /// toDatabaseJson() flattens all fields to root level with snake_case keys,
  /// making them accessible to Firestore compound queries.
  @Deprecated('Use toDatabaseJson() for Firestore writes. toJson() creates nested maps that break Firestore queries.')
  Map<String, dynamic> toJson() => {
        'id': id,
        'auth_uid': authUid, // Include Firebase Auth UID for consistency
        'profile_id': profileId,
        'email': email,
        // Secrets are never serialized — use SecureStorage / hashed fields only.
        'mobile_number': mobileNumber,
        'alternative_mobile_number': alternativeMobileNumber,
        'isEmailVerified': isEmailVerified,
        'verificationCode': verificationCode,
        'verificationCodeExpiry': verificationCodeExpiry?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'profile': profile?.toJson(),
        'membership_tier': membership.tier.name, // ✅ fixed: enum → String
        'membership_json': membership.toJson(),
        'isProfileLocked': isProfileLocked,
        'deletionReason': deletionReason,
        'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
        'isDeleted': isDeleted,
        'weight': weight,
        'isProfileComplete': isProfileComplete,
        'profileCompletionPercentage': profileCompletionPercentage,
        'profileUpdatedAt': profileUpdatedAt?.toIso8601String(),
        'isVerified': isVerified,
        'is_admin': isAdmin,
        'admin_role': adminRole,
        'admin_permissions': adminPermissions,
        'is_online': isOnline,
        'last_active': lastActive?.toIso8601String(),
      };

  /// Create from Firestore document data + document ID
  /// Delegates to fromJson() which handles both snake_case and camelCase
  factory User.fromFirestore(Map<String, dynamic> data, String id) {
    return User.fromJson({...data, 'id': id});
  }

  /// This is NOT deprecated because local storage doesn't affect Firestore queries.
  /// Use this instead of toJson() when saving to local device cache.
  Map<String, dynamic> toLocalCacheJson() => {
        'id': id,
        'auth_uid': authUid, // Include Firebase Auth UID for consistency
        'profile_id': profileId,
        'email': email,
        'mobile_number': mobileNumber,
        'alternative_mobile_number': alternativeMobileNumber,
        'isEmailVerified': isEmailVerified,
        'verificationCode': verificationCode,
        'verificationCodeExpiry': verificationCodeExpiry?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'profile': profile?.toJson(),
        'membership_tier': membership.tier.name,
        'membership_json': membership.toJson(),
        'isProfileLocked': isProfileLocked,
        'deletionReason': deletionReason,
        'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
        'isDeleted': isDeleted,
        'admin_role': adminRole,
        'admin_permissions': adminPermissions,
      };

  /// Converts User to a map matching Hasura/PostgreSQL column names.
  /// Use this for upsertUser — NOT toJson().
  Map<String, dynamic> toDatabaseJson() {
    final map = <String, dynamic>{
      'id': id,
      // Prefer live session UID so Firestore never drifts from Firebase Auth.
      'auth_uid': FirebaseAuth.instance.currentUser?.uid ?? authUid,
      'profile_id': profileId,
      'email': email,
      'mobile_number': mobileNumber,
      'alternative_mobile_number': alternativeMobileNumber,
      'is_email_verified': isEmailVerified,
      'is_profile_locked': isProfileLocked,
      'is_deleted': isDeleted,
      'admin_role': adminRole,
      'admin_permissions': adminPermissions,
      'is_profile_complete': isProfileComplete,
      'profile_completion_percentage': profileCompletionPercentage,
      'membership_tier': membership.tier.name,
      'membership_status': membership.tier.name,  // FIX: mirrors membership_tier for index compatibility
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (lastLoginAt != null) {
      map['last_login_at'] = lastLoginAt!.toIso8601String();
    }
    if (membership.expiryDate != null) {
      map['membership_expiry_date'] = membership.expiryDate!.toIso8601String();
    }
    // LIVE STATUS FIX: persist is_online and last_active so profile_detail_screen
    // can show accurate green dot without a separate Firestore read.
    map['is_online'] = isOnline;
    if (lastActive != null) {
      map['last_active'] = lastActive!.toIso8601String();
    }

    // DATA PROCESSING FIX: Flatten ALL UserProfile fields into the Firestore root doc.
    // Previously only 14 fields were written flat — the rest were buried in a camelCase
    // 'profile' nested map which Firestore compound queries cannot reach.
    // Now we merge toDatabaseMap() (snake_case, complete) so every field is both
    // queryable at the root level AND preserved in the nested 'profile' key.
    if (profile != null) {
      // 1. Write all fields flat (snake_case) using the authoritative toDatabaseMap()
      final flatFields = profile!.toDatabaseMap();
      map.addAll(flatFields);

      // 2. Always recalculate and overwrite profile_completion_percentage before saving.
      //    The stored value is often 0 because it was never computed at write time.
      final computedCompletion = profile!.calculateCompletionPercentage();
      map['profile_completion_percentage'] = computedCompletion;
      // FIX: Also update is_profile_complete based on actual completion percentage
      // A profile is "complete" when at least 80% of fields are filled
      map['is_profile_complete'] = computedCompletion >= 80;

      // 3. Also write the nested 'profile' key using toDatabaseMap() (snake_case)
      //    so User.fromJson can always find data via json['profile'] too.
      final profileNested = Map<String, dynamic>.from(flatFields);
      profileNested['profile_completion_percentage'] = computedCompletion;
      profileNested['is_profile_complete'] = computedCompletion >= 80;
      profileNested.removeWhere((_, v) => v == null);
      map['profile'] = profileNested;
    } else {
      // FALLBACK: When profile is null, ensure isProfileComplete reflects the stored percentage
      // This handles cases where User model is saved without a full profile object
      map['is_profile_complete'] = profileCompletionPercentage >= 80;
    }

    return map;
  }

  /// 🔥 FIX: Helper to parse Firestore Timestamp or ISO String to DateTime
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _toIsoDateString(dynamic value) {
    final dt = _parseDateTime(value);
    return dt?.toIso8601String();
  }

  /// Copy common legacy / alternate Firestore keys into canonical snake_case
  /// fields so [_hasAnyFlatProfileField] and [UserProfile.fromJson] see data.
  static Map<String, dynamic> _normalizeFirestoreProfileKeys(
    Map<String, dynamic> j,
  ) {
    void copyIfMissing(String target, List<String> sources) {
      final existing = j[target];
      if (existing != null && existing.toString().trim().isNotEmpty) return;
      for (final s in sources) {
        final v = j[s];
        if (v != null && v.toString().trim().isNotEmpty) {
          j[target] = v;
          return;
        }
      }
    }

    copyIfMissing('first_name', [
      'name',
      'full_name',
      'fullName',
      'display_name',
      'displayName',
      'firstName',
    ]);
    copyIfMissing('last_name', [
      'surname',
      'family_name',
      'familyName',
    ]);
    copyIfMissing('date_of_birth', [
      'dob',
      'birthdate',
      'dateOfBirth',
      'birth_date',
      'birthDate',
    ]);
    copyIfMissing('gender', [
      'sex',
      'user_gender',
      'profile_gender',
      'Gender',
      'gender_value',
    ]);
    copyIfMissing('education', [
      'education_level',
      'educationLevel',
      'qualification',
      'degree',
      'study',
      'academic_qualification',
    ]);
    copyIfMissing('occupation', [
      'job',
      'profession',
      'work',
      'employment',
      'career',
      'designation',
      'job_title',
      'jobTitle',
    ]);
    copyIfMissing('city', [
      'town',
      'district',
      'current_city',
      'native_city',
    ]);
    copyIfMissing('state', [
      'province',
      'region',
      'location_state',
    ]);
    copyIfMissing('country', ['location_country']);
    copyIfMissing('mobile_number', [
      'phone',
      'mobile',
      'phone_number',
      'phoneNumber',
      'contact_number',
    ]);
    copyIfMissing('about_me', [
      'bio',
      'description',
      'about',
      'about_self',
    ]);
    copyIfMissing('partner_preferences', [
      'expectations',
      'partner_expectation',
      'match_preferences',
    ]);
    copyIfMissing('profile_picture', [
      'avatar',
      'photo',
      'image',
      'profile_image',
      'display_photo',
      'photo_url',
    ]);
    copyIfMissing('father_occupation', ['fatherOccupation']);
    copyIfMissing('father_note', ['fatherNote']);
    copyIfMissing('mother_occupation', ['motherOccupation']);
    copyIfMissing('mother_note', ['motherNote']);
    copyIfMissing('mother_surname', ['motherSurname']);
    copyIfMissing('food_habit', ['foodHabit', 'food_habits', 'foodHabits']);
    copyIfMissing('smoking_habit', ['smokingHabit']);
    copyIfMissing('drinking_habit', ['drinkingHabit']);
    copyIfMissing('profile_completion_percentage', [
      'completion',
      'completion_percent',
      'profile_percent',
    ]);
    copyIfMissing('is_profile_complete', [
      'profile_complete',
      'is_complete',
    ]);
    return j;
  }

  static int _parseRootProfileCompletionPercent(Map<String, dynamic> normalized) {
    final keys = [
      'profile_completion_percentage',
      'profileCompletionPercentage',
      'completion',
      'completion_percent',
      'profile_percent',
    ];
    for (final k in keys) {
      final v = normalized[k];
      if (v is num) return v.round().clamp(0, 100);
      if (v is String) {
        final p = int.tryParse(v.trim());
        if (p != null) return p.clamp(0, 100);
      }
    }
    return 0;
  }

  static bool _coerceBool(dynamic v) =>
      v == true || v == 'true' || v == 1 || v == '1';

  static bool _parseRootProfileCompleteFlags(Map<String, dynamic> normalized) {
    bool truthy(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';
    return truthy(normalized['is_profile_complete']) ||
        truthy(normalized['isProfileComplete']) ||
        truthy(normalized['profile_complete']) ||
        truthy(normalized['is_complete']);
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final normalized =
        _normalizeFirestoreProfileKeys(Map<String, dynamic>.from(json));
    final rawId = normalized['id'] as String? ?? '';
    if (rawId.isEmpty) {
      throw ArgumentError(
        'User.fromJson requires non-empty id (expected Firestore document id).',
      );
    }
    return User(
      id: rawId,
      profileId: normalized['profile_id'] as String? ?? '',
      email: normalized['email'] as String? ?? '',
      password: normalized['password'] as String? ?? '',
      mobileNumber: normalized['mobile_number'] as String? ?? '',
      alternativeMobileNumber: normalized['alternative_mobile_number'] as String?,
      mpin: normalized['mpin'] as String?,
      mpinHash: normalized['mpin_hash'] as String?,
      isEmailVerified: normalized['is_email_verified'] as bool? ?? false,
      isPhoneVerified: normalized['is_phone_verified'] as bool? ?? false,
      verificationCode: normalized['verification_code'] as String?,
      verificationCodeExpiry:
          _parseDateTime(normalized['verification_code_expiry']),
      createdAt: _parseDateTime(normalized['created_at']) ?? DateTime.now(),
      lastLoginAt: _parseDateTime(normalized['last_login_at']),
      // ── Profile reconstruction ─────────────────────────────────────────────
      profile: normalized['profile'] != null
          ? UserProfile.fromJson(
              ProfileFieldMapping.convertProfileToSnakeCase(
                _mergeRootProfileFieldsIntoNestedProfile(
                  normalized['profile'] as Map<String, dynamic>,
                  normalized,
                ),
              ),
            )
          : _hasAnyFlatProfileField(normalized)
              ? UserProfile.fromJson(
                  ProfileFieldMapping.convertProfileToSnakeCase(normalized),
                )
              : null,
      // Root-level membership fields (admin / payments) must win over stale nested
      // membership_json, otherwise premium grants never show until the nested map is updated.
      membership: () {
        final nested = normalized['membership_json'];
        final merged = <String, dynamic>{
          if (nested is Map<String, dynamic>)
            ...Map<String, dynamic>.from(nested),
        };
        var tierRaw = (normalized['membership_tier'] as String? ??
                merged['tier'] as String? ??
                normalized['subscription_tier'] as String? ??
                'free')
            .toLowerCase()
            .trim();
        if (_coerceBool(normalized['is_premium']) ||
            _coerceBool(normalized['isPremium'])) {
          tierRaw = MembershipTier.platinum.name;
        }
        merged['tier'] = tierRaw;
        final expIso = _toIsoDateString(
          normalized['membership_expires_at'] ??
              normalized['membership_expiry_date'] ??
              merged['expiryDate'],
        );
        if (expIso != null) merged['expiryDate'] = expIso;
        final startIso = _toIsoDateString(
          normalized['membership_start_at'] ??
              normalized['membership_start_date'] ??
              merged['startDate'],
        );
        if (startIso != null) merged['startDate'] = startIso;
        return Membership.fromJson(merged);
      }(),
      isProfileLocked: normalized['is_profile_locked'] as bool? ?? false,
      deletionReason: normalized['deletion_reason'] as String?,
      deletionRequestedAt: _parseDateTime(normalized['deletion_requested_at']),
      isDeleted: normalized['is_deleted'] as bool? ?? false,
      isProfileComplete: _parseRootProfileCompleteFlags(normalized),
      profileCompletionPercentage: _parseRootProfileCompletionPercent(normalized),
      isVerified: _coerceBool(normalized['is_verified']) ||
          _coerceBool(normalized['isVerified']),
      isAdmin: _coerceBool(normalized['is_admin']) ||
          _coerceBool(normalized['isAdmin']),
      isOnline: normalized['is_online'] as bool? ?? false,
      adminRole: normalized['admin_role'] as String?,
      adminPermissions: (normalized['admin_permissions'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      lastActive: _parseDateTime(normalized['last_active']),
      authUid: normalized['auth_uid'] as String?,
    );
  }

  /// Factory constructor from Map (Firestore document)
  factory User.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'] as String? ?? '';
    if (rawId.isEmpty) {
      throw ArgumentError(
        'User.fromMap requires non-empty id (expected Firestore document id).',
      );
    }
    return User(
      id: rawId,
      profileId: map['profile_id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      password: map['password'] as String? ?? '',
      mobileNumber: map['mobile_number'] as String? ?? '',
      alternativeMobileNumber: map['alternative_mobile_number'] as String? ?? '',
      mpin: map['mpin'] as String?,
      mpinHash: map['mpin_hash'] as String?,
      isEmailVerified: map['is_email_verified'] as bool? ?? false,
      isPhoneVerified: map['is_phone_verified'] as bool? ?? false,
      verificationCode: map['verification_code'] as String?,
      verificationCodeExpiry: map['verification_code_expiry'] != null
              ? DateTime.tryParse(map['verification_code_expiry'] as String)
              : null,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      lastLoginAt: map['last_login_at'] != null
              ? DateTime.tryParse(map['last_login_at'] as String)
              : null,
      profile: map['profile'] != null
          ? UserProfile.fromMap(map['profile'] as Map<String, dynamic>)
          : null,
      membership: map['membership'] != null
          ? Membership.fromJson(map['membership'] as Map<String, dynamic>)
          : Membership.free(),
      isProfileLocked: map['is_profile_locked'] as bool? ?? false,
      deletionReason: map['deletion_reason'] as String?,
      deletionRequestedAt: map['deletion_requested_at'] != null
              ? DateTime.tryParse(map['deletion_requested_at'] as String)
              : null,
      isDeleted: map['is_deleted'] as bool? ?? false,
      weight: (map['weight'] as num?)?.toDouble(),
      isProfileComplete: map['is_profile_complete'] as bool? ?? false,
      profileCompletionPercentage: map['profile_completion_percentage'] as int? ?? 0,
      profileUpdatedAt: map['profile_updated_at'] != null
              ? DateTime.tryParse(map['profile_updated_at'] as String)
              : null,
      isVerified: map['is_verified'] as bool? ?? false,
      isAdmin: map['is_admin'] as bool? ?? false,
      adminRole: map['admin_role'] as String?,
      adminPermissions: (map['admin_permissions'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      isOnline: map['is_online'] as bool? ?? false,
      lastActive: map['last_active'] != null
          ? DateTime.tryParse(map['last_active'] as String)
          : null,
      authUid: map['auth_uid'] as String?,
    );
  }

  /// Single-field updates (e.g. [is_photo_private]) use [FirebaseService.updateUserProfile]
  /// at the **root** of `users/{id}`. Documents that also keep a nested `profile` map
  /// would otherwise ignore those root keys when building [UserProfile].
  static Map<String, dynamic> _mergeRootProfileFieldsIntoNestedProfile(
    Map<String, dynamic> nested,
    Map<String, dynamic> root,
  ) {
    final m = Map<String, dynamic>.from(nested);
    // Root Firestore docs often hold the authoritative profile fields while
    // nested `profile` may only contain a partial subset. Merge root fields
    // into nested map (without overwriting non-empty nested values) so restore
    // works consistently across devices/reinstalls.
    // Keep in sync with [UserProfile.toDatabaseMap] — root flat fields must flow
    // into nested `profile` on read (fixes "filled but due after restart").
    const rootProfileKeys = [
      'first_name', 'last_name', 'gender', 'date_of_birth', 'time_of_birth',
      'place_of_birth', 'place_of_birth_state', 'place_of_birth_country',
      'height', 'weight', 'complexion', 'body_type', 'physical_status',
      'sect', 'sub_sect', 'gothram', 'nakshatra', 'pada', 'rasi',
      'star_confirmed', 'manglik_status', 'has_horoscope',
      'education', 'specialization', 'education_status', 'university_name',
      'education_location_country', 'education_location_state',
      'education_location_city', 'additional_qualifications',
      'qualification_notes',
      'occupation', 'employment_type', 'company_name', 'business_description',
      'income_range',
      'marital_status', 'family_type', 'family_status', 'family_values',
      'father_name', 'father_occupation', 'father_note',
      'mother_name', 'mother_occupation', 'mother_note', 'mother_surname',
      'family_origin_country', 'family_origin_state', 'family_origin_city',
      'known_reference', 'known_reference_2',
      'brothers', 'brothers_married', 'sisters', 'sisters_married', 'about_family',
      'country', 'state', 'city',
      'native_place', 'native_place_country', 'native_place_state',
      'native_place_city',
      'food_habit', 'smoking_habit', 'drinking_habit',
      'hobbies', 'interests', 'languages', 'about_me',
      'partner_preferences', 'partner_expectations',
      'partner_age_min', 'partner_age_max',
      'partner_height_min', 'partner_height_max',
      'partner_education', 'partner_occupation', 'partner_income_min',
      'partner_marital_status', 'partner_locations', 'partner_manglik_preference',
      'willing_to_relocate', 'relocate_preference', 'settled_abroad', 'citizenship',
      'profile_created_by', 'profile_created_by_relation',
      'mobile_number',
    ];
    for (final k in rootProfileKeys) {
      dynamic rootVal = root[k];
      if (rootVal == null) {
        final camel = ProfileFieldMapping.toCamelCase(k);
        if (camel != k && root.containsKey(camel)) {
          rootVal = root[camel];
        } else {
          continue;
        }
      }
      final hasNested = m.containsKey(k) &&
          m[k] != null &&
          m[k].toString().trim().isNotEmpty;
      if (!hasNested && rootVal != null && rootVal.toString().trim().isNotEmpty) {
        m[k] = rootVal;
      }
    }
    // PhotoService / Firestore often write URLs on the root doc while legacy data
    // keeps a nested `profile` map — without merging, the UI keeps stale nested URLs.
    const photoKeys = [
      'profile_picture',
      'profilePicture',
      'photo_url',
      'photo_last_updated',
      'photoLastUpdated',
      'photo_updated_at',
      'photo_provider',
    ];
    for (final k in photoKeys) {
      if (root.containsKey(k)) {
        m[k] = root[k];
      }
    }
    for (final k in const ['is_photo_private', 'isPhotoPrivate', 'photo_private']) {
      if (root.containsKey(k)) {
        m['is_photo_private'] = root[k];
        break;
      }
    }
    // Privacy settings screen writes snake_case on the user root doc; UserProfile
    // reads show_online_status / show_last_seen on the nested map.
    if (root.containsKey('privacy_show_online_status')) {
      m['show_online_status'] = root['privacy_show_online_status'];
    }
    if (root.containsKey('privacy_show_last_seen')) {
      m['show_last_seen'] = root['privacy_show_last_seen'];
    }
    return m;
  }

  /// Returns true if the flat Firestore document contains at least one
  /// UserProfile field, meaning we should reconstruct the profile from root.
  static bool _hasAnyFlatProfileField(Map<String, dynamic> json) {
    const indicators = [
      // camelCase legacy/root variants
      'firstName', 'lastName', 'dateOfBirth', 'timeOfBirth', 'placeOfBirth',
      'gender', 'profileId', 'profilePicture', 'photoUrl', 'occupation',
      'education', 'city', 'state', 'country', 'maritalStatus',
      'first_name', 'last_name',
      'gender', 'date_of_birth', 'time_of_birth', 'place_of_birth',
      'place_of_birth_state', 'place_of_birth_country', 'height', 'weight',
      'complexion', 'body_type', 'physical_status', 'sect', 'sub_sect',
      'gothram', 'nakshatra', 'pada', 'rasi', 'star_confirmed',
      'manglik_status', 'has_horoscope', 'education', 'specialization',
      'education_status', 'university_name', 'education_location_country',
      'education_location_state', 'education_location_city', 'additional_qualifications',
      'qualification_notes', 'occupation', 'employment_type', 'company_name',
      'business_description', 'businessDescription', 'income_range', 'marital_status', 'family_type', 'family_status',
      'family_values', 'father_name', 'father_occupation', 'father_note',
      'mother_name', 'mother_occupation', 'mother_note', 'mother_surname',
      'food_habit', 'smoking_habit', 'drinking_habit',
      'fatherOccupation', 'motherOccupation', 'foodHabit',
      'brother_names', 'sister_names', 'hobbies', 'interests', 'languages', 'about_me',
      'partner_preferences', 'partner_min_age', 'partner_max_age',
      'partner_education', 'partner_occupation', 'partner_income_range',
      'partner_manglik_preference', 'partner_locations', 'willing_to_relocate',
      'relocate_preference', 'settled_abroad', 'citizenship',
      // Photo / privacy live on the root Firestore user doc — without these,
      // User.profile stayed null and isPhotoPrivate never applied app-wide.
      'is_photo_private', 'isPhotoPrivate',
      'profile_picture', 'profilePicture', 'photos',
      // Legacy / alternate shapes (also normalized into canonical keys above)
      'dob', 'dateOfBirth', 'birth_date', 'birthDate',
      'name', 'full_name', 'fullName', 'display_name', 'displayName',
      'education_level', 'educationLevel', 'qualification',
      'phone', 'mobile', 'phone_number', 'phoneNumber',
      'surname', 'family_name', 'familyName',
      'job', 'profession', 'job_title', 'jobTitle',
      'birthdate', 'sex', 'user_gender', 'profile_gender', 'gender_value',
      'town', 'district', 'current_city', 'native_city', 'province', 'region',
      'location_state', 'location_country',
      'bio', 'description', 'about', 'about_self',
      'expectations', 'partner_expectation', 'match_preferences',
      'avatar', 'photo', 'image', 'profile_image', 'display_photo',
      'contact_number',
      'completion', 'completion_percent', 'profile_percent',
      'profile_complete', 'is_complete',
    ];
    return indicators.any((k) {
      final v = json[k];
      return v != null && v.toString().trim().isNotEmpty;
    });
  }

  /// Check if profile deletion can be restored (within 7 days)
  bool get canRestoreProfile {
    if (!isDeleted || deletionRequestedAt == null) return false;
    final daysSinceDeletion = DateTime.now().difference(deletionRequestedAt!).inDays;
    return daysSinceDeletion <= 7;
  }

  /// Get days remaining to restore profile
  int? get daysRemainingToRestore {
    if (!isDeleted || deletionRequestedAt == null) return null;
    final daysSinceDeletion = DateTime.now().difference(deletionRequestedAt!).inDays;
    final remaining = 7 - daysSinceDeletion;
    return remaining > 0 ? remaining : 0;
  }

  /// For discovery list cards: real [profile] or a safe synthetic row (legacy docs).
  UserProfile get profileForDiscovery =>
      profile ?? UserProfile.fallbackForDiscovery(this);

  /// Whether this member's photo is hidden from others (root + nested profile).
  bool get photoHiddenFromOthers =>
      PrivacyEnforcementService.isPhotoHiddenForProfile(
        profile: profileForDiscovery,
      );

  /// Root + nested fields for [resolveProfilePhotoUrl] on list cards.
  Map<String, dynamic> discoveryPhotoFirestoreMap() {
    final p = profileForDiscovery;
    // Hard data-layer gate for discovery/home/matches:
    // Only expose a direct URL when we can confidently treat the photo as public.
    // If profile parsing is incomplete or privacy state is unknown/private, strip URL.
    final hasParsedProfile = profile != null;
    final isHiddenOrUnknown = !hasParsedProfile || photoHiddenFromOthers;
    final canExposeDiscoveryPhotoUrl = hasParsedProfile && !isHiddenOrUnknown;
    return <String, dynamic>{
      if (canExposeDiscoveryPhotoUrl &&
          (p.profilePicture ?? '').trim().isNotEmpty) ...{
        'profile_picture': p.profilePicture,
        'photo_url': p.profilePicture,
      },
      'is_photo_private': isHiddenOrUnknown,
      'isPhotoPrivate': isHiddenOrUnknown,
      'profile': {
        ...p.toJson(),
        'is_photo_private': isHiddenOrUnknown,
        'isPhotoPrivate': isHiddenOrUnknown,
      },
    };
  }
}

/// Complete user profile with all Vivaaha Vedika details
class UserProfile {
  // Basic Info
  final String id;
  final String firstName;
  final String lastName;
  final Gender gender;
  final DateTime dateOfBirth;
  final String? timeOfBirth; // HH:MM AM/PM format
  final String? placeOfBirth;
  final String? placeOfBirthState;
  final String? placeOfBirthCountry;

  // Physical Attributes
  final String? height;
  final String? complexion;
  final String? bodyType;
  final String? physicalStatus;

  // Religious / Astrological
  final String? sect;
  final String? subSect;
  final String? gothram;
  final String? nakshatra;
  final String? pada;
  final String? rasi;
  final bool? starConfirmed; // If user confirmed the auto-calculated star
  final String? manglikStatus; // Manglik / Non-Manglik / Partial Manglik
  final bool? hasHoroscope; // Whether horoscope is available

  // Education & Career
  final String? education;
  final String? specialization;
  final String? educationStatus; // Pursuing / Completed
  final String? universityName; // University/Institution name
  final String? educationLocationCountry; // Country where degree was completed
  final String? educationLocationState; // State where degree was completed
  final String? educationLocationCity; // City where degree was completed
  final String? additionalQualifications; // Additional qualifications
  final String? qualificationNotes; // Notes about qualifications
  final String? occupation;
  final String? employmentType;
  final String? companyName;
  /// Free text when [occupation] is the wizard value `Own Business`.
  final String? businessDescription;
  final String? incomeRange;

  // Family Details
  final String? maritalStatus;
  final String? familyType;
  final String? familyStatus;
  final String? familyValues;
  final String? fatherName; // Father's full name
  final String? fatherOccupation; // Father's occupation
  final String? fatherNote; // Father's occupation additional note
  final String? motherName; // Mother's full name
  final String? motherOccupation; // Mother's occupation
  final String? motherNote; // Mother's occupation additional note
  final String? motherSurname; // Mother's maiden surname for reference/verification
  final String? familyOrigin; // Family origin/ancestral place for connection (deprecated - use location fields)
  final String? familyOriginCountry; // Family origin country
  final String? familyOriginState; // Family origin state
  final String? familyOriginCity; // Family origin city
  final String? knownReference; // Known reference person 1 in community
  final String? knownReference2; // Known reference person 2 in community
  final int? brothers;
  final int? brothersMarried;
  final int? sisters;
  final int? sistersMarried;
  final String? aboutFamily; // Anything to say about your family

  // Location
  final String? country;
  final String? state;
  final String? city;
  final String? nativePlace; // Deprecated - use location fields
  final String? nativePlaceCountry; // Native place country
  final String? nativePlaceState; // Native place state
  final String? nativePlaceCity; // Native place city

  // Lifestyle
  final String? foodHabit;
  final String? smokingHabit;
  final String? drinkingHabit;

  // Interests
  final List<String>? hobbies;
  final List<String>? interests; // Modern interests like travel, music, etc.
  final List<String>? languages;

  // Modern Preferences
  final bool? willingToRelocate;
  final String? relocatePreference; // Same city / Same state / Anywhere in India / Abroad
  final String? settledAbroad; // Yes / No / Planning
  final String? citizenship; // Indian / NRI / OCI / PIO
  
  // Partner Preferences - Detailed
  final int? partnerAgeMin;
  final int? partnerAgeMax;
  final String? partnerHeightMin;
  final String? partnerHeightMax;
  final List<String>? partnerEducation;
  final List<String>? partnerOccupation;
  final String? partnerIncomeMin;
  final List<String>? partnerMaritalStatus;
  final List<String>? partnerLocations;
  final bool? partnerManglikPreference; // Accepts Manglik
  
  // Expectations
  final String? partnerExpectations; // Free text about what they expect

  // Additional
  final String? aboutMe;
  final String? partnerPreferences;
  final List<String>? photos;
  final String? profilePicture;
  final bool? isPhotoPrivate; // Photo visible only on request
  final DateTime? photoLastUpdated;
  final DateTime? photoPrivacyUpdatedAt; // When photo privacy was last changed
  final bool? showOnlineStatus; // Show online status to other users
  final bool? showLastSeen; // Show last seen timestamp
  final String? weight; // Weight in kg or lbs
  final String? profileCreatedBy; // Who created the profile
  final String? profileCreatedByRelation; // Relationship to profile creator

  // Profile Status
  final bool isProfileComplete;
  final int profileCompletionPercentage;
  final DateTime? profileUpdatedAt;
  final bool? isVerified; // Admin verification status

  UserProfile({
    this.id = '',
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.dateOfBirth,
    this.timeOfBirth,
    this.placeOfBirth,
    this.placeOfBirthState,
    this.placeOfBirthCountry,
    this.height,
    this.complexion,
    this.bodyType,
    this.physicalStatus,
    this.sect,
    this.subSect,
    this.gothram,
    this.nakshatra,
    this.pada,
    this.rasi,
    this.starConfirmed,
    this.manglikStatus,
    this.hasHoroscope,
    this.education,
    this.specialization,
    this.educationStatus,
    this.universityName,
    this.educationLocationCountry,
    this.educationLocationState,
    this.educationLocationCity,
    this.additionalQualifications,
    this.qualificationNotes,
    this.occupation,
    this.employmentType,
    this.companyName,
    this.businessDescription,
    this.incomeRange,
    this.maritalStatus,
    this.familyType,
    this.familyStatus,
    this.familyValues,
    this.fatherName,
    this.fatherOccupation,
    this.fatherNote,
    this.motherName,
    this.motherOccupation,
    this.motherNote,
    this.motherSurname,
    this.familyOrigin,
    this.familyOriginCountry,
    this.familyOriginState,
    this.familyOriginCity,
    this.knownReference,
    this.knownReference2,
    this.brothers,
    this.brothersMarried,
    this.sisters,
    this.sistersMarried,
    this.aboutFamily,
    this.country,
    this.state,
    this.city,
    this.nativePlace,
    this.nativePlaceCountry,
    this.nativePlaceState,
    this.nativePlaceCity,
    this.foodHabit,
    this.smokingHabit,
    this.drinkingHabit,
    this.hobbies,
    this.interests,
    this.languages,
    this.willingToRelocate,
    this.relocatePreference,
    this.settledAbroad,
    this.citizenship,
    this.partnerAgeMin,
    this.partnerAgeMax,
    this.partnerHeightMin,
    this.partnerHeightMax,
    this.partnerEducation,
    this.partnerOccupation,
    this.partnerIncomeMin,
    this.partnerMaritalStatus,
    this.partnerLocations,
    this.partnerManglikPreference,
    this.partnerExpectations,
    this.aboutMe,
    this.partnerPreferences,
    this.photos,
    this.profilePicture,
    this.isPhotoPrivate,
    this.photoLastUpdated,
    this.photoPrivacyUpdatedAt,
    this.showOnlineStatus,
    this.showLastSeen,
    this.weight, // Weight in kg or lbs
    this.profileCreatedBy,
    this.profileCreatedByRelation,
    this.isProfileComplete = false,
    this.profileCompletionPercentage = 0,
    this.profileUpdatedAt,
    this.isVerified,
  });

  String get fullName => '$firstName $lastName';

  int get age {
    final now = DateTime.now();
    int years = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      years--;
    }
    return years;
  }

  /// Get simple nakshatra name without Telugu text
  String? get simpleNakshatra {
    if (nakshatra == null) return null;
    return nakshatra!.contains(' (') 
        ? nakshatra!.split(' (').first 
        : nakshatra!.trim();
  }

  UserProfile copyWith({
    String? firstName,
    String? lastName,
    Gender? gender,
    DateTime? dateOfBirth,
    String? timeOfBirth,
    String? placeOfBirth,
    String? placeOfBirthState,
    String? placeOfBirthCountry,
    String? height,
    String? complexion,
    String? bodyType,
    String? physicalStatus,
    String? sect,
    String? subSect,
    String? gothram,
    String? nakshatra,
    String? pada,
    String? rasi,
    bool? starConfirmed,
    String? manglikStatus,
    bool? hasHoroscope,
    String? education,
    String? specialization,
    String? educationStatus,
    String? universityName,
    String? educationLocationCountry,
    String? educationLocationState,
    String? educationLocationCity,
    String? additionalQualifications,
    String? qualificationNotes,
    String? occupation,
    String? employmentType,
    String? companyName,
    String? businessDescription,
    String? incomeRange,
    String? maritalStatus,
    String? familyType,
    String? familyStatus,
    String? familyValues,
    String? fatherName,
    String? fatherOccupation,
    String? fatherNote,
    String? motherName,
    String? motherOccupation,
    String? motherNote,
    String? motherSurname,
    String? familyOrigin,
    String? familyOriginCountry,
    String? familyOriginState,
    String? familyOriginCity,
    String? knownReference,
    String? knownReference2,
    int? brothers,
    int? brothersMarried,
    int? sisters,
    int? sistersMarried,
    String? aboutFamily,
    String? country,
    String? state,
    String? city,
    String? nativePlace,
    String? nativePlaceCountry,
    String? nativePlaceState,
    String? nativePlaceCity,
    String? mobileNumber,
    String? alternativeMobileNumber,
    String? foodHabit,
    String? smokingHabit,
    String? drinkingHabit,
    List<String>? hobbies,
    List<String>? interests,
    List<String>? languages,
    String? aboutMe,
    String? partnerPreferences,
    List<String>? photos,
    String? profilePicture,
    bool? isPhotoPrivate,
    DateTime? photoLastUpdated,
    String? weight, // Weight in kg or lbs
    String? profileCreatedBy,
    String? profileCreatedByRelation,
    bool? isProfileComplete,
    int? profileCompletionPercentage,
    DateTime? profileUpdatedAt,
    bool? isVerified,
    DateTime? photoPrivacyUpdatedAt,
    bool? showOnlineStatus,
    bool? showLastSeen,
  }) {
    return UserProfile(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      timeOfBirth: timeOfBirth ?? this.timeOfBirth,
      placeOfBirth: placeOfBirth ?? this.placeOfBirth,
      placeOfBirthState: placeOfBirthState ?? this.placeOfBirthState,
      height: height ?? this.height,
      complexion: complexion ?? this.complexion,
      bodyType: bodyType ?? this.bodyType,
      physicalStatus: physicalStatus ?? this.physicalStatus,
      sect: sect ?? this.sect,
      subSect: subSect ?? this.subSect,
      gothram: gothram ?? this.gothram,
      nakshatra: nakshatra ?? this.nakshatra,
      pada: pada ?? this.pada,
      rasi: rasi ?? this.rasi,
      starConfirmed: starConfirmed ?? this.starConfirmed,
      manglikStatus: manglikStatus ?? this.manglikStatus,
      hasHoroscope: hasHoroscope ?? this.hasHoroscope,
      education: education ?? this.education,
      specialization: specialization ?? this.specialization,
      educationStatus: educationStatus ?? this.educationStatus,
      universityName: universityName ?? this.universityName,
      educationLocationCountry: educationLocationCountry ?? this.educationLocationCountry,
      educationLocationState: educationLocationState ?? this.educationLocationState,
      educationLocationCity: educationLocationCity ?? this.educationLocationCity,
      additionalQualifications: additionalQualifications ?? this.additionalQualifications,
      qualificationNotes: qualificationNotes ?? this.qualificationNotes,
      occupation: occupation ?? this.occupation,
      employmentType: employmentType ?? this.employmentType,
      companyName: companyName ?? this.companyName,
      businessDescription: businessDescription ?? this.businessDescription,
      incomeRange: incomeRange ?? this.incomeRange,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      familyType: familyType ?? this.familyType,
      familyStatus: familyStatus ?? this.familyStatus,
      familyValues: familyValues ?? this.familyValues,
      fatherName: fatherName ?? this.fatherName,
      fatherOccupation: fatherOccupation ?? this.fatherOccupation,
      fatherNote: fatherNote ?? this.fatherNote,
      motherName: motherName ?? this.motherName,
      motherOccupation: motherOccupation ?? this.motherOccupation,
      motherNote: motherNote ?? this.motherNote,
      motherSurname: motherSurname ?? this.motherSurname,
      familyOrigin: familyOrigin ?? this.familyOrigin,
      familyOriginCountry: familyOriginCountry ?? this.familyOriginCountry,
      familyOriginState: familyOriginState ?? this.familyOriginState,
      familyOriginCity: familyOriginCity ?? this.familyOriginCity,
      knownReference: knownReference ?? this.knownReference,
      knownReference2: knownReference2 ?? this.knownReference2,
      brothers: brothers ?? this.brothers,
      brothersMarried: brothersMarried ?? this.brothersMarried,
      sisters: sisters ?? this.sisters,
      sistersMarried: sistersMarried ?? this.sistersMarried,
      aboutFamily: aboutFamily ?? this.aboutFamily,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      nativePlace: nativePlace ?? this.nativePlace,
      nativePlaceCountry: nativePlaceCountry ?? this.nativePlaceCountry,
      nativePlaceState: nativePlaceState ?? this.nativePlaceState,
      nativePlaceCity: nativePlaceCity ?? this.nativePlaceCity,
      foodHabit: foodHabit ?? this.foodHabit,
      smokingHabit: smokingHabit ?? this.smokingHabit,
      drinkingHabit: drinkingHabit ?? this.drinkingHabit,
      hobbies: hobbies ?? this.hobbies,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      willingToRelocate: willingToRelocate ?? willingToRelocate,
      relocatePreference: relocatePreference ?? relocatePreference,
      settledAbroad: settledAbroad ?? settledAbroad,
      citizenship: citizenship ?? citizenship,
      partnerAgeMin: partnerAgeMin ?? partnerAgeMin,
      partnerAgeMax: partnerAgeMax ?? partnerAgeMax,
      partnerHeightMin: partnerHeightMin ?? partnerHeightMin,
      partnerHeightMax: partnerHeightMax ?? partnerHeightMax,
      partnerEducation: partnerEducation ?? partnerEducation,
      partnerOccupation: partnerOccupation ?? partnerOccupation,
      partnerIncomeMin: partnerIncomeMin ?? partnerIncomeMin,
      partnerMaritalStatus: partnerMaritalStatus ?? partnerMaritalStatus,
      partnerLocations: partnerLocations ?? partnerLocations,
      partnerManglikPreference: partnerManglikPreference ?? partnerManglikPreference,
      partnerExpectations: partnerExpectations ?? partnerExpectations,
      aboutMe: aboutMe ?? this.aboutMe,
      partnerPreferences: partnerPreferences ?? this.partnerPreferences,
      photos: photos ?? this.photos,
      profilePicture: profilePicture ?? this.profilePicture,
      isPhotoPrivate: isPhotoPrivate ?? this.isPhotoPrivate,
      photoLastUpdated: photoLastUpdated ?? this.photoLastUpdated,
      photoPrivacyUpdatedAt: photoPrivacyUpdatedAt ?? this.photoPrivacyUpdatedAt,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      profileCreatedBy: profileCreatedBy ?? this.profileCreatedBy,
      profileCreatedByRelation: profileCreatedByRelation ?? this.profileCreatedByRelation,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      profileCompletionPercentage: profileCompletionPercentage ?? this.profileCompletionPercentage,
      profileUpdatedAt: profileUpdatedAt ?? this.profileUpdatedAt,
      isVerified: isVerified ?? this.isVerified,
      weight: weight ?? this.weight,
    );
  }

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'gender': gender.name,
        'date_of_birth': dateOfBirth.toIso8601String(),
        'timeOfBirth': timeOfBirth,
        'placeOfBirth': placeOfBirth,
        'placeOfBirthState': placeOfBirthState,
        'placeOfBirthCountry': placeOfBirthCountry,
        'height': height,
        'complexion': complexion,
        'bodyType': bodyType,
        'physicalStatus': physicalStatus,
        'sect': sect,
        'subSect': subSect,
        'gothram': gothram,
        'nakshatra': nakshatra,
        'pada': pada,
        'rasi': rasi,
        'starConfirmed': starConfirmed,
        'manglikStatus': manglikStatus,
        'hasHoroscope': hasHoroscope,
        'education': education,
        'specialization': specialization,
        'educationStatus': educationStatus,
        'universityName': universityName,
        'educationLocationCountry': educationLocationCountry,
        'educationLocationState': educationLocationState,
        'educationLocationCity': educationLocationCity,
        'additionalQualifications': additionalQualifications,
        'qualificationNotes': qualificationNotes,
        'occupation': occupation,
        'employmentType': employmentType,
        'companyName': companyName,
        'businessDescription': businessDescription,
        'incomeRange': incomeRange,
        'maritalStatus': maritalStatus,
        'familyType': familyType,
        'familyStatus': familyStatus,
        'familyValues': familyValues,
        'fatherName': fatherName,
        'fatherOccupation': fatherOccupation,
        'fatherNote': fatherNote,
        'motherName': motherName,
        'motherOccupation': motherOccupation,
        'motherNote': motherNote,
        'motherSurname': motherSurname,
        'familyOrigin': familyOrigin,
        'familyOriginCountry': familyOriginCountry,
        'familyOriginState': familyOriginState,
        'familyOriginCity': familyOriginCity,
        'knownReference': knownReference,
        'knownReference2': knownReference2,
        'brothers': brothers,
        'brothersMarried': brothersMarried,
        'sisters': sisters,
        'sistersMarried': sistersMarried,
        'aboutFamily': aboutFamily,
        'country': country,
        'state': state,
        'city': city,
        'nativePlace': nativePlace,
        'nativePlaceCountry': nativePlaceCountry,
        'nativePlaceState': nativePlaceState,
        'nativePlaceCity': nativePlaceCity,
        'foodHabit': foodHabit,
        'smokingHabit': smokingHabit,
        'drinkingHabit': drinkingHabit,
        'hobbies': hobbies,
        'interests': interests,
        'languages': languages,
        'willingToRelocate': willingToRelocate,
        'relocatePreference': relocatePreference,
        'settledAbroad': settledAbroad,
        'citizenship': citizenship,
        'partnerAgeMin': partnerAgeMin,
        'partnerAgeMax': partnerAgeMax,
        'partnerHeightMin': partnerHeightMin,
        'partnerHeightMax': partnerHeightMax,
        'partnerEducation': partnerEducation,
        'partnerOccupation': partnerOccupation,
        'partnerIncomeMin': partnerIncomeMin,
        'partnerMaritalStatus': partnerMaritalStatus,
        'partnerLocations': partnerLocations,
        'partnerManglikPreference': partnerManglikPreference,
        'partnerExpectations': partnerExpectations,
        'about_me': aboutMe,
        'partnerPreferences': partnerPreferences,
        'profilePicture': profilePicture,
        'isPhotoPrivate': isPhotoPrivate,
        'photoLastUpdated': photoLastUpdated?.toIso8601String(),
        'photoPrivacyUpdatedAt': photoPrivacyUpdatedAt?.toIso8601String(),
        'showOnlineStatus': showOnlineStatus,
        'showLastSeen': showLastSeen,
        'profileCreatedBy': profileCreatedBy,
        'profileCreatedByRelation': profileCreatedByRelation,
        'isProfileComplete': isProfileComplete,
        'profileCompletionPercentage': profileCompletionPercentage,
        'profileUpdatedAt': profileUpdatedAt?.toIso8601String(),
        'isVerified': isVerified,
      };

  /// Converts UserProfile to snake_case map for database storage.
  /// Use this for database operations.
  Map<String, dynamic> toDatabaseMap() {
    final map = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'gender': gender.name,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'is_profile_complete': isProfileComplete,
      'profile_completion_percentage': profileCompletionPercentage,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (timeOfBirth != null)              map['time_of_birth'] = timeOfBirth;
    if (placeOfBirth != null)             map['place_of_birth'] = placeOfBirth;
    if (placeOfBirthState != null)        map['place_of_birth_state'] = placeOfBirthState;
    if (placeOfBirthCountry != null)      map['place_of_birth_country'] = placeOfBirthCountry;
    if (height != null)                   map['height'] = height;
    if (complexion != null)               map['complexion'] = complexion;
    if (bodyType != null)                 map['body_type'] = bodyType;
    if (physicalStatus != null)           map['physical_status'] = physicalStatus;
    if (sect != null)                     map['sect'] = sect;
    if (subSect != null)                  map['sub_sect'] = subSect;
    if (gothram != null)                  map['gothram'] = gothram;
    if (nakshatra != null)                map['nakshatra'] = nakshatra;
    if (pada != null)                     map['pada'] = pada;
    if (rasi != null)                     map['rasi'] = rasi;
    if (manglikStatus != null)            map['manglik_status'] = manglikStatus;
    if (hasHoroscope != null)             map['has_horoscope'] = hasHoroscope;
    if (starConfirmed != null)            map['star_confirmed'] = starConfirmed;
    if (education != null)                map['education'] = education;
    if (specialization != null)           map['specialization'] = specialization;
    if (educationStatus != null)          map['education_status'] = educationStatus;
    if (universityName != null)           map['university_name'] = universityName;
    if (occupation != null)               map['occupation'] = occupation;
    if (employmentType != null)           map['employment_type'] = employmentType;
    if (companyName != null)              map['company_name'] = companyName;
    if (incomeRange != null)              map['income_range'] = incomeRange;
    // Own Business: clear employer name on disk; otherwise clear stale business text.
    const ownBusinessOcc = 'Own Business';
    if (occupation == ownBusinessOcc) {
      map['company_name'] = '';
      map['business_description'] = (businessDescription ?? '').trim();
    } else {
      map['business_description'] = '';
    }
    if (maritalStatus != null)            map['marital_status'] = maritalStatus;
    if (familyType != null)               map['family_type'] = familyType;
    if (familyStatus != null)             map['family_status'] = familyStatus;
    if (familyValues != null)             map['family_values'] = familyValues;
    if (fatherName != null)               map['father_name'] = fatherName;
    if (fatherOccupation != null)         map['father_occupation'] = fatherOccupation;
    if (fatherNote != null)               map['father_note'] = fatherNote;
    if (motherName != null)               map['mother_name'] = motherName;
    if (motherOccupation != null)         map['mother_occupation'] = motherOccupation;
    if (motherNote != null)               map['mother_note'] = motherNote;
    if (brothers != null)                 map['brothers'] = brothers;
    if (brothersMarried != null)          map['brothers_married'] = brothersMarried;
    if (sisters != null)                  map['sisters'] = sisters;
    if (sistersMarried != null)           map['sisters_married'] = sistersMarried;
    if (aboutFamily != null)              map['about_family'] = aboutFamily;
    if (country != null)                  map['country'] = country;
    if (state != null)                    map['state'] = state;
    if (city != null)                     map['city'] = city;
    if (nativePlace != null)              map['native_place'] = nativePlace;
    if (nativePlaceCountry != null)       map['native_place_country'] = nativePlaceCountry;
    if (nativePlaceState != null)         map['native_place_state'] = nativePlaceState;
    if (nativePlaceCity != null)          map['native_place_city'] = nativePlaceCity;
    if (foodHabit != null)                map['food_habit'] = foodHabit;
    if (smokingHabit != null)             map['smoking_habit'] = smokingHabit;
    if (drinkingHabit != null)            map['drinking_habit'] = drinkingHabit;
    if (hobbies != null)                  map['hobbies'] = hobbies;
    if (languages != null)                map['languages'] = languages;
    if (willingToRelocate != null)        map['willing_to_relocate'] = willingToRelocate;
    if (aboutMe != null)                  map['about_me'] = aboutMe;
    if (partnerPreferences != null)       map['partner_preferences'] = partnerPreferences;
    if (partnerExpectations != null)      map['partner_expectations'] = partnerExpectations;
    if (partnerAgeMin != null)            map['partner_age_min'] = partnerAgeMin;
    if (partnerAgeMax != null)            map['partner_age_max'] = partnerAgeMax;
    if (partnerHeightMin != null)         map['partner_height_min'] = partnerHeightMin;
    if (partnerHeightMax != null)         map['partner_height_max'] = partnerHeightMax;
    if (partnerEducation != null)         map['partner_education'] = partnerEducation;
    if (partnerOccupation != null)        map['partner_occupation'] = partnerOccupation;
    if (partnerIncomeMin != null)         map['partner_income_min'] = partnerIncomeMin;
    if (partnerMaritalStatus != null)     map['partner_marital_status'] = partnerMaritalStatus;
    if (partnerLocations != null)         map['partner_locations'] = partnerLocations;
    if (partnerManglikPreference != null) map['partner_manglik_preference'] = partnerManglikPreference;
    // FIX: Always include profile_picture (even when null) so photo removal works
    // When profilePicture is null, this clears the field in Firestore
    map['profile_picture'] = profilePicture;
    map['is_photo_private'] = isPhotoPrivate;
    // FIX: Fields present in toJson() but previously missing from toDatabaseMap()
    // so they were never persisted to Firestore on profile save.
    if (profileCreatedBy != null)         map['profile_created_by'] = profileCreatedBy;
    if (profileCreatedByRelation != null) map['profile_created_by_relation'] = profileCreatedByRelation;
    if (educationLocationCountry != null) map['education_location_country'] = educationLocationCountry;
    if (educationLocationState != null)   map['education_location_state'] = educationLocationState;
    if (educationLocationCity != null)    map['education_location_city'] = educationLocationCity;
    if (motherSurname != null)            map['mother_surname'] = motherSurname;
    if (familyOriginCountry != null)      map['family_origin_country'] = familyOriginCountry;
    if (familyOriginState != null)        map['family_origin_state'] = familyOriginState;
    if (familyOriginCity != null)         map['family_origin_city'] = familyOriginCity;
    if (knownReference != null)           map['known_reference'] = knownReference;
    if (knownReference2 != null)          map['known_reference_2'] = knownReference2;
    if (interests != null)                map['interests'] = interests;
    if (relocatePreference != null)       map['relocate_preference'] = relocatePreference;
    if (settledAbroad != null)            map['settled_abroad'] = settledAbroad;
    if (citizenship != null)              map['citizenship'] = citizenship;
    if (photoLastUpdated != null)         map['photo_last_updated'] = photoLastUpdated!.toIso8601String();
    if (photoPrivacyUpdatedAt != null)  map['photo_privacy_updated_at'] = photoPrivacyUpdatedAt!.toIso8601String();
    if (showOnlineStatus != null)       map['show_online_status'] = showOnlineStatus;
    if (showLastSeen != null)             map['show_last_seen'] = showLastSeen;
    if (additionalQualifications != null) map['additional_qualifications'] = additionalQualifications;
    if (qualificationNotes != null)       map['qualification_notes'] = qualificationNotes;
    return map;
  }

  /// Synthetic profile for list UIs when [User.profile] is null (legacy parse).
  factory UserProfile.fallbackForDiscovery(User user) {
    final fn = user.firstName.trim().isNotEmpty
        ? user.firstName.trim()
        : (user.profileId.trim().isNotEmpty ? user.profileId : 'Member');
    return UserProfile(
      firstName: fn,
      lastName: user.lastName.trim(),
      gender: user.gender,
      dateOfBirth: user.dateOfBirth,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
      DateTime? parseFlexibleDate(dynamic raw) {
        if (raw == null) return null;
        if (raw is DateTime) return raw;
        if (raw is Timestamp) return raw.toDate();
        if (raw is String) return DateTime.tryParse(raw);
        return null;
      }

      // Firestore / merged maps use snake_case; [toJson] and some caches use camelCase
      // for these keys — read both so completion logic matches saved data.
      String? strSnakeOrCamel(String snake, String camel) {
        for (final key in [snake, camel]) {
          final v = json[key];
          if (v is String) {
            final t = v.trim();
            if (t.isNotEmpty) return t;
          }
        }
        return null;
      }
      
      return UserProfile(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      gender: genderFromDynamic(json['gender']) ?? Gender.male,
      // Support Firestore Timestamp or ISO string for DOB.
      dateOfBirth: parseFlexibleDate(json['date_of_birth']) ?? DateTime(1990, 1, 1),
      timeOfBirth: json['time_of_birth'] as String?,
      placeOfBirth: json['place_of_birth'] as String?,
      placeOfBirthState: json['place_of_birth_state'] as String?,
      placeOfBirthCountry: json['place_of_birth_country'] as String?,
      height: (json['height'] as String?)?.trim().isNotEmpty == true
          ? json['height'] as String?
          : json['height_cm'] as String?,
      complexion: json['complexion'] as String?,
      bodyType: json['body_type'] as String?,
      physicalStatus: json['physical_status'] as String?,
      sect: json['sect'] as String?,
      subSect: json['sub_sect'] as String?,
      gothram: json['gothram'] as String?,
      nakshatra: json['nakshatra'] as String?,
      pada: json['pada'] as String?,
      rasi: json['rasi'] as String?,
      starConfirmed: json['star_confirmed'] as bool?,
      manglikStatus: json['manglik_status'] as String?,
      hasHoroscope: json['has_horoscope'] as bool?,
      education: json['education'] as String?,
      specialization: json['specialization'] as String?,
      educationStatus: json['education_status'] as String?,
      universityName: json['university_name'] as String?,
      educationLocationCountry: json['education_location_country'] as String?,
      educationLocationState: json['education_location_state'] as String?,
      educationLocationCity: json['education_location_city'] as String?,
      additionalQualifications: json['additional_qualifications'] as String?,
      qualificationNotes: json['qualification_notes'] as String?,
      occupation: json['occupation'] as String?,
      employmentType: json['employment_type'] as String?,
      companyName: json['company_name'] as String?,
      businessDescription: json['business_description'] as String? ??
          json['businessDescription'] as String?,
      incomeRange: json['income_range'] as String?,
      maritalStatus: json['marital_status'] as String?,
      familyType: json['family_type'] as String?,
      familyStatus: json['family_status'] as String?,
      familyValues: json['family_values'] as String?,
      fatherName: json['father_name'] as String?,
      fatherOccupation: strSnakeOrCamel('father_occupation', 'fatherOccupation'),
      fatherNote: json['father_note'] as String?,
      motherName: json['mother_name'] as String?,
      motherOccupation: strSnakeOrCamel('mother_occupation', 'motherOccupation'),
      motherNote: json['mother_note'] as String?,
      motherSurname: json['mother_surname'] as String?,
      familyOrigin: json['family_origin'] as String?,
      familyOriginCountry: json['family_origin_country'] as String?,
      familyOriginState: json['family_origin_state'] as String?,
      familyOriginCity: json['family_origin_city'] as String?,
      knownReference: json['known_reference'] as String?,
      knownReference2:
          json['known_reference_2'] as String? ?? json['known_reference2'] as String?,
      brothers: json['brothers'] as int?,
      brothersMarried: json['brothers_married'] as int?,
      sisters: json['sisters'] as int?,
      sistersMarried: json['sisters_married'] as int?,
      aboutFamily: json['about_family'] as String?,
      country: json['country'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      nativePlace: json['native_place'] as String?,
      nativePlaceCountry: json['native_place_country'] as String?,
      nativePlaceState: json['native_place_state'] as String?,
      nativePlaceCity: json['native_place_city'] as String?,
      foodHabit: strSnakeOrCamel('food_habit', 'foodHabit'),
      smokingHabit: json['smoking_habit'] as String?,
      drinkingHabit: json['drinking_habit'] as String?,
      hobbies: _parseJsonListField(json['hobbies']) ?? (json['hobbies'] as List<dynamic>?)?.cast<String>(),
      interests: _parseJsonListField(json['interests']) ?? (json['interests'] as List<dynamic>?)?.cast<String>(),
      languages: _parseJsonListField(json['languages']) ?? (json['languages'] as List<dynamic>?)?.cast<String>(),
      willingToRelocate: json['willing_to_relocate'] as bool?,
      relocatePreference: json['relocate_preference'] as String?,
      settledAbroad: json['settled_abroad'] as String?,
      citizenship: json['citizenship'] as String?,
      partnerAgeMin: json['partner_age_min'] as int?,
      partnerAgeMax: json['partner_age_max'] as int?,
      partnerHeightMin: json['partner_height_min'] as String?,
      partnerHeightMax: json['partner_height_max'] as String?,
      partnerEducation: _parseJsonListField(json['partner_education']) ?? (json['partner_education'] as List<dynamic>?)?.cast<String>(),
      partnerOccupation: _parseJsonListField(json['partner_occupation']) ?? (json['partner_occupation'] as List<dynamic>?)?.cast<String>(),
      partnerIncomeMin: json['partner_income_min'] as String?,
      partnerMaritalStatus: _parseJsonListField(json['partner_marital_status']) ?? (json['partner_marital_status'] as List<dynamic>?)?.cast<String>(),
      partnerLocations: _parseJsonListField(json['partner_locations']) ?? (json['partner_locations'] as List<dynamic>?)?.cast<String>(),
      partnerManglikPreference: json['partner_manglik_preference'] as bool?,
      partnerExpectations: json['partner_expectations'] as String?,
      aboutMe: json['about_me'] as String?,
      partnerPreferences: json['partner_preferences'] as String?,
      photos: _parseJsonListField(json['photos']) ?? (json['photos'] as List<dynamic>?)?.cast<String>(),
      profilePicture: json['profile_picture'] as String? ??
          json['profilePicture'] as String? ??
          json['photo_url'] as String? ??
          json['photoUrl'] as String?,
      isPhotoPrivate: User._coerceBool(json['is_photo_private']) ||
          User._coerceBool(json['isPhotoPrivate']) ||
          User._coerceBool(json['photo_private']),
      photoLastUpdated: () {
        final plu = json['photo_last_updated'] ?? json['photo_updated_at'];
        if (plu is Timestamp) return plu.toDate();
        if (plu is String) return DateTime.tryParse(plu);
        return null;
      }(),
      photoPrivacyUpdatedAt: json['photo_privacy_updated_at'] != null
          ? parseFlexibleDate(json['photo_privacy_updated_at'])
          : null,
      showOnlineStatus: json['show_online_status'] as bool? ?? json['privacy_show_online_status'] as bool?,
      showLastSeen: json['show_last_seen'] as bool? ?? json['privacy_show_last_seen'] as bool?,
      profileCreatedBy: json['profile_created_by'] as String?,
      profileCreatedByRelation: json['profile_created_by_relation'] as String?,
      isProfileComplete: json['is_profile_complete'] as bool? ?? false,
      profileCompletionPercentage: json['profile_completion_percentage'] as int? ?? 0,
      profileUpdatedAt: json['profile_updated_at'] != null
          ? parseFlexibleDate(json['profile_updated_at'])
          : null,
      isVerified: json['is_verified'] as bool?,
      weight: json['weight'] as String?,
    );
  }

  /// Parse `List<String>` field from JSON robustly - handles both arrays and comma-separated strings
  static List<String>? _parseJsonListField(dynamic field) {
    if (field == null) return null;
    
    if (field is List) {
      return field.cast<String>();
    }
    
    if (field is String) {
      // Handle comma-separated string format
      return field.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    
    return null;
  }

  /// Calculate profile completion percentage
  int calculateCompletionPercentage() => computedCompletionPercentage;

  /// Get list of missing fields for profile completion
  List<String> getMissingFields() {
    if (computedCompletionPercentage >= 100) return const [];

    final List<String> missing = [];

    bool blank(dynamic v) => v == null || v.toString().trim().isEmpty;
    bool blankList(List? v) => v == null || v.isEmpty;

    if (blank(firstName)) missing.add('First Name');
    if (blank(lastName)) missing.add('Last Name');
    if (blank(height)) missing.add('Height');
    if (blank(complexion)) missing.add('Complexion');
    if (blank(bodyType)) missing.add('Body Type');
    if (blank(physicalStatus)) missing.add('Physical Status');
    if (blank(timeOfBirth)) missing.add('Time of Birth');
    if (blank(placeOfBirth)) missing.add('Place of Birth');
    if (blank(placeOfBirthCountry)) missing.add('Place of Birth Country');
    if (blank(nakshatra)) missing.add('Nakshatra');
    if (blank(pada)) missing.add('Pada');
    if (blank(rasi)) missing.add('Rasi');
    if (blank(sect)) missing.add('Sect');
    if (blank(subSect)) missing.add('Sub-Sect');
    if (blank(gothram)) missing.add('Gothram');
    if (blank(education)) missing.add('Education');
    if (blank(occupation)) missing.add('Occupation');
    if (occupation == 'Own Business' && blank(businessDescription)) {
      missing.add('Business description');
    }
    if (blank(state)) missing.add('State');
    if (blank(city)) missing.add('City/Town');
    if (blank(maritalStatus)) missing.add('Marital Status');
    if (blank(familyType)) missing.add('Family Type');
    if (blank(fatherOccupation)) missing.add('Father\'s Occupation');
    if (blank(motherOccupation)) missing.add('Mother\'s Occupation');
    if (blank(foodHabit)) missing.add('Food Habit');
    if (blank(aboutMe)) missing.add('About Me');
    if (blankList(hobbies)) missing.add('Hobbies');
    if (blankList(languages)) missing.add('Languages');
    if (blank(profilePicture)) missing.add('Profile Picture');
    
    return missing;
  }

  /// Get the first incomplete step number for direct navigation
  int get firstIncompleteStep {
    // Step 0: Basic Info
    if (firstName.isEmpty || lastName.isEmpty || height == null || 
        complexion == null || bodyType == null || physicalStatus == null) {
      return 0;
    }
    
    // Step 1: Birth Details  
    if (timeOfBirth == null || (placeOfBirth?.isEmpty ?? true) || 
        placeOfBirthCountry == null || nakshatra == null || 
        pada == null || rasi == null) {
      return 1;
    }
    
    // Step 2: Religious
    if (sect == null || subSect == null || (gothram?.isEmpty ?? true)) {
      return 2;
    }
    
    // Step 3: Education & Career
    if (education == null || occupation == null || 
        state == null || (city?.isEmpty ?? true)) {
      return 3;
    }
    
    bool wf(String? s) => s == null || s.trim().isEmpty;

    // Step 4: Family
    if (maritalStatus == null || familyType == null ||
        wf(fatherOccupation) || wf(motherOccupation)) {
      return 4;
    }

    // Step 5: Lifestyle & About
    if (wf(foodHabit) || (aboutMe?.isEmpty ?? true) ||
        (hobbies?.isEmpty ?? true) || (languages?.isEmpty ?? true) || 
        profilePicture == null) {
      return 5;
    }
    
    return -1; // Profile is complete
  }

  /// Get height in feet for display
  String get heightFeet {
    if (height == null) return '0\'0"';
    // Convert height string (e.g., "5'6" or "170cm") to feet format
    if (height!.contains("'")) return height!;
    // If in cm, convert to feet
    try {
      final cm = double.parse(height!.replaceAll(RegExp(r'[^0-9.]'), ''));
      final feet = (cm / 30.48).floor();
      final inches = ((cm / 30.48 - feet) * 12).round();
      return '$feet\'$inches"';
    } catch (e) {
      return height!;
    }
  }

  /// Get bio from aboutMe field
  String get bio => aboutMe ?? '';

  /// Computed live completion percentage — mirrors wizard steps.
  int get computedCompletionPercentage {
    int filled = 0;
    const int total = 28;

    void c(dynamic v) { if (v != null && v.toString().trim().isNotEmpty) filled++; }
    void cl(List? v) { if (v != null && v.isNotEmpty) filled++; }

    // Step 1 – Basic Info (6)
    c(firstName); c(lastName); c(height); c(complexion); c(bodyType); c(physicalStatus);
    // Step 2 – Birth Details (6)
    c(timeOfBirth); c(placeOfBirth); c(placeOfBirthCountry); c(nakshatra); c(pada); c(rasi);
    // Step 3 – Religious (3)
    c(sect); c(subSect); c(gothram);
    // Step 4 – Education & Career (4)
    c(education); c(occupation); c(state); c(city);
    // Step 5 – Family (4)
    c(maritalStatus); c(familyType); c(fatherOccupation); c(motherOccupation);
    // Step 6 – Lifestyle & About (5)
    c(foodHabit); c(aboutMe); cl(hobbies); cl(languages); c(profilePicture);

    return ((filled / total) * 100).round().clamp(0, 100);
  }

  /// Profile is functionally complete (>=80%)
  bool get isFunctionallyComplete => computedCompletionPercentage >= 80;

  /// Get match score (placeholder for future algorithm)
  double get matchScore => 0.0; // Will be calculated by matching algorithm

  /// Create UserProfile from map (for Firebase data)
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      gender: genderFromLooseString(map['gender'] as String?) ?? Gender.male,
      // BUG 09b FIX: tryParse avoids FormatException
      dateOfBirth: (map['date_of_birth'] != null
          ? DateTime.tryParse(map['date_of_birth'] as String)
          : null) ?? DateTime(1990, 1, 1),
      timeOfBirth: map['time_of_birth'] as String?,
      placeOfBirth: map['place_of_birth'] as String?,
      height: map['height'] as String?,
      // Add other fields as needed
    );
  }

  /// Convert to Map for storage/serialization (in-memory / AuthService helpers).
  /// Includes photo fields so callers like [AuthService.updateCurrentUserProfileLocally]
  /// can refresh the avatar without waiting for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'gender': gender.name,
      'date_of_birth': dateOfBirth.toIso8601String(),
      'time_of_birth': timeOfBirth,
      'place_of_birth': placeOfBirth,
      'height': height,
      'profile_picture': profilePicture,
      'profilePicture': profilePicture,
      if (photoLastUpdated != null)
        'photo_last_updated': photoLastUpdated!.toIso8601String(),
      if (photoLastUpdated != null)
        'photoLastUpdated': photoLastUpdated!.toIso8601String(),
    };
  }
}

/// Model for user badges (Premium feature)
