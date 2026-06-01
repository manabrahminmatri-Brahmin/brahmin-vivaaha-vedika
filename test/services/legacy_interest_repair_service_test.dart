import 'package:brahmin_vivaaha_vedika/services/legacy_interest_repair_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegacyInterestRepairService', () {
    test('needsSnapshotRepair when sender name missing', () {
      expect(
        LegacyInterestRepairService.needsSnapshotRepair({
          'from_user_id': 'a',
          'to_user_id': 'b',
          'to_first_name': 'Priya',
        }),
        isTrue,
      );
    });

    test('patchFromProfiles fills from_* and to_*', () {
      final patch = LegacyInterestRepairService.patchFromProfiles(
        row: {'from_user_id': 'u1', 'to_user_id': 'u2'},
        profilesByUserId: {
          'u1': {
            'first_name': 'Ravi',
            'last_name': 'K',
            'profile_id': 'BVV-M-100',
            'city': 'Chennai',
            'state': 'TN',
            'age': 28,
          },
          'u2': {
            'first_name': 'Priya',
            'last_name': 'S',
            'profile_id': 'BVV-F-200',
          },
        },
      );
      expect(patch['from_first_name'], 'Ravi');
      expect(patch['to_first_name'], 'Priya');
      expect(patch['from_city'], 'Chennai');
      expect(patch['to_profile_id'], 'BVV-F-200');
    });

    test('mergeIntoRow applies patch in memory', () {
      final merged = LegacyInterestRepairService.mergeIntoRow(
        {'id': 'u1_u2', 'status': 'pending'},
        {'from_first_name': 'Ravi'},
      );
      expect(merged['from_first_name'], 'Ravi');
      expect(merged['status'], 'pending');
    });
  });
}
