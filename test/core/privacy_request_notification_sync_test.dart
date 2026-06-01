import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/privacy_request_notification_sync.dart';

void main() {
  group('PrivacyRequestNotificationSync', () {
    test('shouldMarkNotificationRead clears incoming when not pending', () {
      expect(
        PrivacyRequestNotificationSync.shouldMarkNotificationRead(
          type: 'birth_request',
          requestDocId: 'a_b',
          pendingIncomingRequestDocIds: <String>{},
          requestDocStatuses: const {'a_b': 'pending'},
        ),
        isTrue,
      );
    });

    test('shouldMarkNotificationRead keeps incoming while still pending', () {
      expect(
        PrivacyRequestNotificationSync.shouldMarkNotificationRead(
          type: 'birth_request',
          requestDocId: 'a_b',
          pendingIncomingRequestDocIds: {'a_b'},
          requestDocStatuses: const {'a_b': 'pending'},
        ),
        isFalse,
      );
    });

    test('shouldMarkNotificationRead clears outcome when granted', () {
      expect(
        PrivacyRequestNotificationSync.shouldMarkNotificationRead(
          type: 'birth_request_granted',
          requestDocId: 'a_b',
          pendingIncomingRequestDocIds: <String>{},
          requestDocStatuses: const {'a_b': 'granted'},
        ),
        isTrue,
      );
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

    test('requestDocIdFromNotification reads snake_case field', () {
      expect(
        PrivacyRequestNotificationSync.requestDocIdFromNotification({
          'type': 'birth_request',
          'request_doc_id': 'req1',
        }),
        'req1',
      );
    });
  });
}
