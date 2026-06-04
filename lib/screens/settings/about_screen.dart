import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../utils/app_animations.dart';
import '../../core/support_links.dart';
import '../../utils/app_version.dart';

enum Language { english, telugu }

/// About mana Vivaaha Vedika screen
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Language _selectedLanguage = Language.english;

  Map<String, Map<String, String>> get _content {
    return {
      'brandName': {
        'english': 'mana Vivaaha Vedika',
        'telugu': 'మన వివాహ వేదిక',
      },
      'title': {
        'english': 'About mana Vivaaha Vedika',
        'telugu': 'మన వివాహ వేదిక గురించి',
      },
      'tag': {
        'english': 'Connecting Brahmin Hearts',
        'telugu': 'బ్రాహ్మణ హృదయాలను అనుసంధానిస్తున్నది',
      },
      'version': {
        'english': AppVersion.displayVersion,
        'telugu': AppVersion.displayVersionTelugu,
      },
      'aboutTitle': {
        'english': 'Our Mission',
        'telugu': 'మన లక్ష్యం',
      },
      'aboutContent': {
        'english': 'mana Vivaaha Vedika is dedicated to helping Brahmin families find suitable matches while preserving our cultural values and traditions. We understand the importance of compatibility, family values, and cultural alignment in marriage alliances.',
        'telugu': 'మన వివాహ వేదిక బ్రాహ్మణ కుటుంబాలకు తగిన వివాహ పక్షాలను కనుగొనడంలో సహాయపడటానికి అంకితమైంది; అదేవిధంగా మన సాంస్కృతిక విలువలు, సంప్రదాయాలను కాపాడుతూ. వివాహ బంధాలలో అనుకూలత, కుటుంబ విలువలు మరియు సాంస్కృతిక సమన్వయం యొక్క ముఖ్యతను మేము గ్రహిస్తాము.',
      },
      'valuesTitle': {
        'english': 'Our Values',
        'telugu': 'మన విలువలు',
      },
      'valuesContent': {
        'english': '• Cultural Preservation\n• Family-Centric Approach\n• Privacy & Security\n• Authentic Profiles\n• Traditional Values with Modern Convenience',
        'telugu': '• సాంస్కృతిక సంరక్షణ\n• కుటుంబ-కేంద్రిత విధానం\n• గోప్యత మరియు భద్రత\n• నిజాయితీ ప్రొఫైళ్లు\n• ఆధునిక సౌలభ్యంతో సంప్రదాయ విలువలు',
      },
      'featuresTitle': {
        'english': 'Key Features',
        'telugu': 'ప్రధాన లక్షణాలు',
      },
      'featuresContent': {
        'english': '• Ashtakoot Compatibility Matching\n• Secure MPIN Authentication\n• Family-Managed Profiles\n• Privacy Controls\n• Direct Communication\n• Mobile OTP Verification',
        'telugu': '• అష్టకూట అనుకూలత సరిపోలిక\n• సురక్షిత MPIN ధృవీకరణ\n• కుటుంబ-నిర్వహిత ప్రొఫైళ్లు\n• గోప్యత నియంత్రణలు\n• నేరుగా సంభాషణ\n• మొబైల్ OTP ధృవీకరణ',
      },
      'contactTitle': {
        'english': 'Contact Us',
        'telugu': 'మమ్మలను సంప్రదించండి',
      },
      'contactContent': {
        'english':
            'For any queries, support, or feedback, please reach out to us.\n\n${SupportLinks.contactBlockEn}',
        'telugu':
            'ఏవైనా ప్రశ్నలు, మద్దతు లేదా అభిప్రాయం కోసం, దయచేసి మమ్మలను సంప్రదించండి.\n\n${SupportLinks.contactBlockTe}',
      },
      'websiteButton': {
        'english': 'Visit Website',
        'telugu': 'వెబ్‌సైట్ చూడండి',
      },
      'emailButton': {
        'english': 'Email Us',
        'telugu': 'ఇమెయిల్ చేయండి',
      },
      'copyright': {
        'english': '© 2025 mana Vivaaha Vedika. All rights reserved.',
        'telugu': '© 2025 మన వివాహ వేదిక. అన్ని హక్కులు ప్రత్యేకించబడ్డాయి.',
      },
      'tagline': {
        'english': 'Where Tradition Meets Technology',
        'telugu': 'సంప్రదాయం ఇక్కడ సాంకేతికతతో కలుస్తుంది',
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.favorite, color: Colors.white, size: 48),
                  SizedBox(height: 16),
                  Text(
                    _getText('brandName'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getText('tag'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getText('version'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ).appSlideIn(),

            SizedBox(height: 32),

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

            // About Section
            _buildSection(
              title: _getText('aboutTitle'),
              content: _getText('aboutContent'),
              icon: Icons.info_outline,
            ).appFadeIn(delay: Duration(milliseconds: 200)),

            // Values Section
            _buildSection(
              title: _getText('valuesTitle'),
              content: _getText('valuesContent'),
              icon: Icons.star_outline,
            ).appFadeIn(delay: Duration(milliseconds: 300)),

            // Features Section
            _buildSection(
              title: _getText('featuresTitle'),
              content: _getText('featuresContent'),
              icon: Icons.featured_play_list_outlined,
            ).appFadeIn(delay: Duration(milliseconds: 400)),

            // Contact Section
            _buildSection(
              title: _getText('contactTitle'),
              content: _getText('contactContent'),
              icon: Icons.mail_outline,
              actionButton: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => SupportLinks.openSupportEmail(
                        context,
                        subject: 'Inquiry about mana Vivaaha Vedika',
                        body: '',
                      ),
                      icon: const Icon(Icons.email),
                      label: Text(_getText('emailButton')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => SupportLinks.openWebsite(context),
                      icon: const Icon(Icons.language),
                      label: Text(_getText('websiteButton')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryOrange,
                        side: const BorderSide(color: AppTheme.primaryOrange),
                      ),
                    ),
                  ),
                ],
              ),
            ).appFadeIn(delay: Duration(milliseconds: 500)),

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
                    _getText('copyright'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getText('tagline'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.primaryOrange,
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ).appFadeIn(delay: Duration(milliseconds: 600)),

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
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.peacockBlue,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
    required IconData icon,
    Widget? actionButton,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: AppTheme.primaryOrange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AC.text(context),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AC.textSub(context),
              height: 1.5,
            ),
          ),
          if (actionButton != null) ...[
            const SizedBox(height: 20),
            actionButton,
          ],
        ],
      ),
    );
  }

}
