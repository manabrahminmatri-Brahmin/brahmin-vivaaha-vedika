import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/core/access_request_status.dart';

/// Documents expected server state machine transitions (mirrors Cloud Functions).
void main() {
  group('privacy access state machine', () {
    String transition(String from, String action) {
      final current = AccessRequestStatus.normalize(from);
      switch (action) {
        case 'grant':
          if (current == AccessRequestStatus.granted) return current;
          if ([
            AccessRequestStatus.pending,
            AccessRequestStatus.denied,
            AccessRequestStatus.revoked,
          ].contains(current)) {
            return AccessRequestStatus.granted;
          }
          return current;
        case 'deny':
          if (current == AccessRequestStatus.pending) {
            return AccessRequestStatus.denied;
          }
          return current;
        case 'revoke':
          if (current == AccessRequestStatus.granted) {
            return AccessRequestStatus.revoked;
          }
          return current;
        default:
          return current;
      }
    }

    test('request → grant → revoke → grant again', () {
      expect(transition('pending', 'grant'), 'granted');
      expect(transition('granted', 'revoke'), 'revoked');
      expect(transition('revoked', 'grant'), 'granted');
    });

    test('request → deny blocks grant without new request', () {
      expect(transition('pending', 'deny'), 'denied');
      expect(transition('denied', 'grant'), 'granted');
    });

    test('revoke ignored when not granted', () {
      expect(transition('pending', 'revoke'), 'pending');
      expect(transition('denied', 'revoke'), 'denied');
    });

    test('legacy accepted normalizes before revoke', () {
      expect(transition('accepted', 'revoke'), 'revoked');
    });
  });
}
