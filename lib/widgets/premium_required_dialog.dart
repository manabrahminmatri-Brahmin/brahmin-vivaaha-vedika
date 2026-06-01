import 'package:flutter/material.dart';
import '../models/membership.dart';
import '../theme/app_theme.dart';

/// Dialog to show when premium features are required
class PremiumRequiredDialog {
  static Future<bool> show(BuildContext context, String feature) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PremiumRequiredDialog(feature: feature),
    );
    
    return result ?? false;
  }
}

class _PremiumRequiredDialog extends StatelessWidget {
  final String feature;

  const _PremiumRequiredDialog({required this.feature});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.diamond,
            color: AppTheme.primaryOrange,
            size: 24,
          ),
          SizedBox(width: 8),
          const Text('Premium Feature'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$feature is a premium feature.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AC.text(context),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Upgrade to Silver, Gold, or Platinum membership to access this feature and enjoy many more benefits.',
            style: TextStyle(
              fontSize: 14,
              color: AC.card(context),
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryOrange.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Premium Benefits:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                const SizedBox(height: 8),
                ...MembershipFeatures.platinumFeatures.map((benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: AppTheme.primaryOrange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          benefit,
                          style: TextStyle(
                            fontSize: 12,
                            color: AC.textSub(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Maybe Later'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange,
            foregroundColor: Colors.white,
          ),
          child: const Text('Upgrade Now'),
        ),
      ],
    );
  }
}
