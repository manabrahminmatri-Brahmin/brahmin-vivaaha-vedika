/// 🔥 FIRESTORE FIELDS DEFINITION
/// Complete field mapping for Firestore user documents
library;

class FirestoreFields {
  // Basic Profile Fields
  static const String firstName = 'first_name';
  static const String lastName = 'last_name';
  static const String gender = 'gender';
  static const String dateOfBirth = 'date_of_birth';
  static const String timeOfBirth = 'time_of_birth';
  static const String placeOfBirth = 'place_of_birth';
  static const String placeOfBirthState = 'place_of_birth_state';
  static const String placeOfBirthCountry = 'place_of_birth_country';
  static const String height = 'height';
  static const String heightCm = 'height_cm';
  static const String weight = 'weight';
  static const String complexion = 'complexion';
  static const String bodyType = 'body_type';
  static const String physicalStatus = 'physical_status';
  
  // Religious & Cultural Fields
  static const String sect = 'sect';
  static const String subSect = 'sub_sect';
  static const String gothram = 'gothram';
  static const String nakshatra = 'nakshatra';
  static const String pada = 'pada';
  static const String rasi = 'rasi';
  static const String starConfirmed = 'star_confirmed';
  static const String manglikStatus = 'manglik_status';
  static const String hasHoroscope = 'has_horoscope';
  
  // Education Fields
  static const String education = 'education';
  static const String specialization = 'specialization';
  static const String educationStatus = 'education_status';
  static const String universityName = 'university_name';
  static const String educationLocationCity = 'education_location_city';
  static const String educationLocationState = 'education_location_state';
  static const String educationLocationCountry = 'education_location_country';
  static const String additionalQualifications = 'additional_qualifications';
  static const String qualificationNotes = 'qualification_notes';
  
  // Professional Fields
  static const String occupation = 'occupation';
  static const String employmentType = 'employment_type';
  static const String companyName = 'company_name';
  static const String businessDescription = 'business_description';
  static const String incomeRange = 'income_range';
  
  // Family Fields
  static const String maritalStatus = 'marital_status';
  static const String familyType = 'family_type';
  static const String familyStatus = 'family_status';
  static const String familyValues = 'family_values';
  static const String familyOriginCity = 'family_origin_city';
  static const String familyOriginState = 'family_origin_state';
  static const String familyOriginCountry = 'family_origin_country';
  static const String fatherName = 'father_name';
  static const String fatherNote = 'father_note';
  static const String fatherOccupation = 'father_occupation';
  static const String motherName = 'mother_name';
  static const String motherNote = 'mother_note';
  static const String motherOccupation = 'mother_occupation';
  static const String motherSurname = 'mother_surname';
  static const String brothers = 'brothers';
  static const String brothersMarried = 'brothers_married';
  static const String sisters = 'sisters';
  static const String sistersMarried = 'sisters_married';
  
  // Lifestyle Fields
  static const String hobbies = 'hobbies';
  static const String interests = 'interests';
  static const String languages = 'languages';
  static const String foodHabit = 'food_habit';
  static const String drinkingHabit = 'drinking_habit';
  static const String smokingHabit = 'smoking_habit';
  
  // About Fields
  static const String aboutMe = 'about_me';
  static const String aboutFamily = 'about_family';
  static const String partnerPreferences = 'partner_preferences';
  static const String partnerExpectations = 'partner_expectations';
  
  // Partner Preference Fields
  static const String partnerMinAge = 'partner_min_age';
  static const String partnerMaxAge = 'partner_max_age';
  static const String partnerEducation = 'partner_education';
  static const String partnerOccupation = 'partner_occupation';
  static const String partnerIncomeRange = 'partner_income_range';
  static const String partnerManglikPreference = 'partner_manglik_preference';
  static const String partnerLocations = 'partner_locations';
  static const String partnerHeightMin = 'partner_height_min';
  static const String partnerHeightMax = 'partner_height_max';
  static const String partnerMaritalStatus = 'partner_marital_status';
  static const String willingToRelocate = 'willing_to_relocate';
  static const String relocatePreference = 'relocate_preference';
  static const String settledAbroad = 'settled_abroad';
  static const String citizenship = 'citizenship';
  
  // Photo Fields
  static const String profilePicture = 'profile_picture';
  static const String photoUrl = 'photo_url';
  static const String photos = 'photos';
  static const String photosEnabled = 'photos_enabled';
  static const String photoLastUpdated = 'photo_last_updated';
  static const String isPhotoPrivate = 'is_photo_private';
  static const String photoPrivacy = 'photo_privacy';
  
  // Status Fields
  static const String status = 'status';
  static const String isDeleted = 'is_deleted';
  static const String isProfileLocked = 'is_profile_locked';
  static const String isProfileComplete = 'is_profile_complete';
  static const String isAdmin = 'is_admin';
  static const String isVerified = 'is_verified';
  static const String isEmailVerified = 'is_email_verified';
  static const String isPhoneVerified = 'is_phone_verified';
  static const String isOnline = 'is_online';
  static const String isPremium = 'is_premium';
  static const String isMpinVerified = 'mpin_verified';
  static const String privacyIncognito = 'privacy_incognito';
  static const String privacyShowLastSeen = 'privacy_show_last_seen';
  static const String privacyShowOnlineStatus = 'privacy_show_online_status';
  
  // Membership Fields
  static const String membershipTier = 'membership_tier';
  static const String membershipStatus = 'membership_status';
  static const String membership = 'membership';
  static const String membershipJson = 'membership_json';
  
  // Identity Fields
  static const String profileId = 'profile_id';
  static const String authUid = 'auth_uid';
  static const String alternativeMobileNumber = 'alternative_mobile_number';
  static const String mpinHash = 'mpin_hash';
  static const String password = 'password';
  static const String verificationCode = 'verification_code';
  static const String verificationCodeExpiry = 'verification_code_expiry';
  
  // Profile Completion Fields
  static const String profileCompletionPercentage = 'profile_completion_percentage';
  static const String profileCreatedBy = 'profile_created_by';
  static const String knownReference = 'known_reference';
  static const String knownReference2 = 'known_reference_2';
  
  // Activity Fields
  static const String profileViewsReceived = 'profile_views_received';
  static const String profileViewsSent = 'profile_views_sent';
  static const String likesReceived = 'likes_received';
  static const String likesSent = 'likes_sent';
  static const String lastActive = 'last_active';
  static const String lastLoginAt = 'last_login_at';
  
  // Timestamp Fields
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
  static const String profileUpdatedAt = 'profile_updated_at';
  static const String dataRefreshFlag = 'data_refresh_flag';
  
  // Location Fields
  static const String city = 'city';
  static const String state = 'state';
  static const String country = 'country';
  static const String nativePlaceCity = 'native_place_city';
  static const String nativePlaceState = 'native_place_state';
  static const String nativePlaceCountry = 'native_place_country';
  
  // Contact Fields
  static const String mobileNumber = 'mobile_number';
  static const String email = 'email';
  
  // Admin Fields
  static const String adminPermissions = 'admin_permissions';
  static const String adminRole = 'admin_role';
  
  /// Get all field names
  static List<String> getAllFieldNames() {
    return [
      firstName, lastName, gender, dateOfBirth, timeOfBirth, placeOfBirth,
      placeOfBirthState, placeOfBirthCountry, height, heightCm, weight, complexion,
      bodyType, physicalStatus, sect, subSect, gothram, nakshatra, pada,
      rasi, starConfirmed, manglikStatus, hasHoroscope, education, specialization,
      educationStatus, universityName, educationLocationCity, educationLocationState,
      educationLocationCountry, additionalQualifications, qualificationNotes, occupation,
      employmentType, companyName, businessDescription, incomeRange, maritalStatus, familyType,
      familyStatus, familyValues, familyOriginCity, familyOriginState,
      familyOriginCountry, fatherName, fatherNote, fatherOccupation, motherName,
      motherNote, motherOccupation, motherSurname, brothers, brothersMarried,
      sisters, sistersMarried, hobbies, interests, languages, foodHabit,
      drinkingHabit, smokingHabit, aboutMe, aboutFamily, partnerPreferences,
      partnerExpectations, partnerMinAge, partnerMaxAge, partnerEducation,
      partnerOccupation, partnerIncomeRange, partnerManglikPreference,
      partnerLocations, partnerHeightMin, partnerHeightMax, partnerMaritalStatus,
      willingToRelocate, relocatePreference, settledAbroad, citizenship,
      profilePicture, photoUrl, photos, photosEnabled, photoLastUpdated,
      isPhotoPrivate, photoPrivacy, status, isDeleted, isProfileLocked,
      isProfileComplete, isAdmin, isVerified, isEmailVerified, isPhoneVerified,
      isOnline, isPremium, isMpinVerified, privacyIncognito,
      privacyShowLastSeen, privacyShowOnlineStatus, membershipTier,
      membershipStatus, membership, membershipJson, profileId, authUid,
      alternativeMobileNumber, mpinHash, password, verificationCode,
      verificationCodeExpiry, profileCompletionPercentage, profileCreatedBy,
      knownReference, knownReference2, profileViewsReceived, profileViewsSent,
      likesReceived, likesSent, lastActive, lastLoginAt, createdAt, updatedAt,
      profileUpdatedAt, dataRefreshFlag, city, state, country, nativePlaceCity,
      nativePlaceState, nativePlaceCountry, mobileNumber, email, adminPermissions,
      adminRole
    ];
  }
  
  /// Get required fields
  static List<String> getRequiredFields() {
    return [
      firstName, lastName, gender, dateOfBirth, mobileNumber, status
    ];
  }
  
  /// Get field display names
  static Map<String, String> getFieldDisplayNames() {
    return {
      'firstName': 'First Name',
      'lastName': 'Last Name',
      'gender': 'Gender',
      'dateOfBirth': 'Date of Birth',
      'timeOfBirth': 'Time of Birth',
      'placeOfBirth': 'Place of Birth',
      'placeOfBirthState': 'Place of Birth State',
      'placeOfBirthCountry': 'Place of Birth Country',
      'height': 'Height',
      'heightCm': 'Height (cm)',
      'weight': 'Weight',
      'complexion': 'Complexion',
      'bodyType': 'Body Type',
      'physicalStatus': 'Physical Status',
      'sect': 'Sect',
      'subSect': 'Sub Sect',
      'gothram': 'Gothram',
      'nakshatra': 'Nakshatra',
      'pada': 'Pada',
      'rasi': 'Rasi',
      'starConfirmed': 'Star Confirmed',
      'manglikStatus': 'Manglik Status',
      'hasHoroscope': 'Has Horoscope',
      'education': 'Education',
      'specialization': 'Specialization',
      'educationStatus': 'Education Status',
      'universityName': 'University Name',
      'educationLocationCity': 'Education Location City',
      'educationLocationState': 'Education Location State',
      'educationLocationCountry': 'Education Location Country',
      'additionalQualifications': 'Additional Qualifications',
      'qualificationNotes': 'Qualification Notes',
      'occupation': 'Occupation',
      'employmentType': 'Employment Type',
      'companyName': 'Company Name',
      'businessDescription': 'Business Description',
      'incomeRange': 'Income Range',
      'maritalStatus': 'Marital Status',
      'familyType': 'Family Type',
      'familyStatus': 'Family Status',
      'familyValues': 'Family Values',
      'familyOriginCity': 'Family Origin City',
      'familyOriginState': 'Family Origin State',
      'familyOriginCountry': 'Family Origin Country',
      'fatherName': 'Father Name',
      'fatherNote': 'Father Note',
      'fatherOccupation': 'Father Occupation',
      'motherName': 'Mother Name',
      'motherNote': 'Mother Note',
      'motherOccupation': 'Mother Occupation',
      'motherSurname': 'Mother Surname',
      'brothers': 'Brothers',
      'brothersMarried': 'Brothers Married',
      'sisters': 'Sisters',
      'sistersMarried': 'Sisters Married',
      'hobbies': 'Hobbies',
      'interests': 'Interests',
      'languages': 'Languages',
      'foodHabit': 'Food Habit',
      'drinkingHabit': 'Drinking Habit',
      'smokingHabit': 'Smoking Habit',
      'aboutMe': 'About Me',
      'aboutFamily': 'About Family',
      'partnerPreferences': 'Partner Preferences',
      'partnerExpectations': 'Partner Expectations',
      'partnerMinAge': 'Partner Min Age',
      'partnerMaxAge': 'Partner Max Age',
      'partnerEducation': 'Partner Education',
      'partnerOccupation': 'Partner Occupation',
      'partnerIncomeRange': 'Partner Income Range',
      'partnerManglikPreference': 'Partner Manglik Preference',
      'partnerLocations': 'Partner Locations',
      'partnerHeightMin': 'Partner Height Min',
      'partnerHeightMax': 'Partner Height Max',
      'partnerMaritalStatus': 'Partner Marital Status',
      'willingToRelocate': 'Willing to Relocate',
      'relocatePreference': 'Relocate Preference',
      'settledAbroad': 'Settled Abroad',
      'citizenship': 'Citizenship',
      'profilePicture': 'Profile Picture',
      'photoUrl': 'Photo URL',
      'photos': 'Photos',
      'photosEnabled': 'Photos Enabled',
      'photoLastUpdated': 'Photo Last Updated',
      'isPhotoPrivate': 'Is Photo Private',
      'photoPrivacy': 'Photo Privacy',
      'status': 'Status',
      'isDeleted': 'Is Deleted',
      'isProfileLocked': 'Is Profile Locked',
      'isProfileComplete': 'Is Profile Complete',
      'isAdmin': 'Is Admin',
      'isVerified': 'Is Verified',
      'isEmailVerified': 'Is Email Verified',
      'isPhoneVerified': 'Is Phone Verified',
      'isOnline': 'Is Online',
      'isPremium': 'Is Premium',
      'isMpinVerified': 'Is MPIN Verified',
      'privacyIncognito': 'Privacy Incognito',
      'privacyShowLastSeen': 'Privacy Show Last Seen',
      'privacyShowOnlineStatus': 'Privacy Show Online Status',
      'membershipTier': 'Membership Tier',
      'membershipStatus': 'Membership Status',
      'membership': 'Membership',
      'membershipJson': 'Membership JSON',
      'profileId': 'Profile ID',
      'authUid': 'Auth UID',
      'alternativeMobileNumber': 'Alternative Mobile Number',
      'mpinHash': 'MPIN Hash',
      'password': 'Password',
      'verificationCode': 'Verification Code',
      'verificationCodeExpiry': 'Verification Code Expiry',
      'profileCompletionPercentage': 'Profile Completion Percentage',
      'profileCreatedBy': 'Profile Created By',
      'knownReference': 'Known Reference',
      'knownReference2': 'Known Reference 2',
      'profileViewsReceived': 'Profile Views Received',
      'profileViewsSent': 'Profile Views Sent',
      'likesReceived': 'Likes Received',
      'likesSent': 'Likes Sent',
      'lastActive': 'Last Active',
      'lastLoginAt': 'Last Login At',
      'createdAt': 'Created At',
      'updatedAt': 'Updated At',
      'profileUpdatedAt': 'Profile Updated At',
      'dataRefreshFlag': 'Data Refresh Flag',
      'city': 'City',
      'state': 'State',
      'country': 'Country',
      'nativePlaceCity': 'Native Place City',
      'nativePlaceState': 'Native Place State',
      'nativePlaceCountry': 'Native Place Country',
      'mobileNumber': 'Mobile Number',
      'email': 'Email',
      'adminPermissions': 'Admin Permissions',
      'adminRole': 'Admin Role'
    };
  }
  
  /// Get field validation rules
  static Map<String, dynamic> getFieldValidationRules() {
    return {
      'firstName': {'required': true, 'type': 'String'},
      'lastName': {'required': true, 'type': 'String'},
      'gender': {'required': true, 'type': 'String', 'options': ['Male', 'Female', 'Other']},
      'dateOfBirth': {'required': true, 'type': 'String', 'format': 'YYYY-MM-DD'},
      'mobileNumber': {'required': true, 'type': 'String', 'format': r'^[0-9]{10}$'},
      'email': {'required': false, 'type': 'String', 'format': 'email'},
      'height': {'required': false, 'type': 'String'},
      'weight': {'required': false, 'type': 'String'},
      'education': {'required': false, 'type': 'String'},
      'occupation': {'required': false, 'type': 'String'},
      'incomeRange': {'required': false, 'type': 'String'},
      'profilePicture': {'required': false, 'type': 'String', 'format': 'url'},
      'photos': {'required': false, 'type': 'Array'},
      'isPhotoPrivate': {'required': false, 'type': 'Boolean'},
      'status': {'required': true, 'type': 'String', 'options': ['active', 'inactive']},
      'isDeleted': {'required': false, 'type': 'Boolean'},
      'isProfileComplete': {'required': false, 'type': 'Boolean'},
      'isVerified': {'required': false, 'type': 'Boolean'},
      'isAdmin': {'required': false, 'type': 'Boolean'},
      'isPremium': {'required': false, 'type': 'Boolean'},
      'partnerMinAge': {'required': false, 'type': 'int', 'min': 18},
      'partnerMaxAge': {'required': false, 'type': 'int', 'max': 100},
      'partnerLocations': {'required': false, 'type': 'Array'},
      'willingToRelocate': {'required': false, 'type': 'Boolean'},
      'createdAt': {'required': false, 'type': 'DateTime'},
      'updatedAt': {'required': false, 'type': 'DateTime'}
    };
  }
  
  /// Get default values for fields
  static Map<String, dynamic> getFieldDefaults() {
    return {
      'firstName': '',
      'lastName': '',
      'gender': '',
      'dateOfBirth': '',
      'timeOfBirth': '',
      'placeOfBirth': '',
      'placeOfBirthState': '',
      'placeOfBirthCountry': '',
      'height': '',
      'heightCm': '',
      'weight': '',
      'complexion': '',
      'bodyType': '',
      'physicalStatus': '',
      'sect': '',
      'subSect': '',
      'gothram': '',
      'nakshatra': '',
      'pada': '',
      'rasi': '',
      'starConfirmed': false,
      'manglikStatus': '',
      'hasHoroscope': false,
      'education': '',
      'specialization': '',
      'educationStatus': '',
      'universityName': '',
      'educationLocationCity': '',
      'educationLocationState': '',
      'educationLocationCountry': '',
      'additionalQualifications': '',
      'qualificationNotes': '',
      'occupation': '',
      'employmentType': '',
      'companyName': '',
      'businessDescription': '',
      'incomeRange': '',
      'maritalStatus': '',
      'familyType': '',
      'familyStatus': '',
      'familyValues': '',
      'familyOriginCity': '',
      'familyOriginState': '',
      'familyOriginCountry': '',
      'fatherName': '',
      'fatherNote': '',
      'fatherOccupation': '',
      'motherName': '',
      'motherNote': '',
      'motherOccupation': '',
      'motherSurname': '',
      'brothers': 0,
      'brothersMarried': 0,
      'sisters': 0,
      'sistersMarried': 0,
      'hobbies': [],
      'interests': [],
      'languages': [],
      'aboutMe': '',
      'aboutFamily': '',
      'partnerPreferences': '',
      'partnerExpectations': '',
      'partnerMinAge': null,
      'partnerMaxAge': null,
      'partnerEducation': '',
      'partnerOccupation': '',
      'partnerIncomeRange': '',
      'partnerManglikPreference': '',
      'partnerLocations': [],
      'partnerHeightMin': '',
      'partnerHeightMax': '',
      'partnerMaritalStatus': [],
      'willingToRelocate': false,
      'relocatePreference': '',
      'settledAbroad': false,
      'citizenship': '',
      'profilePicture': '',
      'photoUrl': '',
      'photos': [],
      'photosEnabled': true,
      'photoLastUpdated': '',
      'isPhotoPrivate': false,
      'photoPrivacy': 'public',
      'status': 'active',
      'isDeleted': false,
      'isProfileLocked': false,
      'isProfileComplete': true,
      'isAdmin': false,
      'isVerified': true,
      'isEmailVerified': false,
      'isPhoneVerified': false,
      'isOnline': false,
      'isPremium': false,
      'isMpinVerified': true,
      'privacyIncognito': false,
      'privacyShowLastSeen': true,
      'privacyShowOnlineStatus': true,
      'membershipTier': 'free',
      'membershipStatus': 'free',
      'membership': {'tier': 'free', 'startDate': null, 'expiryDate': null},
      'membershipJson': {'tier': 'free', 'startDate': null, 'expiryDate': null},
      'profileId': '',
      'authUid': '',
      'alternativeMobileNumber': '',
      'mpinHash': null,
      'password': null,
      'verificationCode': '',
      'verificationCodeExpiry': null,
      'profileCompletionPercentage': 100,
      'profileCreatedBy': '',
      'knownReference': '',
      'knownReference2': '',
      'profileViewsReceived': 0,
      'profileViewsSent': 0,
      'likesReceived': 0,
      'likesSent': 0,
      'lastActive': null,
      'lastLoginAt': null,
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
      'profileUpdatedAt': DateTime.now(),
      'dataRefreshFlag': DateTime.now(),
      'foodHabit': '',
      'drinkingHabit': '',
      'smokingHabit': '',
      'city': '',
      'state': '',
      'country': '',
      'nativePlaceCity': '',
      'nativePlaceState': '',
      'nativePlaceCountry': '',
      'adminPermissions': [],
      'adminRole': '',
      'mobileNumber': '',
      'email': ''
    };
  }
}

/// 🔥 USAGE EXAMPLES:
/// 
/// // Import and use in your models
/// import 'firestore_fields.dart';
/// 
/// // Use field constants
/// final fieldName = FirestoreFields.firstName;
/// 
/// // Check if field is required
/// final isRequired = FirestoreFields.getRequiredFields().contains(fieldName);
/// 
/// // Get field display name
/// final displayName = FirestoreFields.getFieldDisplayNames()[fieldName];
/// 
/// // Get validation rules
/// final validationRules = FirestoreFields.getFieldValidationRules()[fieldName];
/// 
/// // Get default value
/// final defaultValue = FirestoreFields.getFieldDefaults()[fieldName];
