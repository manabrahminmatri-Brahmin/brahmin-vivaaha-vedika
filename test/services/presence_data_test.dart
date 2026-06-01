import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/presence_service.dart';

void main() {
  group('PresenceData RTDB mapping', () {
    test('fromRtdbMap reads online and lastSeen millis', () {
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
      final data = PresenceData.fromRtdbMap({
        'online': true,
        'lastSeen': ts,
      });
      expect(data.isOnline, isTrue);
      expect(data.lastActive?.millisecondsSinceEpoch, ts);
    });

    test('fromMap supports legacy Firestore fields', () {
      final data = PresenceData.fromMap({
        'is_online': true,
        'last_active': DateTime.now().toUtc().toIso8601String(),
      });
      expect(data.isOnline, isTrue);
    });

    test('applyStaleness clears stale online without recent lastSeen', () {
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final data = PresenceData(isOnline: true, lastActive: old).applyStaleness();
      expect(data.isOnline, isFalse);
    });

    test('applyStaleness keeps online when lastActive is missing', () {
      const data = PresenceData(isOnline: true, lastActive: null);
      expect(data.applyStaleness().isOnline, isTrue);
    });
  });
}
