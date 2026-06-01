import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/pin_code_location_resolver.dart';
import 'package:brahmin_vivaaha_vedika/services/pincode_service.dart';

void main() {
  group('PinCodeLocationResolver', () {
    test('copies post office name into city when area is set', () {
      const office = PinCodePostOffice(
        name: 'Benz Circle',
        district: 'Krishna',
        state: 'Andhra Pradesh',
        region: 'Vijayawada',
        division: 'Vijayawada',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.state, 'Andhra Pradesh');
      expect(resolved.city, 'Benz Circle');
      expect(resolved.area, 'Benz Circle');
      expect(resolved.cityForProfile, 'Benz Circle');
      expect(resolved.district, 'Krishna');
    });

    test('prefers post office name when it matches city list', () {
      const office = PinCodePostOffice(
        name: 'Guntur',
        district: 'Guntur',
        state: 'Andhra Pradesh',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.city, 'Guntur');
    });

    test('matches state from Circle when State is empty', () {
      const office = PinCodePostOffice(
        name: 'Main SO',
        district: 'Krishna',
        state: '',
        circle: 'Andhra Pradesh',
        region: 'Vijayawada',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.state, 'Andhra Pradesh');
      expect(resolved.apiState, 'Andhra Pradesh');
      expect(resolved.city, 'Main SO');
      expect(resolved.cityForProfile, 'Main SO');
    });

    test('maps Orissa alias from API to Odisha', () {
      const office = PinCodePostOffice(
        name: 'Cuttack HO',
        district: 'Cuttack',
        state: 'Orissa',
      );
      expect(PinCodeLocationResolver.resolve(office).state, 'Odisha');
    });

    test('falls back to area name when district is not a known city', () {
      const office = PinCodePostOffice(
        name: 'Governorpet',
        district: 'Krishna',
        state: 'Andhra Pradesh',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.city, 'Governorpet');
      expect(resolved.area, 'Governorpet');
      expect(resolved.cityForProfile, 'Governorpet');
    });

    test('area wins over suggestedCity for profile city', () {
      const office = PinCodePostOffice(
        name: 'Benz Circle',
        district: 'Krishna',
        state: 'Andhra Pradesh',
        suggestedCity: 'Vijayawada',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.city, 'Benz Circle');
      expect(resolved.cityForProfile, 'Benz Circle');
    });

    test('uses suggestedCity when post office name is empty', () {
      const office = PinCodePostOffice(
        name: '',
        district: 'Krishna',
        state: 'Andhra Pradesh',
        suggestedCity: 'Vijayawada',
        region: 'Vijayawada',
      );
      final resolved = PinCodeLocationResolver.resolve(office);
      expect(resolved.city, 'Vijayawada');
      expect(resolved.cityForProfile, 'Vijayawada');
    });
  });

  group('PinCodeLookupResult.uniqueAreaNames', () {
    test('dedupes duplicate post office names', () {
      const result = PinCodeLookupResult(
        postOffices: [
          PinCodePostOffice(
            name: 'Benz Circle',
            district: 'Krishna',
            state: 'Andhra Pradesh',
          ),
          PinCodePostOffice(
            name: 'Benz Circle',
            district: 'Krishna',
            state: 'Andhra Pradesh',
          ),
          PinCodePostOffice(
            name: 'Governorpet',
            district: 'Krishna',
            state: 'Andhra Pradesh',
          ),
        ],
      );
      expect(result.uniqueAreaNames, ['Benz Circle', 'Governorpet']);
      expect(result.hasMultipleAreas, isTrue);
    });
  });
}
