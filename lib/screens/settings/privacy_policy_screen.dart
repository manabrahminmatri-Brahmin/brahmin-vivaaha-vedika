import 'package:flutter/material.dart';

import '../../core/support_links.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../utils/app_animations.dart';

enum Language { english, telugu }

/// Privacy Policy screen
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  Language _selectedLanguage = Language.english;

  Map<String, Map<String, String>> get _content {
    return {
      'title': {
        'english': 'Privacy Policy',
        'telugu': 'గోప్యతా విధానం',
      },
      'subtitle': {
        'english': 'Your privacy is our priority',
        'telugu': 'మీ గోప్యత మా ప్రాధాన్యత',
      },
      'header': {
        'english': 'Please read our privacy policy in your preferred language',
        'telugu': 'దయచేసి మీ అభిమత భాషలో మా గోప్యతా విధానాన్ని చదవండి',
      },
      'intro_title': {
        'english': 'Introduction',
        'telugu': 'పరిచయం',
      },
      'intro_content': {
        'english': 'At mana Vivaaha Vedika, we are committed to protecting your personal information and ensuring your privacy. This Privacy Policy explains how we collect, use, and protect your data when you use our Vivaaha Vedika service.',
        'telugu': 'మన వివాహ వేదికలో, మేము మీ వ్యక్తిగత సమాచారాన్ని రక్షించడానికి మరియు మీ గోప్యతను నిర్ధారించడానికి అంకితమైనాము. ఈ గోప్యతా విధానం మీరు మా వివాహ వేదిక సేవను ఉపయోగించినప్పుడు మేము మీ డేటాను ఎలా సేకరిస్తాము, ఉపయోగిస్తాము మరియు రక్షిస్తామో వివరిస్తుంది.',
      },
      'collect_title': {
        'english': 'Information We Collect',
        'telugu': 'మేము సేకరించే సమాచారం',
      },
      'collect_content': {
        'english': '• Personal Information: Name, age, gender, education, profession\n• Contact Information: Mobile number, email address\n• Profile Information: Photos, horoscope details, family details\n• Usage Information: App usage patterns, preferences\n• Location Information: General location for matching purposes',
        'telugu': '• వ్యక్తిగత సమాచారం: పేరు, వయస్సు, లింగం, విద్య, వృత్తి\n• సంప్రదింపు సమాచారం: మొబైల్ నంబర్, ఇమెయిల్ చిరునామా\n• ప్రొఫైల్ సమాచారం: ఫోటోలు, జాతక వివరాలు, కుటుంబ వివరాలు\n• వినియోగ సమాచారం: అనువర్తన వినియోగ నమూనాలు, ప్రాధాన్యతలు\n• స్థాన సమాచారం: సరిపోలిక ప్రయోజనాల కోసం సాధారణ స్థానం',
      },
      'use_title': {
        'english': 'How We Use Your Information',
        'telugu': 'మేము మీ సమాచారాన్ని ఎలా ఉపయోగిస్తాము',
      },
      'use_content': {
        'english': '• To provide and maintain our Vivaaha Vedika service\n• To match profiles based on preferences and compatibility\n• To communicate with users about service updates\n• To ensure platform security and prevent fraud\n• To improve our services and user experience\n• To comply with legal requirements',
        'telugu': '• మా వివాహ వేదిక సేవను అందించడానికి మరియు నిర్వహించడానికి\n• ప్రాధాన్యతలు మరియు అనుకూలత ఆధారంగా ప్రొఫైళ్లను సరిపోల్చడానికి\n• సేవా నవీకరణల గురించి వినియోగదారులతో సంభాషించడానికి\n• ప్లాట్‌ఫారమ్ భద్రతను నిర్ధారించడానికి మరియు మోసాన్ని నివారించడానికి\n• మా సేవలు మరియు వినియోగదారు అనుభవాన్ని మెరుగుపరచడానికి\n• చట్టపరమైన అవసరాలకు అనుగుణంగా ఉండటానికి',
      },
      'share_title': {
        'english': 'Information Sharing',
        'telugu': 'సమాచార భాగస్వామ్యం',
      },
      'share_content': {
        'english': '• Your profile is visible to other registered members\n• Contact information is shared only with mutual interest\n• We do not sell your personal information to third parties\n• Family members may manage profiles with user consent\n• Information may be shared for legal compliance purposes',
        'telugu': '• మీ ప్రొఫైల్ ఇతర నమోదైన సభ్యులకు కనిపిస్తుంది\n• సంప్రదింపు సమాచారం పరస్పర ఆసక్తితో మాత్రమే పంచుకోబడుతుంది\n• మేము మీ వ్యక్తిగత సమాచారాన్ని మూడవ పక్షాలకు అమ్మము\n• కుటుంబ సభ్యులు వినియోగదారు అంగీకారంతో ప్రొఫైళ్లను నిర్వహించవచ్చు\n• చట్టపరమైన అనుగుణత ప్రయోజనాల కోసం సమాచారం పంచుకోబడవచ్చు',
      },
      'visibility_title': {
        'english': 'Profile Visibility',
        'telugu': 'ప్రొఫైల్ దృశ్యమానత',
      },
      'visibility_content': {
        'english': '• You can control who sees your profile\n• Photos can be set as private and shared on request\n• Profile can be temporarily hidden\n• Premium members have enhanced visibility controls\n• Blocked users cannot see your profile',
        'telugu': '• మీరు మీ ప్రొఫైల్‌ను ఎవరు చూస్తారో నియంత్రించవచ్చు\n• ఫోటోలను ప్రైవేట్‌గా సెట్ చేయవచ్చు మరియు అభ్యర్థనపై పంచుకోవచ్చు\n• ప్రొఫైల్‌ను తాత్కాలికంగా దాచవచ్చు\n• ప్రీమియం సభ్యులకు మెరుగైన దృశ్యమానత నియంత్రణలు ఉన్నాయి\n• బ్లాక్ చేసిన వినియోగదారులు మీ ప్రొఫైల్‌ను చూడలేరు',
      },
      'security_title': {
        'english': 'Data Security',
        'telugu': 'డేటా భద్రత',
      },
      'security_content': {
        'english': '• All data is encrypted during transmission\n• Secure MPIN authentication for account access\n• Regular security audits and updates\n• Limited access to user data by authorized personnel\n• Compliance with data protection regulations',
        'telugu': '• అన్ని డేటా ప్రసారం సమయంలో గూఢీకరించబడుతుంది\n• ఖాతా ప్రవేశం కోసం సురక్షిత MPIN ధృవీకరణ\n• నియమిత భద్రతా ఆడిట్‌లు మరియు నవీకరణలు\n• అధీకృత సిబ్బంది ద్వారా వినియోగదారు డేటాకు పరిమిత ప్రవేశం\n• డేటా రక్షణ నిబంధనలకు అనుగుణత',
      },
      'retention_title': {
        'english': 'Data Retention',
        'telugu': 'డేటా నిలుపుదల',
      },
      'retention_content': {
        'english': '• Data is retained as long as your account is active\n• Deleted accounts are removed within \n• Some data may be retained for legal compliance\n• You can request data deletion at any time\n• Backup data is securely stored and regularly updated',
        'telugu': '• మీ ఖాతా చురుకుగా ఉన్నంత వరకు డేటా నిలుపుకోబడుతుంది\n• తొలగించిన ఖాతాలు 30 రోజులలోపు తీసివేయబడతాయి\n• కొన్ని డేటా చట్టపరమైన అనుగుణత కోసం నిలుపుకోబడవచ్చు\n• మీరు ఎప్పుడైనా డేటా తొలగింపును అభ్యర్థించవచ్చు\n• బ్యాకప్ డేటా సురక్షితంగా నిల్వ చేయబడుతుంది మరియు క్రమం తప్పకుండా నవీకరించబడుతుంది',
      },
      'rights_title': {
        'english': 'Your Rights',
        'telugu': 'మీ హక్కులు',
      },
      'rights_content': {
        'english': '• Access to your personal information\n• Correction of inaccurate information\n• Deletion of your account and data\n• Opt-out of marketing communications\n• Restriction of data processing\n• Data portability requests',
        'telugu': '• మీ వ్యక్తిగత సమాచారానికి ప్రవేశం\n• అసలు సమాచారాన్ని సరిదిద్దడం\n• మీ ఖాతా మరియు డేటాను తొలగించడం\n• మార్కెటింగ్ సంభాషణల నుండి నిష్క్రమించడం\n• డేటా ప్రాసెసింగ్‌ను పరిమితం చేయడం\n• డేటా పోర్టబిలిటీ అభ్యర్థనలు',
      },
      'children_title': {
        'english': 'Children\'s Privacy',
        'telugu': 'పిల్లల గోప్యత',
      },
      'children_content': {
        'english': 'Our service is not intended for children under 18. We do not knowingly collect personal information from children. If we become aware of such information, we will delete it immediately.',
        'telugu': 'మా సేవ 18 సంవత్సరాల కంటే తక్కువ వయస్సు గల పిల్లల కోసం ఉద్దేశించబడలేదు. మేము తెలిసీ తెలియని పిల్లల నుండి వ్యక్తిగత సమాచారాన్ని సేకరించము. మేము అటువంటి సమాచారాన్ని గుర్తించినట్లయితే, దానిని వెంటనే తొలగిస్తాము.',
      },
      'updates_title': {
        'english': 'Policy Updates',
        'telugu': 'విధానం నవీకరణలు',
      },
      'updates_content': {
        'english': 'We may update this privacy policy from time to time. Changes will be communicated through the app or email. Continued use of the service constitutes acceptance of the updated policy.',
        'telugu': 'మేము ఈ గోప్యతా విధానాన్ని సమయానుసారంగా నవీకరించవచ్చు. మార్పులు అనువర్తనం లేదా ఇమెయిల్ ద్వారా తెలియజేయబడతాయి. సేవను కొనసాగించడం నవీకరించబడిన విధానాన్ని అంగీకరించడానికి సమానం.',
      },
      'contact_title': {
        'english': 'Contact Information',
        'telugu': 'సంప్రదింపు సమాచారం',
      },
      'contact_content': {
        'english':
            'If you have questions about this Privacy Policy or want to exercise your rights, please contact us:\n\n${SupportLinks.contactBlockEn}',
        'telugu':
            'ఈ గోప్యతా విధానం గురించి మీకు ప్రశ్నలు ఉంటే లేదా మీ హక్కులను అమలు చేయాలనుకుంటే, దయచేసి మమ్మలను సంప్రదించండి:\n\n${SupportLinks.contactBlockTe}',
      },
      'lastUpdated': {
        'english': 'Last Updated: December 2025',
        'telugu': 'చివరిగా నవీకరించబడింది: డిసెంబర్ 2025',
      },
      'footer': {
        'english': 'By using mana Vivaaha Vedika, you acknowledge that you have read, understood, and agree to this Privacy Policy.',
        'telugu': 'మన వివాహ వేదికను ఉపయోగించడం ద్వారా, మీరు ఈ గోప్యతా విధానాన్ని చదివినట్లు, అర్థం చేసుకున్నట్లు మరియు అంగీకరించినట్లు గుర్తిస్తారు.',
      },
    };
  }

  String _getText(String key) {
    final langKey = _selectedLanguage == Language.english ? 'english' : 'telugu';
    return _content[key]?[langKey] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: _getText('title'),
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.security, color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    _getText('title'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getText('subtitle'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AC.card(context).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getText('header'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ).appSlideIn(),

            SizedBox(height: 24),

            // Language Toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.peacockBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.peacockBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLanguageButton('English', Language.english),
                  const SizedBox(width: 16),
                  _buildLanguageButton('తెలుగు', Language.telugu),
                ],
              ),
            ).appFadeIn(delay: Duration(milliseconds: 100)),

            const SizedBox(height: 24),

            // Sections
            _buildSection(
              title: _getText('intro_title'),
              content: _getText('intro_content'),
            ).appFadeIn(delay: Duration(milliseconds: 200)),

            _buildSection(
              title: _getText('collect_title'),
              content: _getText('collect_content'),
            ).appFadeIn(delay: Duration(milliseconds: 300)),

            _buildSection(
              title: _getText('use_title'),
              content: _getText('use_content'),
            ).appFadeIn(delay: Duration(milliseconds: 400)),

            _buildSection(
              title: _getText('share_title'),
              content: _getText('share_content'),
            ).appFadeIn(delay: Duration(milliseconds: 500)),

            _buildSection(
              title: _getText('visibility_title'),
              content: _getText('visibility_content'),
            ).appFadeIn(delay: Duration(milliseconds: 600)),

            _buildSection(
              title: _getText('security_title'),
              content: _getText('security_content'),
            ).appFadeIn(delay: Duration(milliseconds: 700)),

            _buildSection(
              title: _getText('retention_title'),
              content: _getText('retention_content'),
            ).appFadeIn(delay: Duration(milliseconds: 800)),

            _buildSection(
              title: _getText('rights_title'),
              content: _getText('rights_content'),
            ).appFadeIn(delay: Duration(milliseconds: 900)),

            _buildSection(
              title: _getText('children_title'),
              content: _getText('children_content'),
            ).appFadeIn(delay: Duration(milliseconds: 1000)),

            _buildSection(
              title: _getText('updates_title'),
              content: _getText('updates_content'),
            ).appFadeIn(delay: Duration(milliseconds: 1100)),

            _buildSection(
              title: _getText('contact_title'),
              content: _getText('contact_content'),
            ).appFadeIn(delay: Duration(milliseconds: 1200)),

            const SizedBox(height: 32),

            // Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AC.textMuted(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _getText('lastUpdated'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getText('footer'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AC.text(context),
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ).appFadeIn(delay: Duration(milliseconds: 1300)),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageButton(String label, Language language) {
    final isSelected = _selectedLanguage == language;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLanguage = language;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryOrange : AppTheme.peacockBlue,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: isSelected ? Colors.white : AppTheme.peacockBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AC.text(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          SizedBox(height: 16),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AC.textSub(context),
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
