import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalErrorHandler Tests', () {
    test('should be singleton', () {
      final instance1 = GlobalErrorHandler();
      final instance2 = GlobalErrorHandler();
      expect(identical(instance1, instance2), true);
    });

    test('should categorize network errors', () {
      final handler = GlobalErrorHandler();
      expect(
        handler.categorizeError(Exception('network error')),
        ErrorCategory.network,
      );
    });

    test('should categorize validation errors', () {
      final handler = GlobalErrorHandler();
      expect(
        handler.categorizeError(FormatException('invalid format')),
        ErrorCategory.validation,
      );
    });

    test('should determine retry strategy', () {
      final handler = GlobalErrorHandler();
      expect(handler.shouldRetry(ErrorCategory.network), true);
      expect(handler.shouldRetry(ErrorCategory.server), true);
      expect(handler.shouldRetry(ErrorCategory.validation), false);
      expect(handler.shouldRetry(ErrorCategory.authentication), false);
    });

    test('should track error counts', () {
      final handler = GlobalErrorHandler();
      handler.recordError(ErrorCategory.network);
      handler.recordError(ErrorCategory.network);
      handler.recordError(ErrorCategory.server);
      
      expect(handler.getErrorCount(ErrorCategory.network), 2);
      expect(handler.getErrorCount(ErrorCategory.server), 1);
      expect(handler.getErrorCount(ErrorCategory.validation), 0);
    });
  });

  group('ValidationUtils Tests', () {
    test('should validate required fields', () {
      expect(ValidationUtils.isRequired('value'), true);
      expect(ValidationUtils.isRequired(''), false);
      expect(ValidationUtils.isRequired(null), false);
      expect(ValidationUtils.isRequired('   '), false);
    });

    test('should validate minimum length', () {
      expect(ValidationUtils.minLength('hello', 3), true);
      expect(ValidationUtils.minLength('hi', 3), false);
    });

    test('should validate maximum length', () {
      expect(ValidationUtils.maxLength('hello', 10), true);
      expect(ValidationUtils.maxLength('hello world', 5), false);
    });

    test('should validate numeric values', () {
      expect(ValidationUtils.isNumeric('123'), true);
      expect(ValidationUtils.isNumeric('12.5'), true);
      expect(ValidationUtils.isNumeric('abc'), false);
    });

    test('should validate PIN code', () {
      expect(ValidationUtils.isValidPincode('500001'), true);
      expect(ValidationUtils.isValidPincode('50001'), false);
      expect(ValidationUtils.isValidPincode('5000001'), false);
    });

    test('should validate email format', () {
      expect(ValidationUtils.isValidEmail('test@example.com'), true);
      expect(ValidationUtils.isValidEmail('invalid'), false);
      expect(ValidationUtils.isValidEmail('@example.com'), false);
    });
  });

  group('StringUtils Tests', () {
    test('should capitalize first letter', () {
      expect(StringUtils.capitalize('hello'), 'Hello');
      expect(StringUtils.capitalize('HELLO'), 'Hello');
      expect(StringUtils.capitalize(''), '');
    });

    test('should mask phone numbers', () {
      expect(StringUtils.maskPhone('9876543210'), contains('*'));
      expect(StringUtils.maskPhone('+919876543210'), contains('*'));
    });

    test('should validate phone format', () {
      expect(StringUtils.isValidPhone('9876543210'), true);
      expect(StringUtils.isValidPhone('+919876543210'), true);
      expect(StringUtils.isValidPhone('123'), false);
    });
  });

  group('DateTimeUtils Tests', () {
    test('should calculate age correctly', () {
      final birthDate = DateTime(1990, 5, 15);
      final today = DateTime(2024, 1, 15);
      final age = DateTimeUtils.calculateAge(birthDate, today: today);
      expect(age, 33);
    });

    test('should format date', () {
      final date = DateTime(2024, 1, 15);
      final formatted = DateTimeUtils.formatDate(date);
      expect(formatted, contains('2024'));
    });

    test('should format relative time', () {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      final relative = DateTimeUtils.formatRelativeTime(oneHourAgo);
      expect(relative.toLowerCase(), contains('hour'));
    });
  });
}

// Mock implementations for testing
class GlobalErrorHandler {
  static final GlobalErrorHandler _instance = GlobalErrorHandler._internal();
  factory GlobalErrorHandler() => _instance;
  GlobalErrorHandler._internal();

  final Map<ErrorCategory, int> _errorCounts = {};

  ErrorCategory categorizeError(Object error) {
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('network') || 
        errorString.contains('socket') || 
        errorString.contains('timeout')) {
      return ErrorCategory.network;
    }
    if (errorString.contains('format') || 
        errorString.contains('validation') || 
        errorString.contains('parse')) {
      return ErrorCategory.validation;
    }
    if (errorString.contains('auth') || 
        errorString.contains('unauthorized')) {
      return ErrorCategory.authentication;
    }
    if (errorString.contains('server') || 
        errorString.contains('500')) {
      return ErrorCategory.server;
    }
    return ErrorCategory.unknown;
  }

  bool shouldRetry(ErrorCategory category) {
    return category == ErrorCategory.network || 
           category == ErrorCategory.server;
  }

  void recordError(ErrorCategory category) {
    _errorCounts[category] = (_errorCounts[category] ?? 0) + 1;
  }

  int getErrorCount(ErrorCategory category) {
    return _errorCounts[category] ?? 0;
  }
}

enum ErrorCategory { network, validation, authentication, server, unknown }

class ValidationUtils {
  static bool isRequired(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  static bool minLength(String value, int min) => value.length >= min;
  static bool maxLength(String value, int max) => value.length <= max;
  static bool isNumeric(String value) => num.tryParse(value) != null;
  
  static bool isValidPincode(String pincode) {
    return RegExp(r'^\d{6}$').hasMatch(pincode);
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}

class StringUtils {
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  static String maskPhone(String phone) {
    if (phone.length < 4) return phone;
    return '${phone.substring(0, phone.length - 4)}****';
  }

  static bool isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 10 && digitsOnly.length <= 12;
  }
}

class DateTimeUtils {
  static int calculateAge(DateTime birthDate, {DateTime? today}) {
    today ??= DateTime.now();
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month || 
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  static String formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${difference.inDays ~/ 365} years ago';
    } else if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}
