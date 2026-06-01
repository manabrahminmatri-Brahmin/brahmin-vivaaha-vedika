import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/privacy_enforcement_service.dart';

void main() {
  group('Discover photo privacy flags', () {
    test('isPhotoHiddenFromOthers respects parsed profile flag', () {
      expect(
        PrivacyEnforcementService.isPhotoHiddenFromOthers(
          null,
          fromParsedProfile: true,
        ),
        isTrue,
      );
      expect(
        PrivacyEnforcementService.isPhotoHiddenFromOthers(
          null,
          fromParsedProfile: false,
        ),
        isFalse,
      );
    });

    test('isPhotoHiddenFromOthers reads Firestore doc fields', () {
      expect(
        PrivacyEnforcementService.isPhotoHiddenFromOthers(
          {'is_photo_private': true},
        ),
        isTrue,
      );
      expect(
        PrivacyEnforcementService.isPhotoHiddenFromOthers(
          {'profile': {'isPhotoPrivate': true}},
        ),
        isTrue,
      );
      expect(
        PrivacyEnforcementService.isPhotoHiddenFromOthers(const {}),
        isFalse,
      );
    });

    test('blur and hide-until-accepted flags read from doc', () {
      expect(
        PrivacyEnforcementService.blurPhotosForStrangers(
          {'privacy_blur_photos_for_strangers': true},
        ),
        isTrue,
      );
      expect(
        PrivacyEnforcementService.hidePhotosUntilAccepted(
          {'privacy_photo_visible_after_acceptance': true},
        ),
        isTrue,
      );
    });
  });
}
