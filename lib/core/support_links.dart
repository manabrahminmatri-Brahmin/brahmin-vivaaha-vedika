import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Support contact + official [mana Vivaaha Vedika WhatsApp channel](https://whatsapp.com/channel/0029VbCYZdDLY6d9W19WRi2C).
class SupportLinks {
  SupportLinks._();

  static const String supportPhone = '+918985936678';
  static const String supportPhoneDisplay = '+91 8985936678';
  static const String supportEmail = 'support@manavivaahavedika.in';

  /// Official updates channel — replaces legacy Mana matrimony announcements.
  static const String whatsAppChannelUrl =
      'https://whatsapp.com/channel/0029VbCYZdDLY6d9W19WRi2C';

  /// Digits-only E.164 without '+' for [wa.me](https://wa.me) links.
  static const String supportPhoneWaMe = '918985936678';

  static Uri get whatsAppSupportUri =>
      Uri.parse('https://wa.me/$supportPhoneWaMe');

  static Uri get whatsAppChannelUri => Uri.parse(whatsAppChannelUrl);

  static Future<void> openWhatsAppSupport(BuildContext context) async {
    await _launch(context, whatsAppSupportUri, 'Could not open WhatsApp chat.');
  }

  static Future<void> openWhatsAppChannel(BuildContext context) async {
    await _launch(
      context,
      whatsAppChannelUri,
      'Could not open the mana Vivaaha Vedika WhatsApp channel.',
    );
  }

  static Future<void> _launch(
    BuildContext context,
    Uri uri,
    String errorMessage,
  ) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        _snack(context, errorMessage);
      }
    } catch (_) {
      if (context.mounted) _snack(context, errorMessage);
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.kumkumRed,
      ),
    );
  }
}
