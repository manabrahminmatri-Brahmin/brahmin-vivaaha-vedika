import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/membership.dart';
import '../core/app_router.dart';

/// Service to check and alert users about subscription expiry
class SubscriptionAlertService {
  static const String _lastAlertKey = 'subscription_last_alert_date';
  static Timer? _checkTimer;
  
  /// Start periodic subscription expiry checks
  static void startPeriodicCheck() {
    // Check every 24 hours
    _checkTimer = Timer.periodic(const Duration(hours: 24), (timer) {
      _checkSubscriptionExpiry();
    });
    
    // Also check immediately when service starts
    _checkSubscriptionExpiry();
  }
  
  /// Stop periodic checks
  static void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }
  
  /// Check subscription expiry and show alert if needed
  static Future<void> _checkSubscriptionExpiry() async {
    try {
      // This would be called from app initialization
      // We'll need to access the current user's subscription status
      debugPrint('🔍 Checking subscription expiry...');
    } catch (e) {
      debugPrint('❌ Error checking subscription expiry: $e');
    }
  }
  
  /// Check if user should be shown expiry alert (7 days before expiry)
  static Future<bool> shouldShowExpiryAlert(Membership membership) async {
    if (!membership.isPremium || membership.expiryDate == null) {
      return false;
    }
    
    final daysRemaining = membership.expiryDate != null 
        ? membership.expiryDate!.difference(DateTime.now()).inDays 
        : 0;
    final today = DateTime.now();
    
    // Check if we're within 7 days of expiry
    if (daysRemaining <= 7 && daysRemaining > 0) {
      // Check if we haven't shown alert today
      final lastAlertDate = await _getLastAlertDate();
      if (lastAlertDate == null || !_isSameDay(lastAlertDate, today)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Show subscription expiry alert dialog
  static void showExpiryAlert(BuildContext context, Membership membership) {
    final daysRemaining = membership.expiryDate != null 
        ? membership.expiryDate!.difference(DateTime.now()).inDays 
        : 0;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: AppTheme.kumkumRed),
            const SizedBox(width: 8),
            const Text('Subscription Expiring Soon'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your premium subscription will expire in $daysRemaining day${daysRemaining == 1 ? '' : 's'}.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'To continue enjoying premium features, please renew your subscription before it expires.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryOrange.withAlpha(50)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: const Color(0xFF9E9E9E), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can renew from the Settings > Premium Member section.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Mark that we showed alert today
              await _markAlertShown();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _markAlertShown();
              if (!context.mounted) return;
              Navigator.pop(context);
              NavHelper.push(context, Routes.premiumUpgrade);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Renew Now'),
          ),
        ],
      ),
    );
  }
  
  /// Get the last date we showed an alert
  static Future<DateTime?> _getLastAlertDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateString = prefs.getString(_lastAlertKey);
      if (dateString != null) {
        return DateTime.tryParse(dateString);
      }
    } catch (e) {
      debugPrint('❌ Error getting last alert date: $e');
    }
    return null;
  }
  
  /// Mark that we showed an alert today
  static Future<void> _markAlertShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAlertKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Silently fail - not critical for app functionality
    }
  }
  
  /// Check if two dates are the same day
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
}
