import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_router.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';

/// Service to handle membership renewal and upgrade reminders
class MembershipReminderService {
  static const String _lastUpgradeReminderKey = 'last_upgrade_reminder_date';
  static const String _lastRenewalReminderKey = 'last_renewal_reminder_date';

  /// Check and show membership reminders if needed
  static Future<void> checkAndShowReminders(
    BuildContext context,
    User? user,
  ) async {
    if (user == null) return;

    // Check if user is premium and show renewal reminder
    if (user.isPremium) {
      await _checkRenewalReminder(context, user);
    } else {
      // Show upgrade reminder for non-premium users (once per day)
      await _checkUpgradeReminder(context);
    }
  }

  /// Check if renewal reminder should be shown (5 days before expiration)
  static Future<void> _checkRenewalReminder(
    BuildContext context,
    User user,
  ) async {
    if (user.membership.expiryDate == null) return;

    final daysRemaining = user.membership.daysRemaining;
    
    // Show reminder if 5 days or less remaining (show every time app opens)
    if (daysRemaining <= 5 && daysRemaining >= 0) {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastShownDate = prefs.getString(_lastRenewalReminderKey);
      
      // Show reminder every time app opens if 5 days or less remaining
      // But only once per day to avoid spam
      if (lastShownDate != today) {
        if (!context.mounted) return;
        await _showRenewalDialog(context, daysRemaining);
        
        // Mark reminder as shown for today
        await prefs.setString(_lastRenewalReminderKey, today);
      }
    }
  }

  /// Check if upgrade reminder should be shown (once per day for non-premium users)
  static Future<void> _checkUpgradeReminder(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastReminderDate = prefs.getString(_lastUpgradeReminderKey);
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Show reminder only if not shown today
    if (lastReminderDate != today) {
      if (!context.mounted) return;
      await _showUpgradeDialog(context);
      
      // Mark reminder as shown for today
      await prefs.setString(_lastUpgradeReminderKey, today);
    }
  }

  /// Show renewal dialog for premium users
  static Future<void> _showRenewalDialog(
    BuildContext context,
    int daysRemaining,
  ) async {
    // Wait a bit for the screen to load
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismissal but make it prominent
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: AC.card(context),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppTheme.goldGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(200),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: AppTheme.primaryMaroon,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Membership Renewal Reminder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryMaroon,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Urgency message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: daysRemaining <= 2
                        ? AppTheme.kumkumRed.withAlpha(30)
                        : AppTheme.primaryOrange.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: daysRemaining <= 2
                          ? AppTheme.kumkumRed
                          : AppTheme.primaryOrange,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        daysRemaining == 0
                            ? Icons.warning
                            : daysRemaining <= 2
                                ? Icons.error_outline
                                : Icons.info_outline,
                        color: daysRemaining <= 2
                            ? AppTheme.kumkumRed
                            : AppTheme.primaryOrange,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          daysRemaining == 0
                              ? '⚠️ Your Premium membership expires TODAY!'
                              : daysRemaining == 1
                                  ? '⚠️ Your Premium membership expires TOMORROW!'
                                  : daysRemaining <= 2
                                      ? '⚠️ Your Premium membership expires in $daysRemaining days!'
                                      : '⏰ Your Premium membership expires in $daysRemaining days',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: daysRemaining <= 2
                                ? AppTheme.kumkumRed
                                : AppTheme.primaryMaroon,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Renew now to continue enjoying all premium features:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AC.text(context),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFeatureItem('View full profiles & photos'),
                _buildFeatureItem('Request contact details'),
                _buildFeatureItem('Profile analytics & insights'),
                _buildFeatureItem('Priority support'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.sacredGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: AppTheme.sacredGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Starting at just ₹99/month',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.sacredGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Remind Me Later',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryOrange.withAlpha(100),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                NavHelper.push(context, Routes.premiumUpgrade);
              },
              icon: const Icon(
                Icons.workspace_premium,
                color: AppTheme.primaryMaroon,
                size: 20,
              ),
              label: const Text(
                'Renew Now',
                style: TextStyle(
                  color: AppTheme.primaryMaroon,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show upgrade dialog for non-premium users
  static Future<void> _showUpgradeDialog(BuildContext context) async {
    // Wait a bit for the screen to load
    await Future.delayed(const Duration(seconds: 1));
    
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: AC.card(context),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: AppTheme.primaryOrange,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Upgrade to Premium',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unlock all premium features for just ₹99/month!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Premium features include:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildFeatureItem('View full profiles & photos'),
            _buildFeatureItem('Request contact details'),
            _buildFeatureItem('Profile analytics & insights'),
            _buildFeatureItem('Priority support'),
            _buildFeatureItem('No profile viewing restrictions'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              NavHelper.push(context, Routes.premiumUpgrade);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  /// Build a feature list item
  static Widget _buildFeatureItem(String feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 18,
            color: AppTheme.sacredGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feature,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
