import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OtpService', () {
    test('should validate phone numbers correctly', () {
      expect(OtpService.validatePhoneNumber('9876543210'), true);
      expect(OtpService.validatePhoneNumber('987654321'), false);
      expect(OtpService.validatePhoneNumber('98765432101'), false);
      expect(OtpService.validatePhoneNumber('abcdefghij'), false);
    });

    test('should clean phone numbers', () {
      expect(OtpService.cleanPhoneNumber('+91 98765 43210'), '9876543210');
      expect(OtpService.cleanPhoneNumber('987-654-3210'), '9876543210');
      expect(OtpService.cleanPhoneNumber('9876543210'), '9876543210');
    });

    test('should validate OTP format', () {
      expect(OtpService.isValidOtpFormat('123456'), true);
      expect(OtpService.isValidOtpFormat('12345'), false);
      expect(OtpService.isValidOtpFormat('1234567'), false);
      expect(OtpService.isValidOtpFormat('abc123'), false);
    });

    test('should format phone for API', () {
      expect(OtpService.formatPhoneForApi('9876543210'), '+919876543210');
      expect(OtpService.formatPhoneForApi('+919876543210'), '+919876543210');
    });

    test('should mask phone number', () {
      final masked = OtpService.maskPhone('9876543210');
      expect(masked, contains('****'));
      expect(masked.length, 10);
    });
  });

  group('OtpRateLimitService', () {
    test('should track request counts', () {
      final service = OtpRateLimitService();
      const phone = '9876543210';
      
      expect(service.getRemainingRequests(phone), 5);
      
      service.recordRequest(phone);
      expect(service.getRemainingRequests(phone), 4);
      
      service.recordRequest(phone);
      service.recordRequest(phone);
      expect(service.getRemainingRequests(phone), 2);
    });

    test('should check if limit exceeded', () {
      final service = OtpRateLimitService();
      const phone = '9876543210';
      
      expect(service.isLimitExceeded(phone), false);
      
      // Use up all requests
      for (var i = 0; i < 5; i++) {
        service.recordRequest(phone);
      }
      
      expect(service.isLimitExceeded(phone), true);
    });

    test('should reset after window', () {
      final service = OtpRateLimitService();
      const phone = '9876543210';
      
      service.recordRequest(phone);
      expect(service.getRemainingRequests(phone), 4);
      
      // Simulate time passing (reset window)
      service.reset(phone);
      expect(service.getRemainingRequests(phone), 5);
    });

    test('should track multiple phones independently', () {
      final service = OtpRateLimitService();
      
      service.recordRequest('9876543210');
      service.recordRequest('9876543211');
      
      expect(service.getRemainingRequests('9876543210'), 4);
      expect(service.getRemainingRequests('9876543211'), 4);
    });
  });

  group('RateLimitService', () {
    test('should track action limits', () {
      final service = RateLimitService();
      const action = 'login';
      const identifier = 'user-123';
      
      expect(service.canPerformAction(action, identifier), true);
      
      service.recordAction(action, identifier);
      expect(service.getAttemptCount(action, identifier), 1);
    });

    test('should block after max attempts', () {
      final service = RateLimitService();
      const action = 'login';
      const identifier = 'user-123';
      
      // Exceed limit
      for (var i = 0; i < 6; i++) {
        service.recordAction(action, identifier);
      }
      
      expect(service.canPerformAction(action, identifier), false);
    });

    test('should calculate remaining time', () {
      final service = RateLimitService();
      const action = 'login';
      const identifier = 'user-123';
      
      // Block the action
      for (var i = 0; i < 6; i++) {
        service.recordAction(action, identifier);
      }
      
      final remainingTime = service.getRemainingTime(action, identifier);
      expect(remainingTime, greaterThan(Duration.zero));
    });
  });
}

// Mock implementations
class OtpService {
  static bool validatePhoneNumber(String phone) {
    final cleaned = cleanPhoneNumber(phone);
    return cleaned.length == 10 && RegExp(r'^\d{10}$').hasMatch(cleaned);
  }

  static String cleanPhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91'), '');
  }

  static bool isValidOtpFormat(String otp) {
    return otp.length == 6 && RegExp(r'^\d{6}$').hasMatch(otp);
  }

  static String formatPhoneForApi(String phone) {
    final cleaned = cleanPhoneNumber(phone);
    return '+91$cleaned';
  }

  static String maskPhone(String phone) {
    if (phone.length < 4) return phone;
    return phone.substring(0, phone.length - 4) + '****';
  }
}

class OtpRateLimitService {
  final Map<String, int> _requestCounts = {};
  static const int _maxRequests = 5;

  void recordRequest(String phone) {
    final normalized = _normalizePhone(phone);
    _requestCounts[normalized] = (_requestCounts[normalized] ?? 0) + 1;
  }

  int getRemainingRequests(String phone) {
    final normalized = _normalizePhone(phone);
    final used = _requestCounts[normalized] ?? 0;
    return _maxRequests - used;
  }

  bool isLimitExceeded(String phone) {
    return getRemainingRequests(phone) <= 0;
  }

  void reset(String phone) {
    _requestCounts.remove(_normalizePhone(phone));
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '');
  }
}

class RateLimitService {
  final Map<String, Map<String, int>> _attempts = {};
  final Map<String, Map<String, DateTime>> _lastAttempt = {};
  static const int _maxAttempts = 5;
  static const Duration _window = Duration(minutes: 15);

  bool canPerformAction(String action, String identifier) {
    final key = '$action:$identifier';
    final attempts = _attempts[action]?[identifier] ?? 0;
    
    if (attempts >= _maxAttempts) {
      final lastAttempt = _lastAttempt[action]?[identifier];
      if (lastAttempt != null) {
        final elapsed = DateTime.now().difference(lastAttempt);
        if (elapsed < _window) {
          return false;
        }
      }
    }
    return true;
  }

  void recordAction(String action, String identifier) {
    _attempts.putIfAbsent(action, () => {});
    _attempts[action]![identifier] = (_attempts[action]![identifier] ?? 0) + 1;
    
    _lastAttempt.putIfAbsent(action, () => {});
    _lastAttempt[action]![identifier] = DateTime.now();
  }

  int getAttemptCount(String action, String identifier) {
    return _attempts[action]?[identifier] ?? 0;
  }

  Duration getRemainingTime(String action, String identifier) {
    final lastAttempt = _lastAttempt[action]?[identifier];
    if (lastAttempt == null) return Duration.zero;
    
    final elapsed = DateTime.now().difference(lastAttempt);
    return _window - elapsed;
  }
}
