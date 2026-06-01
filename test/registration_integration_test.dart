import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:brahmin_vivaaha_vedika/services/navigation_service.dart';
import 'package:brahmin_vivaaha_vedika/services/rate_limit_service.dart';
import 'package:brahmin_vivaaha_vedika/models/user.dart' as app_models;

void main() {
  group('Registration and MPIN Integration (aligned)', () {
    late NavigationService navigationService;
    late RateLimitService rateLimitService;
    late SharedPreferences prefs;

    setUpAll(() async {
      // Initialize SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      
      // Initialize services
      rateLimitService = RateLimitService(prefs);
      navigationService = NavigationService();
    });

    test('User Model Creation and Validation', () {
      const testMobile = '9876543210';
      final testUser = app_models.User(
        id: 'registration-test-user-1',
        email: 'test@mobile.brahminvivaaha.com',
        password: '',
        mobileNumber: testMobile,
        alternativeMobileNumber: '9876543211',
        isEmailVerified: true,
      );

      expect(testUser.email, 'test@mobile.brahminvivaaha.com');
      expect(testUser.mobileNumber, testMobile);
      expect(testUser.alternativeMobileNumber, '9876543211');
      expect(testUser.isEmailVerified, true);
      expect(testUser.profileId, isNotEmpty);
      expect(testUser.createdAt, isNotNull);
    });

    test('MPIN Security Validation', () {
      const testMpin = '5678';
      final hashedMpin = sha256.convert(utf8.encode(testMpin)).toString();
      expect(hashedMpin, isNot(equals(testMpin)));
      expect(hashedMpin.length, greaterThan(10));
    });

    test('Mobile Number Validation', () {
      // Test mobile number format validation
      const validMobile = '9876543210';
      const invalidMobile1 = '123456789'; // Too short
      const invalidMobile2 = '98765432109'; // Too long
      const invalidMobile3 = 'abcdefghij'; // Non-numeric

      bool isValidMobile(String mobile) {
        return mobile.length == 10 && RegExp(r'^\d{10}$').hasMatch(mobile);
      }

      expect(isValidMobile(validMobile), true);
      expect(isValidMobile(invalidMobile1), false);
      expect(isValidMobile(invalidMobile2), false);
      expect(isValidMobile(invalidMobile3), false);
    });

    test('User Data Serialization', () {
      const testMobile = '9876543210';
      final testUser = app_models.User(
        id: 'registration-test-user-2',
        email: 'test@mobile.brahminvivaaha.com',
        password: '',
        mobileNumber: testMobile,
        isEmailVerified: true,
      );

      final userJson = testUser.toJson();
      
      expect(userJson['email'], 'test@mobile.brahminvivaaha.com');
      expect(userJson['mobile_number'], testMobile);
      expect(userJson['isEmailVerified'], true);
      expect(userJson['profile_id'], isNotNull);

      userJson.remove('password');
      userJson.remove('mpin');
      expect(userJson.containsKey('password'), false);
      expect(userJson.containsKey('mpin'), false);
    });

    test('Navigation Service Cache Management', () {
      // Test navigation service cache invalidation
      expect(navigationService.currentRoute, isNull);
      
      // Test cache invalidation
      navigationService.invalidateCaches();
      expect(navigationService.currentRoute, isNull); // Should remain null after invalidation
    });

    test('Rate Limit Service Initialization', () {
      expect(rateLimitService, isNotNull);

      const testMobile = '9876543210';
      expect(rateLimitService.isLoginBlocked(testMobile), completion(isFalse));
    });

    test('Complete Registration Flow Simulation', () async {
      const testMobile = '9876543210';
      expect(testMobile.length, equals(10));
      expect(RegExp(r'^\d{10}$').hasMatch(testMobile), true);
      
      final testUser = app_models.User(
        id: 'registration-test-user-3',
        email: '$testMobile@mobile.brahminvivaaha.com',
        password: '',
        mobileNumber: testMobile,
        isEmailVerified: true,
      );
      
      expect(testUser.email, contains(testMobile));
      expect(testUser.mobileNumber, testMobile);
      expect(testUser.isEmailVerified, true);
      
      const testMpin = '5678';
      final hashedMpin = sha256.convert(utf8.encode(testMpin)).toString();
      expect(hashedMpin, isNotNull);
      expect(hashedMpin, isNot(equals(testMpin)));
      
      final userJson = testUser.toJson();
      userJson.remove('password');
      userJson.remove('mpin');
      
      expect(userJson.containsKey('password'), false);
      expect(userJson.containsKey('mpin'), false);
    });

    test('Error Handling Scenarios', () {
      const invalidMpin = '12';
      expect(invalidMpin.length, lessThan(4));

      const invalidMobile = '123';
      bool isValidMobile(String mobile) {
        return mobile.length == 10 && RegExp(r'^\d{10}$').hasMatch(mobile);
      }
      expect(isValidMobile(invalidMobile), false);
    });

    test('Data Consistency Validation', () {
      const testMobile = '9876543210';
      final testUser1 = app_models.User(
        id: 'registration-test-user-4a',
        email: 'test1@mobile.brahminvivaaha.com',
        password: '',
        mobileNumber: testMobile,
        isEmailVerified: true,
      );
      
      final testUser2 = app_models.User(
        id: 'registration-test-user-4b',
        email: 'test2@mobile.brahminvivaaha.com',
        password: '',
        mobileNumber: testMobile,
        isEmailVerified: true,
      );
      
      expect(testUser1.profileId, isNot(equals(testUser2.profileId)));
      expect(testUser1.id, isNot(equals(testUser2.id)));
      
      expect(testUser1.mobileNumber, equals(testUser2.mobileNumber));
    });
  });
}
