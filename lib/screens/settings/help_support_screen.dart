import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/support_links.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../utils/app_animations.dart';

/// Help & Support screen with FAQ, contact options, and resources
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  static const String _supportPhone = SupportLinks.supportPhone;
  static const String _supportEmail = SupportLinks.supportEmail;
  
  final List<FAQItem> _faqs = [
    FAQItem(
      question: '🚀 What makes Mana Vivaaha Vedika special?',
      answer: 'We combine traditional Vedic compatibility with modern discovery and privacy-first controls. You get curated interests, structured requests, profile analytics, and real-time updates in one place.',
    ),
    FAQItem(
      question: '🎠 Where is Discover 3D and how do I open it?',
      answer: 'Discover 3D is a Premium feature. Premium members can open it from the Home tab using the floating "Discover 3D" control.',
    ),
    FAQItem(
      question: '💌 How do Interests work now?',
      answer: 'Use "Send Interest" from profile. Received interests are handled in Received tab. Sent interests are managed in Sent tab, including status tracking. For pending items, Withdraw and Reminder actions are managed in Sent tab.',
    ),
    FAQItem(
      question: '🧾 Why don’t I see Withdraw/Reminder on profile screen?',
      answer: 'To avoid duplicate actions and keep flow clean, Withdraw and Reminder are centralized in Sent tab only. Profile screen keeps primary actions focused.',
    ),
    FAQItem(
      question: '📨 Messages tab shows count but what appears there?',
      answer: 'Messages tab lists chat conversations with accepted matches only. The badge counts unread chat messages. Photo requests and birthday wishes stay on Received or Notifications — not Messages.',
    ),
    FAQItem(
      question: '📸 How do Photo Requests work?',
      answer: 'Photo requests appear in both Received and Sent sections. In Received, you can Accept or Decline. In Sent, you can Withdraw or send Reminder for pending requests. Withdrawn requests are removed from active pending view.',
    ),
    FAQItem(
      question: '🔒 How is privacy enforced across lists and chat previews?',
      answer: 'Protected profiles are masked consistently. Depending on privacy settings, photos, identity text, contact details, and chat preview details can be hidden until allowed.',
    ),
    FAQItem(
      question: '📊 How do I use Interest statistics cards?',
      answer: 'In Overview and Views, statistics cards are wired for quick navigation. Tapping counts opens corresponding sections like Received, Sent, Views, and viewer history for faster workflow.',
    ),
    FAQItem(
      question: '👀 What is shown in the Views tab now?',
      answer: 'Views tab focuses on View History and recent activity flow. It keeps viewer access clear while supporting quick movement back to overview stats.',
    ),
    FAQItem(
      question: '✅ How do I verify my profile?',
      answer: 'Go to Profile and complete verification steps (phone/email/required checks). Verified profiles improve trust and visibility in matching flows.',
    ),
    FAQItem(
      question: '🚫 How do I block or report someone?',
      answer: 'Open profile options and choose Block or Report. Blocked profiles are excluded from active discovery/interests flows where applicable.',
    ),
    FAQItem(
      question: '📝 Can I edit my profile?',
      answer: 'Yes. Go to Profile > Edit Profile and update details. Keeping profile details current improves discovery quality and request relevance.',
    ),
    FAQItem(
      question: '🔐 How do I reset password or MPIN?',
      answer: 'Go to Settings > Security. Use reset options with verification. Never share MPIN or OTP with anyone, including support.',
    ),
    FAQItem(
      question: '📊 How do I see my stats?',
      answer: 'Open Interests hub. Overview, Received, Sent, Messages, and Views tabs provide counts and drill-down actions for engagement and activity tracking.',
    ),
    FAQItem(
      question: '🆘 How do I contact support?',
      answer:
          'Open Settings → Support tab → Chat with Support for in-app messages, or use Call / WhatsApp / Email / Website on this page (${SupportLinks.supportEmail}, ${SupportLinks.supportWebsiteDisplay}). Share your profile ID and a screenshot for faster resolution.',
    ),
  ];
  
  List<FAQItem> get _filteredFAQs {
    if (_searchQuery.isEmpty) return _faqs;
    final query = _searchQuery.toLowerCase();
    return _faqs.where((faq) => 
      faq.question.toLowerCase().contains(query) ||
      faq.answer.toLowerCase().contains(query)
    ).toList();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _makePhoneCall() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: _supportPhone);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not make phone call. Please check your phone settings.'),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error making phone call. Please try again.'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    }
  }
  
  Future<void> _openWhatsApp() async {
    await SupportLinks.openWhatsAppSupport(context);
  }
  
  Future<void> _sendEmail() async {
    await SupportLinks.openSupportEmail(context);
  }

  Future<void> _openWebsite() async {
    await SupportLinks.openWebsite(context);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Help & Support',
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contact Options Section
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section Header
                  _buildSectionHeader(context, 'Contact Us'),

                  const SizedBox(height: 16),
                  
                  // Phone and WhatsApp Buttons Row
                  Row(
                    children: [
                      // Call Button
                      Expanded(
                        child: _buildContactButton(
                          context,
                          icon: Icons.phone,
                          title: 'Call',
                          subtitle: SupportLinks.supportPhoneDisplay,
                          color: AppTheme.primaryOrange,
                          onTap: _makePhoneCall,
                        ).appSlideIn(baseDelay: Duration(milliseconds: 100)),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // WhatsApp Button
                      Expanded(
                        child: _buildContactButton(
                          context,
                          icon: Icons.message,
                          title: 'WhatsApp',
                          subtitle: SupportLinks.supportPhoneDisplay,
                          color: AppTheme.sacredGreen,
                          onTap: _openWhatsApp,
                        ).appSlideIn(baseDelay: Duration(milliseconds: 200)),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Email Card
                  _buildContactCard(
                    context,
                    icon: Icons.email,
                    title: 'Email Support',
                    subtitle: _supportEmail,
                    description: 'Send detailed queries via email',
                    color: AppTheme.peacockBlue,
                    onTap: _sendEmail,
                  ).appSlideIn(baseDelay: Duration(milliseconds: 300)),

                  const SizedBox(height: 12),

                  _buildContactCard(
                    context,
                    icon: Icons.language,
                    title: 'Website',
                    subtitle: SupportLinks.supportWebsiteDisplay,
                    description: 'Policies, registration info & updates',
                    color: AppTheme.templeGold,
                    onTap: _openWebsite,
                  ).appSlideIn(baseDelay: Duration(milliseconds: 350)),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // FAQ Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: AC.text(context)),
                    decoration: InputDecoration(
                      hintText: 'Search FAQs...',
                      prefixIcon: Icon(Icons.search, color: AC.textSub(context)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AC.textSub(context)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AC.surface(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: AppTheme.primaryOrange, width: 2),
                      ),
                      hintStyle: TextStyle(color: AC.textMuted(context)),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ).appSlideIn(baseDelay: Duration(milliseconds: 400)),
                  
                  const SizedBox(height: 24),
                  
                  // Section Header
                  _buildSectionHeader(context, 'Frequently Asked Questions'),
                  
                  const SizedBox(height: 16),
                  
                  // FAQ List
                  _filteredFAQs.isEmpty
                      ? _buildEmptyState(context).appSlideIn(baseDelay: Duration(milliseconds: 500))
                      : Column(
                          children: _filteredFAQs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final faq = entry.value;
                            return _buildFAQCard(faq, index).appSlideIn(baseDelay: Duration(milliseconds: 500 + (index * 50)));
                          }).toList(),
                        ),
                ],
              ),
            ),
            
            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AC.textSub(context),
              letterSpacing: 1,
              fontSize: 16,
            ),
      ),
    );
  }
  
  Widget _buildContactButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.divider(context)),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? []
            : [
                BoxShadow(
                  color: AC.shadow(context),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AC.text(context),
                  ),
            ),
            
            const SizedBox(height: 2),
            
            // Subtitle
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContactCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.divider(context)),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? []
            : [
                BoxShadow(
                  color: AC.shadow(context),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AC.text(context),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textMuted(context),
                        ),
                  ),
                ],
              ),
            ),
            
            // Arrow
            Icon(
              Icons.arrow_forward_ios,
              color: AC.textMuted(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFAQCard(FAQItem faq, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.divider(context)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(20),
        iconColor: AC.textSub(context),
        collapsedIconColor: AC.textMuted(context),
        title: Text(
          faq.question,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AC.text(context),
              ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(
              faq.answer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AC.textSub(context),
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.divider(context)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: AC.textMuted(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No FAQs found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AC.textSub(context),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textMuted(context),
                ),
          ),
        ],
      ),
    );
  }
}

class FAQItem {
  final String question;
  final String answer;
  
  FAQItem({required this.question, required this.answer});
}
