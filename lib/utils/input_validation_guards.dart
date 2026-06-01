import 'dart:core';

/// Comprehensive input validation guards for Brahmin Vivaaha Vedika app
/// Prevents contact sharing, ensures data integrity, and validates specific field types
class InputValidationGuards {
  // Regex patterns for detecting contact information
  static final RegExp _phonePattern = RegExp(r'\b(?:\+91|0)?[6-9]\d{9}\b');
  static final RegExp _emailPattern = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
  static final RegExp _whatsappPattern = RegExp(r'\b(?:whatsapp|wa|w\.a\.|call|msg|text|sms)\b', caseSensitive: false);
  static final RegExp _websitePattern = RegExp(r'\b(?:www\.|http|https|\.com|\.in|\.org|\.net|\.co)\b', caseSensitive: false);
  static final RegExp _socialPattern = RegExp(r'\b(?:instagram|fb|facebook|twitter|linkedin|telegram|signal|snapchat)\b', caseSensitive: false);
  
  // Number words in English and Telugu
  static final RegExp _numberWordsPattern = RegExp(
    r'\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|lakh|crore|సున్న|ఒకటి|రెండు|మూడు|నాలుగు|ఐదు|ఆరు|ఏడు|ఎనిమిది|తొమ్మిది|పది|వంద|వెయ్యి|లక్ష|కోటి)\b',
    caseSensitive: false
  );
  
  // Consecutive digits pattern (3 or more)
  static final RegExp _consecutiveDigitsPattern = RegExp(r'\d{3,}');

  /// Same as private patterns — exposed for [ValidationService.sanitizeInput].
  static RegExp get phonePattern => _phonePattern;
  static RegExp get emailPattern => _emailPattern;
  static RegExp get whatsappPattern => _whatsappPattern;
  static RegExp get websitePattern => _websitePattern;
  static RegExp get socialPattern => _socialPattern;

  /// Alpha Only Guard - For names, cities, gothrams, sects
  /// Allows only letters and basic punctuation, no digits or contact info
  static ValidationResult validateAlphaOnly(String input, {String fieldName = 'Field'}) {
    if (input.isEmpty) {
      return ValidationResult(true, ''); // Empty is allowed (optional fields)
    }

    // Check for contact information
    final contactCheck = _checkForContactInfo(input);
    if (!contactCheck.isValid) {
      return contactCheck;
    }

    // Check for number words
    if (_numberWordsPattern.hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain number words');
    }

    // Check for any digits
    if (RegExp(r'\d').hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain numbers');
    }

    // Allow only letters, spaces, and basic punctuation (.,'-)
    if (!RegExp(r"^[a-zA-Z\u0C00-\u0C7F\s.,'\-]+$").hasMatch(input)) {
      return ValidationResult(false, '$fieldName can only contain letters and basic punctuation');
    }

    return ValidationResult(true, '');
  }

  /// Note Field Guard - For About Me, family notes, decline reasons, feedback
  /// Allows limited digits (max 3 consecutive), no number words, no contact info
  static ValidationResult validateNoteField(String input, {String fieldName = 'Field'}) {
    if (input.isEmpty) {
      return ValidationResult(true, ''); // Empty is allowed
    }

    // Check for contact information
    final contactCheck = _checkForContactInfo(input);
    if (!contactCheck.isValid) {
      return contactCheck;
    }

    // Check for number words
    if (_numberWordsPattern.hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain number words');
    }

    // Check for 3+ consecutive digits
    if (_consecutiveDigitsPattern.hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain 3 or more consecutive digits');
    }

    // Allow reasonable characters for notes (concatenate to avoid \' / \" in one raw literal)
    if (!RegExp(
      r'^[a-zA-Z0-9\u0C00-\u0C7F\s.,;:!?'
      "'" 
      r'"'
      r'()\-'
      r'\n'
      r']+$',
    ).hasMatch(input)) {
      return ValidationResult(false, '$fieldName contains invalid characters');
    }

    return ValidationResult(true, '');
  }

  /// Numeric With Unit Guard - For height, weight
  /// Allows digits only with unit suffix letters
  static ValidationResult validateNumericWithUnit(String input, {String fieldName = 'Field'}) {
    if (input.isEmpty) {
      return ValidationResult(true, ''); // Empty is allowed
    }

    // Check for contact information
    final contactCheck = _checkForContactInfo(input);
    if (!contactCheck.isValid) {
      return contactCheck;
    }

    // Allow patterns like: "175cm", "5.5ft", "70kg", "150lbs"
    if (!RegExp(r'^[\d.]+\s*[a-zA-Z]+$').hasMatch(input)) {
      return ValidationResult(false, '$fieldName must be in format: number + unit (e.g., 175cm, 70kg)');
    }

    return ValidationResult(true, '');
  }

  /// Parent Name Guard - For father's/mother's names
  /// No digits, no number words, but allows more words than alpha guard
  static ValidationResult validateParentName(String input, {String fieldName = 'Parent Name'}) {
    if (input.isEmpty) {
      return ValidationResult(true, ''); // Empty is allowed
    }

    // Check for contact information
    final contactCheck = _checkForContactInfo(input);
    if (!contactCheck.isValid) {
      return contactCheck;
    }

    // Check for number words
    if (_numberWordsPattern.hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain number words');
    }

    // Check for any digits
    if (RegExp(r'\d').hasMatch(input)) {
      return ValidationResult(false, '$fieldName cannot contain numbers');
    }

    // Allow letters, spaces, and more punctuation for parent names
    if (!RegExp(r"^[a-zA-Z\u0C00-\u0C7F\s.,'\-&()]+$").hasMatch(input)) {
      return ValidationResult(false, '$fieldName can only contain letters and basic punctuation');
    }

    return ValidationResult(true, '');
  }

  /// Comprehensive contact information check
  static ValidationResult _checkForContactInfo(String input) {
    final lowerInput = input.toLowerCase();

    // Check for phone numbers
    if (_phonePattern.hasMatch(input)) {
      return ValidationResult(false, 'Phone numbers are not allowed');
    }

    // Check for email addresses
    if (_emailPattern.hasMatch(input)) {
      return ValidationResult(false, 'Email addresses are not allowed');
    }

    // Check for WhatsApp references
    if (_whatsappPattern.hasMatch(lowerInput)) {
      return ValidationResult(false, 'WhatsApp references are not allowed');
    }

    // Check for website URLs
    if (_websitePattern.hasMatch(lowerInput)) {
      return ValidationResult(false, 'Website URLs are not allowed');
    }

    // Check for social media references
    if (_socialPattern.hasMatch(lowerInput)) {
      return ValidationResult(false, 'Social media references are not allowed');
    }

    // Check for common contact-sharing patterns
    final contactPatterns = [
      RegExp(r'\b(?:call|contact|reach|message|text|sms|ping)\s+(?:me|at|on)\b', caseSensitive: false),
      RegExp(r'\b(?:my|our)\s+(?:number|contact|phone|mobile)\b', caseSensitive: false),
      RegExp(r'\b(?:available|find|search)\s+(?:me|us)\s+(?:on|at)\b', caseSensitive: false),
    ];

    for (final pattern in contactPatterns) {
      if (pattern.hasMatch(lowerInput)) {
        return ValidationResult(false, 'Contact sharing is not allowed');
      }
    }

    return ValidationResult(true, '');
  }

  /// Generic validator that can be used with specific guard types
  static ValidationResult validate(String input, ValidationGuardType guardType, {String fieldName = 'Field'}) {
    switch (guardType) {
      case ValidationGuardType.alphaOnly:
        return validateAlphaOnly(input, fieldName: fieldName);
      case ValidationGuardType.noteField:
        return validateNoteField(input, fieldName: fieldName);
      case ValidationGuardType.numericWithUnit:
        return validateNumericWithUnit(input, fieldName: fieldName);
      case ValidationGuardType.parentName:
        return validateParentName(input, fieldName: fieldName);
    }
  }
}

/// Types of validation guards
enum ValidationGuardType {
  alphaOnly,
  noteField,
  numericWithUnit,
  parentName,
}

/// Validation result class
class ValidationResult {
  final bool isValid;
  final String errorMessage;

  const ValidationResult(this.isValid, this.errorMessage);

  @override
  String toString() => 'ValidationResult(isValid: $isValid, errorMessage: $errorMessage)';
}

/// Extension methods for easy validation
extension InputValidationExtension on String {
  /// Validate as alpha-only field
  ValidationResult validateAsAlphaOnly({String fieldName = 'Field'}) {
    return InputValidationGuards.validateAlphaOnly(this, fieldName: fieldName);
  }

  /// Validate as note field
  ValidationResult validateAsNoteField({String fieldName = 'Field'}) {
    return InputValidationGuards.validateNoteField(this, fieldName: fieldName);
  }

  /// Validate as numeric with unit field
  ValidationResult validateAsNumericWithUnit({String fieldName = 'Field'}) {
    return InputValidationGuards.validateNumericWithUnit(this, fieldName: fieldName);
  }

  /// Validate as parent name field
  ValidationResult validateAsParentName({String fieldName = 'Parent Name'}) {
    return InputValidationGuards.validateParentName(this, fieldName: fieldName);
  }

  /// Check if contains contact information
  bool get containsContactInfo {
    final result = InputValidationGuards._checkForContactInfo(this);
    return !result.isValid;
  }

  /// Check if contains number words
  bool get containsNumberWords {
    return InputValidationGuards._numberWordsPattern.hasMatch(this);
  }

  /// Check if contains 3+ consecutive digits
  bool get hasConsecutiveDigits {
    return InputValidationGuards._consecutiveDigitsPattern.hasMatch(this);
  }
}
