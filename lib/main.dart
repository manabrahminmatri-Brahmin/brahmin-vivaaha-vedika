import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_router.dart';
import 'core/constants.dart';
import 'features/auth/auth_controller.dart';
import 'services/interest_service_v2.dart' show InterestService;
import 'services/like_service_v2.dart' show LikeService;
import 'features/match/filter_engine.dart';
import 'features/profile/analytics_service.dart' show AnalyticsService;
import 'firebase_options.dart';
import 'services/block_service.dart';
import 'services/filter_service.dart';
import 'services/membership_service.dart';
import 'services/message_service.dart';
import 'services/navigation_service.dart';
import 'services/notification_service.dart';
import 'services/network_service.dart';
import 'services/payment_service.dart';
import 'services/plan_service.dart';
import 'services/realtime_sync_service.dart';
import 'services/theme_service.dart';
import 'services/user_activity_service.dart';
import 'services/verification_service.dart';
import 'services/notification_sound_service.dart';
import 'widgets/app_lifecycle_handler.dart';
import 'widgets/auth_wrapper.dart';
import 'widgets/global_offline_banner.dart';

// Global SharedPreferences instance for app-wide access
SharedPreferences? _prefsInstance;
SharedPreferences get prefs {
  if (_prefsInstance == null) {
    throw StateError('SharedPreferences not initialized. Call main() first.');
  }
  return _prefsInstance!;
}

void main() {
  // Disable provider debug check for Listenable types - we handle updates correctly
  Provider.debugCheckInvalidValueType = null;

  runZonedGuarded<Future<void>>(
    () async {
      debugPrint('🚀 App starting...');
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('✅ Flutter bindings initialized');

      debugPrint('🔥 Initializing app...');
      await _initializeApp();
      debugPrint('✅ App initialized, running...');
      runApp(const BrahminVivahApp());
    },
    (error, stack) {
      debugPrint('❌ ERROR in main: $error');
      dev.log('Uncaught error: $error');
      if (!kDebugMode && !kIsWeb) {
        try {
          if (Firebase.apps.isNotEmpty) {
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          }
        } catch (_) {
          // Crashlytics needs a live Firebase app; ignore if init never completed.
        }
      }
    },
  );
}

/// Hot restart and some emulators briefly break the Firebase Core platform
/// channel; retry a few times. Handles duplicate-app if native already inited.
Future<void> _initializeFirebaseCoreWithRetry() async {
  if (Firebase.apps.isNotEmpty) {
    dev.log('Firebase Core already initialized (${Firebase.apps.length} app(s))');
    return;
  }

  const maxAttempts = 4;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      dev.log('Firebase Core initialized (attempt $attempt)');
      return;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        dev.log('Firebase default app already exists; continuing.');
        return;
      }
      rethrow;
    } on PlatformException catch (e) {
      final channelBroken = e.code == 'channel-error' ||
          (e.message?.contains('channel-error') ?? false) ||
          (e.message?.contains('FirebaseCoreHostApi') ?? false);
      if (channelBroken && attempt < maxAttempts) {
        debugPrint(
          '⚠️ Firebase init platform channel error ($attempt/$maxAttempts). '
          'Retrying after delay… (if this persists, stop the app and cold-start)',
        );
        await Future<void>.delayed(Duration(milliseconds: 180 * attempt));
        continue;
      }
      rethrow;
    }
  }
}

Future<void> _initializeApp() async {
  try {
    // 1. Firebase Core
    await _initializeFirebaseCoreWithRetry();

    // 2. Crashlytics (skip on web - not supported)
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      dev.log('Crashlytics initialized');
    } else {
      dev.log('Crashlytics skipped on web');
    }

    // 3. Analytics
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await FirebaseAnalytics.instance.logAppOpen();
    dev.log('Analytics initialized');

    // 4. App Check — required when Cloud Functions use MVV_ENFORCE_APP_CHECK=true
    const webRecaptchaSiteKey = String.fromEnvironment(
      'FIREBASE_APP_CHECK_WEB_SITE_KEY',
    );
    if (kIsWeb) {
      if (webRecaptchaSiteKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(webRecaptchaSiteKey),
        );
        dev.log('App Check activated (web ReCaptcha)');
      } else {
        dev.log(
          'App Check web skipped — set --dart-define=FIREBASE_APP_CHECK_WEB_SITE_KEY=... '
          'or keep MVV_ENFORCE_APP_CHECK unset on Functions',
        );
      }
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      );
      dev.log('App Check activated');
    }

    // 5. Firestore offline persistence (not supported on web)
    // Bounded cache avoids multi‑hundred‑MB growth on long‑running installs (Android
    // low‑storage kills, slower cold start).
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 50 * 1024 * 1024,
      );
      dev.log('Firestore persistence enabled (50 MiB cache cap)');
    } else {
      dev.log('Firestore using default web cache');
    }

    // 6. SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    dev.log('SharedPreferences initialized');

    // Store for global access
    _prefsInstance = prefs;

    // Live Wi‑Fi / mobile data state for [GlobalOfflineBanner] and [NetworkService].
    await NetworkService.initialize();

    PlanService.instance.startListening();

    // Prepare local-notification bell channel (custom sound with safe fallback).
    await NotificationSoundService.initialize();

    debugPrint('🎉 App initialization complete!');
    dev.log('App initialization complete');
  } catch (e, stack) {
    debugPrint('❌ App initialization failed: $e');
    dev.log('App initialization failed: $e');
    if (!kDebugMode && !kIsWeb) {
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseCrashlytics.instance.recordError(e, stack, fatal: true);
        }
      } catch (_) {}
    }
    rethrow;
  }
}

class BrahminVivahApp extends StatelessWidget {
  const BrahminVivahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>(create: (_) => AuthController()),
        ChangeNotifierProvider<ThemeService>(
          create: (_) => ThemeService(prefs),
        ),
        ChangeNotifierProvider<FilterService>(create: (_) => FilterService()),
        ChangeNotifierProvider<FilterEngine>(create: (_) => FilterEngine()),
        ChangeNotifierProvider<InterestService>(
            create: (_) => InterestService()),
        Provider<LikeService>(create: (_) => LikeService()),
        ChangeNotifierProvider<MembershipService>(
            create: (_) => MembershipService()),
        ChangeNotifierProvider<MessageService>(create: (_) => MessageService()),
        ChangeNotifierProvider<NotificationService>(
            create: (_) => NotificationService()),
        ChangeNotifierProvider<PaymentService>(
            create: (_) => PaymentService.instance),
        ChangeNotifierProvider<RealtimeSyncService>(
            create: (_) => RealtimeSyncService()),
        ChangeNotifierProvider<UserActivityService>(
            create: (_) => UserActivityService()),
        ChangeNotifierProvider<VerificationService>(
            create: (_) => VerificationService(prefs)),
        ChangeNotifierProvider<BlockService>(
            create: (_) => BlockService(prefs)),
        Provider<NavigationService>(create: (_) => NavigationService()),
        ChangeNotifierProvider<AnalyticsService>(
            create: (_) => AnalyticsService()),
        Provider<FirebaseAnalytics>(create: (_) => FirebaseAnalytics.instance),
        Provider<FirebaseFirestore>(create: (_) => FirebaseFirestore.instance),
      ],
      child: Builder(builder: (context) {
        final navService = context.read<NavigationService>();
        return Consumer<ThemeService>(
          builder: (context, themeService, child) {
            return MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              navigatorKey: navService.navigatorKey,
              navigatorObservers: [
                FirebaseAnalyticsObserver(
                    analytics: FirebaseAnalytics.instance),
                AppRouter.routeObserver,
              ],
              onGenerateRoute: AppRouter.onGenerateRoute,
              theme: themeService.currentTheme,
              home: const AuthWrapper(),
              builder: (context, child) {
                return AppLifecycleHandler(
                  child: GlobalOfflineBanner(
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        );
      }),
    );
  }
}
