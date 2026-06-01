import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_sound_service.dart';
import '../models/user.dart';

/// Utility functions for contact actions (phone call, WhatsApp)
class ContactUtils {

  /// Make a phone call — opens the system dialler pre-filled with the number.
  /// Uses [LaunchMode.externalApplication] so Android always opens the dialler
  /// directly instead of showing an app-chooser sheet.
  static Future<void> makePhoneCall(String phoneNumber) async {
    debugPrint('📞 makePhoneCall: Starting with number: "$phoneNumber"');
    
    // Strip everything except digits and leading +
    final clean = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    debugPrint('📞 makePhoneCall: Cleaned number: "$clean"');
    
    if (clean.isEmpty) {
      debugPrint('⚠️ makePhoneCall: empty number after cleaning');
      return;
    }
    
    final uri = Uri(scheme: 'tel', path: clean);
    debugPrint('📞 makePhoneCall: Created URI: $uri');
    
    try {
      final canLaunch = await canLaunchUrl(uri);
      debugPrint('📞 makePhoneCall: canLaunchUrl result: $canLaunch');
      
      if (!canLaunch) {
        debugPrint('⚠️ makePhoneCall: canLaunchUrl returned false for $uri');
        debugPrint('⚠️ This might be due to missing permissions or no dialer app');
        return;
      }
      
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('📞 makePhoneCall: launchUrl result: $launched');
      
      if (launched) {
        debugPrint('✅ makePhoneCall: Successfully launched dialer for $clean');
      } else {
        debugPrint('❌ makePhoneCall: Failed to launch dialer for $clean');
      }
    } catch (e) {
      debugPrint('❌ makePhoneCall error: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Open WhatsApp with phone number.
  /// Automatically adds India country code (91) if the number is 10 digits.
  static Future<void> openWhatsApp(String phoneNumber, {String? message}) async {
    var clean = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.startsWith('+')) clean = clean.substring(1);

    final String whatsappNumber;
    if (clean.length == 10) {
      whatsappNumber = '91$clean';
    } else if (clean.startsWith('91') && clean.length == 12) {
      whatsappNumber = clean;
    } else {
      whatsappNumber = clean;
    }

    final messageText = message ?? '''Hello,

I came across your profile on Mana Brahmin Vivaaha Vedika and would like to know more about you and your family. If you are interested, please feel free to contact me.

Thank you.''';

    final uri = Uri.parse(
      'https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(messageText)}',
    );

    try {
      NotificationSoundService.playInterestSentSound();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ openWhatsApp error: $e');
      rethrow;
    }
  }

  /// Send interest via WhatsApp to a matched profile.
  /// This sends an interest message, not direct contact with the user.
  static Future<void> sendInterestViaWhatsApp({
    required String phoneNumber,
    required String profileId,
    required String profileName,
    String? requesterName,
    String? requesterProfileId,
  }) async {
    final message = '''
🙏 *MANA BRAHMIN Vivaaha Vedika*

Hello $profileName,

I came across your profile on Mana Brahmin Vivaaha Vedika and am interested in knowing more about you and your family.

${requesterName != null ? '''
*My Details:*
━━━━━━━━━━━━━━━━━━
📋 Profile ID: $requesterProfileId
👤 Name: $requesterName
''' : ''}I have sent you an interest request through the app. If you are interested, please accept my request so we can connect further.

Looking forward to your response.

Thank you.
''';
    await openWhatsApp(phoneNumber, message: message);
  }

  /// Share profile via WhatsApp with a formatted message.
  static Future<void> shareProfileViaWhatsApp({
    required String phoneNumber,
    required String profileId,
    required String profileName,
    required String profileDetails,
    String? requesterName,
    String? requesterProfileId,
  }) async {
    final message = '''
🙏 *MANA BRAHMIN Vivaaha Vedika*

Hello,

I came across your profile on Mana Brahmin Vivaaha Vedika and would like to know more about you and your family.

*Profile Details:*
━━━━━━━━━━━━━━━━━━
📋 Profile ID: $profileId
👤 Name: $profileName
$profileDetails
${requesterName != null ? '''
*My Details:*
━━━━━━━━━━━━━━━━━━
📋 Profile ID: $requesterProfileId
👤 Name: $requesterName
''' : ''}━━━━━━━━━━━━━━━━━━
If you are interested, please feel free to contact me. Looking forward to hearing from you.

Thank you.
''';
    await openWhatsApp(phoneNumber, message: message);
  }

  /// Show contact request dialog
  static void showContactRequestDialog(BuildContext context, UserProfile profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Request'),
        content: Text(
          'Would you like to send an interest to ${profile.firstName} ${profile.lastName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Interest feature available from profile view'),
                ),
              );
            },
            child: const Text('Send Interest'),
          ),
        ],
      ),
    );
  }
}
