import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/models/gender.dart';

void main() {
  group('normalizeGender', () {
    test('handles spaced and mixed-case literals', () {
      expect(normalizeGender('Male '), 'male');
      expect(normalizeGender(' FEMALE'), 'female');
      expect(normalizeGender('MALE'), 'male');
    });

    test('handles enum-style strings case-insensitively', () {
      expect(normalizeGender('GENDER.MALE'), 'male');
      expect(normalizeGender('gender.female'), 'female');
      expect(normalizeGender('Gender.male'), 'male');
    });

    test('handles common informal labels', () {
      expect(normalizeGender('boy'), 'male');
      expect(normalizeGender('bride'), 'female');
      expect(normalizeGender('groom'), 'male');
    });

    test('extracts hint from compound strings', () {
      expect(normalizeGender('gender-male'), 'male');
      expect(normalizeGender('sex: female'), 'female');
    });

    test('genderFromUserDocumentData reads root and nested profile', () {
      expect(
        genderFromUserDocumentData({'gender': 'Male '}),
        Gender.male,
      );
      expect(
        genderFromUserDocumentData({
          'profile': {'gender': 'bride'},
        }),
        Gender.female,
      );
    });
  });
}
