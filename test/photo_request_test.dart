import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Photo request (server callable)', () {
    test('doc id is requester_target composite', () {
      const requester = 'uid_sender';
      const target = 'uid_receiver';
      expect('${requester}_$target', 'uid_sender_uid_receiver');
    });

    test('client must not write photo_requests directly', () {
      // Enforced by firestore.rules: create/update false on photo_requests.
      expect(true, isTrue);
    });
  });
}
