import 'package:flutter/material.dart';
import '../../core/support_links.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

enum Language { english, telugu }

/// Terms and Conditions screen
class TermsScreen extends StatefulWidget {
  final bool showAcceptButton;
  final VoidCallback? onAccept;
  
  const TermsScreen({
    super.key,
    this.showAcceptButton = false,
    this.onAccept,
  });

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  Language _selectedLanguage = Language.english;

  Map<String, Map<String, String>> get _content {
    return {
      'title': {
        'english': 'Terms & Conditions',
        'telugu': 'నియమాలు మరియు షరతులు',
      },
      'lastUpdated': {
        'english': 'Last Updated: December 2025',
        'telugu': 'చివరిగా నవీకరించబడింది: డిసెంబర్ 2025',
      },
      'header': {
        'english': 'Please read the terms and conditions in your preferred language',
        'telugu': 'దయచేసి మీ అభిమత భాషలో నియమాలు మరియు షరతులను చదవండి',
      },
      'section1_title': {
        'english': 'Acceptance of Terms',
        'telugu': 'నియమాలను అంగీకరించడం',
      },
      'section1_content': {
        'english': '''
By downloading, installing, or using the mana Vivaaha Vedika application ("App"), you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the App.

The App is intended for use by individuals seeking Vivaaha Vedika alliances within the Brahmin community. Users must be at least 18 years of age (21 for males and 18 for females as per Indian law) to register on this platform.
''',
        'telugu': '''
మన వివాహ వేదిక అనువర్తనాన్ని ("App") డౌన్‌లోడ్ చేయడం, ఇన్‌స్టాల్ చేయడం లేదా ఉపయోగించడం ద్వారా, మీరు ఈ నియమాలు మరియు షరతులకు బద్ధులవుతారు. మీరు ఈ నియమాలకు అంగీకరించకపోతే, దయచేసి App ను ఉపయోగించవద్దు.

ఈ App బ్రాహ్మణ సమాజంలో వివాహ బంధాల కోసం వెతుకుతున్న వ్యక్తుల కోసం ఉద్దేశించబడింది. ఈ ప్లాట్‌ఫార్మ్‌లో నమోదు చేయడానికి వినియోగదారులు కనీసం 18 సంవత్సరాల వయస్సు (భారతీయ చట్టం ప్రకారం మగవారికి 21 మరియు ఆడవారికి 18) కలిగి ఉండాలి.
''',
      },
      'section2_title': {
        'english': 'Registration & Account',
        'telugu': 'నమోదు మరియు ఖాతా',
      },
      'section2_content': {
        'english': '''
• Users must provide accurate, current, and complete information during registration.
• Each user is allowed only one account. Multiple accounts may result in permanent ban.
• Users are responsible for maintaining the confidentiality of their login credentials and MPIN.
• Profiles can be created by the individual themselves or by their parents/guardians/relatives on their behalf.
• The profile creator must declare their relationship with the person whose profile is being created.
• False information may lead to account suspension or termination.
''',
        'telugu': '''
• నమోదు సమయంలో యూజర్లు ఖచ్చితమైన, ప్రస్తుత మరియు పూర్తి సమాచారాన్ని అందించాలి.
• ప్రతి యూజర్‌కు ఒక ఖాతా మాత్రమే అనుమతించబడుతుంది. బహుళ ఖాతాలు శాశ్వత నిషేధానికి దారి తీయవచ్చు.
• తమ లాగిన్ ఆధారాలు మరియు MPIN యొక్క గోప్యతను నిర్వహించడానికి యూజర్లు బాధ్యత వహిస్తారు.
• ప్రొఫైళ్లను వ్యక్తి స్వయంగా లేదా అతని తల్లిదండ్రులు/సంరక్షకులు/బంధువులచే తమ తరపున సృష్టించవచ్చు.
• ప్రొఫైల్ సృష్టికర్త తన సంబంధాన్ని ప్రొఫైల్ సృష్టించబడుతున్న వ్యక్తితో ప్రకటించాలి.
• తప్పుడు సమాచారం ఖాతా సస్పెన్షన్ లేదా ముగింపుకు దారి తీయవచ్చు.
''',
      },
      'agreement': {
        'english': 'By using mana Vivaaha Vedika, you acknowledge that you have read, understood, and agree to these Terms and Conditions.',
        'telugu': 'మన వివాహ వేదికను ఉపయోగించడం ద్వారా, మీరు ఈ నియమాలు మరియు షరతులను చదివినట్లు, అర్థం చేసుకున్నట్లు మరియు అంగీకరించినట్లు గుర్తిస్తారు.',
      },
      'contact': {
        'english': 'For any queries: ${SupportLinks.contactFooterEn}',
        'telugu': 'ఏవైనా ప్రశ్నలకు: ${SupportLinks.contactFooterTe}',
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
                  Icon(Icons.description, color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    _selectedLanguage == Language.telugu
                        ? 'మన వివాహ వేదిక'
                        : 'mana Vivaaha Vedika',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getText('lastUpdated'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getText('header'),
                      style: TextStyle(
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

            // Language Toggle
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
                  _buildLanguageButton(Language.english, 'English'),
                  const SizedBox(width: 16),
                  _buildLanguageButton(Language.telugu, 'తెలుగు'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildTermSection(
              context,
              title: _getText('section1_title'),
              content: _getText('section1_content'),
            ),

            _buildTermSection(
              context,
              title: _getText('section2_title'),
              content: _getText('section2_content'),
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Eligibility Criteria'
                  : 'అర్హత ప్రమాణాలు',
              content: _selectedLanguage == Language.english
                  ? '''
To use mana Vivaaha Vedika, you must:
• Be of legal marriageable age as per Indian law
• Be a member of the Brahmin community (any sub-sect)
• Be legally single, divorced, or widowed
• Not be currently married to another person
• Have genuine intention of marriage
• Provide valid identity proof when requested
'''
                  : '''
మన వివాహ వేదికను ఉపయోగించడానికి, మీరు:
• భారతీయ చట్టం ప్రకారం చట్టబద్ధమైన వివాహ వయస్సు కలిగి ఉండాలి
• బ్రాహ్మణ సమాజం (ఏదైనా ఉప-సంఘం) సభ్యుడిగా ఉండాలి
• చట్టబద్ధంగా ఒంటరిగా, విడాకుల పొందినవారు లేదా విధవగా ఉండాలి
• ప్రస్తుతం మరొక వ్యక్తితో వివాహం చేసుకోకూడదు
• వివాహం యొక్క నిజాయితీ ఉద్దేశం కలిగి ఉండాలి
• అభ్యర్థించినప్పుడు చెల్లుబాటు అయ్యే గుర్తింపు రుజువును అందించాలి
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'User Conduct'
                  : 'యూజర్ ప్రవర్తన',
              content: _selectedLanguage == Language.english
                  ? '''
Users agree NOT to:
• Post false, misleading, or fraudulent information
• Upload obscene, offensive, or inappropriate content
• Harass, abuse, or threaten other users
• Use the platform for any illegal purposes
• Share contact information publicly before mutual interest
• Attempt to hack, disrupt, or manipulate the platform
• Use automated systems or bots to access the service
• Share login credentials with others
• Create fake profiles or impersonate others
'''
                  : '''
యూజర్లు ఈ క్రింది వాటిని చేయవద్దని అంగీకరిస్తారు:
• తప్పుడు, ఎవరికీ భ్రమ కలిగించే లేదా మోసపూరిత సమాచారాన్ని పోస్ట్ చేయడం
• అశ్లీలమైన, అప్రియమైన లేదా తగని కంటెంట్‌ను అప్‌లోడ్ చేయడం
• ఇతర యూజర్లను వేధించడం, దౌర్జన్యం చేయడం లేదా బెదిరించడం
• ఏవైనా చట్టవిరుద్ధ ప్రయోజనాల కోసం ప్లాట్‌ఫార్మ్‌ను ఉపయోగించడం
• పరస్పర ఆసక్తి ముందు సంప్రదింపు సమాచారాన్ని బహిరంగంగా భాగస్వామ్యం చేయడం
• ప్లాట్‌ఫార్మ్‌ను హ్యాక్ చేయడానికి, ఆటంకం కలిగించడానికి లేదా మార్చడానికి ప్రయత్నించడం
• సేవకు ప్రవేశించడానికి ఆటోమేటెడ్ సిస్టమ్‌లు లేదా బాట్‌లను ఉపయోగించడం
• ఇతరులతో లాగిన్ ఆధారాలను భాగస్వామ్యం చేయడం
• నకిలీ ప్రొఫైళ్లను సృష్టించడం లేదా ఇతరులను అనుకరించడం
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Profile Content'
                  : 'ప్రొఫైల్ కంటెంట్',
              content: _selectedLanguage == Language.english
                  ? '''
• All profile information must be truthful and verifiable
• Photos must be recent (within last 2 years) and clearly show the person
• Horoscope details if provided must be accurate
• Users consent to their profile being viewed by other registered members
• Profile photos can be set as private and shared only on request
• We reserve the right to remove any content that violates our guidelines
'''
                  : '''
• అన్ని ప్రొఫైల్ సమాచారం నిజాయితీ మరియు ధృవీకరించదగినదిగా ఉండాలి
• ఫోటోలు ఇటీవల (గత 2 సంవత్సరాలలో) ఉండాలి మరియు వ్యక్తిని స్పష్టంగా చూపించాలి
• అందించబడిన జాతక వివరాలు ఖచ్చితమైనవిగా ఉండాలి
• నమోదు చేయబడిన ఇతర సభ్యులు తమ ప్రొఫైల్‌ను చూడడానికి యూజర్లు అంగీకరిస్తారు
• ప్రొఫైల్ ఫోటోలను ప్రైవేట్‌గా సెట్ చేయవచ్చు మరియు అభ్యర్థనపై మాత్రమే భాగస్వామ్యం చేయవచ్చు
• మా మార్గదర్శకాలను ఉల్లంఘించే ఏదైనా కంటెంట్‌ను తీసివేసే హక్కును మేము కలిగి ఉన్నాము
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Ashtakoot Matching'
                  : 'అష్టకూట సరిపోలిక',
              content: _selectedLanguage == Language.english
                  ? '''
• The Ashtakoot (8-fold) compatibility matching is provided for reference only
• Results are based on traditional astrological calculations
• Users should consult a qualified astrologer for detailed horoscope matching
• mana Vivaaha Vedika is not responsible for decisions made based on compatibility scores
• Nadi Dosha warnings are indicators and not definitive conclusions
'''
                  : '''
• అష్టకూట (8-రెట్లు) అనుకూలత సరిపోలిక సూచన కొరకు మాత్రమే అందించబడుతుంది
• ఫలితాలు సాంప్రదాయ జ్యోతిష్య గణనల ఆధారంగా ఉంటాయి
• వివరమైన జాతక సరిపోలిక కోసం యూజర్లు అర్హత కలిగిన జ్యోతిష్యుడిని సంప్రదించాలి
• అనుకూలత స్కోర్‌ల ఆధారంగా తీసుకున్న నిర్ణయాలకు మన వివాహ వేదిక బాధ్యత వహించదు
• నాడి దోష హెచ్చరికలు సూచికలు మరియు నిర్ణయాత్మకమైన ముగింపులు కావు
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Premium Membership'
                  : 'ప్రీమియం సభ్యత్వం',
              content: _selectedLanguage == Language.english
                  ? '''
• Premium membership is available at ₹99/month paid in advance
• Payment is accepted via UPI only
• Premium benefits include: viewing photos, contact requests, advanced filters
• Membership is non-refundable once activated
• Premium is activated automatically after your payment successfully completes and is confirmed—usually within a short time
• Membership does not guarantee finding a suitable match
'''
                  : '''
• ప్రీమియం సభ్యత్వం ₹99/నెల చొప్పున ముందుగా చెల్లించడంతో అందుబాటులో ఉంది
• చెల్లింపు UPI ద్వారా మాత్రమే అంగీకరించబడుతుంది
• ప్రీమియం ప్రయోజనాలు: ఫోటోలను చూడడం, సంప్రదింపు అభ్యర్థనలు, అధునాతన ఫిల్టర్‌లు
• సభ్యత్వం ఒకసారి సక్రియం చేయబడిన తర్వాత వాపసు చేయబడదు
• చెల్లింపు విజయవంతంగా పూర్తయి ధృవీకరించబడిన తర్వాత ప్రీమియం ఆటోమేటిక్‌గా సక్రియం అవుతుంది — సాధారణంగా కొద్ది సమయంలోనే
• సభ్యత్వం తగిన సరిపోలికను కనుగొనడాన్ని హామీ ఇవ్వదు
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Contact Requests'
                  : 'సంప్రదింపు అభ్యర్థనలు',
              content: _selectedLanguage == Language.english
                  ? '''
• Contact details are shared only through admin via WhatsApp
• Both parties must consent before contact information is exchanged
• Misuse of contact information is strictly prohibited
• Users should verify the authenticity of the other party before meeting
• Always meet in public places for first meetings
• Inform family members about any meetings
• Inform family members about any meetings
'''
                  : '''
• సంప్రదింపు వివరాలు WhatsApp ద్వారా నిర్వాహకుడి ద్వారా మాత్రమే భాగస్వామ్యం చేయబడతాయి
• సంప్రదింపు సమాచారం మార్పిడి చేయడానికి ముందు రెండు పార్టీలు అంగీకరించాలి
• సంప్రదింపు సమాచారం యొక్క దుర్వినియోగం కఠినంగా నిషేధించబడింది
• కలవడానికి ముందు యూజర్లు ఇతర పక్షం యొక్క నిజాయితీని ధృవీకరించాలి
• మొదటి సమావేశాల కోసం ఎల్లప్పుడూ బహిరంగ స్థలాలలో కలవండి
• ఏవైనా సమావేశాల గురించి కుటుంబ సభ్యులకు తెలియజేయండి
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Privacy & Data'
                  : 'గోప్యత మరియు డేటా',
              content: _selectedLanguage == Language.english
                  ? '''
• User data is stored securely and used only for matchmaking purposes
• We do not sell or share personal data with third parties
• Users can request deletion of their profile and data
• Some anonymized data may be used for analytics and improvement
• Please refer to our Privacy Policy for detailed information
'''
                  : '''
• యూజర్ డేటా సురక్షితంగా నిల్వ చేయబడుతుంది మరియు వివాహ సంబంధం ప్రయోజనాల కోసం మాత్రమే ఉపయోగించబడుతుంది
• మేము వ్యక్తిగత డేటాను మూడవ పక్షాలకు విక్రయించము లేదా భాగస్వామ్యం చేయము
• యూజర్లు తమ ప్రొఫైల్ మరియు డేటా తొలగింపును అభ్యర్థించవచ్చు
• కొన్ని అజ్ఞాత డేటా విశ్లేషణ మరియు మెరుగుదల కోసం ఉపయోగించబడవచ్చు
• వివరమైన సమాచారం కోసం దయచేసి మా గోప్యతా విధానాన్ని చూడండి
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Limitation of Liability'
                  : 'బాధ్యత పరిమితి',
              content: _selectedLanguage == Language.english
                  ? '''
• mana Vivaaha Vedika is a platform to facilitate introductions only
• We are not responsible for the conduct of any user
• We do not conduct background verification of users
• Users are advised to verify all information independently
• We are not liable for any disputes between users
• We are not responsible for marriages or relationships formed through the platform
'''
                  : '''
• మన వివాహ వేదిక పరిచయాలను సులభపరచే ఒక వేదిక మాత్రమే
• మేము ఏ యూజర్ యొక్క ప్రవర్తనకు బాధ్యత వహించము
• మేము యూజర్ల యొక్క నేపథ్య ధృవీకరణను నిర్వహించము
• యూజర్లు అన్ని సమాచారాన్ని స్వతంత్రంగా ధృవీకరించమని సూచించబడ్డారు
• యూజర్ల మధ్య ఏవైనా వివాదాలకు మేము బాధ్యత వహించము
• ప్లాట్‌ఫార్మ్ ద్వారా ఏర్పడిన వివాహాలు లేదా సంబంధాలకు మేము బాధ్యత వహించము
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Termination'
                  : 'ముగింపు',
              content: _selectedLanguage == Language.english
                  ? '''
• Users can delete their account at any time
• We reserve the right to suspend or terminate accounts that violate these terms
• Banned users cannot create new accounts
• Upon termination, all user data will be deleted within 7 days
'''
                  : '''
• యూజర్లు ఎప్పుడైనా తమ ఖాతాను తొలగించవచ్చు
• ఈ నియమాలను ఉల్లంఘించే ఖాతాలను సస్పెండ్ చేయడానికి లేదా ముగించడానికి మేము హక్కును కలిగి ఉన్నాము
• నిషేధించబడిన యూజర్లు కొత్త ఖాతాలను సృష్టించలేరు
• ముగింపు సమయంలో, అన్ని యూజర్ డేటా 7 రోజులలో తొలగించబడుతుంది
''',
            ),

            _buildTermSection(
              context,
              title: _selectedLanguage == Language.english
                  ? 'Governing Law'
                  : 'పాలన చట్టం',
              content: _selectedLanguage == Language.english
                  ? 'These terms are governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of the courts in Andhra Pradesh, India.'
                  : 'ఈ నియమాలు భారతదేశ చట్టాల ద్వారా పరిపాలించబడతాయి. ఏవైనా వివాదాలు ఆంధ్రప్రదేశ్, భారతదేశంలోని న్యాయస్థానాల యొక్క ప్రత్యేక అధికార పరిధికి లోబడి ఉంటాయి.',
            ),

            const SizedBox(height: 24),

            // Agreement
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
                  const Icon(Icons.check_circle, color: AppTheme.sacredGreen, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    _getText('agreement'),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Accept Button (only shown in registration flow)
            if (widget.showAcceptButton) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.sacredGreen,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'I Accept Terms & Conditions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Contact
            Center(
              child: Text(
                _getText('contact'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageButton(Language language, String label) {
    final isSelected = _selectedLanguage == language;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedLanguage = language;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange : Colors.white.withAlpha(200),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryOrange : AppTheme.primaryOrange.withAlpha(150),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected 
                  ? AppTheme.primaryOrange.withAlpha(50)
                  : (Colors.black.withAlpha(20)),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.primaryOrange,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTermSection(BuildContext context, {
    required String title,
    required String content,
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
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AC.text(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            content.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
