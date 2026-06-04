import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Official support contact for mana Vivaaha Vedika (app + policies).
class SupportLinks {
  SupportLinks._();

  static const String supportPhone = '+918985936678';
  static const String supportPhoneDisplay = '+91 8985936678';
  static const String supportEmail = 'support@manavivaahavedika.in';
  static const String supportWebsiteDisplay = 'www.manavivaahavedika.in';
  static const String supportWebsiteUrl = 'https://www.manavivaahavedika.in';

  /// Digits-only E.164 without '+' for [wa.me](https://wa.me) links.
  static const String supportPhoneWaMe = '918985936678';

  static Uri get whatsAppSupportUri =>
      Uri.parse('https://wa.me/$supportPhoneWaMe');

  static Uri get supportWebsiteUri => Uri.parse(supportWebsiteUrl);

  /// Single-line footer for Terms, Privacy, About, etc.
  static String get contactFooterEn =>
      'Email: $supportEmail · Website: $supportWebsiteDisplay · WhatsApp: $supportPhoneDisplay';

  static String get contactFooterTe =>
      'ఇమెయిల్: $supportEmail · వెబ్‌సైట్: $supportWebsiteDisplay · WhatsApp: $supportPhoneDisplay';

  /// Multi-line block for refund / payment policy contact sections.
  static String get contactBlockEn => '''
Email: $supportEmail
Website: $supportWebsiteDisplay
Phone / WhatsApp: $supportPhoneDisplay''';

  static String get contactBlockTe => '''
ఇమెయిల్: $supportEmail
వెబ్‌సైట్: $supportWebsiteDisplay
ఫోన్ / WhatsApp: $supportPhoneDisplay''';

  static Future<void> openWhatsAppSupport(BuildContext context) async {
    await _launch(context, whatsAppSupportUri, 'Could not open WhatsApp chat.');
  }

  static Future<void> openSupportEmail(
    BuildContext context, {
    String subject = 'Support Request - Mana Vivaaha Vedika',
    String body =
        'Please describe your issue or question here...\n\nApp Version: 1.0.0',
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    await _launch(
      context,
      uri,
      'Could not open email client. Please make sure you have an email app installed.',
    );
  }

  static Future<void> openWebsite(BuildContext context) async {
    await _launch(
      context,
      supportWebsiteUri,
      'Could not open the website.',
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
