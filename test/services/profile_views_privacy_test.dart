import 'package:brahmin_vivaaha_vedika/services/profile_views_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileViewsPrivacy', () {
    test('shouldHideViewerRow when incognito flag set', () {
      expect(
        ProfileViewsPrivacy.shouldHideViewerRow({'viewer_incognito': true}),
        isTrue,
      );
      expect(
        ProfileViewsPrivacy.shouldHideViewerRow({'viewer_hidden': true}),
        isTrue,
      );
      expect(
        ProfileViewsPrivacy.shouldHideViewerRow({'viewer_user_id': 'x'}),
        isFalse,
      );
    });
  });
}
