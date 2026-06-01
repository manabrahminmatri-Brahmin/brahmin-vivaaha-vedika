import 'package:shared_preferences/shared_preferences.dart';

/// Rules for [FirebaseAuth.signInAnonymously] in sensitive paths.
///
/// After **explicit logout**, anonymous sign-in must not run for background
/// Firestore writes — it can resurrect a session the user intentionally ended.
///
/// Auth flows (OTP / MPIN login) still use anonymous sign-in when needed so
/// `request.auth != null` for Firestore reads; those paths do not use this flag.
class FirebaseSessionPolicy {
  FirebaseSessionPolicy._();

  static Future<bool> _explicitLogout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('user_explicitly_logged_out') ?? false;
  }

  /// `false` after explicit logout — block anonymous in services layer.
  static Future<bool> mayUseAnonymousFirebaseSession() async {
    return !(await _explicitLogout());
  }
}
