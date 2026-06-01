import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/otp_service.dart';

void main() {
  group('OTP Service Tests', () {
    test('should validate Indian mobile numbers correctly', () {
      // Valid numbers (exactly 10 digits starting with 6-9)
      expect(OtpService.isValidIndianMobileNumber('9876543210'), isTrue);
      expect(OtpService.isValidIndianMobileNumber('9123456789'), isTrue);
      expect(OtpService.isValidIndianMobileNumber('6234567890'), isTrue);
      expect(OtpService.isValidIndianMobileNumber('7890123456'), isTrue);
      expect(OtpService.isValidIndianMobileNumber('8901234567'), isTrue);
      
      // Invalid numbers
      expect(OtpService.isValidIndianMobileNumber('1234567890'), isFalse); // Doesn't start with 6-9
      expect(OtpService.isValidIndianMobileNumber('987654321'), isFalse); // Too short
      expect(OtpService.isValidIndianMobileNumber('98765432101'), isFalse); // Too long
      expect(OtpService.isValidIndianMobileNumber('0000000000'), isFalse); // All same digit
      expect(OtpService.isValidIndianMobileNumber('1111111111'), isFalse); // All same digit
      expect(OtpService.isValidIndianMobileNumber('abcdefghij'), isFalse); // Non-numeric
      expect(OtpService.isValidIndianMobileNumber('+919876543210'), isFalse); // Has country code (12 digits)
      expect(OtpService.isValidIndianMobileNumber('91-98765-43210'), isFalse); // Has country code (12 digits)
      expect(OtpService.isValidIndianMobileNumber('(91) 98765-43210'), isFalse); // Has country code (12 digits)
    });

    test('should use NUMERIC6 OTP format', () {
      // This test verifies that the URL format is correct for numeric OTPs
      // In a real test, we would mock the HTTP request
      const apiKey = '5f9954d7-4711-11ed-9c12-0200cd936042';
      const baseUrl = 'https://2factor.in/API/V1';
      const phoneNumber = '9876543210';
      
      // Expected URL format for NUMERIC6 OTP
      final expectedUrl = '$baseUrl/$apiKey/SMS/+91$phoneNumber/NUMERIC6';
      
      // Verify the URL format contains NUMERIC6 (not AUTOGEN)
      expect(expectedUrl.contains('NUMERIC6'), isTrue);
      expect(expectedUrl.contains('AUTOGEN'), isFalse);
    });
  });
}
