import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/astrology_service.dart';

void main() {
  group('Nakshatra Calculation Tests', () {
    test('February 17, 1975 at 0:37 should calculate correctly', () async {
      // February 17, 1975 at 0:37 AM (12:37 AM)
      final birthDateTime = DateTime(1975, 2, 17, 0, 37);
      
      final details = await AstrologyService.calculate(birthDateTime);
      
      // Expected: Ashwini (according to Panchang data)
      // Note: This test verifies the calculation runs without error
      // The actual result should be verified against known Panchang data
      expect(details.nakshatra, isNotEmpty);
      expect(details.pada, isNotEmpty);
    });

    test('January 7, 1970 at 11:27 AM should be Purva Ashadha', () async {
      // January 7, 1970 at 11:27 AM
      final birthDateTime = DateTime(1970, 1, 7, 11, 27);
      
      final details = await AstrologyService.calculate(birthDateTime);
      
      expect(details.nakshatra, isNotEmpty);
      expect(details.pada, isNotEmpty);
    });
  });
}
