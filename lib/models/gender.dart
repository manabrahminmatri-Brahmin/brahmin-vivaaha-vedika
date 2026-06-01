// gender.dart

enum Gender {
  male,
  female;

  Gender get opposite =>
      this == Gender.male ? Gender.female : Gender.male;

  /// Returns 'male' or 'female' (lowercase).
  String get genderName =>
      this == Gender.male ? 'male' : 'female';

  String get displayName =>
      this == Gender.male ? 'Male' : 'Female';

  String get profileType =>
      this == Gender.male ? 'Groom' : 'Bride';

  String get lookingForType =>
      this == Gender.male ? 'Bride' : 'Groom';
}

/// Normalize any legacy Firestore / form value to canonical `'male'`, `'female'`, or null.
String? normalizeGender(dynamic value) {
  if (value == null) return null;
  if (value is Gender) return value.genderName;

  var s = value.toString().trim();
  if (s.isEmpty) return null;

  // Enum-style strings: "Gender.male", "Gender.female"
  final lower = s.toLowerCase();
  if (lower.startsWith('gender.')) {
    s = s.substring(s.indexOf('.') + 1).trim();
  }

  final t = s.toLowerCase();
  if (t.isEmpty) return null;

  const maleHints = {
    'male', 'm', 'groom', 'boy', 'man', 'masculine', 'masc',
    'son', 'gentleman',
  };
  const femaleHints = {
    'female', 'f', 'bride', 'girl', 'woman', 'lady', 'feminine', 'fem',
    'daughter',
  };

  if (maleHints.contains(t)) return 'male';
  if (femaleHints.contains(t)) return 'female';

  // Compound / noisy values: "gender-male", "sex: female", "MALE (groom)"
  for (final part in t.split(RegExp(r'[^a-z]+'))) {
    if (part.isEmpty || part == 'gender') continue;
    if (maleHints.contains(part)) return 'male';
    if (femaleHints.contains(part)) return 'female';
  }

  return null;
}

/// Parse [Gender] from dynamic (Firestore, forms, enums).
Gender? genderFromDynamic(dynamic value) {
  final s = normalizeGender(value);
  if (s == null) return null;
  return s == 'male' ? Gender.male : Gender.female;
}

/// Parse gender from string-only legacy callers.
Gender? genderFromLooseString(String? raw) => genderFromDynamic(raw);

/// Gender from a Firestore `users` document (root + nested `profile` map).
Gender? genderFromUserDocumentData(Map<String, dynamic> data) {
  const keys = [
    'gender',
    'sex',
    'user_gender',
    'profile_gender',
    'Gender',
    'gender_value',
  ];
  for (final k in keys) {
    final g = genderFromDynamic(data[k]);
    if (g != null) return g;
  }
  final prof = data['profile'];
  if (prof is Map<String, dynamic>) {
    for (final k in keys) {
      final g = genderFromDynamic(prof[k]);
      if (g != null) return g;
    }
  }
  return null;
}

/// Firestore `whereIn` values for opposite-gender queries (case + common legacy variants).
/// Keep list size within Firestore limits (typically 10–30; we stay ≤ 10 per query).
List<String> genderFirestoreQueryAliases(String canonicalMaleOrFemaleLower) {
  final n = normalizeGender(canonicalMaleOrFemaleLower);
  if (n == null || (n != 'male' && n != 'female')) {
    return [canonicalMaleOrFemaleLower.toString()];
  }
  if (n == 'male') {
    return [
      'male',
      'Male',
      'MALE',
      'm',
      'groom',
      'Groom',
      'boy',
      'Boy',
      'Gender.male',
    ];
  }
  return [
    'female',
    'Female',
    'FEMALE',
    'f',
    'bride',
    'Bride',
    'girl',
    'Girl',
    'Gender.female',
  ];
}
