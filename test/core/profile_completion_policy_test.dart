import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/profile_completion_policy.dart';
import 'package:brahmin_vivaaha_vedika/models/gender.dart';
import 'package:brahmin_vivaaha_vedika/models/user.dart' as app_models;

void main() {
  group('ProfileCompletionPolicy', () {
    test('grants full app access when stored percent reaches threshold', () {
      expect(
        ProfileCompletionPolicy.meetsFullAppAccessThreshold(
          storedPercent: 80,
          isProfileCompleteFlag: false,
        ),
        isTrue,
      );
    });

    test('grants full app access when Firestore complete flag is true', () {
      expect(
        ProfileCompletionPolicy.meetsFullAppAccessThreshold(
          storedPercent: 10,
          isProfileCompleteFlag: true,
        ),
        isTrue,
      );
    });

    test('blocks full app access below threshold without complete flag', () {
      expect(
        ProfileCompletionPolicy.meetsFullAppAccessThreshold(
          storedPercent: 79,
          isProfileCompleteFlag: false,
        ),
        isFalse,
      );
    });

    test('excludes admin users from discovery', () {
      final admin = app_models.User(
        id: 'user-admin-discovery',
        email: 'admin@example.com',
        password: '',
        mobileNumber: '9876543210',
        isAdmin: true,
        profileCompletionPercentage: 100,
      );
      expect(ProfileCompletionPolicy.isEligibleForDiscovery(admin), isFalse);
    });

    test('User.fromJson maps is_admin for discovery exclusion', () {
      final u = app_models.User.fromJson({
        'id': 'admin-json',
        'email': 'a@b.com',
        'password': '',
        'mobile_number': '9999999999',
        'is_admin': true,
        'profile_completion_percentage': 100,
      });
      expect(u.isAdmin, isTrue);
      expect(ProfileCompletionPolicy.isEligibleForDiscovery(u), isFalse);
    });

    test('excludes deleted users from discovery regardless of completion', () {
      final user = app_models.User(
        id: 'user-deleted-discovery',
        email: 'deleted@example.com',
        password: '',
        mobileNumber: '9876543210',
        isDeleted: true,
        profileCompletionPercentage: 100,
      );

      expect(ProfileCompletionPolicy.isEligibleForDiscovery(user), isFalse);
    });

    test('requires discovery completion threshold for active users', () {
      final incomplete = app_models.User(
        id: 'user-incomplete-discovery',
        email: 'incomplete@example.com',
        password: '',
        mobileNumber: '9876543210',
        profileCompletionPercentage: 79,
      );
      final complete = app_models.User(
        id: 'user-complete-discovery',
        email: 'complete@example.com',
        password: '',
        mobileNumber: '9876543211',
        profileCompletionPercentage: 80,
      );

      expect(
          ProfileCompletionPolicy.isEligibleForDiscovery(incomplete), isFalse);
      expect(ProfileCompletionPolicy.isEligibleForDiscovery(complete), isTrue);
    });

    test('meaningful legacy row is discovery-eligible when stored % is zero', () {
      final u = app_models.User(
        id: 'user-meaningful-legacy',
        email: 'legacy@example.com',
        password: '',
        mobileNumber: '9876543210',
        profileCompletionPercentage: 0,
        profile: app_models.UserProfile(
          firstName: 'L',
          lastName: 'egacy',
          gender: Gender.male,
          dateOfBirth: DateTime(1992, 3, 4),
          occupation: 'Engineer',
          education: 'B.Tech',
          city: 'Chennai',
          profilePicture: 'https://example.com/p.jpg',
        ),
      );
      expect(ProfileCompletionPolicy.isEligibleForDiscovery(u), isTrue);
    });

    test('effectiveCompletion prefers stored percent over computed', () {
      final u = app_models.User(
        id: 'user-stored-over-computed',
        email: 'x@example.com',
        password: '',
        mobileNumber: '9876543210',
        profileCompletionPercentage: 40,
        profile: app_models.UserProfile(
          firstName: 'A',
          lastName: 'B',
          gender: Gender.female,
          dateOfBirth: DateTime(1995, 5, 5),
          profileCompletionPercentage: 95,
        ),
      );
      expect(ProfileCompletionPolicy.effectiveCompletionPercent(u), 40);
    });
  });
}
