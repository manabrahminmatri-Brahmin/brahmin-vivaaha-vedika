import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/access_request_status.dart';
import 'package:brahmin_vivaaha_vedika/core/privacy_request_notification_sync.dart';

void main() {
  group('AccessRequestStatus', () {
    test('normalize maps legacy values', () {
      expect(AccessRequestStatus.normalize('accepted'), 'granted');
      expect(AccessRequestStatus.normalize('approved'), 'granted');
      expect(AccessRequestStatus.normalize('rejected'), 'denied');
      expect(AccessRequestStatus.normalize('declined'), 'denied');
      expect(AccessRequestStatus.normalize('revoked'), 'revoked');
      expect(AccessRequestStatus.normalize('pending'), 'pending');
    });

    test('isSettled excludes pending and withdrawn', () {
      expect(AccessRequestStatus.isSettled('pending'), isFalse);
      expect(AccessRequestStatus.isSettled('withdrawn'), isFalse);
      expect(AccessRequestStatus.isSettled('granted'), isTrue);
      expect(AccessRequestStatus.isSettled('revoked'), isTrue);
      expect(AccessRequestStatus.isSettled('denied'), isTrue);
    });
  });

  group('revoke lifecycle notification sync', () {
    test('revoked outcome clears when doc is revoked', () {
      expect(
        PrivacyRequestNotificationSync.shouldMarkNotificationRead(
          type: 'photo_request_revoked',
          requestDocId: 'a_b',
          pendingIncomingRequestDocIds: <String>{},
          requestDocStatuses: const {'a_b': 'revoked'},
        ),
        isTrue,
      );
    });

    test('granted outcome stays unread while still pending', () {
      expect(
        PrivacyRequestNotificationSync.shouldMarkNotificationRead(
          type: 'birth_request_granted',
          requestDocId: 'a_b',
          pendingIncomingRequestDocIds: <String>{},
          requestDocStatuses: const {'a_b': 'pending'},
        ),
        isFalse,
      );
    });
  });
}
