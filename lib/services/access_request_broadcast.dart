import 'package:flutter/foundation.dart';

/// Notifies birth/community access UIs when a remote withdraw/reminder/send completes
/// (e.g. Sent tab vs profile screen must stay aligned).
class AccessRequestBroadcast {
  AccessRequestBroadcast._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void notifyChanged() {
    tick.value = tick.value + 1;
  }
}
