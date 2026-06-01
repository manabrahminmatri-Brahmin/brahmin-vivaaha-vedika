import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

/// Notification Settings screen
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  // Push Notifications
  bool _pushEnabled = true;
  bool _newMatchNotif = true;
  bool _profileViewNotif = true;
  bool _interestNotif = true;
  bool _messageNotif = true;
  bool _likeNotif = true;

  // Email Notifications
  bool _emailEnabled = true;
  bool _weeklyMatchEmail = true;
  bool _profileSuggestionEmail = true;
  bool _promotionalEmail = false;

  // SMS Notifications
  bool _smsEnabled = false;
  bool _importantAlertsSms = true;
  bool _verificationSms = true;

  // Quiet Hours
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushEnabled = prefs.getBool('notif_push_enabled') ?? true;
      _newMatchNotif = prefs.getBool('notif_new_match') ?? true;
      _profileViewNotif = prefs.getBool('notif_profile_view') ?? true;
      _interestNotif = prefs.getBool('notif_interest') ?? true;
      _messageNotif = prefs.getBool('notif_message') ?? true;
      _likeNotif = prefs.getBool('notif_like') ?? true;
      
      _emailEnabled = prefs.getBool('notif_email_enabled') ?? true;
      _weeklyMatchEmail = prefs.getBool('notif_weekly_match') ?? true;
      _profileSuggestionEmail = prefs.getBool('notif_profile_suggestion') ?? true;
      _promotionalEmail = prefs.getBool('notif_promotional') ?? false;
      
      _smsEnabled = prefs.getBool('notif_sms_enabled') ?? false;
      _importantAlertsSms = prefs.getBool('notif_important_sms') ?? true;
      _verificationSms = prefs.getBool('notif_verification_sms') ?? true;
      
      _quietHoursEnabled = prefs.getBool('notif_quiet_enabled') ?? false;
      _quietStart = TimeOfDay(
        hour: prefs.getInt('notif_quiet_start_hour') ?? 22,
        minute: prefs.getInt('notif_quiet_start_min') ?? 0,
      );
      _quietEnd = TimeOfDay(
        hour: prefs.getInt('notif_quiet_end_hour') ?? 7,
        minute: prefs.getInt('notif_quiet_end_min') ?? 0,
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Notifications',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryMaroon.withAlpha(10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryMaroon.withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.notifications, color: Color(0xFF757575)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stay Updated',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: AppTheme.primaryMaroon,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Manage how you receive notifications',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),

                  const SizedBox(height: 24),

                  // Push Notifications Section
                  _buildSectionTitle(context, 'Push Notifications'),
                  _buildMainToggle(
                    context,
                    icon: Icons.notifications_active,
                    title: 'Push Notifications',
                    subtitle: 'Receive notifications on your device',
                    value: _pushEnabled,
                    onChanged: (value) {
                      setState(() => _pushEnabled = value);
                      _saveSetting('notif_push_enabled', value);
                    },
                  ),
                  
                  if (_pushEnabled) ...[
                    _buildSubToggle(
                      context,
                      title: 'New Matches',
                      subtitle: 'When you get a new match',
                      value: _newMatchNotif,
                      onChanged: (value) {
                        setState(() => _newMatchNotif = value);
                        _saveSetting('notif_new_match', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Profile Views',
                      subtitle: 'When someone views your profile',
                      value: _profileViewNotif,
                      onChanged: (value) {
                        setState(() => _profileViewNotif = value);
                        _saveSetting('notif_profile_view', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Interest Received',
                      subtitle: 'When someone shows interest',
                      value: _interestNotif,
                      onChanged: (value) {
                        setState(() => _interestNotif = value);
                        _saveSetting('notif_interest', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Messages',
                      subtitle: 'When you receive a message',
                      value: _messageNotif,
                      onChanged: (value) {
                        setState(() => _messageNotif = value);
                        _saveSetting('notif_message', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Liked',
                      subtitle: 'When someone likes you',
                      value: _likeNotif,
                      onChanged: (value) {
                        setState(() => _likeNotif = value);
                        _saveSetting('notif_like', value);
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Email Notifications Section
                  _buildSectionTitle(context, 'Email Notifications'),
                  _buildMainToggle(
                    context,
                    icon: Icons.email,
                    title: 'Email Notifications',
                    subtitle: 'Receive emails about your account',
                    value: _emailEnabled,
                    onChanged: (value) {
                      setState(() => _emailEnabled = value);
                      _saveSetting('notif_email_enabled', value);
                    },
                  ),
                  
                  if (_emailEnabled) ...[
                    _buildSubToggle(
                      context,
                      title: 'Weekly Match Summary',
                      subtitle: 'Get weekly email with new matches',
                      value: _weeklyMatchEmail,
                      onChanged: (value) {
                        setState(() => _weeklyMatchEmail = value);
                        _saveSetting('notif_weekly_match', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Profile Suggestions',
                      subtitle: 'Personalized profile recommendations',
                      value: _profileSuggestionEmail,
                      onChanged: (value) {
                        setState(() => _profileSuggestionEmail = value);
                        _saveSetting('notif_profile_suggestion', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Offers & Updates',
                      subtitle: 'Promotional emails and app updates',
                      value: _promotionalEmail,
                      onChanged: (value) {
                        setState(() => _promotionalEmail = value);
                        _saveSetting('notif_promotional', value);
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // SMS Notifications Section
                  _buildSectionTitle(context, 'SMS Notifications'),
                  _buildMainToggle(
                    context,
                    icon: Icons.sms,
                    title: 'SMS Notifications',
                    subtitle: 'Receive SMS alerts',
                    value: _smsEnabled,
                    onChanged: (value) {
                      setState(() => _smsEnabled = value);
                      _saveSetting('notif_sms_enabled', value);
                    },
                  ),
                  
                  if (_smsEnabled) ...[
                    _buildSubToggle(
                      context,
                      title: 'Important Alerts',
                      subtitle: 'Critical account notifications',
                      value: _importantAlertsSms,
                      onChanged: (value) {
                        setState(() => _importantAlertsSms = value);
                        _saveSetting('notif_important_sms', value);
                      },
                    ),
                    _buildSubToggle(
                      context,
                      title: 'Verification Codes',
                      subtitle: 'OTP and verification messages',
                      value: _verificationSms,
                      onChanged: (value) {
                        setState(() => _verificationSms = value);
                        _saveSetting('notif_verification_sms', value);
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Quiet Hours Section
                  _buildSectionTitle(context, 'Quiet Hours'),
                  _buildMainToggle(
                    context,
                    icon: Icons.do_not_disturb_on,
                    title: 'Quiet Hours',
                    subtitle: 'Pause notifications during specific hours',
                    value: _quietHoursEnabled,
                    onChanged: (value) {
                      setState(() => _quietHoursEnabled = value);
                      _saveSetting('notif_quiet_enabled', value);
                    },
                  ),
                  
                  if (_quietHoursEnabled)
                    Container(
                      margin: const EdgeInsets.only(left: 16, top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AC.card(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AC.divider(context)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTimeSelector(
                              context,
                              label: 'From',
                              time: _quietStart,
                              onTap: () => _selectTime(context, true),
                            ),
                          ),
                          SizedBox(width: 16),
                          Icon(Icons.arrow_forward, color: AC.textMuted(context)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTimeSelector(
                              context,
                              label: 'To',
                              time: _quietEnd,
                              onTap: () => _selectTime(context, false),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 32),

                  // Test Notification
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Test notification sent!'),
                            backgroundColor: AppTheme.sacredGreen,
                          ),
                        );
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Send Test Notification'),
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AC.textMuted(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _buildMainToggle(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.divider(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryMaroon.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Color(0xFF757575)),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textMuted(context),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${value ? 'ON' : 'OFF'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: value
                            ? AppTheme.sacredGreen
                            : AC.textMuted(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ],
            ),
          ),
          _buildLabeledSwitch(context, value: value, onChanged: onChanged),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildSubToggle(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AC.divider(context).withAlpha(50)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textMuted(context),
                        fontSize: 11,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${value ? 'ON' : 'OFF'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: value
                            ? AppTheme.sacredGreen
                            : AC.textMuted(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ],
            ),
          ),
          _buildLabeledSwitch(context, value: value, onChanged: onChanged),
        ],
      ),
    ).animate().fadeIn();
  }

  /// OFF / ON labels + adaptive switch so the active state is obvious in light and dark mode.
  Widget _buildLabeledSwitch(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppTheme.primaryOrange;
    final muted = AC.textMuted(context);
    return Semantics(
      label: value ? 'On' : 'Off',
      toggled: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'OFF',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: value ? muted : accent,
                ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: cs.onPrimary,
              activeTrackColor: accent,
              inactiveThumbColor: cs.surfaceContainerHighest,
              inactiveTrackColor: muted.withAlpha(120),
            ),
          ),
          Text(
            'ON',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: value ? accent : muted,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSelector(
    BuildContext context, {
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textMuted(context),
                ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryMaroon.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _formatTime(time),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.primaryMaroon,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _quietStart : _quietEnd,
    );
    
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietStart = picked;
          _saveSetting('notif_quiet_start_hour', picked.hour);
          _saveSetting('notif_quiet_start_min', picked.minute);
        } else {
          _quietEnd = picked;
          _saveSetting('notif_quiet_end_hour', picked.hour);
          _saveSetting('notif_quiet_end_min', picked.minute);
        }
      });
    }
  }
}
