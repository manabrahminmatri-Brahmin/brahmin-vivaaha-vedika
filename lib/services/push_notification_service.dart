import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../core/contract.dart';

/// Top-level handler required by [FirebaseMessaging.onBackgroundMessage].
/// Keep minimal: init Firebase only; avoid heavy work (saves cold-start + billing).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] background message: ${message.messageId} type=${message.data['type']}');
}

/// Registers the device FCM token on the **canonical** `users/{firestoreUserDocId}` doc.
///
/// **Billing / design**
/// - One merge-write when the token **changes** (not on every app resume).
/// - Cloud Function sends push on existing `notifications` creates — **no extra
///   Firestore writes** from the client for push delivery.
/// - Recipient resolution in Functions: 1× `get(users/{user_id})` then optional
///   1× `where(auth_uid == user_id).limit(1)` only if the first doc has no token.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _initialized = false;
  String? _cachedToken;
  String? _lastTokenUserDocId;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Call once after [Firebase.initializeApp]. Registers [onBackgroundMessage].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.setAutoInitEnabled(true);

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Foreground: optional logging (in-app Firestore notification still drives UI).
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint(
        '[FCM] foreground: ${msg.notification?.title} data=${msg.data}',
      );
    });

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) async {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getString('current_user_id')?.trim() ?? '';
        if (uid.isEmpty) return;
        // Re-login: prefs doc id can change while [_lastTokenUserDocId] still points at the previous user.
        if (_lastTokenUserDocId != null && _lastTokenUserDocId != uid) {
          _cachedToken = null;
        }
        await _persistTokenIfChanged(firestoreUserDocId: uid, token: newToken);
        _lastTokenUserDocId = uid;
      },
      onError: (e) => debugPrint('[FCM] onTokenRefresh error: $e'),
    );
  }

  /// Request OS permission, resolve token, write to Firestore for [firestoreUserDocId].
  Future<void> registerForLoggedInUser(String? firestoreUserDocId) async {
    if (firestoreUserDocId == null || firestoreUserDocId.isEmpty) return;
    if (_lastTokenUserDocId != firestoreUserDocId) {
      _lastTokenUserDocId = firestoreUserDocId;
      _cachedToken = null;
    }
    await initialize();

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] permission denied');
        return;
      }
    } catch (e) {
      debugPrint('[FCM] requestPermission: $e');
    }

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FCM] no token (check Google Play services / iOS capability)');
        return;
      }
      await _persistTokenIfChanged(
        firestoreUserDocId: firestoreUserDocId,
        token: token,
      );
    } catch (e) {
      debugPrint('[FCM] getToken / persist: $e');
    }
  }

  Future<void> _persistTokenIfChanged({
    required String firestoreUserDocId,
    required String token,
  }) async {
    if (_cachedToken == token) {
      return;
    }
    _cachedToken = token;
    try {
      await _db.collection(Collections.users).doc(firestoreUserDocId).set(
        {
          'fcm_token': token,
          'fcm_token_updated_at': FieldValue.serverTimestamp(),
          'fcm_platform': defaultTargetPlatform.name,
        },
        SetOptions(merge: true),
      );
      debugPrint('[FCM] token saved for user doc $firestoreUserDocId');
    } catch (e) {
      debugPrint('[FCM] Firestore write failed: $e');
      _cachedToken = null;
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  /// Clear in-memory cache when the session ends so the next login re-writes if needed.
  void onLogout() {
    _cachedToken = null;
    _lastTokenUserDocId = null;
  }
}
