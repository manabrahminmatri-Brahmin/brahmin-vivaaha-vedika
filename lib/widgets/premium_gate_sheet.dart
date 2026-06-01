import 'package:flutter/material.dart';
import '../core/app_router.dart';
import '../theme/app_theme.dart';

/// Trigger types — controls the headline & body copy shown in the gate sheet.
enum PremiumGateTrigger {
  sendInterest,      // free user tapped "Send Interest"
  liked,         // free user tapped "Like"
  contactProfile,    // free user tried to call / message
  receivedInterest,  // free user received interest and wants to reply/contact
  likedYou,    // free user sees someone liked them
}

/// Shows a bottom-sheet premium upsell when a free user hits a locked feature.
///
/// Returns `true` if the user successfully upgraded (navigated to upgrade screen),
/// `false` / `null` if they dismissed.
Future<bool?> showPremiumGateSheet(
  BuildContext context, {
  required PremiumGateTrigger trigger,
  String? personName, // optional — personalises the copy
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumGateSheet(trigger: trigger, personName: personName),
  );
}

class _PremiumGateSheet extends StatelessWidget {
  final PremiumGateTrigger trigger;
  final String? personName;

  const _PremiumGateSheet({required this.trigger, this.personName});

  // ── Copy per trigger ──────────────────────────────────────────────

  IconData get _icon {
    switch (trigger) {
      case PremiumGateTrigger.sendInterest:      return Icons.favorite;
      case PremiumGateTrigger.liked:         return Icons.favorite;
      case PremiumGateTrigger.contactProfile:    return Icons.call;
      case PremiumGateTrigger.receivedInterest:  return Icons.mark_email_read;
      case PremiumGateTrigger.likedYou:    return Icons.star_rounded;
    }
  }

  String get _headline {
    final name = personName?.isNotEmpty == true ? personName! : 'someone';
    switch (trigger) {
      case PremiumGateTrigger.sendInterest:
        return '💌 Show Your Interest';
      case PremiumGateTrigger.liked:
        return '❤️ Like Profile';
      case PremiumGateTrigger.contactProfile:
        return '📞 Contact $name';
      case PremiumGateTrigger.receivedInterest:
        return '💛 $name Liked Your Profile!';
      case PremiumGateTrigger.likedYou:
        return '⭐ $name Liked You!';
    }
  }

  String get _body {
    final name = personName?.isNotEmpty == true ? personName! : 'this person';
    switch (trigger) {
      case PremiumGateTrigger.sendInterest:
        return 'Upgrade to Platinum to send interests and connect with matches directly.';
      case PremiumGateTrigger.liked:
        return 'Upgrade to Platinum to like profiles and revisit them anytime.';
      case PremiumGateTrigger.contactProfile:
        return 'Upgrade to Platinum to view contact details, call, or WhatsApp $name directly.';
      case PremiumGateTrigger.receivedInterest:
        return '$name has shown interest in your profile. Upgrade to Platinum to accept, contact, and start your journey together!';
      case PremiumGateTrigger.likedYou:
        return '$name has liked your profile. Upgrade to Platinum to reach out and connect!';
    }
  }

  // Key benefits to show in the sheet
  static const _benefits = [
    ('Send & receive unlimited interests', Icons.favorite_outline),
    ('Contact matches directly via call & WhatsApp', Icons.call_outlined),
    ('View full contact details', Icons.contact_phone_outlined),
    ('Like profiles', Icons.favorite_border),
    ('Priority profile visibility', Icons.trending_up_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(80),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Crown + gradient badge
        Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGold.withAlpha(80),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(_icon, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),

        // "Platinum Members Only" pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            '✦ PLATINUM MEMBERS ONLY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Headline
        Text(
          _headline,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),

        // Body copy
        Text(
          _body,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Benefits list
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
          ),
          child: Column(
            children: _benefits.map((b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGold.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(b.$2, size: 14, color: const Color(0xFFC8860A)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(b.$1,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              ]),
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),

        // Price hint
        Text(
          'Starting at just ₹99/month',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 20),

        // CTA button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true); // close sheet
              NavHelper.push(context, Routes.premiumUpgrade);
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.workspace_premium, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Upgrade to Platinum',
                      style: TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Maybe later
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Maybe later',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ),
      ]),
    );
  }
}
