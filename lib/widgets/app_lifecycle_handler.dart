import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
// ─────────────────────────────────────────────────────────────────────────────
// AppLifecycleHandler  —  FIXED v4
//
// BUG FIXED:
//   Was importing presence_service_clean.dart which defines its own
//   PresenceService singleton. But main.dart and the rest of the app use
//   presence_service.dart (the canonical version). These are two DIFFERENT
//   singletons — so setOnline()/setOffline() calls here had no effect on
//   the presence state the rest of the app was using.
//
//   FIX: Import the canonical presence_service.dart.
//   Also: presence_service_clean.dart had uid getter that throws on null
//   (currentUser!.uid) — this caused hard crashes on foreground/background
//   transitions when the user was not logged in.
// ─────────────────────────────────────────────────────────────────────────────
import '../services/presence_service.dart'; // FIX: was presence_service_clean.dart

class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({super.key, required this.child});

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  final _presence = PresenceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (!_presence.isSessionActive) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _presence.goForeground();
        break;
      // Do not mark offline on `inactive` (dialogs, overlays, app switcher) — only
      // when the app is no longer visible.
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _presence.goBackground();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
