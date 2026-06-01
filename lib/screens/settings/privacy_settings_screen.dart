import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../services/presence_service.dart';
import '../../models/user.dart' as app_models;
import '../../theme/app_theme.dart';
import '../../widgets/screenshot_protected_widget.dart';
import '../../widgets/app_header.dart';
import '../../widgets/common/labeled_adaptive_switch.dart';
import '../../utils/app_error_handler.dart';
import '../../utils/service_health_checker.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/profile/profile_repository.dart';
import '../../services/notification_sound_service.dart';

/// Photo visibility is a single toggle: Public vs Hidden (`is_photo_private`).
/// Older blur / hide-until-interest flags load as ON once; turning Public clears them.

/// Privacy Settings screen
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> with ScreenshotProtection {
  /// Hidden = protected until you accept a member’s photo-view request.
  bool _photoHiddenFromOthers = false;
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _showProfileViews = true;
  bool _allowContactRequests = true;
  bool _hideContactDetails = false;
  bool _premiumOnlyVisibility = false;
  bool _onlyVerifiedUsers = false;
  bool _hideFromSearch = false;
  bool _incognitoMode = false;
  bool _notificationSoundEnabled = true;
  bool _interestSoundEnabled = true;
  bool _messageSoundEnabled = true;
  bool _requestBellSoundEnabled = true;
  final bool _isLoading = false;
  
  // Individual loading states for each setting
  bool _isUpdatingPhotoVisibility = false;
  bool _isUpdatingOnlineStatus = false;
  bool _isUpdatingLastSeen = false;
  bool _isUpdatingProfileViews = false;
  bool _isUpdatingContactRequests = false;
  bool _isUpdatingHideContact = false;
  bool _isUpdatingPremiumOnlyVisibility = false;
  bool _isUpdatingOnlyVerified = false;
  bool _isUpdatingHideSearch = false;
  bool _isUpdatingIncognito = false;
  bool _isUpdatingNotificationSound = false;
  bool _isUpdatingInterestSound = false;
  bool _isUpdatingMessageSound = false;
  bool _isUpdatingRequestBellSound = false;
  bool _isUpdatingDebug = false;
  bool _isUpdatingReport = false;
  DateTime? _photoPrivacySyncedAt;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  bool _fb(app_models.User? user, String key, bool fallback) {
    if (user == null) return fallback;
    // Access privacy settings from user object
    switch (key) {
      case 'is_photo_private':
      case 'profile.isPhotoPrivate':
        return user.profile?.isPhotoPrivate ?? fallback;
      case 'privacy_show_online_status':
        return user.profile?.showOnlineStatus ?? fallback;
      case 'privacy_show_last_seen':
        return user.profile?.showLastSeen ?? fallback;
      default:
        return fallback;
    }
  }

  /// Root-level Firestore field (snake_case keys written by this screen).
  static bool? _docBool(Map<String, dynamic>? d, String key) {
    if (d == null || !d.containsKey(key)) return null;
    final v = d[key];
    if (v is bool) return v;
    return null;
  }

  static bool? _nestedProfileBool(Map<String, dynamic>? d, String key) {
    final p = d?['profile'];
    if (p is! Map<String, dynamic>) return null;
    if (!p.containsKey(key)) return null;
    final v = p[key];
    if (v is bool) return v;
    return null;
  }

  Future<void> _loadSettings() async {
    final authService = context.read<AuthController>();
    final prefs = await SharedPreferences.getInstance();
    final userId = authService.currentUser?.id ?? '';
    final userFallback = authService.currentUser;
    Map<String, dynamic>? docData;
    if (userId.isNotEmpty) {
      docData =
          await ProfileRepository().getUserDocumentDataCacheFirst(userId);
    }
    final notifSoundEnabled = await NotificationSoundService.isSoundEnabled();
    final interestSoundEnabled =
        await NotificationSoundService.isInterestSoundEnabled();
    final messageSoundEnabled =
        await NotificationSoundService.isMessageSoundEnabled();
    final requestBellSoundEnabled =
        await NotificationSoundService.isRequestSoundEnabled();

    if (!mounted) return;

    setState(() {
      // Firestore user doc is source of truth for toggles; prefs only fill gaps.
      final photoFallback = authService.currentUser?.profile?.isPhotoPrivate ??
          prefs.getBool('privacy_photo_private') ??
          false;
      final storedPhotoPrivate = _docBool(docData, 'is_photo_private') ??
          _docBool(docData, 'isPhotoPrivate') ??
          _nestedProfileBool(docData, 'isPhotoPrivate') ??
          _fb(userFallback, 'is_photo_private', photoFallback);
      final storedBlur =
          _docBool(docData, 'privacy_blur_photos_for_strangers') ??
              prefs.getBool('privacy_blur_photos_for_strangers') ??
              false;
      final storedAfterAccept =
          _docBool(docData, 'privacy_photo_visible_after_acceptance') ??
              prefs.getBool('privacy_photo_visible_after_acceptance') ??
              false;
      _photoHiddenFromOthers =
          storedPhotoPrivate || storedBlur || storedAfterAccept;
      _photoPrivacySyncedAt = _parseSyncTime(docData?['photo_privacy_updated_at']);
      _showOnlineStatus = _docBool(docData, 'privacy_show_online_status') ??
          _fb(userFallback, 'privacy_show_online_status', prefs.getBool('privacy_online_status') ?? true);
      _showLastSeen = _docBool(docData, 'privacy_show_last_seen') ??
          _fb(userFallback, 'privacy_show_last_seen', prefs.getBool('privacy_last_seen') ?? true);
      _showProfileViews = _docBool(docData, 'privacy_show_profile_views') ??
          _fb(userFallback, 'privacy_show_profile_views', prefs.getBool('privacy_profile_views') ?? true);
      _allowContactRequests = _docBool(docData, 'privacy_allow_contact_requests') ??
          _fb(
              userFallback, 'privacy_allow_contact_requests', prefs.getBool('privacy_contact_requests') ?? true);
      _hideContactDetails = _docBool(docData, 'privacy_hide_contact_details') ??
          prefs.getBool('privacy_hide_contact_details') ??
          false;
      _premiumOnlyVisibility = _docBool(docData, 'privacy_premium_only_visibility') ??
          prefs.getBool('privacy_premium_only_visibility') ??
          false;
      _onlyVerifiedUsers = _docBool(docData, 'privacy_only_verified_users') ??
          prefs.getBool('privacy_only_verified_users') ??
          false;
      _hideFromSearch = _docBool(docData, 'privacy_hide_from_search') ??
          _fb(userFallback, 'privacy_hide_from_search', prefs.getBool('privacy_hide_search') ?? false);
      _incognitoMode = _docBool(docData, 'privacy_incognito') ??
          _fb(userFallback, 'privacy_incognito', prefs.getBool('privacy_incognito') ?? false);
      _notificationSoundEnabled = notifSoundEnabled;
      _interestSoundEnabled = interestSoundEnabled;
      _messageSoundEnabled = messageSoundEnabled;
      _requestBellSoundEnabled = requestBellSoundEnabled;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      // Firestore first — avoids delaying the network round-trip behind disk I/O.
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;

      if (userId != null && userId.isNotEmpty) {
        switch (key) {
          case 'privacy_online_status':
            await _syncOnlineStatus(value);
            break;
          case 'privacy_last_seen':
            await _syncLastSeen(value);
            break;
          case 'privacy_hide_search':
            await _syncSearchVisibility(value);
            break;
          case 'privacy_contact_requests':
            await _syncContactRequests(value);
            break;
          case 'privacy_hide_contact_details':
            await _syncGenericPrivacyFlag('privacy_hide_contact_details', value);
            break;
          case 'privacy_premium_only_visibility':
            await _syncGenericPrivacyFlag('privacy_premium_only_visibility', value);
            break;
          case 'privacy_only_verified_users':
            await _syncGenericPrivacyFlag('privacy_only_verified_users', value);
            break;
          case 'privacy_profile_views':
            await _syncProfileViews(value);
            break;
          case 'privacy_incognito':
            // Update database with privacy preference
            await authService.updateUserProfileField(userId, 'privacy_incognito', value);
            break;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      // TODO: Implement refreshUserData method in AuthController
      // await authService.refreshUserData();
      AppErrorHandler.logSuccess('PrivacySettings', 'Setting saved: $key = $value');
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to save setting $key: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save setting: ${AppErrorHandler.getErrorMessage(e)}'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _syncOnlineStatus(bool showStatus) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      
      if (userId != null && userId.isNotEmpty) {
        // Update database with privacy preference
        await authService.updateUserProfileField(userId, 'privacy_show_online_status', showStatus);
        
        // If user wants to hide online status, update presence immediately
        final presence = PresenceService();
        if (!showStatus) {
          await presence.goBackground();
        } else {
          final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          if (authUid.isNotEmpty && !presence.isSessionActive) {
            await presence.startTracking(authUid);
          } else {
            await presence.goForeground();
          }
        }
        
        AppErrorHandler.logSuccess('PrivacySettings', 'Online status synced: $showStatus');
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync online status: $e');
    }
  }

  Future<void> _syncSearchVisibility(bool hideFromSearch) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      
      if (userId != null && userId.isNotEmpty) {
        // Update database with privacy preference
        await authService.updateUserProfileField(userId, 'privacy_hide_from_search', hideFromSearch);
        AppErrorHandler.logSuccess('PrivacySettings', 'Search visibility synced: $hideFromSearch');
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync search visibility: $e');
    }
  }

  Future<void> _syncContactRequests(bool allowRequests) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      
      if (userId != null && userId.isNotEmpty) {
        await authService.updateUserProfileField(userId, 'privacy_allow_contact_requests', allowRequests);
        AppErrorHandler.logSuccess('PrivacySettings', 'Contact requests synced: $allowRequests');
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync contact requests: $e');
    }
  }

  Future<void> _syncGenericPrivacyFlag(String field, bool value) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      if (userId != null && userId.isNotEmpty) {
        await authService.updateUserProfileField(userId, field, value);
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync $field: $e');
    }
  }

  Future<void> _syncLastSeen(bool showLastSeen) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      
      if (userId != null && userId.isNotEmpty) {
        // Update database with privacy preference
        await authService.updateUserProfileField(userId, 'privacy_show_last_seen', showLastSeen);
        AppErrorHandler.logSuccess('PrivacySettings', 'Last seen synced: $showLastSeen');
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync last seen: $e');
    }
  }

  Future<void> _syncProfileViews(bool showProfileViews) async {
    try {
      final authService = context.read<AuthController>();
      final userId = authService.currentUser?.id;
      
      if (userId != null && userId.isNotEmpty) {
        // Update database with privacy preference
        await authService.updateUserProfileField(userId, 'privacy_show_profile_views', showProfileViews);
        AppErrorHandler.logSuccess('PrivacySettings', 'Profile views synced: $showProfileViews');
      }
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Failed to sync profile views: $e');
    }
  }

  Future<void> _syncPhotoHiddenFromOthers(bool hidden) async {
    if (_isUpdatingPhotoVisibility || hidden == _photoHiddenFromOthers) return;

    final auth = context.read<AuthController>();
    final userId = auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    final previous = _photoHiddenFromOthers;
    setState(() {
      _isUpdatingPhotoVisibility = true;
      _photoHiddenFromOthers = hidden;
    });

    try {
      final res = await auth.syncPhotoPrivacyBundle(
        isPhotoPrivate: hidden,
        blurPhotosForStrangers: false,
        photoVisibleAfterAcceptance: false,
      );
      if (!mounted) return;
      if (!res.success) {
        setState(() => _photoHiddenFromOthers = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message.isNotEmpty ? res.message : 'Could not save photo privacy'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('privacy_photo_private', hidden);
      await prefs.setBool('privacy_blur_photos_for_strangers', false);
      await prefs.setBool('privacy_photo_visible_after_acceptance', false);

      if (!mounted) return;
      setState(() => _photoPrivacySyncedAt = DateTime.now().toUtc());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hidden
                ? 'Photo is hidden until you accept a photo-view request.'
                : 'Photo is public for members allowed to view your profile.',
          ),
          backgroundColor: AppTheme.sacredGreen,
          duration: const Duration(seconds: 2),
        ),
      );
      AppErrorHandler.logSuccess('PrivacySettings', 'Photo visibility hidden=$hidden');
    } catch (e) {
      AppErrorHandler.logError('PrivacySettings', 'Photo visibility failed: $e');
      if (mounted) {
        setState(() => _photoHiddenFromOthers = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save photo privacy: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPhotoVisibility = false);
    }
  }

  Future<void> _updateOnlineStatus(bool showStatus) async {
    setState(() { _isUpdatingOnlineStatus = true; _showOnlineStatus = showStatus; });
    
    try {
      await _saveSetting('privacy_online_status', showStatus);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showStatus 
                ? '🟢 Online status is now visible to others' 
                : '🔴 Online status is now hidden'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update online status: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingOnlineStatus = false);
      }
    }
  }

  Future<void> _updateLastSeen(bool showLastSeen) async {
    setState(() { _isUpdatingLastSeen = true; _showLastSeen = showLastSeen; });
    
    try {
      await _saveSetting('privacy_last_seen', showLastSeen);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showLastSeen 
                ? '🕐 Last seen is now visible to others' 
                : '🕕 Last seen is now hidden'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update last seen: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingLastSeen = false);
      }
    }
  }

  Future<void> _updateProfileViews(bool showProfileViews) async {
    setState(() { _isUpdatingProfileViews = true; _showProfileViews = showProfileViews; });
    
    try {
      await _saveSetting('privacy_profile_views', showProfileViews);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showProfileViews 
                ? '👁️ Profile views are now visible' 
                : '🙈 Profile views are now hidden'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update profile views: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingProfileViews = false);
      }
    }
  }

  Future<void> _updateContactRequests(bool allowRequests) async {
    setState(() { _isUpdatingContactRequests = true; _allowContactRequests = allowRequests; });
    
    try {
      await _saveSetting('privacy_contact_requests', allowRequests);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allowRequests 
                ? '✅ Contact requests are now enabled' 
                : '🚫 Contact requests are now disabled'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update contact requests: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingContactRequests = false);
      }
    }
  }

  Future<void> _updateHideContactDetails(bool hideContact) async {
    setState(() { _isUpdatingHideContact = true; _hideContactDetails = hideContact; });
    try {
      await _saveSetting('privacy_hide_contact_details', hideContact);
    } finally {
      if (mounted) setState(() => _isUpdatingHideContact = false);
    }
  }

  Future<void> _updatePremiumOnlyVisibility(bool value) async {
    setState(() { _isUpdatingPremiumOnlyVisibility = true; _premiumOnlyVisibility = value; });
    try {
      await _saveSetting('privacy_premium_only_visibility', value);
    } finally {
      if (mounted) setState(() => _isUpdatingPremiumOnlyVisibility = false);
    }
  }

  Future<void> _updateOnlyVerifiedUsers(bool value) async {
    setState(() { _isUpdatingOnlyVerified = true; _onlyVerifiedUsers = value; });
    try {
      await _saveSetting('privacy_only_verified_users', value);
    } finally {
      if (mounted) setState(() => _isUpdatingOnlyVerified = false);
    }
  }

  Future<void> _updateHideSearch(bool hideFromSearch) async {
    setState(() { _isUpdatingHideSearch = true; _hideFromSearch = hideFromSearch; });

    try {
      await _saveSetting('privacy_hide_search', hideFromSearch);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hideFromSearch 
                ? '🔍 Your profile is now hidden from search' 
                : '🌐 Your profile is now visible in search'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update search visibility: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingHideSearch = false);
      }
    }
  }

  Future<void> _updateIncognito(bool incognitoMode) async {
    final authService = context.read<AuthController>();
    final isPremium = authService.currentUser?.membership.isPremium ?? false;
    
    if (!isPremium) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔒 Incognito mode is a premium feature'),
            backgroundColor: AppTheme.kumkumRed,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    setState(() { _isUpdatingIncognito = true; _incognitoMode = incognitoMode; });
    
    try {
      await _saveSetting('privacy_incognito', incognitoMode);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(incognitoMode 
                ? '🥷 Incognito mode is now active' 
                : '👤 Incognito mode is now disabled'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update incognito mode: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingIncognito = false);
      }
    }
  }

  Future<void> _updateNotificationSoundEnabled(bool value) async {
    setState(() {
      _isUpdatingNotificationSound = true;
      _notificationSoundEnabled = value;
    });
    try {
      await NotificationSoundService.setSoundEnabled(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Bell sounds enabled for notifications'
              : 'Bell sounds disabled for notifications'),
          backgroundColor: AppTheme.sacredGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingNotificationSound = false);
    }
  }

  Future<void> _updateInterestSoundEnabled(bool value) async {
    setState(() {
      _isUpdatingInterestSound = true;
      _interestSoundEnabled = value;
    });
    try {
      await NotificationSoundService.setInterestSoundEnabled(value);
    } finally {
      if (mounted) setState(() => _isUpdatingInterestSound = false);
    }
  }

  Future<void> _updateMessageSoundEnabled(bool value) async {
    setState(() {
      _isUpdatingMessageSound = true;
      _messageSoundEnabled = value;
    });
    try {
      await NotificationSoundService.setMessageSoundEnabled(value);
    } finally {
      if (mounted) setState(() => _isUpdatingMessageSound = false);
    }
  }

  Future<void> _updateRequestBellSoundEnabled(bool value) async {
    setState(() {
      _isUpdatingRequestBellSound = true;
      _requestBellSoundEnabled = value;
    });
    try {
      await NotificationSoundService.setRequestSoundEnabled(value);
    } finally {
      if (mounted) setState(() => _isUpdatingRequestBellSound = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.select<AuthController, bool>(
        (a) => a.currentUser?.membership.isPremium ?? false);

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Privacy Settings',
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AC.surface(context),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.privacy_tip, color: AC.textMuted(context)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Control Your Privacy',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryOrange,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage what others can see about you',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 24),

                // Photo Privacy — single consolidated control (maps to legacy fields)
                _buildSectionTitle(context, 'Photo visibility'),
                _buildPhotoVisibilityCard(context),

                const SizedBox(height: 24),

                // Profile Visibility
                _buildSectionTitle(context, 'Profile Visibility'),
                _buildSettingCard(
                  context,
                  icon: Icons.circle,
                  iconColor: AppTheme.sacredGreen,
                  title: 'Show online status',
                  subtitle:
                      'When ON, your green “online” indicator is visible. When OFF, you appear offline.',
                  value: _showOnlineStatus,
                  isLoading: _isUpdatingOnlineStatus,
                  onChanged: (value) => _updateOnlineStatus(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.access_time,
                  title: 'Show last seen',
                  subtitle:
                      'When ON, others see when you were last active. When OFF, last seen is hidden.',
                  value: _showLastSeen,
                  isLoading: _isUpdatingLastSeen,
                  onChanged: (value) => _updateLastSeen(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.visibility,
                  title: 'Reveal profile visits',
                  subtitle:
                      'When ON, people whose profiles you open may see you in their visitors list. When OFF, your visits stay private.',
                  value: _showProfileViews,
                  isLoading: _isUpdatingProfileViews,
                  onChanged: (value) => _updateProfileViews(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.workspace_premium_outlined,
                  title: 'Premium-only visibility',
                  subtitle:
                      'When ON, only premium members can open your profile.',
                  value: _premiumOnlyVisibility,
                  isLoading: _isUpdatingPremiumOnlyVisibility,
                  onChanged: (value) => _updatePremiumOnlyVisibility(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.verified_user_outlined,
                  title: 'Allow only verified users',
                  subtitle:
                      'When ON, only verified members can open your profile.',
                  value: _onlyVerifiedUsers,
                  isLoading: _isUpdatingOnlyVerified,
                  onChanged: (value) => _updateOnlyVerifiedUsers(value),
                ),

                const SizedBox(height: 24),

                // Contact Settings
                _buildSectionTitle(context, 'Contact Settings'),
                _buildSettingCard(
                  context,
                  icon: Icons.message,
                  title: 'Allow contact requests',
                  subtitle:
                      'When ON, members can send you contact / interest requests. When OFF, incoming requests are blocked.',
                  value: _allowContactRequests,
                  isLoading: _isUpdatingContactRequests,
                  onChanged: (value) => _updateContactRequests(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.contact_phone_outlined,
                  title: 'Hide contact details',
                  subtitle:
                      'When ON, your phone/contact details are hidden from profile viewers.',
                  value: _hideContactDetails,
                  isLoading: _isUpdatingHideContact,
                  onChanged: (value) => _updateHideContactDetails(value),
                ),

                const SizedBox(height: 24),

                _buildSectionTitle(context, 'Notification Sounds'),
                _buildSettingCard(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: 'All notification sounds',
                  subtitle:
                      'Master switch for all bell sounds in the app.',
                  value: _notificationSoundEnabled,
                  isLoading: _isUpdatingNotificationSound,
                  onChanged: (value) => _updateNotificationSoundEnabled(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.request_page_outlined,
                  title: 'Request bell sound',
                  subtitle:
                      'Bell when any request is received (interest/photo/birth/community).',
                  value: _requestBellSoundEnabled,
                  isLoading: _isUpdatingRequestBellSound,
                  isDisabled: !_notificationSoundEnabled,
                  onChanged: (value) => _updateRequestBellSoundEnabled(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.favorite_border,
                  title: 'Interest sound',
                  subtitle: 'Sound for interest-related alerts.',
                  value: _interestSoundEnabled,
                  isLoading: _isUpdatingInterestSound,
                  isDisabled: !_notificationSoundEnabled,
                  onChanged: (value) => _updateInterestSoundEnabled(value),
                ),
                _buildSettingCard(
                  context,
                  icon: Icons.message_outlined,
                  title: 'Message sound',
                  subtitle: 'Sound for incoming messages.',
                  value: _messageSoundEnabled,
                  isLoading: _isUpdatingMessageSound,
                  isDisabled: !_notificationSoundEnabled,
                  onChanged: (value) => _updateMessageSoundEnabled(value),
                ),

                const SizedBox(height: 24),

                // Search Visibility
                _buildSectionTitle(context, 'Search Visibility'),
                _buildSettingCard(
                  context,
                  icon: Icons.search_off,
                  title: 'Hide from search',
                  subtitle:
                      'When ON, your profile is excluded from member search. When OFF, you appear in results as usual.',
                  value: _hideFromSearch,
                  isLoading: _isUpdatingHideSearch,
                  onChanged: (value) => _updateHideSearch(value),
                ),

                const SizedBox(height: 24),

                // Premium Features
                _buildSectionTitle(context, 'Premium Privacy Features'),
                _buildSettingCard(
                  context,
                  icon: Icons.visibility_off,
                  title: 'Incognito mode',
                  subtitle:
                      'When ON, your profile visits are not shown to others (premium). When OFF, normal visibility rules apply.',
                  value: _incognitoMode,
                  isLoading: _isUpdatingIncognito,
                  isPremium: true,
                  isLocked: !isPremium,
                  onChanged: (value) => _updateIncognito(value),
                ),

                const SizedBox(height: 32),

                // Debug Section (Debug Mode Only)
                if (kDebugMode) ...[
                  _buildSectionTitle(context, 'Debug & Diagnostics'),
                  _buildSettingCard(
                    context,
                    icon: Icons.bug_report,
                    title: 'Service Health Check',
                    subtitle: 'Run comprehensive service diagnostics',
                    value: false,
                    isLoading: _isUpdatingDebug,
                    isLocked: false,
                    onChanged: (value) => _runServiceHealthCheck(),
                  ),
                  _buildSettingCard(
                    context,
                    icon: Icons.analytics,
                    title: 'View Health Report',
                    subtitle: 'Show detailed service health information',
                    value: false,
                    isLoading: _isUpdatingReport,
                    isLocked: false,
                    onChanged: (value) => _showHealthReport(),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoVisibilityCard(BuildContext context) {
    final muted = AC.textMuted(context);
    final hidden = _photoHiddenFromOthers;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingRowWithLabeledSwitch(
            icon: hidden ? Icons.lock_outline : Icons.lock_open_outlined,
            title: 'Photo visibility',
            subtitle: hidden
                ? 'Hidden — others can see your photo only after you accept their photo-view request.'
                : 'Public — members who may open your profile see your photo as usual.',
            switchValue: hidden,
            inactiveLabel: 'PUBLIC',
            activeLabel: 'HIDDEN',
            semanticsPrefix: 'Photo visibility',
            onSwitchChanged: _isUpdatingPhotoVisibility
                ? null
                : (v) => _syncPhotoHiddenFromOthers(v),
            trailing: _isUpdatingPhotoVisibility
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (_photoPrivacySyncedAt != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8),
              child: Text(
                'Saved: ${_formatSyncTime(_photoPrivacySyncedAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
        ],
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

  Widget _buildSettingCard(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isPremium = false,
    bool isLocked = false,
    bool isDisabled = false,
    bool isLoading = false,
  }) {
    final muted = AC.textMuted(context);
    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              color: AC.surface2(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor ?? AC.textMuted(context)),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: AppTheme.goldGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PREMIUM',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
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
                        color: value && !isDisabled
                            ? AppTheme.sacredGreen
                            : muted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ],
            ),
          ),
          if (isLocked)
            Icon(Icons.lock, size: 20, color: AC.textMuted(context))
          else if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryOrange),
              ),
            )
          else
            Flexible(
              fit: FlexFit.loose,
              child: LabeledAdaptiveSwitch(
                value: value,
                onChanged: isDisabled ? null : onChanged,
              ),
            ),
        ],
      ),
    );

    if (!isDisabled) return card;

    return IgnorePointer(
      child: Opacity(opacity: 0.45, child: card),
    );
  }

  DateTime? _parseSyncTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  String _formatSyncTime(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year} $hh:$min';
  }

  void _runServiceHealthCheck() {
    setState(() => _isUpdatingDebug = true);
    
    ServiceHealthChecker.runHealthCheckAndReport().then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Service health check completed'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Service health check failed: ${AppErrorHandler.getErrorMessage(e)}'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _isUpdatingDebug = false);
      }
    });
  }

  void _showHealthReport() {
    setState(() => _isUpdatingReport = true);
    
    ServiceHealthChecker.getDetailedHealthReport().then((report) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.analytics, color: AppTheme.primaryOrange),
                const SizedBox(width: 8),
                const Text('Service Health Report'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Health: ${report['overall_health_score']}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: report['overall_health_score'] >= 80 
                          ? AppTheme.sacredGreen.withValues(alpha: 0.1)
                          : AppTheme.kumkumRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${report['overall_health_score']}%',
                      style: TextStyle(
                        color: report['overall_health_score'] >= 80 
                            ? AppTheme.sacredGreen
                            : AppTheme.kumkumRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (report['critical_issues'].isNotEmpty) ...[
                    Text('Critical Issues:',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.kumkumRed)),
                    const SizedBox(height: 4),
                    ...report['critical_issues'].map<Widget>((issue) => 
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $issue', style: const TextStyle(fontSize: 14)),
                      ),
                    ).toList(),
                  ],
                  const SizedBox(height: 16),
                  Text('Recommendations:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  ...report['recommendations'].map<Widget>((rec) => 
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $rec', style: const TextStyle(fontSize: 14)),
                      ),
                    ).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to show health report: ${AppErrorHandler.getErrorMessage(e)}'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _isUpdatingReport = false);
      }
    });
  }
}
