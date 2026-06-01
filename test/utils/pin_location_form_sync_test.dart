import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/data/reference_data.dart';
import 'package:brahmin_vivaaha_vedika/services/pin_code_location_resolver.dart';
import 'package:brahmin_vivaaha_vedika/services/pincode_service.dart';
import 'package:brahmin_vivaaha_vedika/utils/pin_location_form_sync.dart';

void main() {
  group('PinLocationSlot.applyResolved', () {
    test('canonicalizes state and copies area into city', () {
      final slot = PinLocationSlot();
      slot.applyResolved(
        const PinCodeResolvedLocation(
          country: 'India',
          state: 'Andhra Pradesh',
          apiState: 'Andhra Pradesh',
          city: 'Vijayawada',
          area: 'Benz Circle',
          district: 'Krishna',
        ),
      );
      expect(slot.state, 'Andhra Pradesh');
      expect(slot.city, 'Benz Circle');
      expect(slot.applySerial, 1);
    });

    test('falls back to apiState when resolver state is null', () {
      final slot = PinLocationSlot();
      slot.applyResolved(
        const PinCodeResolvedLocation(
          country: 'India',
          state: null,
          apiState: 'Telangana',
          city: 'Hyderabad',
          area: 'Abids',
          district: 'Hyderabad',
        ),
      );
      expect(slot.state, 'Telangana');
      expect(slot.city, 'Abids');
    });
  });

  group('canonicalCityForState', () {
    test('returns pick when state has no city list', () {
      expect(canonicalCityForState(null, 'Somewhere'), 'Somewhere');
    });
  });

  group('pinMajorCityDropdownOptions', () {
    test('lists only PIN-derived cities not full state catalog', () {
      const result = PinCodeLookupResult(
        postOffices: [
          PinCodePostOffice(
            name: 'Benz Circle',
            district: 'Krishna',
            state: 'Andhra Pradesh',
            region: 'Vijayawada',
          ),
          PinCodePostOffice(
            name: 'Governorpet',
            district: 'Krishna',
            state: 'Andhra Pradesh',
            region: 'Vijayawada',
          ),
        ],
      );
      final options = pinMajorCityDropdownOptions(
        result,
        state: 'Andhra Pradesh',
      );
      expect(options, contains('Vijayawada'));
      expect(options.length, lessThan(20));
      final fullState = ReferenceData.cities['Andhra Pradesh']!;
      expect(options.length, lessThan(fullState.length));
    });
  });

  group('indianCityDropdownItems pin scope', () {
    test('uses pinScopedOptions instead of entire state list', () {
      final scoped = indianCityDropdownItems(
        'Andhra Pradesh',
        selectedCity: 'Vijayawada',
        pinScopedOptions: ['Vijayawada', 'Guntur'],
      );
      expect(scoped, ['Vijayawada', 'Guntur']);
      expect(scoped.length, 2);
    });
  });
}
