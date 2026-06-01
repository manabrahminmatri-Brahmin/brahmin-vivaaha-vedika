import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to handle notification sounds
/// Uses system sounds for bell/notification alerts
class NotificationSoundService {
  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);
  static Uint8List? _fallbackBellBytes;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsReady = false;
  static const String _bellChannelId = 'bell_channel_v2';
  static const String _bellChannelName = 'Bell Notifications';
  static const String _androidBellRawName = 'bell';
  static const String _iosBellFileName = 'bell.caf';
  static int _nextNotificationId = 7000;

  static const String _prefKeySoundEnabled = 'notif_sound_enabled';
  static const String _prefKeyInterestSoundEnabled = 'notif_sound_interest';
  static const String _prefKeyMessageSoundEnabled = 'notif_sound_message';
  static const String _prefKeyRequestSoundEnabled = 'notif_sound_request';

  /// Initializes local notifications for custom notification bell assets.
  /// Safe to call multiple times.
  static Future<void> initialize() async {
    if (_localNotificationsReady) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(settings);

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _bellChannelId,
          _bellChannelName,
          description: 'Custom bell notification sound',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_androidBellRawName),
        ),
      );

      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      _localNotificationsReady = true;
    } catch (e) {
      debugPrint('⚠️ NotificationSoundService.initialize failed: $e');
    }
  }

  /// Play bell/notification sound
  /// Uses app-owned bell audio via audioplayers with system fallback.
  static Future<void> playNotificationSound() async {
    try {
      // Reliable in-app playback path (works even without notification assets).
      _fallbackBellBytes ??= _buildBellWavBytes();
      await _player.stop();
      await _player.play(BytesSource(_fallbackBellBytes!));
      return;
    } catch (e) {
      debugPrint('⚠️ Failed to play notification sound: $e');
      try {
        // Optional custom-asset path for platforms where local notifications
        // are preferred/configured.
        await initialize();
        if (_localNotificationsReady && (Platform.isAndroid || Platform.isIOS)) {
          final androidDetails = AndroidNotificationDetails(
            _bellChannelId,
            _bellChannelName,
            channelDescription: 'Custom bell notification sound',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound(_androidBellRawName),
            enableVibration: false,
            ticker: 'bell',
          );
          const iosDetails = DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: true,
            sound: _iosBellFileName,
          );
          final details = NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          );
          await _localNotifications.show(
            _nextNotificationId++,
            '',
            '',
            details,
          );
          return;
        }
        if (Platform.isAndroid || Platform.isIOS) {
          await SystemSound.play(SystemSoundType.alert);
        } else {
          await SystemSound.play(SystemSoundType.click);
        }
      } catch (_) {}
    }
  }

  /// Check if sounds are enabled
  static Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeySoundEnabled) ?? true; // Default to enabled
  }

  /// Check if interest sound is enabled
  static Future<bool> isInterestSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = await isSoundEnabled();
    if (!soundEnabled) return false;
    return prefs.getBool(_prefKeyInterestSoundEnabled) ?? true; // Default to enabled
  }

  /// Check if message sound is enabled
  static Future<bool> isMessageSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = await isSoundEnabled();
    if (!soundEnabled) return false;
    return prefs.getBool(_prefKeyMessageSoundEnabled) ?? true; // Default to enabled
  }

  /// Check if request bell sound is enabled
  static Future<bool> isRequestSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = await isSoundEnabled();
    if (!soundEnabled) return false;
    return prefs.getBool(_prefKeyRequestSoundEnabled) ?? true;
  }

  /// Play sound for interest received (premium users only)
  static Future<void> playInterestReceivedSound({required bool isPremium}) async {
    // Only play sound for premium users
    if (!isPremium) return;

    final soundEnabled = await isInterestSoundEnabled();
    if (!soundEnabled) return;

    await playNotificationSound();
  }

  /// Play sound for message received
  static Future<void> playMessageReceivedSound() async {
    final soundEnabled = await isMessageSoundEnabled();
    if (!soundEnabled) return;

    await playNotificationSound();
  }

  /// Play bell for incoming requests (interest/photo/birth/community)
  static Future<void> playRequestReceivedSound() async {
    final prefs = await SharedPreferences.getInstance();
    final masterEnabled = prefs.getBool(_prefKeySoundEnabled) ?? true;
    final requestEnabled = prefs.getBool(_prefKeyRequestSoundEnabled) ?? true;
    final soundEnabled = masterEnabled && requestEnabled;
    if (kDebugMode) {
      debugPrint(
        '🔔 BellDebug prefs master=$masterEnabled request=$requestEnabled '
        'effective=$soundEnabled platform='
        '${Platform.isAndroid ? "android" : Platform.isIOS ? "ios" : "other"}',
      );
    }
    if (!soundEnabled) return;
    if (kDebugMode) {
      debugPrint('🔔 BellDebug playRequestReceivedSound -> playing app bell');
    }
    await playNotificationSound();
  }

  /// Play sound when interest is sent (optional - just for confirmation)
  static Future<void> playInterestSentSound() async {
    final soundEnabled = await isInterestSoundEnabled();
    if (!soundEnabled) return;

    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('⚠️ Failed to play interest sent sound: $e');
    }
  }

  /// Enable/disable all sounds
  static Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySoundEnabled, enabled);
  }

  /// Enable/disable interest sound
  static Future<void> setInterestSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyInterestSoundEnabled, enabled);
  }

  /// Enable/disable message sound
  static Future<void> setMessageSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyMessageSoundEnabled, enabled);
  }

  /// Enable/disable request bell sound
  static Future<void> setRequestSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyRequestSoundEnabled, enabled);
  }

  static Uint8List _buildBellWavBytes({
    int sampleRate = 44100,
    int durationMs = 980,
  }) {
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final dataLength = sampleCount * 2;
    final byteData = ByteData(44 + dataLength);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        byteData.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    byteData.setUint32(40, dataLength, Endian.little);

    const bellFundamental = 1244.51; // D#6 / Eb6
    const overtone1 = 1864.66; // ~minor 12th
    const overtone2 = 2489.02; // octave above fundamental
    const twopi = 2 * pi;
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      // Single lingering bell: "tingggg" with bright attack and long tail.
      final attack = t < 0.008 ? (t / 0.008) : 1.0;
      final sustainDecay = exp(-3.15 * t);
      final shimmer = 0.90 + 0.10 * exp(-5.5 * t) * sin(twopi * 4.8 * t);
      final envelope = attack * sustainDecay * shimmer;
      final wave = (sin(twopi * bellFundamental * t) * 0.70 +
              sin(twopi * overtone1 * t) * 0.24 +
              sin(twopi * overtone2 * t) * 0.14) *
          envelope;
      final pcm16 = (wave * 32767).clamp(-32768, 32767).toInt();
      byteData.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return byteData.buffer.asUint8List();
  }
}
