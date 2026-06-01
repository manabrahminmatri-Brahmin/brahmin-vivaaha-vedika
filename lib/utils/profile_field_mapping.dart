/// Profile field mapping utility
/// Ensures consistent naming between app models (camelCase) and database (snake_case)
library;

import 'package:flutter/foundation.dart';
class ProfileFieldMapping {
  /// Maps camelCase field names to snake_case for database operations
  static const Map<String, String> camelToSnake = {
    // User-level fields
    'id': 'id',
    'email': 'email',
    'profile_id': 'profile_id',
    'mobile_number': 'mobile_number',
    'alternativeMobileNumber': 'alternative_mobile_number',
    'isEmailVerified': 'is_email_verified',
    'verificationCode': 'verification_code',
    'verificationCodeExpiry': 'verification_code_expiry',
    'created_at': 'created_at',
    'lastLoginAt': 'last_login_at',
    'isProfileLocked': 'is_profile_locked',
    'deletionReason': 'deletion_reason',
    'deletionRequestedAt': 'deletion_requested_at',
    'isDeleted': 'is_deleted',
    
    // Membership fields
    'tier': 'tier',
    'startDate': 'start_date',
    'expiryDate': 'expiry_date',
    'is_premium': 'is_premium',
    'subscriptionDate': 'subscription_date',
    'features': 'features',
    // membership_json / billing (nested maps)
    'paymentMethod': 'payment_method',
    'amountPaid': 'amount_paid',
    'contactsUsed': 'contacts_used',
    'transactionId': 'transaction_id',
    'premiumSince': 'premium_since',

    // Basic Info
    'first_name': 'first_name',
    'last_name': 'last_name',
    'date_of_birth': 'date_of_birth',
    'timeOfBirth': 'time_of_birth',
    'placeOfBirth': 'place_of_birth',
    'placeOfBirthState': 'place_of_birth_state',
    'placeOfBirthCountry': 'place_of_birth_country',
    'height': 'height',
    'complexion': 'complexion',
    'bodyType': 'body_type',
    'physicalStatus': 'physical_status',
    'sect': 'sect',
    'subSect': 'sub_sect',
    'gothram': 'gothram',
    'nakshatra': 'nakshatra',
    'pada': 'pada',
    'rasi': 'rasi',
    'starConfirmed': 'star_confirmed',
    'manglikStatus': 'manglik_status',
    'hasHoroscope': 'has_horoscope',
    
    // Education
    'education': 'education',
    'specialization': 'specialization',
    'educationStatus': 'education_status',
    'universityName': 'university_name',
    'educationLocationCountry': 'education_location_country',
    'educationLocationState': 'education_location_state',
    'educationLocationCity': 'education_location_city',
    'additionalQualifications': 'additional_qualifications',
    'qualificationNotes': 'qualification_notes',
    
    // Professional
    'occupation': 'occupation',
    'employmentType': 'employment_type',
    'companyName': 'company_name',
    'businessDescription': 'business_description',
    'incomeRange': 'income_range',
    
    // Family
    'maritalStatus': 'marital_status',
    'familyType': 'family_type',
    'familyStatus': 'family_status',
    'familyValues': 'family_values',
    'fatherName': 'father_name',
    'fatherOccupation': 'father_occupation',
    'fatherNote': 'father_note',
    'motherName': 'mother_name',
    'motherOccupation': 'mother_occupation',
    'motherNote': 'mother_note',
    'motherSurname': 'mother_surname',
    'familyOrigin': 'family_origin',
    'familyOriginCountry': 'family_origin_country',
    'familyOriginState': 'family_origin_state',
    'familyOriginCity': 'family_origin_city',
    'knownReference': 'known_reference',
    'knownReference2': 'known_reference_2',
    'brothers': 'brothers',
    'brothersMarried': 'brothers_married',
    'sisters': 'sisters',
    'sistersMarried': 'sisters_married',
    'aboutFamily': 'about_family',
    
    // Location
    'country': 'country',
    'state': 'state',
    'city': 'city',
    'nativePlace': 'native_place',
    'nativePlaceCountry': 'native_place_country',
    'nativePlaceState': 'native_place_state',
    'nativePlaceCity': 'native_place_city',
    
    // Lifestyle
    'foodHabit': 'food_habit',
    'smokingHabit': 'smoking_habit',
    'drinkingHabit': 'drinking_habit',
    'hobbies': 'hobbies',
    'interests': 'interests',
    'languages': 'languages',
    'willingToRelocate': 'willing_to_relocate',
    'relocatePreference': 'relocate_preference',
    'settledAbroad': 'settled_abroad',
    'citizenship': 'citizenship',
    
    // Partner Preferences
    'partnerAgeMin': 'partner_age_min',
    'partnerAgeMax': 'partner_age_max',
    'partnerHeightMin': 'partner_height_min',
    'partnerHeightMax': 'partner_height_max',
    'partnerEducation': 'partner_education',
    'partnerOccupation': 'partner_occupation',
    'partnerIncomeMin': 'partner_income_min',
    'partnerMaritalStatus': 'partner_marital_status',
    'partnerLocations': 'partner_locations',
    'partnerManglikPreference': 'partner_manglik_preference',
    'partnerExpectations': 'partner_expectations',
    'partnerPreferences': 'partner_preferences',
    
    // Profile Management
    'photos': 'photos',
    'profilePicture': 'profile_picture',
    'isPhotoPrivate': 'is_photo_private',
    'photoLastUpdated': 'photo_last_updated',
    'photoPrivacyUpdatedAt': 'photo_privacy_updated_at',
    'profileCreatedBy': 'profile_created_by',
    'profileCreatedByRelation': 'profile_created_by_relation',
    'isProfileComplete': 'is_profile_complete',
    'weight': 'weight',
    'profileCompletionPercentage': 'profile_completion_percentage',
    'profileUpdatedAt': 'profile_updated_at',
    'isVerified': 'is_verified',

    // Interest / access-request lifecycle (merged on user/interest paths)
    'withdrawnAt': 'withdrawn_at',
    'responseMessage': 'response_message',
  };

  /// Maps snake_case field names to camelCase for app models
  static const Map<String, String> snakeToCamel = {
    // User-level fields
    'id': 'id',
    'email': 'email',
    'profile_id': 'profile_id',
    'mobile_number': 'mobile_number',
    'alternative_mobile_number': 'alternativeMobileNumber',
    'is_email_verified': 'isEmailVerified',
    'verification_code': 'verificationCode',
    'verification_code_expiry': 'verificationCodeExpiry',
    'created_at': 'created_at',
    'last_login_at': 'lastLoginAt',
    'is_profile_locked': 'isProfileLocked',
    'deletion_reason': 'deletionReason',
    'deletion_requested_at': 'deletionRequestedAt',
    'is_deleted': 'isDeleted',
    
    // Membership fields
    'tier': 'tier',
    'start_date': 'startDate',
    'expiry_date': 'expiryDate',
    'is_premium': 'is_premium',
    'subscription_date': 'subscriptionDate',
    'features': 'features',
    'payment_method': 'paymentMethod',
    'amount_paid': 'amountPaid',
    'contacts_used': 'contactsUsed',
    'transaction_id': 'transactionId',
    'premium_since': 'premiumSince',

    // Basic Info
    'first_name': 'first_name',
    'last_name': 'last_name',
    'date_of_birth': 'date_of_birth',
    'time_of_birth': 'timeOfBirth',
    'place_of_birth': 'placeOfBirth',
    'place_of_birth_state': 'placeOfBirthState',
    'place_of_birth_country': 'placeOfBirthCountry',
    'height': 'height',
    'complexion': 'complexion',
    'body_type': 'bodyType',
    'physical_status': 'physicalStatus',
    'sect': 'sect',
    'sub_sect': 'subSect',
    'gothram': 'gothram',
    'nakshatra': 'nakshatra',
    'pada': 'pada',
    'rasi': 'rasi',
    'star_confirmed': 'starConfirmed',
    'manglik_status': 'manglikStatus',
    'has_horoscope': 'hasHoroscope',
    
    // Education
    'education': 'education',
    'specialization': 'specialization',
    'education_status': 'educationStatus',
    'university_name': 'universityName',
    'education_location_country': 'educationLocationCountry',
    'education_location_state': 'educationLocationState',
    'education_location_city': 'educationLocationCity',
    'additional_qualifications': 'additionalQualifications',
    'qualification_notes': 'qualificationNotes',
    
    // Professional
    'occupation': 'occupation',
    'employment_type': 'employmentType',
    'company_name': 'companyName',
    'business_description': 'businessDescription',
    'income_range': 'incomeRange',
    
    // Family
    'marital_status': 'maritalStatus',
    'family_type': 'familyType',
    'family_status': 'familyStatus',
    'family_values': 'familyValues',
    'father_name': 'fatherName',
    'father_occupation': 'fatherOccupation',
    'mother_name': 'motherName',
    'mother_occupation': 'motherOccupation',
    'mother_surname': 'motherSurname',
    'family_origin': 'familyOrigin',
    'family_origin_country': 'familyOriginCountry',
    'family_origin_state': 'familyOriginState',
    'family_origin_city': 'familyOriginCity',
    'known_reference': 'knownReference',
    'known_reference_2': 'knownReference2',
    'brothers': 'brothers',
    'brothers_married': 'brothersMarried',
    'sisters': 'sisters',
    'sisters_married': 'sistersMarried',
    'about_family': 'aboutFamily',
    
    // Location
    'country': 'country',
    'state': 'state',
    'city': 'city',
    'native_place': 'nativePlace',
    'native_place_country': 'nativePlaceCountry',
    'native_place_state': 'nativePlaceState',
    'native_place_city': 'nativePlaceCity',
    
    // Lifestyle
    'food_habit': 'foodHabit',
    'smoking_habit': 'smokingHabit',
    'drinking_habit': 'drinkingHabit',
    'hobbies': 'hobbies',
    'interests': 'interests',
    'languages': 'languages',
    'willing_to_relocate': 'willingToRelocate',
    'relocate_preference': 'relocatePreference',
    'settled_abroad': 'settledAbroad',
    'citizenship': 'citizenship',
    
    // Partner Preferences
    'partner_age_min': 'partnerAgeMin',
    'partner_age_max': 'partnerAgeMax',
    'partner_height_min': 'partnerHeightMin',
    'partner_height_max': 'partnerHeightMax',
    'partner_education': 'partnerEducation',
    'partner_occupation': 'partnerOccupation',
    'partner_income_min': 'partnerIncomeMin',
    'partner_marital_status': 'partnerMaritalStatus',
    'partner_locations': 'partnerLocations',
    'partner_manglik_preference': 'partnerManglikPreference',
    'partner_expectations': 'partnerExpectations',
    'partner_preferences': 'partnerPreferences',
    
    // Profile Management
    'photos': 'photos',
    'profile_picture': 'profilePicture',
    'is_photo_private': 'isPhotoPrivate',
    'photo_privacy_updated_at': 'photoPrivacyUpdatedAt',
    'photo_last_updated': 'photoLastUpdated',
    'profile_created_by': 'profileCreatedBy',
    'profile_created_by_relation': 'profileCreatedByRelation',
    'is_profile_complete': 'isProfileComplete',
    'weight': 'weight',
    'profile_completion_percentage': 'profileCompletionPercentage',
    'profile_updated_at': 'profileUpdatedAt',
    'is_verified': 'isVerified',

    // Interest / access-request lifecycle
    'withdrawn_at': 'withdrawnAt',
    'response_message': 'responseMessage',
  };

  /// Interest / access-request lifecycle keys (Firestore may use camelCase on reads).
  static const Map<String, String> _interestLifecycleCamelToSnake = {
    'withdrawnAt': 'withdrawn_at',
    'responseMessage': 'response_message',
    'respondedAt': 'responded_at',
    'viewedByRecipient': 'viewed_by_recipient',
    'viewedBySender': 'viewed_by_sender',
  };

  static final Set<String> _unmappedCamelKeysLogged = <String>{};

  static bool _looksLikeCamelCase(String key) =>
      key.contains(RegExp(r'[a-z][A-Z]'));

  /// Fallback when a key is not in [camelToSnake] (e.g. new interest fields).
  static String _camelCaseToSnakeFallback(String input) {
    return input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z])([A-Z][a-z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
  }

  /// Convert camelCase field name to snake_case for database operations
  static String toSnakeCase(String camelCaseField) {
    final explicit = camelToSnake[camelCaseField];
    if (explicit != null) return explicit;
    final interest = _interestLifecycleCamelToSnake[camelCaseField];
    if (interest != null) return interest;
    if (_looksLikeCamelCase(camelCaseField)) {
      return _camelCaseToSnakeFallback(camelCaseField);
    }
    return camelCaseField;
  }

  /// Convert snake_case field name to camelCase for app models
  static String toCamelCase(String snakeCaseField) {
    return snakeToCamel[snakeCaseField] ?? snakeCaseField;
  }

  /// Convert entire profile data map from camelCase to snake_case
  /// Enhanced with validation and unmapped key tracking
  static Map<String, dynamic> convertProfileToSnakeCase(Map<String, dynamic> camelCaseData) {
    final Map<String, dynamic> snakeCaseData = {};
    final List<String> unmappedKeys = [];

    camelCaseData.forEach((key, value) {
      final snakeKey = toSnakeCase(key);

      if (snakeKey == key && key.contains(RegExp(r'[a-z][A-Z]'))) {
        unmappedKeys.add(key);
      }
      
      if (value is Map) {
        // Recursively convert nested Maps
        snakeCaseData[snakeKey] = convertProfileToSnakeCase(Map<String, dynamic>.from(value));
      } else if (value is List) {
        // Convert Lists with Maps inside
        snakeCaseData[snakeKey] = value.map((item) => 
          item is Map ? convertProfileToSnakeCase(Map<String, dynamic>.from(item)) : item
        ).toList();
      } else {
        snakeCaseData[snakeKey] = value;
      }
    });
    
    if (kDebugMode && unmappedKeys.isNotEmpty) {
      final fresh = unmappedKeys
          .where((k) => _unmappedCamelKeysLogged.add(k))
          .toList();
      if (fresh.isNotEmpty) {
        debugPrint(
          '⚠️ Unmapped camelCase keys in convertProfileToSnakeCase: $fresh',
        );
      }
    }

    return snakeCaseData;
  }

  /// Convert entire profile data map from snake_case to camelCase
  /// Enhanced with validation and unmapped key tracking
  static Map<String, dynamic> convertProfileToCamelCase(Map<String, dynamic> snakeCaseData) {
    final Map<String, dynamic> camelCaseData = {};
    final List<String> unmappedKeys = [];

    snakeCaseData.forEach((key, value) {
      final camelKey = toCamelCase(key);

      if (camelKey == key && key.contains(RegExp(r'[a-z]_[a-z]'))) {
        unmappedKeys.add(key);
      }
      
      if (value is Map) {
        // Recursively convert nested Maps
        camelCaseData[camelKey] = convertProfileToCamelCase(Map<String, dynamic>.from(value));
      } else if (value is List) {
        // Convert Lists with Maps inside
        camelCaseData[camelKey] = value.map((item) => 
          item is Map ? convertProfileToCamelCase(Map<String, dynamic>.from(item)) : item
        ).toList();
      } else {
        camelCaseData[camelKey] = value;
      }
    });
    
    if (kDebugMode && unmappedKeys.isNotEmpty) {
      debugPrint(
        '⚠️ Unmapped snake_case keys in convertProfileToCamelCase: $unmappedKeys',
      );
    }

    return camelCaseData;
  }

  /// Get all field mappings for debugging
  static Map<String, String> getAllCamelToSnakeMappings() => Map.from(camelToSnake);
  static Map<String, String> getAllSnakeToCamelMappings() => Map.from(snakeToCamel);

  /// Validate mapping completeness for a given data map
  static MappingValidationResult validateMappings(Map<String, dynamic> data, {bool isCamelCase = true}) {
    final List<String> unmappedKeys = [];
    final List<String> mappedKeys = [];
    final List<String> invalidKeys = [];
    
    data.forEach((key, value) {
      final pattern = isCamelCase ? RegExp(r'[a-z][A-Z]') : RegExp(r'[a-z]_[a-z]');
      final convertedKey = isCamelCase ? toSnakeCase(key) : toCamelCase(key);
      
      if (convertedKey == key && key.contains(pattern)) {
        unmappedKeys.add(key);
      } else if (convertedKey != key) {
        mappedKeys.add(key);
      }
      
      // Check for obviously invalid keys
      if (key.contains(' ') || key.startsWith('_') || key.endsWith('_')) {
        invalidKeys.add(key);
      }
    });
    
    return MappingValidationResult(
      totalKeys: data.length,
      mappedKeys: mappedKeys,
      unmappedKeys: unmappedKeys,
      invalidKeys: invalidKeys,
      mappingCompleteness: data.isEmpty ? 1.0 : mappedKeys.length / data.length,
    );
  }

  /// Get mapping statistics
  static MappingStatistics getMappingStatistics() {
    return MappingStatistics(
      totalCamelToSnakeMappings: camelToSnake.length,
      totalSnakeToCamelMappings: snakeToCamel.length,
      userLevelFields: 14, // id, email, profileId, etc.
      membershipFields: 5, // tier, expiryDate, etc.
      profileFields: camelToSnake.length - 19, // Total minus user and membership
      hasBidirectionalMapping: _validateBidirectionalMapping(),
    );
  }

  /// Check if all mappings have bidirectional equivalents
  static bool _validateBidirectionalMapping() {
    final camelToSnakeKeys = camelToSnake.keys.toSet();
    final snakeToCamelValues = snakeToCamel.values.toSet();
    return camelToSnakeKeys.difference(snakeToCamelValues).isEmpty;
  }
}

/// Result of mapping validation
class MappingValidationResult {
  final int totalKeys;
  final List<String> mappedKeys;
  final List<String> unmappedKeys;
  final List<String> invalidKeys;
  final double mappingCompleteness;

  MappingValidationResult({
    required this.totalKeys,
    required this.mappedKeys,
    required this.unmappedKeys,
    required this.invalidKeys,
    required this.mappingCompleteness,
  });

  bool get isComplete => mappingCompleteness == 1.0 && invalidKeys.isEmpty;
  bool get hasIssues => unmappedKeys.isNotEmpty || invalidKeys.isNotEmpty;

  @override
  String toString() {
    return 'MappingValidationResult('
        'total: $totalKeys, '
        'mapped: ${mappedKeys.length}, '
        'unmapped: ${unmappedKeys.length}, '
        'invalid: ${invalidKeys.length}, '
        'completeness: ${(mappingCompleteness * 100).toStringAsFixed(1)}%)';
  }
}

/// Statistics about field mappings
class MappingStatistics {
  final int totalCamelToSnakeMappings;
  final int totalSnakeToCamelMappings;
  final int userLevelFields;
  final int membershipFields;
  final int profileFields;
  final bool hasBidirectionalMapping;

  MappingStatistics({
    required this.totalCamelToSnakeMappings,
    required this.totalSnakeToCamelMappings,
    required this.userLevelFields,
    required this.membershipFields,
    required this.profileFields,
    required this.hasBidirectionalMapping,
  });

  @override
  String toString() {
    return 'MappingStatistics('
        'totalMappings: $totalCamelToSnakeMappings, '
        'userFields: $userLevelFields, '
        'membershipFields: $membershipFields, '
        'profileFields: $profileFields, '
        'bidirectional: $hasBidirectionalMapping)';
  }
}
