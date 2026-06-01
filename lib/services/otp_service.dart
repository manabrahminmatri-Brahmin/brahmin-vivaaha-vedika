import 'package:flutter/foundation.dart';

/// OTP Service - Utility class for OTP validation and mobile number formatting
/// Provides validation methods used throughout the app
class OtpService {
  OtpService._(); // Private constructor to prevent instantiation

  /// Validate Indian mobile number (10 digits, starts with 6-9, not all same digits)
  static bool isValidIndianMobileNumber(String mobile) {
    if (mobile.length != 10) return false;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) return false;
    if (RegExp(r'^(\d)\1{9}$').hasMatch(mobile)) return false; // All same digits
    return true;
  }

  /// Clean and format mobile number to standard 10-digit format.
  /// Handles all input variants:
  ///   +919876543210  →  9876543210
  ///   919876543210   →  9876543210
  ///   9876543210     →  9876543210
  ///   +91 98765 43210 →  9876543210
  static String cleanMobileNumber(String mobile) {
    // Step 1: strip whitespace, dashes, and parentheses
    var clean = mobile.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Step 2: strip +91 prefix BEFORE the bare-91 check so that
    // "+919876543210" is handled by this branch (13 chars) and not
    // mis-handled by the bare-91 branch below.
    if (clean.startsWith('+91')) {
      clean = clean.substring(3);
    }

    // Step 3: strip bare 91 country code (12-digit number, e.g. "919876543210")
    if (clean.length == 12 && clean.startsWith('91')) {
      clean = clean.substring(2);
    }

    return clean.trim();
  }

  /// Format mobile number with +91 prefix for API calls
  static String formatMobileWithCountryCode(String mobile) {
    final clean = cleanMobileNumber(mobile);
    return '+91$clean';
  }

  /// Validate OTP format (exactly 6 digits)
  static bool isValidOtpFormat(String otp) {
    return RegExp(r'^\d{6}$').hasMatch(otp);
  }

  /// Extract mobile number from various formats.
  /// Strips all non-digit characters then removes a leading 91 country
  /// code if the result is 12 digits (covers both "91..." and "+91...").
  static String extractMobileNumber(String input) {
    // Remove all non-digit characters first
    var digits = input.replaceAll(RegExp(r'\D'), '');

    // After stripping non-digits, +919876543210 and 919876543210 both
    // become the same 12-digit string "919876543210".
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }

    return digits;
  }

  /// Check if mobile number format is common test/invalid pattern
  static bool isTestMobileNumber(String mobile) {
    final clean = cleanMobileNumber(mobile);

    // Common test patterns
    final testPatterns = [
      '1234567890',
      '9876543210',
      '9999999999',
      '8888888888',
      '7777777777',
      '6666666666',
      '5555555555',
      '0000000000',
      '1111111111',
    ];

    return testPatterns.contains(clean);
  }

  /// Validate mobile number for registration (more strict)
  static bool isValidMobileForRegistration(String mobile) {
    if (!isValidIndianMobileNumber(mobile)) return false;
    if (isTestMobileNumber(mobile)) {
      debugPrint('🚫 Test mobile number detected: $mobile');
      return false;
    }
    return true;
  }

  /// Get mobile number type (prepaid/postpaid detection based on patterns)
  static String getMobileNumberType(String mobile) {
    final clean = cleanMobileNumber(mobile);

    // Simple heuristic based on starting digits (not 100% accurate)
    final firstDigit = clean.substring(0, 1);
    switch (firstDigit) {
      case '9':
      case '8':
        return 'likely_postpaid';
      case '7':
      case '6':
        return 'likely_prepaid';
      default:
        return 'unknown';
    }
  }

  /// Mask mobile number for display (show only last 4 digits)
  static String maskMobileNumber(String mobile) {
    final clean = cleanMobileNumber(mobile);
    if (clean.length != 10) return mobile;

    return 'XXXXXX${clean.substring(6)}';
  }

  /// Format mobile number for display with proper formatting
  static String formatMobileForDisplay(String mobile) {
    final clean = cleanMobileNumber(mobile);
    if (clean.length != 10) return mobile;

    return '+91 $clean'; // Simple format: +91 9876543210
  }
}
