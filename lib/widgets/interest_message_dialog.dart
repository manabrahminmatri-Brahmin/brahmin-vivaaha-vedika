import 'package:flutter/material.dart';
import '../services/user_action_service.dart';
import '../widgets/action_button.dart' show ActionType;
import '../theme/app_theme.dart';
import 'celebration_effects.dart';
import 'soft_touch.dart';

/// AI-suggested message templates
class InterestMessageTemplates {
  static const List<String> freeTemplates = [
    "Hi, I came across your profile and found it interesting. Would like to know more about you.",
    "Hello! I liked your profile. Would be happy to connect and discuss further.",
    "Namaste! Your profile seems compatible with what I'm looking for. Let's connect?",
    "Hi there! I'm interested in your profile. Would love to learn more about you.",
    "Hello! I found your profile appealing. Hoping we can get to know each other better.",
  ];

  static const List<String> premiumTemplates = [
    "Hi! I'm genuinely interested in your profile. Your values and background seem aligned with what I seek. Would love to connect.",
    "Namaste! After reviewing your profile, I feel we could be a good match. Would you be open to a conversation?",
    "Hello! Your profile stood out to me. I'm looking for a meaningful connection and would like to know you better.",
    "Hi! I was impressed by your profile. If you feel the same, let's take this forward and see where it leads.",
    "Greetings! Your profile resonates with my expectations. I'd be honored to connect and explore compatibility.",
  ];

  static String getRandomTemplate(bool isPremium) {
    final templates = isPremium ? premiumTemplates : freeTemplates;
    return templates[DateTime.now().millisecond % templates.length];
  }
}

/// Dialog for sending interest with message
class InterestMessageDialog extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final bool isPremium;
  final VoidCallback? onPremiumUpgrade;

  const InterestMessageDialog({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.isPremium,
    this.onPremiumUpgrade,
  });

  @override
  State<InterestMessageDialog> createState() => _InterestMessageDialogState();

  /// Show the dialog
  static Future<bool> show({
    required BuildContext context,
    required String targetUserId,
    required String targetUserName,
    required bool isPremium,
    VoidCallback? onPremiumUpgrade,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => InterestMessageDialog(
        targetUserId: targetUserId,
        targetUserName: targetUserName,
        isPremium: isPremium,
        onPremiumUpgrade: onPremiumUpgrade,
      ),
    );
    return result ?? false;
  }
}

class _InterestMessageDialogState extends State<InterestMessageDialog> {
  final _messageController = TextEditingController();
  final _service = UserActionService();
  bool _isSending = false;
  bool _sharePhone = false;
  String? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    // Auto-fill with AI suggestion
    _messageController.text = InterestMessageTemplates.getRandomTemplate(widget.isPremium);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendInterest() async {
    if (_isSending) return;

    if (!widget.isPremium) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium membership is required to send interests.'),
          backgroundColor: AppTheme.primaryOrange,
        ),
      );
      widget.onPremiumUpgrade?.call();
      return;
    }

    SoftTouch.impact();
    setState(() => _isSending = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final result = await _service.sendAction(
      targetUserId: widget.targetUserId,
      type: ActionType.interest,
      message: _messageController.text.trim(),
    );
    if (!mounted) return;
    final success = result['success'] == true;
    final feedback = (result['message'] ?? '').toString().trim();

    setState(() => _isSending = false);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            feedback.isNotEmpty ? feedback : 'Interested! 💌',
          ),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
      await CelebrationEffects.showInterestBurst(context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            feedback.isNotEmpty
                ? feedback
                : 'Failed to send interest. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyTemplate(String template) {
    setState(() {
      _selectedTemplate = template;
      _messageController.text = template;
    });
  }

  void _generateNewSuggestion() {
    setState(() {
      _messageController.text = InterestMessageTemplates.getRandomTemplate(widget.isPremium);
      _selectedTemplate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxChars = widget.isPremium ? 200 : 100;
    final currentLength = _messageController.text.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.favorite, color: AppTheme.primaryOrange, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Send Interest to ${widget.targetUserName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // AI Suggestion Button
            Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.primaryGold, size: 18),
                const SizedBox(width: 8),
                Text(
                  'AI Suggested Message',
                  style: TextStyle(
                    color: AppTheme.primaryGold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _generateNewSuggestion,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Template chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (widget.isPremium
                      ? InterestMessageTemplates.premiumTemplates
                      : InterestMessageTemplates.freeTemplates)
                  .take(3)
                  .map((template) => ActionChip(
                        label: Text(
                          '${template.substring(0, template.length > 30 ? 30 : template.length)}...',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _applyTemplate(template),
                        backgroundColor: _selectedTemplate == template
                            ? AppTheme.primaryOrange.withValues(alpha: 0.2)
                            : null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Message input
            TextField(
              controller: _messageController,
              maxLines: 4,
              maxLength: maxChars,
              decoration: InputDecoration(
                hintText: 'Write a personal message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '$currentLength/$maxChars',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Premium: Share phone option
            if (widget.isPremium)
              CheckboxListTile(
                value: _sharePhone,
                onChanged: (v) => setState(() => _sharePhone = v ?? false),
                title: const Text('Share my contact number'),
                subtitle: const Text('Let them call you directly'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Premium users can share contact numbers',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber[800],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onPremiumUpgrade,
                      child: const Text('Upgrade'),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Send button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _sendInterest,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSending ? 'Sending...' : 'Send Interest'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
