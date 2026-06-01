import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_bank_widgets.dart';
import '../../widgets/auth/auth_screen_shell.dart';
import 'registration_screen.dart';

/// Disclaimer screen for first-time users
class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({super.key});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _acceptedDisclaimer = false;

  void _goBackSafely() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushNamedAndRemoveUntil(Routes.authSelection, (_) => false);
  }

  @override
  Widget build(BuildContext context) {

    return AuthScreenShell(
      showBack: true,
      onBack: _goBackSafely,
      screenTitle: 'Before you register',
      screenSubtitle: 'Please read and accept',
      body: Column(
        children: [
          AuthBankCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ముఖ్యమైన సమాచారం',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AC.accent(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AC.card(context).withAlpha(240),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disclaimer',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AC.accent(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDisclaimerPoint(
                        context,
                        '• ఈ ప్లాట్‌ఫారమ్ వివాహ ప్రయోజనాల కోసం మాత్రమే ఉద్దేశించబడింది.',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• నమోదు చేసుకోవడానికి వినియోగదారులు కనీసం 18 సంవత్సరాల వయస్సు కలిగి ఉండాలి.',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• దయచేసి ఖచ్చితమైన మరియు నిజమైన సమాచారాన్ని అందించండి.',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• మేము మీ గోప్యత మరియు డేటా భద్రతను గౌరవిస్తాము',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• ప్లాట్‌ఫామ్‌ను దుర్వినియోగం చేస్తే ఖాతా సస్పెన్షన్‌కు దారితీస్తుంది.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'About payments',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AC.accent(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDisclaimerPoint(
                        context,
                        '• ప్రీమియం లేదా ఇతర చెల్లింపులు UPI, డెబిట్/క్రెడిట్ కార్డ్, నెట్ బ్యాంకింగ్, వాలెట్‌లు వంటి RBI ఆమోదిత డిజిటల్ పద్ధతుల ద్వారా మాత్రమే చేయాలి.',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• చెల్లింపు ప్లాట్‌ఫారమ్ ఫీచర్లకు / సభ్యత్వ యాక్సెస్‌కి మాత్రమే; వివాహం లేదా మ్యాచ్ ఫలితానికి హామీ లేదు. సభ్యత్వ ఫీజులు సాధారణంగా తిరిగి ఇవ్వబడవు (చెల్లింపు & రిఫండ్ విధానం చూడండి).',
                      ),
                      _buildDisclaimerPoint(
                        context,
                        '• విజయవంతమైన చెల్లింపు పూర్తయిన తర్వాత ప్రీమియం సిస్టమ్ ద్వారా ఆటోమేటిక్‌గా సక్రియం అవుతుంది.',
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.sacredGreen.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.sacredGreen.withAlpha(40),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.security,
                              color: AppTheme.sacredGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'మీ సమాచారం సురక్షితం మరియు సమ్మతి లేకుండా భాగస్వామ్యం చేయబడదు.',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AC.text(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
          const SizedBox(height: 16),
          AuthBankCard(
            child: Row(
              children: [
                Checkbox(
                  value: _acceptedDisclaimer,
                  onChanged: (value) {
                    setState(() {
                      _acceptedDisclaimer = value ?? false;
                    });
                  },
                  activeColor: AppTheme.primaryOrange,
                  checkColor: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'పైన ఉన్న సమాచారం అంతటినీ చదివి, నేను దానిని అర్థం చేసుకున్నాను.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AC.text(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AuthPrimaryButton(
            label: 'Continue to register',
            onPressed: _acceptedDisclaimer
                ? () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegistrationScreen(
                          disclosureAccepted: true,
                        ),
                      ),
                    );
                  }
                : null,
          ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDisclaimerPoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: AC.text(context),
          height: 1.4,
        ),
      ),
    );
  }
}
