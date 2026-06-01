import 'package:flutter/services.dart';

/// **Not** Indian mobile OTP validation ([OtpService] / `validation/phone_validator.dart`).
/// These formatters enforce free-text rules (names, bios, numeric+unit fields) and block digit/contact patterns.
// FIELD INPUT RULES  (applies to every free-text entry in the app)
//
//  ALPHA-ONLY fields  (names, city, about-me, descriptions, etc.)
//    • No digit characters (0-9) are permitted — hard blocked on keypress
//    • Number words ("one", "two", … "thousand") are blocked
//    • Phone / contact patterns are blocked (see _detectContactSharing)
//
//  NUMERIC-WITH-UNIT fields  (height, weight, etc.)
//    • Digits are freely allowed
//    • Letters are allowed ONLY if they form a recognised unit suffix
//      (cm, ft, in, kg, lbs, m) — max 3 alpha chars total
//    • If the user tries to type a 3rd alpha char that is NOT part of an
//      allowed unit, the keystroke is silently dropped
//    • Phone / contact patterns are blocked
//
//  ALL FIELDS  (both types)
//    • Sequences of 7+ consecutive digits are blocked
//    • 10+ total digits in any field are blocked
//    • Common obfuscation tricks are caught (Unicode digit look-alikes,
//      trigger phrases like "call me", "whatsapp", email domains)
// ─────────────────────────────────────────────────────────────────────────────

/// Allowed unit suffixes for NUMERIC-WITH-UNIT fields.
const _kAllowedUnits = {'cm', 'ft', 'in', 'm', 'kg', 'lbs', 'lb'};

/// Maximum alpha characters allowed in a NUMERIC-WITH-UNIT field.
const int _kMaxAlphaInNumeric = 3;

// ─────────────────────────────────────────────────────────────────────────────
//  CONTACT-SHARING DETECTOR
// ─────────────────────────────────────────────────────────────────────────────

String? _detectContactSharing(String text) {
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();

  // Count digits ignoring separators
  final stripped = text.replaceAll(RegExp(r'[\s\-\.\,\/\(\)\+]'), '');
  final totalDigits = RegExp(r'\d').allMatches(text).length;

  // 7+ consecutive digits in stripped text = likely a phone number
  if (RegExp(r'\d{7,}').hasMatch(stripped)) {
    return '⚠ Sharing phone numbers is not allowed in this field.';
  }

  // 10+ total digits anywhere = likely a phone number (even spaced out)
  if (totalDigits >= 10) {
    return '⚠ Phone numbers or numeric sequences cannot be shared here.';
  }

  // Trigger phrases that precede contact sharing
  const triggerPhrases = [
    'call me', 'whatsapp', 'whats app', 'contact me', 'my number',
    'my no', 'reach me', 'ping me', 'dm me', 'message me', 'text me',
    'telegram', 'watsapp', 'wattsapp', 'mob:', 'ph:', 'ph.',
    'mobile:', 'mobile.', 'contact:', 'no:', '@gmail', '@yahoo',
    '@hotmail', '@outlook', 'gmail.com', 'yahoo.com', 'hotmail.com',
    'instagram', 'facebook', 'snapchat', 'twitter',
  ];

  for (final phrase in triggerPhrases) {
    if (lower.contains(phrase)) {
      return '⚠ Sharing contact details is not permitted in this field.';
    }
  }

  // Unicode digit look-alikes (circled numbers, fullwidth digits)
  if (RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩０-９]').hasMatch(text)) {
    return '⚠ Contact numbers in alternate formats are not allowed.';
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ALPHA-ONLY GUARD  ──  for name, city, description, about-me fields
// ─────────────────────────────────────────────────────────────────────────────

class AlphaOnlyGuard extends TextInputFormatter {
  final void Function(String reason)? onBlocked;
  const AlphaOnlyGuard({this.onBlocked});

  static const _numberWords = {
    // English number words
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
    'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
    'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
    'hundred', 'thousand',
    // Telugu number words (spelled in English)
    'okati', 'rendu', 'moodu', 'naalugu', 'aidu', 'aaru', 'eedu', 'edhu',
    'enimidhi', 'tommidhi', 'padi', 'padakonda', 'panendu', 'padi_moodu',
    'padi_naallugu', 'padi_aidhu', 'padi_aaru', 'padi_edhu', 'padi_enimidhi',
    'iravai', 'muppai', 'nalabai', 'vandha', 'veyla',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Block any digit character
    if (RegExp(r'\d').hasMatch(text)) {
      onBlocked?.call('⚠ Numbers are not allowed in this field.');
      return oldValue;
    }

    // Block standalone number words
    final lower = text.toLowerCase();
    for (final word in _numberWords) {
      if (RegExp('\\b$word\\b').hasMatch(lower)) {
        onBlocked?.call(
          '⚠ Number words like "$word" are not allowed in this field.',
        );
        return oldValue;
      }
    }

    // Block contact-sharing patterns
    final warning = _detectContactSharing(text);
    if (warning != null) {
      onBlocked?.call(warning);
      return oldValue;
    }

    return newValue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NUMERIC-WITH-UNIT GUARD  ──  for height / weight / measurement fields
// ─────────────────────────────────────────────────────────────────────────────

class NumericWithUnitGuard extends TextInputFormatter {
  final void Function(String reason)? onBlocked;
  const NumericWithUnitGuard({this.onBlocked});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Check contact-sharing first
    final contactWarning = _detectContactSharing(text);
    if (contactWarning != null) {
      onBlocked?.call(contactWarning);
      return oldValue;
    }

    // Extract only the alpha characters
    final alphaChars = text.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    final alphaLower = alphaChars.toLowerCase();

    if (alphaChars.isEmpty) return newValue; // Pure numeric — always fine

    // Allow if within max alpha length AND is a prefix of a known unit
    if (alphaChars.length <= _kMaxAlphaInNumeric) {
      final isUnitPrefix =
          _kAllowedUnits.any((u) => u.startsWith(alphaLower)) ||
          _kAllowedUnits.contains(alphaLower);
      if (isUnitPrefix) return newValue;
    }

    // Too many alpha chars or not a recognised unit
    onBlocked?.call(
      '⚠ Only numeric values are accepted here (with unit like cm, ft, kg).',
    );
    return oldValue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CONTACT-SHARING GUARD  ──  lightweight guard for free-text fields
// ─────────────────────────────────────────────────────────────────────────────

class ContactSharingGuard extends TextInputFormatter {
  final void Function(String reason)? onBlocked;
  const ContactSharingGuard({this.onBlocked});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final warning = _detectContactSharing(newValue.text);
    if (warning != null) {
      onBlocked?.call(warning);
      return oldValue;
    }
    return newValue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NOTE FIELD GUARD  ──  for short description / note fields
//
//  Rules:
//    • Allows digits BUT limits any consecutive digit run to 3 (e.g. "30 yrs",
//      "1st", "100" are fine; "9876" or more in a row are blocked)
//    • Blocks all contact-sharing patterns (phone, email, social, trigger words)
//    • Blocks Unicode digit look-alikes
// ─────────────────────────────────────────────────────────────────────────────

class NoteFieldGuard extends TextInputFormatter {
  final void Function(String reason)? onBlocked;
  const NoteFieldGuard({this.onBlocked});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Block 4+ consecutive digits anywhere in the text
    if (RegExp(r'\d{4,}').hasMatch(text)) {
      onBlocked?.call('⚠ Only up to 3 digits in a row are allowed (no phone numbers).');
      return oldValue;
    }

    // Block contact-sharing patterns (phone, email, social media, etc.)
    final warning = _detectContactSharing(text);
    if (warning != null) {
      onBlocked?.call(warning);
      return oldValue;
    }

    return newValue;
  }
}




// ─────────────────────────────────────────────────────────────────────────────
//  PARENT NAME GUARD  ──  for Father's Name / Mother's Name fields
//
//  Rules:
//    • No digit characters (0–9) — hard blocked on every keystroke
//    • No number words ("one", "two", … "thousand") — blocked as whole words
//    • No contact-sharing patterns (phone, email, social media triggers)
//    • Maximum 3 space-separated words  (e.g. "Sri Ram Sharma" is fine;
//      a fourth word is silently dropped)
//    • No individual Unicode digit look-alikes
// ─────────────────────────────────────────────────────────────────────────────

class ParentNameGuard extends TextInputFormatter {
  final void Function(String reason)? onBlocked;
  const ParentNameGuard({this.onBlocked});

  static const _numberWords = {
    // English number words
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
    'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
    'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
    'hundred', 'thousand',
    // Telugu number words (spelled in English)
    'okati', 'rendu', 'moodu', 'naalugu', 'aidu', 'aaru', 'eedu', 'edhu',
    'enimidhi', 'tommidhi', 'padi', 'padakonda', 'panendu', 'padi_moodu',
    'padi_naallugu', 'padi_aidhu', 'padi_aaru', 'padi_edhu', 'padi_enimidhi',
    'iravai', 'muppai', 'nalabai', 'vandha', 'veyla',
  };

  static const int _maxWords = 3;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Block any digit character
    if (RegExp(r'\d').hasMatch(text)) {
      onBlocked?.call('⚠ Numbers are not allowed in parent name fields.');
      return oldValue;
    }

    // Block Unicode digit look-alikes
    if (RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩０-９]').hasMatch(text)) {
      onBlocked?.call('⚠ Numbers are not allowed in parent name fields.');
      return oldValue;
    }

    // Block standalone number words
    final lower = text.toLowerCase();
    for (final word in _numberWords) {
      if (RegExp('\\b$word\\b').hasMatch(lower)) {
        onBlocked?.call(
          '⚠ Number words like "$word" are not allowed in parent name fields.',
        );
        return oldValue;
      }
    }

    // Block contact-sharing patterns
    final warning = _detectContactSharing(text);
    if (warning != null) {
      onBlocked?.call(warning);
      return oldValue;
    }

    // Enforce maximum 3 words: count non-empty tokens split by whitespace
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > _maxWords) {
      onBlocked?.call('⚠ Parent name may have at most $_maxWords words.');
      return oldValue;
    }

    return newValue;
  }
}

/// Drop-in replacement — delegates to [AlphaOnlyGuard] so every existing
/// call site automatically gets the full protection suite without changes.
class PhoneNumberGuard extends TextInputFormatter {
  final void Function(String reason)? onPhoneDetected;

  PhoneNumberGuard({this.onPhoneDetected});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      AlphaOnlyGuard(onBlocked: onPhoneDetected)
          .formatEditUpdate(oldValue, newValue);
}

// ─────────────────────────────────────────────────────────────────────────────
//  VALIDATOR HELPERS  (for TextFormField.validator callbacks)
// ─────────────────────────────────────────────────────────────────────────────

String? validateNoNumbers(String? value) {
  if (value == null || value.isEmpty) return null;
  if (RegExp(r'\d').hasMatch(value)) return 'Numbers are not allowed in this field.';

  const numberWords = {
    // English number words
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
    'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
    'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
    'hundred', 'thousand',
    // Telugu number words (spelled in English)
    'okati', 'rendu', 'moodu', 'naalugu', 'aidu', 'aaru', 'eedu', 'edhu',
    'enimidhi', 'tommidhi', 'padi', 'padakonda', 'panendu', 'padi_moodu',
    'padi_naallugu', 'padi_aidhu', 'padi_aaru', 'padi_edhu', 'padi_enimidhi',
    'iravai', 'muppai', 'nalabai', 'vandha', 'veyla',
  };

  final lower = value.toLowerCase();
  for (final word in numberWords) {
    if (RegExp('\\b$word\\b').hasMatch(lower)) {
      return 'Number words like "$word" are not allowed in this field.';
    }
  }

  return _detectContactSharing(value);
}

String? validateNoContactSharing(String? value) {
  if (value == null || value.isEmpty) return null;
  return _detectContactSharing(value);
}

// Backward-compatible alias
String? validateNoPhoneNumber(String? value) => validateNoNumbers(value);
