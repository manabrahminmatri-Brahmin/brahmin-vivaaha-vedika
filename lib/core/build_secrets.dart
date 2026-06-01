import 'package:flutter/foundation.dart';

/// Compile-time secrets and environment-specific config via `--dart-define`.
///
/// **OTP (2factor.in):** supply `TWO_FACTOR_API_KEY` or `Two_Factor_API_Key`
/// (or dev key in debug). Optional `TWO_FACTOR_OTP_TEMPLATE` — approved template
/// name from 2factor CP (appends `/AUTOGEN/{template}` to the send URL).
///
/// **Cloudinary (only photo upload)** — profile images use Cloudinary unsigned uploads.
///
/// **Dashboard / upload presets (create or verify your unsigned preset here):**
/// https://console.cloudinary.com/app/c-b897dfb6d2f0438c97a554380c2e4d/settings/upload/presets
///
/// **Where to set “environment” values for Flutter** (OS env vars are *not* read
/// at runtime; use `--dart-define`, project-root `dart_defines.json`, or IDE):
/// - **Easiest (Cursor / VS Code):** edit **`dart_defines.json`** at the project
///   root — set `"TWO_FACTOR_API_KEY"` to your 2factor.in Global / Phone Verification key.
///   `launch.json` loads this file on every **Run / Debug**. Optional: also set the
///   Windows user env var `TWO_FACTOR_API_KEY` (overrides the file if both are set).
/// - **Cloudinary overrides:** same file or `--dart-define=CLOUDINARY_...`
/// - **Terminal:** `flutter run --dart-define-from-file=dart_defines.json` or flags below.
///
/// **Defaults in code** (methods below): cloud `dibgihscr`, preset `brahmin_vivaaha_vedika`
/// when defines are omitted.
///
/// Example release build (or use the same keys in `dart_defines.json`):
/// ```text
/// flutter build apk --release ^
///   --dart-define-from-file=dart_defines.json
/// ```
/// Or inline: `--dart-define=TWO_FACTOR_API_KEY=<key>` and optionally
/// `--dart-define=TWO_FACTOR_OTP_TEMPLATE=<approved template name>` (Global OTP, not TSMS-only).
/// (On bash/macOS use `\` line continuation instead of `^`.)
abstract final class BuildSecrets {
  BuildSecrets._();

  // ── 2factor.in ─────────────────────────────────────────────────────────

  static String get twoFactorApiKey {
    const tier1 = String.fromEnvironment('TWO_FACTOR_API_KEY', defaultValue: '');
    final t1 = tier1.trim();
    if (t1.isNotEmpty) return t1;

    const tier1Alt =
        String.fromEnvironment('Two_Factor_API_Key', defaultValue: '');
    final t1Alt = tier1Alt.trim();
    if (t1Alt.isNotEmpty) return t1Alt;

    // Common legacy aliases used in some CI/build setups.
    const tier1AliasA =
        String.fromEnvironment('TWO_FACTOR_KEY', defaultValue: '');
    final t1AliasA = tier1AliasA.trim();
    if (t1AliasA.isNotEmpty) return t1AliasA;

    const tier1AliasB =
        String.fromEnvironment('TWO_FACTOR_APIKEY', defaultValue: '');
    final t1AliasB = tier1AliasB.trim();
    if (t1AliasB.isNotEmpty) return t1AliasB;

    const tier2 =
        String.fromEnvironment('REMOTE_TWO_FACTOR_KEY', defaultValue: '');
    final t2 = tier2.trim();
    if (t2.isNotEmpty) return t2;

    if (kDebugMode) {
      const dev = String.fromEnvironment('TWO_FACTOR_DEV_KEY', defaultValue: '');
      final d = dev.trim();
      if (d.isNotEmpty) return d;

      // 🔥 FIX: Dev fallback with provided key (safe for development only)
      // Remove before production builds - use dart_defines.json for prod
      return '5f9954d7-4711-11ed-9c12-0200cd936042';
    }

    // SECURITY: No hardcoded fallback for production.
    // Production builds must use --dart-define or dart_defines.json
    if (kDebugMode) {
      debugPrint('⚠️ TWO_FACTOR_API_KEY not set. OTP will fail.');
      debugPrint('   Set it in dart_defines.json or use --dart-define=TWO_FACTOR_API_KEY=xxx');
    }
    return ''; // No fallback - key must be provided via build configuration
  }

  static bool get hasTwoFactorApiKey => twoFactorApiKey.isNotEmpty;

  /// Approved 2factor.in OTP template name (DLT). Empty = default `AUTOGEN` route.
  static String get twoFactorOtpTemplate {
    const v =
        String.fromEnvironment('TWO_FACTOR_OTP_TEMPLATE', defaultValue: '');
    return v.trim();
  }

  // ── Cloudinary (sole photo upload — no Firebase Storage) ────────────────
  //
  // Upload presets UI:
  // https://console.cloudinary.com/app/c-b897dfb6d2f0438c97a554380c2e4d/settings/upload/presets
  // Preset must be **Unsigned**. Never embed the API secret in the app.
  //
  // Env keys: CLOUDINARY_CLOUD_NAME, CLOUDINARY_UPLOAD_PRESET (via --dart-define only).

  /// Cloud name — override: `--dart-define=CLOUDINARY_CLOUD_NAME=...`
  static String resolveCloudinaryCloudName() {
    const v = String.fromEnvironment('CLOUDINARY_CLOUD_NAME', defaultValue: '');
    if (v.isNotEmpty) return v;
    return 'dibgihscr';
  }

  /// Unsigned upload preset — override: `--dart-define=CLOUDINARY_UPLOAD_PRESET=...`
  static String resolveCloudinaryUploadPreset() {
    const v =
        String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET', defaultValue: '');
    if (v.isNotEmpty) return v;
    return 'brahmin_vivaaha_vedika';
  }

  /// True when both Cloudinary identifiers resolve (always true with defaults above).
  static bool get isCloudinaryUploadConfigured =>
      resolveCloudinaryCloudName().isNotEmpty &&
      resolveCloudinaryUploadPreset().isNotEmpty;

  // ── Admin bootstrap ─────────────────────────────────────────────────────
  // Primary source: --dart-define values.
  // Fallbacks below keep existing admin login working on local/dev builds.

  static String get adminMobile {
    const v = String.fromEnvironment('ADMIN_MOBILE', defaultValue: '');
    return v.trim(); // no fallback — empty means "not configured"
  }

  /// SHA-256 hex of UTF-8 `mana_matrimony_mpin_salt` + 4-digit MPIN.
  static String get adminMpinHash {
    const v = String.fromEnvironment('ADMIN_MPIN_HASH', defaultValue: '');
    if (v.isNotEmpty) return v;
    if (kDebugMode) {
      const dev =
          String.fromEnvironment('ADMIN_MPIN_HASH_DEV', defaultValue: '');
      if (dev.isNotEmpty) return dev;
    }
    return ''; // no fallback
  }
}
