/// Advanced filter criteria for matching
class AdvancedFilter {
  // Education & Career
  final String? educationLevel;
  final String? occupation;
  final String? employmentType; // Full-time, Part-time, Business, etc.
  final double? minSalary;
  final double? maxSalary;
  final String? salaryCurrency;

  // Physical Attributes
  final int? minHeight;
  final int? maxHeight;
  final String? bodyType;
  final String? complexion;

  // Lifestyle
  final String? diet;
  final String? smoking;
  final String? drinking;
  final String? maritalStatus;

  // Religion & Culture
  final String? religion;
  final String? caste;
  final String? motherTongue;
  final String? nakshatra;
  final String? rashi;

  // Location
  final String? country;
  final String? state;
  final String? city;
  final double? maxDistance;
  final String? distanceUnit;

  // Profile Quality
  final bool? withPhoto;
  final bool? withHoroscope;
  final bool? verifiedOnly;
  final bool? premiumOnly;

  // Activity
  final String? lastActive; // '24h', '7d', '30d', 'any'
  final String? joinedDate; // 'today', 'week', 'month', 'any'

  const AdvancedFilter({
    this.educationLevel,
    this.occupation,
    this.employmentType,
    this.minSalary,
    this.maxSalary,
    this.salaryCurrency,
    this.minHeight,
    this.maxHeight,
    this.bodyType,
    this.complexion,
    this.diet,
    this.smoking,
    this.drinking,
    this.maritalStatus,
    this.religion,
    this.caste,
    this.motherTongue,
    this.nakshatra,
    this.rashi,
    this.country,
    this.state,
    this.city,
    this.maxDistance,
    this.distanceUnit,
    this.withPhoto,
    this.withHoroscope,
    this.verifiedOnly,
    this.premiumOnly,
    this.lastActive,
    this.joinedDate,
  });

  /// Empty filter with no criteria
  factory AdvancedFilter.empty() => const AdvancedFilter();

  /// Check if any filter is active
  bool get isActive {
    return educationLevel != null ||
        occupation != null ||
        employmentType != null ||
        minSalary != null ||
        maxSalary != null ||
        minHeight != null ||
        maxHeight != null ||
        bodyType != null ||
        complexion != null ||
        diet != null ||
        smoking != null ||
        drinking != null ||
        maritalStatus != null ||
        religion != null ||
        caste != null ||
        motherTongue != null ||
        nakshatra != null ||
        rashi != null ||
        country != null ||
        state != null ||
        city != null ||
        maxDistance != null ||
        withPhoto != null ||
        withHoroscope != null ||
        verifiedOnly != null ||
        premiumOnly != null ||
        lastActive != null ||
        joinedDate != null;
  }

  /// Count of active filters
  int get activeCount {
    int count = 0;
    if (educationLevel != null) count++;
    if (occupation != null) count++;
    if (employmentType != null) count++;
    if (minSalary != null || maxSalary != null) count++;
    if (minHeight != null || maxHeight != null) count++;
    if (bodyType != null) count++;
    if (complexion != null) count++;
    if (diet != null) count++;
    if (smoking != null) count++;
    if (drinking != null) count++;
    if (maritalStatus != null) count++;
    if (religion != null) count++;
    if (caste != null) count++;
    if (motherTongue != null) count++;
    if (nakshatra != null) count++;
    if (rashi != null) count++;
    if (country != null || state != null || city != null) count++;
    if (maxDistance != null) count++;
    if (withPhoto != null) count++;
    if (withHoroscope != null) count++;
    if (verifiedOnly != null) count++;
    if (premiumOnly != null) count++;
    if (lastActive != null) count++;
    if (joinedDate != null) count++;
    return count;
  }

  /// Create a copy with some fields changed
  AdvancedFilter copyWith({
    String? educationLevel,
    String? occupation,
    String? employmentType,
    double? minSalary,
    double? maxSalary,
    String? salaryCurrency,
    int? minHeight,
    int? maxHeight,
    String? bodyType,
    String? complexion,
    String? diet,
    String? smoking,
    String? drinking,
    String? maritalStatus,
    String? religion,
    String? caste,
    String? motherTongue,
    String? nakshatra,
    String? rashi,
    String? country,
    String? state,
    String? city,
    double? maxDistance,
    String? distanceUnit,
    bool? withPhoto,
    bool? withHoroscope,
    bool? verifiedOnly,
    bool? premiumOnly,
    String? lastActive,
    String? joinedDate,
    bool clearEducationLevel = false,
    bool clearOccupation = false,
    bool clearMinSalary = false,
    bool clearMaxSalary = false,
    bool clearMinHeight = false,
    bool clearMaxHeight = false,
    bool clearDiet = false,
    bool clearLocation = false,
  }) {
    return AdvancedFilter(
      educationLevel: clearEducationLevel ? null : (educationLevel ?? this.educationLevel),
      occupation: clearOccupation ? null : (occupation ?? this.occupation),
      employmentType: employmentType ?? this.employmentType,
      minSalary: clearMinSalary ? null : (minSalary ?? this.minSalary),
      maxSalary: clearMaxSalary ? null : (maxSalary ?? this.maxSalary),
      salaryCurrency: salaryCurrency ?? this.salaryCurrency,
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
      maxHeight: clearMaxHeight ? null : (maxHeight ?? this.maxHeight),
      bodyType: bodyType ?? this.bodyType,
      complexion: complexion ?? this.complexion,
      diet: clearDiet ? null : (diet ?? this.diet),
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      religion: religion ?? this.religion,
      caste: caste ?? this.caste,
      motherTongue: motherTongue ?? this.motherTongue,
      nakshatra: nakshatra ?? this.nakshatra,
      rashi: rashi ?? this.rashi,
      country: clearLocation ? null : (country ?? this.country),
      state: clearLocation ? null : (state ?? this.state),
      city: clearLocation ? null : (city ?? this.city),
      maxDistance: maxDistance ?? this.maxDistance,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      withPhoto: withPhoto ?? this.withPhoto,
      withHoroscope: withHoroscope ?? this.withHoroscope,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      premiumOnly: premiumOnly ?? this.premiumOnly,
      lastActive: lastActive ?? this.lastActive,
      joinedDate: joinedDate ?? this.joinedDate,
    );
  }

  /// Convert to Map for storage/serialization
  Map<String, dynamic> toMap() {
    return {
      if (educationLevel != null) 'education_level': educationLevel,
      if (occupation != null) 'occupation': occupation,
      if (employmentType != null) 'employment_type': employmentType,
      if (minSalary != null) 'min_salary': minSalary,
      if (maxSalary != null) 'max_salary': maxSalary,
      if (salaryCurrency != null) 'salary_currency': salaryCurrency,
      if (minHeight != null) 'min_height': minHeight,
      if (maxHeight != null) 'max_height': maxHeight,
      if (bodyType != null) 'body_type': bodyType,
      if (complexion != null) 'complexion': complexion,
      if (diet != null) 'diet': diet,
      if (smoking != null) 'smoking': smoking,
      if (drinking != null) 'drinking': drinking,
      if (maritalStatus != null) 'marital_status': maritalStatus,
      if (religion != null) 'religion': religion,
      if (caste != null) 'caste': caste,
      if (motherTongue != null) 'mother_tongue': motherTongue,
      if (nakshatra != null) 'nakshatra': nakshatra,
      if (rashi != null) 'rashi': rashi,
      if (country != null) 'country': country,
      if (state != null) 'state': state,
      if (city != null) 'city': city,
      if (maxDistance != null) 'max_distance': maxDistance,
      if (distanceUnit != null) 'distance_unit': distanceUnit,
      if (withPhoto != null) 'with_photo': withPhoto,
      if (withHoroscope != null) 'with_horoscope': withHoroscope,
      if (verifiedOnly != null) 'verified_only': verifiedOnly,
      if (premiumOnly != null) 'premium_only': premiumOnly,
      if (lastActive != null) 'last_active': lastActive,
      if (joinedDate != null) 'joined_date': joinedDate,
    };
  }

  /// Create from Map
  factory AdvancedFilter.fromMap(Map<String, dynamic> map) {
    return AdvancedFilter(
      educationLevel: map['education_level'],
      occupation: map['occupation'],
      employmentType: map['employment_type'],
      minSalary: map['min_salary']?.toDouble(),
      maxSalary: map['max_salary']?.toDouble(),
      salaryCurrency: map['salary_currency'],
      minHeight: map['min_height'],
      maxHeight: map['max_height'],
      bodyType: map['body_type'],
      complexion: map['complexion'],
      diet: map['diet'],
      smoking: map['smoking'],
      drinking: map['drinking'],
      maritalStatus: map['marital_status'],
      religion: map['religion'],
      caste: map['caste'],
      motherTongue: map['mother_tongue'],
      nakshatra: map['nakshatra'],
      rashi: map['rashi'],
      country: map['country'],
      state: map['state'],
      city: map['city'],
      maxDistance: map['max_distance']?.toDouble(),
      distanceUnit: map['distance_unit'],
      withPhoto: map['with_photo'],
      withHoroscope: map['with_horoscope'],
      verifiedOnly: map['verified_only'],
      premiumOnly: map['premium_only'],
      lastActive: map['last_active'],
      joinedDate: map['joined_date'],
    );
  }

  @override
  String toString() => 'AdvancedFilter(active: $activeCount)';
}

/// Filter options for dropdowns
class FilterOptions {
  static const List<String> educationLevels = [
    'Doctorate',
    'Masters',
    'Bachelors',
    'Diploma',
    'High School',
    'Other',
  ];

  static const List<String> occupations = [
    'IT Professional',
    'Doctor',
    'Engineer',
    'Business',
    'Government',
    'Teacher',
    'Lawyer',
    'CA/Accountant',
    'Architect',
    'Consultant',
    'Self Employed',
    'Not Working',
    'Other',
  ];

  static const List<String> employmentTypes = [
    'Full-time',
    'Part-time',
    'Business Owner',
    'Freelancer',
    'Student',
    'Homemaker',
    'Not Working',
  ];

  static const List<String> diets = [
    'Vegetarian',
    'Non-Vegetarian',
    'Eggetarian',
    'Vegan',
    'Jain',
  ];

  static const List<String> maritalStatuses = [
    'Never Married',
    'Divorced',
    'Widowed',
    'Awaiting Divorce',
  ];

  static const List<String> smokingOptions = [
    'No',
    'Occasionally',
    'Yes',
  ];

  static const List<String> drinkingOptions = [
    'No',
    'Occasionally',
    'Yes',
  ];

  static const List<String> bodyTypes = [
    'Slim',
    'Average',
    'Athletic',
    'Heavy',
  ];

  static const List<String> complexions = [
    'Very Fair',
    'Fair',
    'Wheatish',
    'Wheatish Brown',
    'Dark',
  ];

  static const List<String> religions = [
    'Hindu',
    'Christian',
    'Muslim',
    'Jain',
    'Sikh',
    'Buddhist',
    'Parsi',
    'Jewish',
    'Other',
  ];

  static const List<String> lastActiveOptions = [
    '24h',
    '7d',
    '30d',
    'any',
  ];

  static const List<String> joinedDateOptions = [
    'today',
    'week',
    'month',
    'any',
  ];

  /// Get human-readable label for option
  static String getLabel(String value, String category) {
    switch (category) {
      case 'last_active':
        return {
          '24h': 'Active in last 24 hours',
          '7d': 'Active in last 7 days',
          '30d': 'Active in last 30 days',
          'any': 'Any time',
        }[value] ?? value;
      case 'joined_date':
        return {
          'today': 'Joined today',
          'week': 'Joined this week',
          'month': 'Joined this month',
          'any': 'Any time',
        }[value] ?? value;
      default:
        return value;
    }
  }
}
