import 'package:flutter/material.dart';
import '../../core/support_links.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/whatsapp_channel_card.dart';

enum _PolicyLang { english, telugu }

/// Payment & Refund Policy — bilingual (EN/TE), same layout as [TermsScreen].
/// Shown in Settings/About and linked before in-app payments (Play policy alignment).
class PaymentRefundPolicyScreen extends StatefulWidget {
  const PaymentRefundPolicyScreen({super.key});

  @override
  State<PaymentRefundPolicyScreen> createState() =>
      _PaymentRefundPolicyScreenState();
}

class _PaymentRefundPolicyScreenState extends State<PaymentRefundPolicyScreen> {
  _PolicyLang _lang = _PolicyLang.english;

  Map<String, Map<String, String>> get _content => {
        'title': {
          'english': 'Payment & Refund Policy',
          'telugu': 'చెల్లింపు & రీఫండ్ విధానం',
        },
        'lastUpdated': {
          'english': 'Last updated: April 2026',
          'telugu': 'చివరిగా నవీకరించబడింది: ఏప్రిల్ 2026',
        },
        'header': {
          'english':
              'Please read this policy in your preferred language before making a payment.',
          'telugu':
              'చెల్లింపు చేయడానికి ముందు ఈ విధానాన్ని మీ భాషలో చదవండి.',
        },
        'acknowledgment': {
          'english':
              'By making a payment or purchasing membership through this app, you acknowledge that you have read and agree to this Payment & Refund Policy.',
          'telugu':
              'ఈ అనువర్తనం ద్వారా చెల్లింపు లేదా సభ్యత్వం కొనుగోలు చేయడం ద్వారా, మీరు ఈ చెల్లింపు & రీఫండ్ విధానాన్ని చదివినట్లు మరియు అంగీకరించినట్లు గుర్తిస్తారు.',
        },
        'section1_title': {
          'english': 'Membership & Payment',
          'telugu': 'సభ్యత్వం & చెల్లింపు',
        },
        'section1_body': {
          'english': '''
• This platform offers both free and paid membership plans.
• Paid memberships provide premium features such as viewing contact details, priority listing, messaging, and profile visibility.
• Payments must be made via RBI-approved methods (UPI, Debit/Credit Card, Net Banking, Wallets).
• Premium access is activated automatically after your payment successfully completes and is confirmed by the system—typically within a short time, without manual approval in the app.
''',
          'telugu': '''
• ఈ ప్లాట్‌ఫారమ్‌లో ఉచిత మరియు చెల్లింపు సభ్యత్వ ప్లాన్‌లు ఉన్నాయి.
• చెల్లింపు సభ్యత్వం ద్వారా కాంటాక్ట్ వివరాలు, ప్రాధాన్యత లిస్టింగ్, మెసేజింగ్, ప్రొఫైల్ విజిబిలిటీ వంటి ప్రీమియం సదుపాయాలు లభిస్తాయి.
• చెల్లింపులు UPI, డెబిట్/క్రెడిట్ కార్డులు, నెట్ బ్యాంకింగ్, వాలెట్‌లు వంటి RBI ఆమోదిత పద్ధతుల్లో చేయాలి.
• చెల్లింపు విజయవంతంగా పూర్తై సిస్టమ్ ద్వారా ధృవీకరించబడిన తర్వాత ప్రీమియం యాక్సెస్ ఆటోమేటిక్‌గా సక్రియం అవుతుంది — సాధారణంగా కొద్ది సమయంలో; యాప్‌లో మానవ అనుమోదం అవసరం లేదు.
''',
        },
        'section2_title': {
          'english': 'Nature of Service',
          'telugu': 'సేవ యొక్క స్వభావం',
        },
        'section2_body': {
          'english': '''
• The platform acts only as an intermediary to connect individuals.
• We do not guarantee marriage, matchmaking success, or response from other users.
• Payment is for access to features/services, not for guaranteed results.
''',
          'telugu': '''
• ఈ ప్లాట్‌ఫారమ్ వ్యక్తులను కలిపే మధ్యవర్తిగా మాత్రమే పనిచేస్తుంది.
• వివాహం, మ్యాచ్ విజయం లేదా ఇతర వినియోగదారుల స్పందనకు హామీ ఇవ్వబడదు.
• చెల్లింపు ఫలితానికి కాదు — ప్లాట్‌ఫారమ్ ఫీచర్లు/సేవల యాక్సెస్‌కు మాత్రమే.
''',
        },
        'section3_title': {
          'english': 'No Refund Policy',
          'telugu': 'రీఫండ్ లేదు (No Refund)',
        },
        'section3_body': {
          'english': '''
• All payments made for membership plans are non-refundable and non-transferable.
• Once a membership is activated, no refund will be provided under any circumstances.
''',
          'telugu': '''
• సభ్యత్వ ప్లాన్‌లకు చేసిన చెల్లింపులు తిరిగి ఇవ్వబడవు మరియు ఇతరులకు బదిలీ చేయబడవు.
• సభ్యత్వం యాక్టివేట్ అయిన తర్వాత ఏ సందర్భంలోనూ రీఫండ్ ఇవ్వబడదు.
''',
        },
        'section4_title': {
          'english': 'Exceptions (Limited Cases)',
          'telugu': 'మినహాయింపులు (ప్రత్యేక సందర్భాలు)',
        },
        'section4_body': {
          'english': '''
Refunds may be considered only if:
• Duplicate payment due to technical error.
• Payment deducted but membership not activated.
• Unauthorized transaction reported immediately.

Note: Refund requests must be raised within 3–5 days of the transaction.
''',
          'telugu': '''
క్రింది సందర్భాల్లో మాత్రమే రీఫండ్ పరిగణించబడుతుంది:
• టెక్నికల్ లోపం వల్ల డూప్లికేట్ చెల్లింపు జరిగితే.
• చెల్లింపు కట్ అయినా సభ్యత్వం యాక్టివేట్ కాకపోతే.
• అనధికార లావాదేవీ వెంటనే నివేదించబడితే.

గమనిక: లావాదేవీ తేదీ నుండి 3–5 రోజుల లోపు రీఫండ్ అభ్యర్థన చేయాలి.
''',
        },
        'section5_title': {
          'english': 'Auto-Renewal (If Applicable)',
          'telugu': 'ఆటో రిన్యూవల్ (వర్తిస్తే)',
        },
        'section5_body': {
          'english': '''
• Some plans may auto-renew unless canceled before the expiry date.
• Users are responsible for disabling auto-renewal in their app store or payment settings.
• No refunds will be issued for auto-renewed subscriptions.
''',
          'telugu': '''
• కొన్ని ప్లాన్‌లు గడువు ముందు రద్దు చేయకపోతే ఆటోమేటిక్‌గా రిన్యూ కావచ్చు.
• ఆటో రిన్యూవల్ నిలిపివేయడం వినియోగదారి బాధ్యత (యాప్ స్టోర్/చెల్లింపు సెట్టింగ్‌లు).
• ఆటో రిన్యూవల్‌కు రీఫండ్ ఇవ్వబడదు.
''',
        },
        'section6_title': {
          'english': 'Cancellation Policy',
          'telugu': 'రద్దు విధానం',
        },
        'section6_body': {
          'english': '''
• Users may cancel membership anytime subject to store/platform rules.
• Cancellation will stop future billing but will not result in a refund for the current billing period.
''',
          'telugu': '''
• స్టోర్/ప్లాట్‌ఫారమ్ నిబంధనల ప్రకారం ఎప్పుడైనా సభ్యత్వాన్ని రద్దు చేయవచ్చు.
• రద్దు చేసినా భవిష్యత్ బిల్లింగ్ ఆగుతుంది; ప్రస్తుత బిల్లింగ్ కాలానికి రీఫండ్ ఉండదు.
''',
        },
        'section7_title': {
          'english': 'Profile Removal / Termination',
          'telugu': 'ప్రొఫైల్ తొలగింపు / ముగింపు',
        },
        'section7_body': {
          'english': '''
• If a profile is removed due to violation of terms, no refund will be issued.
• Misuse, fake profiles, or policy violations may lead to suspension without refund.
''',
          'telugu': '''
• నిబంధనల ఉల్లంఘన వల్ల ప్రొఫైల్ తొలగించబడితే రీఫండ్ ఇవ్వబడదు.
• దుర్వినియోగం, నకిలీ ప్రొఫైల్‌లు లేదా విధాన ఉల్లంఘనలకు సస్పెన్షన్ — రీఫండ్ లేదు.
''',
        },
        'section8_title': {
          'english': 'Pricing & Taxes',
          'telugu': 'ధరలు & పన్నులు',
        },
        'section8_body': {
          'english': '''
• All prices are in INR (₹), inclusive or exclusive of GST as stated at checkout or in the app.
• Prices may change without prior notice; applicable taxes follow Indian law.
''',
          'telugu': '''
• ధరలు INR (₹)లో ఉంటాయి; చెక్‌అవుట్/యాప్‌లో పేర్కొన్న విధంగా GST సహా లేదా ప్రత్యేకం.
• ధరలు ముందు హెచ్చరిక లేకుండా మారవచ్చు; పన్నులు భారత చట్టాల ప్రకారం.
''',
        },
        'section9_title': {
          'english': 'Dispute Resolution',
          'telugu': 'వివాద పరిష్కారం',
        },
        'section9_body': {
          'english': '''
• Any disputes will be handled as per Indian laws and RBI digital payment guidelines.
• Jurisdiction: Eluru, Andhra Pradesh, India.
''',
          'telugu': '''
• వివాదాలు భారత చట్టాలు మరియు RBI డిజిటల్ చెల్లింపు మార్గదర్శకాల ప్రకారం పరిష్కరించబడతాయి.
• న్యాయ అధికార పరిధి: ఏలూరు, ఆంధ్రప్రదేశ్, భారతదేశం.
''',
        },
        'section10_title': {
          'english': 'Contact',
          'telugu': 'సంప్రదింపు',
        },
        'section10_body': {
          'english': '''
For payment-related queries:

• Service: mana Vivaaha Vedika
• Phone / WhatsApp: ${SupportLinks.supportPhoneDisplay}
• WhatsApp Channel: ${SupportLinks.whatsAppChannelUrl}
''',
          'telugu': '''
చెల్లింపు మరియు రీఫండ్ సంబంధిత ప్రశ్నలకు:

• సేవా పేరు: మన వివాహ వేదిక
• ఫోన్ / WhatsApp: ${SupportLinks.supportPhoneDisplay}
• WhatsApp Channel: ${SupportLinks.whatsAppChannelUrl}
''',
        },
      };

  String _t(String key) {
    final k = _lang == _PolicyLang.english ? 'english' : 'telugu';
    return _content[key]?[k] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(title: _t('title')),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.payments_rounded,
                      color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _lang == _PolicyLang.telugu
                        ? 'మన వివాహ వేదిక'
                        : 'mana Vivaaha Vedika',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('lastUpdated'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _t('header'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.peacockBlue.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.peacockBlue.withAlpha(30)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _langChip(_PolicyLang.english, 'English'),
                  const SizedBox(width: 16),
                  _langChip(_PolicyLang.telugu, 'తెలుగు'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 1; i <= 10; i++)
              _section(
                context,
                number: '$i',
                title: _t('section${i}_title'),
                body: _t('section${i}_body'),
              ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.sacredGreen.withAlpha(50)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.verified_outlined,
                      color: AppTheme.sacredGreen, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    _t('acknowledgment'),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const WhatsAppChannelCard(compact: true),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _langChip(_PolicyLang lang, String label) {
    final sel = _lang == lang;
    return InkWell(
      onTap: () => setState(() => _lang = lang),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primaryOrange : Colors.white.withAlpha(200),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? AppTheme.primaryOrange : AppTheme.primaryOrange.withAlpha(150),
            width: sel ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: sel
                  ? AppTheme.primaryOrange.withAlpha(50)
                  : Colors.black.withAlpha(20),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : AppTheme.primaryOrange,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String number,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AC.text(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
