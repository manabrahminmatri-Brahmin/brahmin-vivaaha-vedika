import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';
import '../../utils/contact_utils.dart';
import '../../widgets/app_header.dart';

/// Rate App screen
class RateAppScreen extends StatefulWidget {
  const RateAppScreen({super.key});

  @override
  State<RateAppScreen> createState() => _RateAppScreenState();
}

class _RateAppScreenState extends State<RateAppScreen> {
  int _selectedRating = 0;
  final _feedbackController = TextEditingController();
  bool _isSubmitting = false;
  bool _hasRated = false;

  @override
  void initState() {
    super.initState();
    _checkPreviousRating();
  }

  Future<void> _checkPreviousRating() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final rating = prefs.getInt('app_rating');
    if (rating != null) {
      setState(() {
        _selectedRating = rating;
        _hasRated = true;
      });
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Save rating locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_rating', _selectedRating);
    await prefs.setString('app_feedback', _feedbackController.text);

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _hasRated = true;
    });

    // Show thank you dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite,
                size: 48,
                color: AppTheme.sacredGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Thank You!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryOrange,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedRating >= 4
                  ? 'We\'re glad you\'re enjoying mana Vivaaha Vedika! Your support means a lot to us.'
                  : 'Thank you for your feedback. We\'ll work hard to improve your experience.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_selectedRating >= 4) ...[
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openPlayStore();
                },
                icon: Icon(Icons.star, color: AC.card(context)),
                label: const Text('Rate on Play Store'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.sacredGreen,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlayStore() async {
    // Replace with actual Play Store URL
    const url = 'https://play.google.com/store/apps/details?id=com.manavivaahavedika.brahmin';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Play Store'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Rate mana Vivaaha Vedika',
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE85D04).withAlpha(40),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE85D04),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              'mana',
                              style: TextStyle(
                                fontSize: 22,
                                color: AC.card(context),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'mana Vivaaha Vedika',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AC.card(context), 
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: AC.card(context).withAlpha(150),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().scale(begin: Offset(0.95, 0.95)),

            const SizedBox(height: 32),

            // Rating Section
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AC.card(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AC.surface(context),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    _hasRated ? 'Your Rating' : 'How would you rate us?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.primaryOrange,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your feedback helps us improve',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),

                  // Star Rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNumber = index + 1;
                      return GestureDetector(
                        onTap: _hasRated
                            ? null
                            : () => setState(() => _selectedRating = starNumber),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            _selectedRating >= starNumber
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 48,
                            color: _selectedRating >= starNumber
                                ? AppTheme.primaryGold
                                : AppTheme.textLight,
                          ).animate(
                            target: _selectedRating >= starNumber ? 1 : 0,
                          ).scale(
                            begin: const Offset(1, 1),
                            end: const Offset(1.2, 1.2),
                            duration: 200.ms,
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 16),

                  // Rating Text
                  if (_selectedRating > 0)
                    Text(
                      _getRatingText(_selectedRating),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _getRatingColor(_selectedRating),
                            fontWeight: FontWeight.w600,
                          ),
                    ).animate().fadeIn(),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // Feedback Section
            if (!_hasRated) ...[
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AC.card(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AC.divider(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit_note, color: Color(0xFF757575)),
                        SizedBox(width: 12),
                        Text(
                          'Share Your Feedback',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Tell us what you think about mana Vivaaha Vedika...',
                        hintStyle: TextStyle(color: AC.textMuted(context)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AC.divider(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.primaryOrange),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms),

              SizedBox(height: 24),

              // Submit Button
              Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AC.border(context),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRating,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AC.card(context),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send, color: AC.card(context)),
                            SizedBox(width: 8),
                            Text(
                              'Submit Rating',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AC.card(context),
                              ),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(delay: 300.ms).scale(begin: Offset(0.95, 0.95)),
            ],

            // Already Rated
            if (_hasRated) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.sacredGreen.withAlpha(30)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppTheme.sacredGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Thank you for rating us!',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppTheme.sacredGreen,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 24),

              // Rate on Play Store Button
              OutlinedButton.icon(
                onPressed: _openPlayStore,
                icon: const Icon(Icons.shop),
                label: const Text('Rate on Google Play'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ).animate().fadeIn(delay: 300.ms),
            ],

            const SizedBox(height: 32),

            // Other Ways to Help
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AC.surface(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Other Ways to Help',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AC.textMuted(context),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _buildHelpItem(
                    context,
                    icon: Icons.share,
                    title: 'Share with Friends',
                    subtitle: 'Help others find their life partner',
                    onTap: () => _shareApp(context),
                  ),
                  const Divider(height: 24),
                  _buildHelpItem(
                    context,
                    icon: Icons.bug_report,
                    title: 'Report a Bug',
                    subtitle: 'Help us fix issues',
                    onTap: () => _openWhatsApp('Bug Report'),
                  ),
                  const Divider(height: 24),
                  _buildHelpItem(
                    context,
                    icon: Icons.lightbulb_outline,
                    title: 'Suggest a Feature',
                    subtitle: 'Share your ideas with us',
                    onTap: () => _openWhatsApp('Feature Suggestion'),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor 😔';
      case 2:
        return 'Fair 😐';
      case 3:
        return 'Good 🙂';
      case 4:
        return 'Very Good 😊';
      case 5:
        return 'Excellent! 🥰';
      default:
        return '';
    }
  }

  Color _getRatingColor(int rating) {
    switch (rating) {
      case 1:
        return AppTheme.kumkumRed;
      case 2:
        return Colors.orange;
      case 3:
        return AppTheme.templeGold;
      case 4:
        return AppTheme.sacredGreen;
      case 5:
        return AppTheme.sacredGreen;
      default:
        return AppTheme.textMedium;
    }
  }

  Widget _buildHelpItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AC.surface2(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AC.textMuted(context)),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textMuted(context),
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AC.textMuted(context)),
        ],
      ),
    );
  }

  Future<void> _shareApp(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appName = packageInfo.appName;
      final packageName = packageInfo.packageName;
      
      final shareText = '''
🌟 *$appName* - Premium Vivaaha Vedika App for Brahmin Community

Find your perfect life partner with our advanced matching system based on:
✨ Ashtakoot & Jatakam Compatibility
📱 Easy profile creation and management  
🔒 Privacy-first approach
💎 Premium features for serious matches

Download now and start your journey to find your soulmate!

${Platform.isAndroid ? 'https://play.google.com/store/apps/details?id=$packageName' : 'https://apps.apple.com/app/id$packageName'}
''';
      
      // Copy to clipboard and show WhatsApp share option
      await Clipboard.setData(ClipboardData(text: shareText));
      
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.share, color: Color(0xFF757575)),
                SizedBox(width: 12),
                Text('Share App'),
              ],
            ),
            content: const Text(
              'App link copied to clipboard! Choose how you want to share:',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ContactUtils.openWhatsApp(
                    '918985936678',
                    message: shareText,
                  );
                },
                icon: const Icon(Icons.message, size: 18),
                label: const Text('WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String subject) async {
    final message = 'Hi, I would like to share a $subject for mana Vivaaha Vedika app:\n\n';
    final uri = Uri.parse('whatsapp://send?phone=+918985936678&text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(uri);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }
}
