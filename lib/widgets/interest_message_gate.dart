import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Premium gate that blocks free users from reading interest messages
/// Shows teaser only - "Upgrade to Premium to see message"
class InterestMessageGate extends StatelessWidget {
  final String senderName;
  final bool hasMessage;
  final bool hasPhone;
  final VoidCallback? onUpgrade;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const InterestMessageGate({
    super.key,
    required this.senderName,
    required this.hasMessage,
    this.hasPhone = false,
    this.onUpgrade,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lock icon with glow
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock,
              size: 40,
              color: AppTheme.primaryOrange,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'Premium Feature',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryMaroon,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            hasMessage
                ? '$senderName sent you a message with their interest'
                : '$senderName is interested in your profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),

          // Teaser
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: Colors.grey[400]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message Preview',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ...List.generate(
                            8,
                            (index) => Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Text(
                            ' •••',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Phone teaser (if shared)
          if (hasPhone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone, color: Colors.amber[700], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Contact number shared - Premium only',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Upgrade button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.diamond),
              label: const Text('Upgrade to Premium'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Free option: Accept/Reject without reading
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('Decline', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAccept,
                  icon: Icon(Icons.check, color: AppTheme.sacredGreen),
                  label: Text('Accept', style: TextStyle(color: AppTheme.sacredGreen)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.sacredGreen),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact version for list items
class InterestMessageGateCompact extends StatelessWidget {
  final VoidCallback? onUpgrade;

  const InterestMessageGateCompact({super.key, this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 6),
          Text(
            'Premium to view',
            style: TextStyle(
              fontSize: 12,
              color: Colors.amber[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
