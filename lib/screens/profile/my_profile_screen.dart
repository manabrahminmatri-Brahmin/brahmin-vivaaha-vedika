import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/reference_data.dart';
import '../../legacy/compatibility.dart';
import '../../models/user.dart' as app_models;
import '../../theme/app_theme.dart';
import '../../widgets/profile_photo.dart';
import '../../utils/app_transitions.dart';
import '../../widgets/loading_widgets.dart';
import '../../widgets/screenshot_protected_widget.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/security/protected_image_cache_service.dart';
import '../../utils/profile_photo_cache.dart';
import '../../services/profile_document_submission_service.dart';
import '../../core/identity_service.dart';
import '../../core/app_router.dart';
import 'profile_wizard_screen.dart';
import '../../widgets/app_header.dart';
import '../../widgets/common/labeled_adaptive_switch.dart';

/// Profile section data model
class ProfileSection {
  final String title;
  final IconData icon;
  final List<Map<String, String>> items;
  final bool isVisible;

  ProfileSection({
    required this.title,
    required this.icon,
    required this.items,
    this.isVisible = true,
  });
}

/// User's own profile screen with collapsible sections
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with TickerProviderStateMixin, ScreenshotProtection {
  bool _isLoading = true;
  late ScrollController _scrollController;
  late TabController _tabController;
  bool _showScrollToTop = false;
  bool _isUpdatingOwnPhotoPrivacy = false;
  bool _submittingIdProof = false;

  void _showSnack(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(snackBar);
  }

  // Tracks the last profileId we loaded — if auth service emits a new user
  // (after wizard edit) we reload so edits appear without a full restart.
  String? _lastLoadedUserId;
  AuthService? _authReloadListenerTarget;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _scrollController = ScrollController();
    _tabController = TabController(length: 7, vsync: this);

    // Add scroll listener
    _scrollController.addListener(_onScroll);
    
    // Load profile data
    _loadProfileData();
  }

  /// When a different user logs in, reload. Avoid [context.watch] here — it
  /// subscribed the whole screen to every [AuthService] notification.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    if (!identical(_authReloadListenerTarget, auth)) {
      _authReloadListenerTarget?.removeListener(_onAuthUserIdentityChanged);
      _authReloadListenerTarget = auth;
      _authReloadListenerTarget!.addListener(_onAuthUserIdentityChanged);
    }
  }

  void _onAuthUserIdentityChanged() {
    if (!mounted) return;
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId != null && userId != _lastLoadedUserId && !_isLoading) {
      _lastLoadedUserId = userId;
      _loadProfileData();
    }
  }

  /// 🔧 DEBUG: Check and log authentication state
  Future<void> _debugAuthenticationState() async {
    try {
      debugPrint('🔧 === AUTHENTICATION DEBUG ===');
      
      // Check Firebase Auth state
      final firebaseUser = FirebaseAuth.instance.currentUser;
      debugPrint('🔧 Firebase Auth User: ${firebaseUser?.uid ?? 'null'}');
      
      // Check IdentityService state
      final identityService = IdentityService();
      try {
        final profileId = await identityService.getProfileId();
        debugPrint('🔧 Profile ID: $profileId');
      } catch (e) {
        debugPrint('🔧 Profile ID Error: $e');
      }
      
      try {
        final userId = await identityService.getUserId();
        debugPrint('🔧 User ID: $userId');
      } catch (e) {
        debugPrint('🔧 User ID Error: $e');
      }
      
      // Check SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      debugPrint('🔧 SharedPreferences profile_id: ${prefs.getString('profile_id')}');
      debugPrint('🔧 SharedPreferences current_user_id: ${prefs.getString('current_user_id')}');
      
      debugPrint('🔧 === END AUTHENTICATION DEBUG ===');
    } catch (e) {
      debugPrint('🔧 Debug authentication state failed: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.offset > 300 && !_showScrollToTop) {
      setState(() {
        _showScrollToTop = true;
      });
    } else if (_scrollController.offset <= 300 && _showScrollToTop) {
      setState(() {
        _showScrollToTop = false;
      });
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadProfileData() async {
    try {
      debugPrint('🔍 Loading profile data...');
      final authService = context.read<AuthService>();
      debugPrint('🔍 AuthService retrieved');
      
      // 🔧 DEBUG: Check authentication state
      await _debugAuthenticationState();

      // Always pull the latest data from Firestore so edits made in the
      // profile wizard are reflected immediately when returning to this tab.
      // Without this, IndexedStack keeps the widget alive and initState is
      // never re-called, so stale in-memory data is shown after an edit.
      await authService.refreshUserData();

      final user = authService.currentUser;
      debugPrint('🔍 Current user: ${user?.id}');

      if (user != null) {
        _lastLoadedUserId = user.id; // mark as loaded so didChangeDependencies doesn't re-fire immediately
        // Just set loading to false - let build method handle null profile
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        debugPrint('✅ Profile data loaded successfully');

        // Load analytics in the background so the analytics section is ready
        // when the user scrolls down to it (non-blocking — errors are swallowed).
        if (mounted) {
          final analyticsService = context.read<ProfileAnalyticsService>();
          final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          analyticsService
              .loadAnalyticsForUser(
                authUid.isNotEmpty ? authUid : user.id,
              )
              .catchError((e) => debugPrint('⚠️ MyProfile analytics load: $e'));
        }
      } else {
        // User is null - try to recover or redirect to login
        debugPrint('❌ User is null - attempting recovery...');
        
        // Try to recover from Firebase Auth state
        try {
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            debugPrint('🔧 Firebase user exists, trying to recover identity...');
            // Force re-initialization of auth service
            await authService.initialize();
            
            // Try loading again after recovery
            await Future.delayed(const Duration(seconds: 1));
            await _loadProfileData();
            return;
          }
        } catch (recoveryError) {
          debugPrint('❌ Recovery failed: $recoveryError');
        }
        
        // If all recovery attempts fail, redirect to login
        debugPrint('❌ All recovery failed - redirecting to login');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(Routes.authSelection);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading profile data: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorDialog('Failed to load profile data. Please try again.\n\nError: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AC.card(context),
        title: Text('Error', style: TextStyle(color: AC.text(context))),
        content: SingleChildScrollView(
          child: Text(message, style: TextStyle(color: AC.textSub(context))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadProfileData(); // Retry loading
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    _showSnack(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _authReloadListenerTarget?.removeListener(_onAuthUserIdentityChanged);
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Format `List<String>` field for display as comma-separated text.
  String formatList(dynamic value) {
    if (value == null) return 'Not specified';
    if (value is List) return value.join(', ');
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    try {
      debugPrint('🔍 Building MyProfileScreen...');
      return _buildContent(context);
    } catch (e, stackTrace) {
      debugPrint('❌ MyProfileScreen build error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppHeader(
          title: 'My Profile',
          showLogo: true,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Profile Screen Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed(Routes.home);
                  },
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    // Show loading state while initializing
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppHeader(
          title: 'My Profile',
          showLogo: true,
        ),
        body: const Center(
          child: LoadingIndicator(
            message: 'Loading your profile...',
            size: 48,
          ),
        ),
      );
    }

    return Selector<AuthService, app_models.User?>(
      selector: (_, a) => a.currentUser,
      builder: (context, user, __) {
        final authService = context.read<AuthService>();
        final profile = user?.profile;
        final isPremium = user?.membership.isPremium ?? false;
        return _buildProfileBody(
            context, authService, user, profile, isPremium);
      },
    );
  }

  Widget _buildProfileBody(
    BuildContext context,
    AuthService authService,
    app_models.User? user,
    app_models.UserProfile? profile,
    bool isPremium,
  ) {
    // Handle null profile case with automatic redirection
    if (profile == null) {
      // Queue navigation after this frame to avoid context-after-async warnings.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(this.context).pushReplacementNamed('/profile-wizard');
      });
      
      // Show loading while redirecting
      return Scaffold(
        appBar: AppHeader(
          title: 'My Profile',
          showLogo: true,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: null,
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Setting up your profile...',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If profile exists but is empty, show minimal profile with create button
    if (profile.firstName.isEmpty == true && profile.lastName.isEmpty == true) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppHeader(
          title: 'My Profile',
          showLogo: true,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_outline,
                  size: 80,
                  color: AC.textSub(context),
                ),
                SizedBox(height: 20),
                Text(
                  'Complete Your Profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AC.text(context),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Please add your basic information to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: AC.textSub(context),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/profile-wizard');
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Complete Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: null,
          color: AC.bg(context),
        ),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Standardized Header
            SliverAppHeader(
              title: 'My Profile',
              showLogo: true,
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),

            // Enhanced Profile Card with larger photo
            SliverToBoxAdapter(
              child: _buildEnhancedProfileCard(
                    context,
                    authService,
                    profile,
                    isPremium,
                  )
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideX(begin: 0.1),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),

            // Profile Details Tabs
            SliverToBoxAdapter(
              child: _buildProfileDetailsTabs(context, profile)
                  .animate()
                  .fadeIn(delay: const Duration(milliseconds: 400))
                  .slideX(begin: 0.1),
            ),

            // Quick Actions
            SliverToBoxAdapter(
              child: _buildQuickActionsSection(context, authService, isPremium)
                  .animate()
                  .fadeIn(delay: 500.ms)
                  .slideX(begin: 0.1),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100), // Extra padding to clear tab bar
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _showScrollToTop
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80), // clears the floating bottom nav
              child: FloatingActionButton(
                onPressed: _scrollToTop,
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                mini: true,
                elevation: 6,
                child: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            )
          : null,
    );
  }

  // Inline profile card widget that was referenced but not defined
  Widget _buildEnhancedProfileCard(
    BuildContext context,
    AuthService authService,
    app_models.UserProfile? profile,
    bool isPremium,
  ) {
    // 🔥 Get FRESH user data directly from auth service
    final freshUser = authService.currentUser;
    final freshProfile = freshUser?.profile;
    final hasPhoto = freshProfile?.profilePicture?.isNotEmpty == true;
    final membership = freshUser?.membership;
    final isPremiumActive = membership?.isPremium ?? false;
    final daysLeft = membership?.daysRemaining ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Enhanced Photo Section - Larger size
          GestureDetector(
            onTap: () => _showPhotoUploadDialog(context),
            child: Stack(
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: hasPhoto ? null : AC.surface2(context),
                    borderRadius: BorderRadius.circular(20),
                    border: hasPhoto
                        ? Border.all(color: AppTheme.primaryOrange, width: 3)
                        : Border.all(
                            color: AppTheme.primaryGold.withAlpha(100),
                            width: 2,
                          ),
                  ),
                  child: ProfilePhoto(
                      key: ValueKey('profile_photo_${freshProfile?.profilePicture ?? "empty"}'),
                      profile: freshProfile ?? profile!,
                      size: 200,
                      borderRadius: 17,
                      borderWidth: hasPhoto ? 3 : 2,
                      borderColor: hasPhoto ? AppTheme.primaryOrange : AppTheme.primaryGold.withAlpha(100),
                      isOwner: true,
                    ),
                ),
                // Edit photo badge
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(50),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.edit,
                      color: AC.card(context),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          Text(
            hasPhoto ? 'Tap to change photo' : 'Tap to add photo',
            style: TextStyle(
              fontSize: 12,
              color: AC.textSub(context),
            ),
          ),

          const SizedBox(height: 14),

          // Same single control as Privacy Settings: PUBLIC / HIDDEN (request to view).
          Container(
            width: MediaQuery.sizeOf(context).width * 0.92,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AC.border(context)),
            ),
            child: SettingRowWithLabeledSwitch(
              icon: (freshProfile?.isPhotoPrivate ?? false)
                  ? Icons.lock_outline
                  : Icons.lock_open_outlined,
              title: 'Photo visibility',
              subtitle: (freshProfile?.isPhotoPrivate ?? false)
                  ? 'Hidden — visible only after you accept a photo-view request.'
                  : 'Public — visible to members who may open your profile.',
              switchValue: freshProfile?.isPhotoPrivate ?? false,
              inactiveLabel: 'PUBLIC',
              activeLabel: 'HIDDEN',
              semanticsPrefix: 'Photo visibility',
              onSwitchChanged: _isUpdatingOwnPhotoPrivacy
                  ? null
                  : (value) => _updateOwnPhotoPrivacy(authService, value),
              trailing: _isUpdatingOwnPhotoPrivacy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),

          const SizedBox(height: 20),

          if (isPremiumActive)
            Container(
              width: MediaQuery.sizeOf(context).width * 0.8,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.sacredGreen.withAlpha(70)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: AppTheme.sacredGreen, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      daysLeft > 0
                          ? 'Premium active - $daysLeft day${daysLeft == 1 ? '' : 's'} remaining'
                          : 'Premium expires today',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.sacredGreen,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, Routes.premiumUpgrade),
                    child: const Text('Renew'),
                  ),
                ],
              ),
            ),

          // Profile Completion with Linear Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AC.card(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AC.shadow(context).withAlpha(26),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Profile Completion',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AC.text(context),
                      ),
                ),
                SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (profile?.computedCompletionPercentage ?? 0) / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${profile?.computedCompletionPercentage ?? 0}% Complete',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AC.text(context),
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Profile ID — solid orange band + white label (readable in light & dark)
          Builder(
            builder: (context) {
              final isDark =
                  Theme.of(context).brightness == Brightness.dark;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            AppTheme.primaryOrange.withAlpha(200),
                            AppTheme.primaryOrange.withAlpha(160),
                          ]
                        : [
                            AppTheme.primaryOrange,
                            AppTheme.primaryOrange.withAlpha(235),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.templeGold.withAlpha(isDark ? 200 : 255),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryOrange.withAlpha(
                          isDark ? 40 : 55),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.badge,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ID: ${Provider.of<AuthService>(context, listen: false).currentUser?.profileId ?? 'N/A'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14,
                            letterSpacing: 0.35,
                            shadows: [
                              Shadow(
                                color: Colors.black.withAlpha(35),
                                offset: const Offset(0, 0.5),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                    ),
                  ],
                ),
              );
            },
          ),

          SizedBox(height: 16),

          // Name
          Text(
            profile?.fullName ?? 'Complete Your Profile',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AC.text(context),
                ),
            textAlign: TextAlign.center,
          ),

          if (profile?.age != null) ...[
            const SizedBox(height: 4),
            Text(
              '${profile?.age} years • ${profile?.height ?? 'Not specified'}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AC.textSub(context),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _updateOwnPhotoPrivacy(
      AuthService authService, bool isPrivate) async {
    if (_isUpdatingOwnPhotoPrivacy) return;
    setState(() => _isUpdatingOwnPhotoPrivacy = true);
    try {
      final userId = authService.currentUser?.id ?? '';
      if (userId.isEmpty) throw Exception('No user logged in');

      await authService.updatePhotoPrivacy(isPrivate);

      if (mounted) {
        _showSnack(
          SnackBar(
            content: Text(isPrivate
                ? 'Photo hidden until you accept a photo-view request'
                : 'Photo is public for profile viewers'),
            backgroundColor: AppTheme.sacredGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          SnackBar(
            content: Text('Failed to update photo privacy: $e'),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingOwnPhotoPrivacy = false);
      }
    }
  }

  Widget _buildProfileDetailsTabs(BuildContext context, profile) {
    if (profile == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AC.shadow(context).withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Tab Bar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.primaryOrange,
                    width: 3,
                  ),
                ),
              ),
              indicatorColor: AppTheme.primaryOrange,
              indicatorWeight: 3,
              labelColor: AC.text(context),
              unselectedLabelColor: AC.textSub(context),
              labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AC.text(context),
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AC.textSub(context),
              ),
              tabs: const [
                Tab(text: 'Basic'),
                Tab(text: 'Birth'),
                Tab(text: 'Religious'),
                Tab(text: 'Education'),
                Tab(text: 'Family'),
                Tab(text: 'Lifestyle'),
                Tab(text: 'Partner'),
              ],
            ),
          ),
          // Tab Content
          SizedBox(
            height: 400, // Fixed height for tab content
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBasicInfoTab(context, profile),
                _buildBirthDetailsTab(context, profile),
                _buildReligiousDetailsTab(context, profile),
                _buildEducationCareerTab(context, profile),
                _buildFamilyDetailsTab(context, profile),
                _buildLifestyleTab(context, profile),
                _buildPartnerPreferencesTab(context, profile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoItem(context,'Name',            profile?.fullName          ?? 'Not specified'),
          _buildInfoItem(context,'Age',             '${profile?.age ?? 'Not specified'} years'),
          _buildInfoItem(context,'Gender',          profile?.gender.displayName ?? 'Not specified'),
          _buildInfoItem(context,'Height',          profile?.height            ?? 'Not specified'),
          _buildInfoItem(context,'Weight',          profile?.weight            ?? 'Not specified'),
          _buildInfoItem(context,'Complexion',      profile?.complexion        ?? 'Not specified'),
          _buildInfoItem(context,'Body Type',       profile?.bodyType          ?? 'Not specified'),
          _buildInfoItem(context,'Physical Status', profile?.physicalStatus    ?? 'Not specified'),
          _buildInfoItem(context,'Marital Status',  profile?.maritalStatus     ?? 'Not specified'),
          _buildInfoItem(context,'Profile Created By',       profile?.profileCreatedBy         ?? 'Not specified'),
          _buildInfoItem(context,'Creator Relation',          profile?.profileCreatedByRelation ?? 'Not specified'),
        ],
      ),
    );
  }

  Widget _buildBirthDetailsTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoItem(context,'Date of Birth',   profile?.dateOfBirth.toString().split(' ')[0] ?? 'Not specified'),
          _buildInfoItem(context,'Time of Birth',   profile?.timeOfBirth       ?? 'Not specified'),
          _buildInfoItem(context,'Place of Birth',  profile?.placeOfBirth      ?? 'Not specified'),
          _buildInfoItem(context,'Birth State',     profile?.placeOfBirthState ?? 'Not specified'),
          _buildInfoItem(context,'Birth Country',   profile?.placeOfBirthCountry ?? 'Not specified'),
          _buildInfoItem(context,'Nakshatra',       profile?.nakshatra         ?? 'Not specified'),
          _buildInfoItem(context,'Pada',            profile?.pada              ?? 'Not specified'),
          _buildInfoItem(context,'Rasi',            profile?.rasi              ?? 'Not specified'),
          _buildInfoItem(context,'Manglik Status',  profile?.manglikStatus     ?? 'Not specified'),
          _buildInfoItem(context,'Has Horoscope',   profile?.hasHoroscope == true ? 'Yes' : 'No'),
        ],
      ),
    );
  }

  Widget _buildReligiousDetailsTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoItem(context,'Sect',         profile?.sect          ?? 'Not specified'),
          _buildInfoItem(context,'Sub-Sect',     profile?.subSect       ?? 'Not specified'),
          _buildInfoItem(context,'Gothram',      profile?.gothram       ?? 'Not specified'),
          _buildInfoItem(context,'Has Horoscope', profile?.hasHoroscope == true ? 'Yes' : 'No'),
        ],
      ),
    );
  }

  Widget _buildEducationCareerTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Education'),
          _buildInfoItem(context,'Education',            profile?.education              ?? 'Not specified'),
          _buildInfoItem(context,'Specialization',        profile?.specialization        ?? 'Not specified'),
          _buildInfoItem(context,'Education Status',      profile?.educationStatus       ?? 'Not specified'),
          _buildInfoItem(context,'University / Institution', profile?.universityName     ?? 'Not specified'),
          _buildInfoItem(context,'Edu. City',             profile?.educationLocationCity ?? 'Not specified'),
          _buildInfoItem(context,'Edu. State',            profile?.educationLocationState ?? 'Not specified'),
          _buildInfoItem(context,'Edu. Country',          profile?.educationLocationCountry ?? 'Not specified'),
          if ((profile?.additionalQualifications ?? '').isNotEmpty)
            _buildInfoItem(context,'Additional Qualifications', profile!.additionalQualifications!),
          if ((profile?.qualificationNotes ?? '').isNotEmpty)
            _buildInfoItem(context,'Qualification Notes', profile!.qualificationNotes!),
          const SizedBox(height: 8),
          _buildSectionHeader('Career'),
          _buildInfoItem(context,'Occupation',       profile?.occupation      ?? 'Not specified'),
          if (profile?.occupation == ReferenceData.ownBusinessOccupation) ...[
            if ((profile?.businessDescription ?? '').trim().isNotEmpty)
              _buildInfoItem(
                context,
                'Business',
                profile!.businessDescription!.trim(),
              ),
          ] else ...[
            _buildInfoItem(context,'Employment Type',  profile?.employmentType  ?? 'Not specified'),
            _buildInfoItem(context,'Company / Org.',   profile?.companyName     ?? 'Not specified'),
          ],
          _buildInfoItem(context,'Income Range',     profile?.incomeRange     ?? 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('Current Location'),
          _buildInfoItem(context,'City',    profile?.city    ?? 'Not specified'),
          _buildInfoItem(context,'State',   profile?.state   ?? 'Not specified'),
          _buildInfoItem(context,'Country', profile?.country ?? 'Not specified'),
        ],
      ),
    );
  }

  Widget _buildFamilyDetailsTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Family Overview'),
          _buildInfoItem(context,'Family Type',   profile?.familyType   ?? 'Not specified'),
          _buildInfoItem(context,'Family Status', profile?.familyStatus ?? 'Not specified'),
          _buildInfoItem(context,'Family Values', profile?.familyValues ?? 'Not specified'),
          if ((profile?.aboutFamily ?? '').isNotEmpty)
            _buildInfoItem(context,'About Family', profile!.aboutFamily!),
          const SizedBox(height: 8),
          _buildSectionHeader('Father'),
          _buildInfoItem(context,'Father\'s Name',       profile?.fatherName       ?? 'Not specified'),
          _buildInfoItem(context,'Father\'s Occupation', profile?.fatherOccupation ?? 'Not specified'),
          if ((profile?.fatherNote ?? '').isNotEmpty)
            _buildInfoItem(context,'Father\'s Note', profile!.fatherNote!),
          const SizedBox(height: 8),
          _buildSectionHeader('Mother'),
          _buildInfoItem(context,'Mother\'s Name',       profile?.motherName       ?? 'Not specified'),
          _buildInfoItem(context,'Mother\'s Occupation', profile?.motherOccupation ?? 'Not specified'),
          if ((profile?.motherNote ?? '').isNotEmpty)
            _buildInfoItem(context,'Mother\'s Note', profile!.motherNote!),
          if ((profile?.motherSurname ?? '').isNotEmpty)
            _buildInfoItem(context,'Mother\'s Maiden Surname', profile!.motherSurname!),
          const SizedBox(height: 8),
          _buildSectionHeader('Siblings'),
          _buildInfoItem(context,'Brothers', '${profile?.brothers ?? 0} (${profile?.brothersMarried ?? 0} married)'),
          _buildInfoItem(context,'Sisters',  '${profile?.sisters  ?? 0} (${profile?.sistersMarried  ?? 0} married)'),
          const SizedBox(height: 8),
          _buildSectionHeader('Family Origin'),
          _buildInfoItem(context,'Family Origin City',    profile?.familyOriginCity    ?? 'Not specified'),
          _buildInfoItem(context,'Family Origin State',   profile?.familyOriginState   ?? 'Not specified'),
          _buildInfoItem(context,'Family Origin Country', profile?.familyOriginCountry ?? 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('Native Place'),
          _buildInfoItem(context,'Native City',    profile?.nativePlaceCity    ?? 'Not specified'),
          _buildInfoItem(context,'Native State',   profile?.nativePlaceState   ?? 'Not specified'),
          _buildInfoItem(context,'Native Country', profile?.nativePlaceCountry ?? 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('Community References'),
          _buildInfoItem(context,'Known Reference 1', profile?.knownReference  ?? 'Not specified'),
          _buildInfoItem(context,'Known Reference 2', profile?.knownReference2 ?? 'Not specified'),
        ],
      ),
    );
  }

  Widget _buildLifestyleTab(BuildContext context, profile) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Food & Habits'),
          _buildInfoItem(context,'Food Habit',  profile?.foodHabit    ?? 'Not specified'),
          _buildInfoItem(context,'Smoking',     profile?.smokingHabit ?? 'Not specified'),
          _buildInfoItem(context,'Drinking',    profile?.drinkingHabit ?? 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('Interests & Languages'),
          _buildInfoItem(context,'Languages', formatList(profile?.languages)),
          _buildInfoItem(context,'Hobbies',   formatList(profile?.hobbies)),
          _buildInfoItem(context,'Interests', formatList(profile?.interests)),
          const SizedBox(height: 8),
          _buildSectionHeader('Relocation'),
          _buildInfoItem(context,'Citizenship',        profile?.citizenship       ?? 'Not specified'),
          _buildInfoItem(context,'Settled Abroad',     profile?.settledAbroad     ?? 'Not specified'),
          _buildInfoItem(context,'Willing to Relocate', (profile?.willingToRelocate == true) ? 'Yes' : 'Not specified'),
          _buildInfoItem(context,'Relocation Pref.',   profile?.relocatePreference ?? 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('About Me'),
          if ((profile?.aboutMe ?? '').isNotEmpty)
            _buildInfoItem(context,'About Me', profile!.aboutMe!)
          else
            _buildInfoItem(context,'About Me', 'Not specified'),
        ],
      ),
    );
  }

  Widget _buildPartnerPreferencesTab(BuildContext context, profile) {
    final ageMin = profile?.partnerAgeMin;
    final ageMax = profile?.partnerAgeMax;
    final ageRange = (ageMin != null && ageMax != null)
        ? '$ageMin – $ageMax years'
        : (ageMin != null ? '$ageMin+ years' : 'Not specified');

    final htMin = profile?.partnerHeightMin;
    final htMax = profile?.partnerHeightMax;
    final htRange = (htMin != null && htMax != null)
        ? '$htMin – $htMax'
        : (htMin ?? 'Not specified');

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Basic Expectations'),
          _buildInfoItem(context,'Age Range',      ageRange),
          _buildInfoItem(context,'Height Range',   htRange),
          _buildInfoItem(context,'Marital Status', formatList(profile?.partnerMaritalStatus)),
          _buildInfoItem(context,'Income Min',     profile?.partnerIncomeMin ?? 'Not specified'),
          _buildInfoItem(context,'Manglik Pref.',  (profile?.partnerManglikPreference == true) ? 'Accepts Manglik' : 'Not specified'),
          const SizedBox(height: 8),
          _buildSectionHeader('Education & Career'),
          _buildInfoItem(context,'Education',  formatList(profile?.partnerEducation)),
          _buildInfoItem(context,'Occupation', formatList(profile?.partnerOccupation)),
          const SizedBox(height: 8),
          _buildSectionHeader('Location Preferences'),
          _buildInfoItem(context,'Preferred Locations', formatList(profile?.partnerLocations)),
          const SizedBox(height: 8),
          _buildSectionHeader('Expectations'),
          if ((profile?.partnerExpectations ?? '').isNotEmpty)
            _buildInfoItem(context,'Partner Expectations', profile!.partnerExpectations!)
          else
            _buildInfoItem(context,'Partner Expectations', 'Not specified'),
          if ((profile?.partnerPreferences ?? '').isNotEmpty)
            _buildInfoItem(context,'Additional Preferences', profile!.partnerPreferences!)
          else
            _buildInfoItem(context,'Additional Preferences', 'Not specified'),
        ],
      ),
    );
  }

  /// Sub-section header within a tab
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Text(title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppTheme.primaryOrange)),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ]),
    );
  }

  Widget _buildInfoItem(BuildContext context, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AC.surface(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AC.textSub(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: AC.text(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadIdentityDocument(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uid = context.read<AuthService>().currentUser?.id ?? '';
    if (uid.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Please sign in again to upload documents.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _submittingIdProof = true);
    try {
      final result =
          await ProfileDocumentSubmissionService().pickAndSubmitIdProof(uid);
      if (!mounted) return;
      if (result.cancelled) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Document submitted for admin review.'
                : (result.errorMessage ??
                    'Could not upload. Please try again.'),
          ),
          backgroundColor:
              result.success ? Colors.green : AppTheme.kumkumRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingIdProof = false);
    }
  }

  Widget _buildQuickActionsSection(BuildContext context, AuthService authService, bool isPremium) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AC.text(context),
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.edit,
                  label: 'Edit Profile',
                  onTap: () {
                    final authService = Provider.of<AuthService>(context, listen: false);
                    final existingProfile = authService.currentUser?.profile;
                    if (existingProfile != null) {
                      Navigator.push(
                        context,
                        AppTransitions.slide(ProfileWizardScreen(isEditMode: true, initialStep: 0)),
                      ).then((_) {
                        // Refresh so any field changes are visible immediately on return.
                        if (mounted) {
                          authService.refreshUserData();
                        }
                      });
                    } else {
                      Navigator.push(
                        context,
                        AppTransitions.slide(const ProfileWizardScreen()),
                      ).then((_) {
                        if (mounted) {
                          authService.refreshUserData();
                        }
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.share,
                  label: 'Share Profile',
                  onTap: () => _shareProfileAsText(context, authService),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _submittingIdProof
                  ? null
                  : () => _uploadIdentityDocument(context),
              icon: _submittingIdProof
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.badge_outlined, color: AppTheme.primaryOrange),
              label: Text(
                _submittingIdProof ? 'Uploading…' : 'Upload identity document',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AC.text(context),
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: AppTheme.primaryOrange.withAlpha(180)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Share profile as a formatted text message (WhatsApp-friendly)
  Future<void> _shareProfileAsText(BuildContext context, AuthService authService) async {
    final user = authService.currentUser;
    final profile = user?.profile;

    if (profile == null) {
      _showSnack(
        const SnackBar(
          content: Text('Please complete your profile first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String line(String label, String? value) {
      if (value == null || value.isEmpty || value == 'null' || value == 'Not specified') return '';
      return '• $label: $value\n';
    }

    final name = profile.fullName;
    final profileId = user?.profileId ?? 'N/A';

    final buffer = StringBuffer();
    buffer.writeln('🙏 *mana Vivaaha Vedika – Brahmin Profile*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('*Profile ID:* $profileId');
    buffer.writeln('*Name:* $name');
    buffer.writeln();

    // Basic Info
    buffer.writeln('👤 *Basic Information*');
    buffer.write(line('Age', profile.age.toString()));
    buffer.write(line('Height', profile.height));
    buffer.write(line('Weight', profile.weight));
    buffer.write(line('Complexion', profile.complexion));
    buffer.write(line('Physical Status', profile.physicalStatus));
    buffer.write(line('About', profile.aboutMe));
    buffer.writeln();

    // Birth Details
    buffer.writeln('🗓 *Birth Details*');
    buffer.write(line('Date of Birth', profile.dateOfBirth.toString().split(' ')[0]));
    buffer.write(line('Time of Birth', profile.timeOfBirth));
    buffer.write(line('Place of Birth', profile.placeOfBirth));
    buffer.write(line('Nakshatra', profile.nakshatra));
    buffer.write(line('Rasi', profile.rasi));
    buffer.write(line('Manglik', profile.manglikStatus));
    buffer.writeln();

    // Religious Details
    buffer.writeln('🛕 *Religious Details*');
    buffer.write(line('Sect', profile.sect));
    buffer.write(line('Sub-sect', profile.subSect));
    buffer.write(line('Gothram', profile.gothram));
    if (profile.hasHoroscope == true) buffer.writeln('• Has Horoscope: Yes');
    buffer.writeln();

    // Education & Career
    buffer.writeln('🎓 *Education & Career*');
    buffer.write(line('Education', profile.education));
    buffer.write(line('Specialization', profile.specialization));
    buffer.write(line('Occupation', profile.occupation));
    if (profile.occupation == ReferenceData.ownBusinessOccupation) {
      buffer.write(line('Business', profile.businessDescription));
    } else {
      buffer.write(line('Company', profile.companyName));
    }
    buffer.write(line('Income', profile.incomeRange));
    buffer.writeln();

    // Family Details
    buffer.writeln('👨‍👩‍👧 *Family Details*');
    buffer.write(line("Father's Name", profile.fatherName));
    buffer.write(line("Father's Occupation", profile.fatherOccupation));
    buffer.write(line("Mother's Name", profile.motherName));
    buffer.write(line("Mother's Occupation", profile.motherOccupation));
    if (profile.brothers != null) {
      buffer.writeln('• Brothers: ${profile.brothers} (${profile.brothersMarried ?? 0} married)');
    }
    if (profile.sisters != null) {
      buffer.writeln('• Sisters: ${profile.sisters} (${profile.sistersMarried ?? 0} married)');
    }
    buffer.write(line('Family Type', profile.familyType));
    buffer.write(line('Family Status', profile.familyStatus));
    buffer.writeln();

    // Location
    buffer.writeln('📍 *Location*');
    buffer.write(line('City', profile.city));
    buffer.write(line('State', profile.state));
    buffer.write(line('Country', profile.country));
    buffer.writeln();

    // Lifestyle
    final hobbies = formatList(profile.hobbies);
    final interests = formatList(profile.interests);
    final languages = formatList(profile.languages);
    if (hobbies != 'Not specified' || interests != 'Not specified' || languages != 'Not specified') {
      buffer.writeln('🌟 *Lifestyle & Interests*');
      buffer.write(line('Hobbies', hobbies));
      buffer.write(line('Interests', interests));
      buffer.write(line('Languages', languages));
      buffer.write(line('Food Habits', profile.foodHabit));
      buffer.writeln();
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('_Shared via mana Vivaaha Vedika App_ 🙏');

    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Vivaaha Vedika Profile – $name',
      ),
    );
  }


  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDanger 
              ? AppTheme.kumkumRed.withAlpha(15)
              : AppTheme.primaryOrange.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDanger ? AppTheme.kumkumRed.withAlpha(50) : AppTheme.primaryOrange.withAlpha(50),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isDanger ? AppTheme.kumkumRed : AppTheme.primaryOrange,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDanger ? AppTheme.kumkumRed : AppTheme.primaryOrange,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoUploadDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Update Profile Photo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPhotoOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _takePhoto();
                  },
                ),
                _buildPhotoOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFromGallery();
                  },
                ),
                _buildPhotoOption(
                  icon: Icons.delete,
                  label: 'Remove',
                  onTap: () {
                    debugPrint('🔴 Remove photo button tapped');
                    Navigator.pop(context);
                    // Small delay to ensure dialog is fully dismissed before showing confirmation
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        debugPrint('🔴 Calling _removePhoto()...');
                        _removePhoto();
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AC.surface(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: label == 'Remove' ? Colors.redAccent : AppTheme.primaryOrange,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    try {
      // 🔥 Windows/Desktop: Camera not supported via image_picker
      if (!kIsWeb && Platform.isWindows) {
        _showErrorDialog('Camera capture is not supported on Windows desktop. Please select a photo from your gallery.');
        return;
      }

      // Check camera permission first
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        _showErrorDialog('Camera permission is required to take photos. Please enable it in settings.');
        return;
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        debugPrint('📸 Camera photo captured: ${image.path}');
        await _uploadAndUpdateProfilePhoto(image.path);
      }
    } catch (e) {
      debugPrint('❌ Error taking photo: $e');
      _showErrorDialog('Failed to capture photo. Please try again.\n\nError: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // 🔥 Windows/Desktop: Use file_picker instead of image_picker
      if (!kIsWeb && Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.single.path != null) {
          debugPrint('🖼️ Windows file selected: ${result.files.single.path}');
          await _uploadAndUpdateProfilePhoto(result.files.single.path!);
        }
        return;
      }

      // Android 13+ (SDK 33+) uses READ_MEDIA_IMAGES, older uses READ_EXTERNAL_STORAGE
      // Permission.photos maps to READ_MEDIA_IMAGES on Android 13+ automatically
      bool permissionGranted = false;
      if (Platform.isAndroid) {
        // Try photos permission first (Android 13+), fall back to storage
        final photosPermission = await Permission.photos.request();
        if (photosPermission.isGranted || photosPermission.isLimited) {
          permissionGranted = true;
        } else {
          final storagePermission = await Permission.storage.request();
          permissionGranted = storagePermission.isGranted;
        }
      } else {
        final photosPermission = await Permission.photos.request();
        permissionGranted = photosPermission.isGranted || photosPermission.isLimited;
      }

      if (!permissionGranted) {
        _showErrorDialog('Storage permission is required to access photos. Please enable it in Settings > Apps > Mana Vivaaha Vedika > Permissions.');
        return;
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        debugPrint('🖼️ Gallery photo selected: ${image.path}');
        await _uploadAndUpdateProfilePhoto(image.path);
      }
    } catch (e) {
      debugPrint('❌ Error picking photo: $e');
      _showErrorDialog('Failed to select photo. Please try again.\n\nError: $e');
    }
  }

  Future<void> _removePhoto() async {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    debugPrint('🔍 _removePhoto() called');
    debugPrint('🔍 Current user: ${user?.id}');
    debugPrint('🔍 Profile: ${user?.profile?.toJson()}');

    if (user?.profile == null) {
      debugPrint('❌ No profile found');
      _showErrorDialog('No profile found');
      return;
    }

    // 🔥 FIX: Show confirmation dialog first before removing
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Photo?'),
        content: const Text('Are you sure you want to remove your profile photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      debugPrint('⏹️ User cancelled photo removal');
      return;
    }

    // Now proceed with removal
    if (!mounted) return;
    
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ── Step 1: Delete from Cloudinary first (if there's an existing photo)
      final currentPhotoUrl = user?.profile?.profilePicture ?? '';
      debugPrint('🔍 Current photo URL: $currentPhotoUrl');
      if (currentPhotoUrl.trim().isNotEmpty) {
        await ProtectedImageCacheService.evictUrl(currentPhotoUrl);
      }
      
      // 🔥 Mark photo for deletion (Firestore URL cleared, next upload overwrites)
      debugPrint('🗑️ Marking Cloudinary photo for deletion...');
      try {
        await CloudinaryUploadService.deleteProfilePhoto(uid: user?.id);
        debugPrint('✅ Cloudinary photo marked for deletion');
      } catch (e) {
        debugPrint('⚠️ Cloudinary delete note: $e');
        // Continue with removal — photo is already hidden in UI
      }

      // ── Step 2: Persist to Firestore ─────────────────────────────────────
      // ✅ Write to Firestore BEFORE clearing local state to prevent race conditions
      // with AuthService's onSnapshot listener re-firing with stale cached data
      debugPrint('📝 Updating Firestore for user: ${user?.id}');
      
      try {
        await FirebaseService().updateUserProfile(user!.id, {
          'profile_picture': null,
          'photo_url': null,
          'profilePicture': null,
          'photo_last_updated': FieldValue.serverTimestamp(),
          'profile': {
            'profile_picture': null,
            'profilePicture': null,
            'photo_last_updated': FieldValue.serverTimestamp(),
          },
          'updated_at': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Photo fields cleared in Firestore');
      } catch (e) {
        debugPrint('❌ Firestore update failed: $e');
        // Check for auth errors
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('invalid-credential') || 
            errorStr.contains('unauthenticated') ||
            errorStr.contains('permission-denied') ||
            errorStr.contains('session expired')) {
          throw Exception('Session expired. Please sign out and sign in again.');
        }
        throw Exception('Failed to update Firestore: $e');
      }

      // ── Step 3: Now clear local state ─────────────────────────────────────
      debugPrint('🧹 Clearing local state...');
      final clearedProfile = user.profile!.copyWith(
        profilePicture: '',          // empty string → _Avatar shows initial
        photoLastUpdated: DateTime.now(),
      );
      final clearedUser = user.copyWith(
        profile: clearedProfile,
        profileUpdatedAt: DateTime.now(),
      );
      
      if (mounted) {
        authService.setCurrentUser(clearedUser);
        debugPrint('✅ Local user state cleared');
        
        await ProtectedImageCacheService.evictUrl(currentPhotoUrl);
        await ProtectedImageCacheService.clearProtectedImageCache();
        debugPrint('🧹 Image cache cleared');
        
        // Force rebuild
        setState(() {});
        debugPrint('✅ UI rebuilt with cleared state');
      }

      // ── Step 4: Close loading dialog ─────────────────────────
      // Note: Removed Firestore re-sync to avoid race condition where
      // cached Firestore data restores the photo before write commits
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
        debugPrint('✅ Loading dialog closed');
      }

      if (mounted) {
        _showSuccessMessage('Photo removed successfully');
        debugPrint('✅ Success message shown');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error removing photo: $e');
      debugPrint('📍 Stack trace: $stackTrace');

      // Close loading dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        _showErrorDialog('Failed to remove photo: $e');
      }
    } finally {
      // no-op
    }
  }

  /// Upload photo to backend Storage and update user profile
  Future<void> _uploadAndUpdateProfilePhoto(String filePath) async {
    try {
      debugPrint('📤 Starting photo upload process...');
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AC.card(context),
          content: Row(
            children: [
              const CircularProgressIndicator(color: AppTheme.primaryOrange),
              const SizedBox(width: 20),
              Text(
                'Uploading photo...',
                style: TextStyle(color: AC.text(context)),
              ),
            ],
          ),
        ),
      );

      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      
      if (user == null) {
        throw Exception('User not found. Please login again.');
      }

      debugPrint('📤 User found: ${user.id}');

      // Validate file exists
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('Photo file not found at path: $filePath');
      }

      // Read file and validate size
      final fileBytes = await file.readAsBytes();
      if (fileBytes.isEmpty) {
        throw Exception('Photo file is empty or corrupted');
      }

      // Check file size (max 5MB)
      const maxSize = 5 * 1024 * 1024; // 5MB
      if (fileBytes.length > maxSize) {
        throw Exception('Photo size too large (${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)}MB). Please select a photo smaller than 5MB.');
      }

      // Validate file extension
      final fileName = file.path.toLowerCase();
      final validExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
      final hasValidExtension = validExtensions.any((ext) => fileName.endsWith(ext));
      
      if (!hasValidExtension) {
        throw Exception('Invalid photo format. Please select JPG, PNG, GIF, or WebP.');
      }

      // Determine content type
      String contentType = 'image/jpeg';
      if (fileName.endsWith('.png')) contentType = 'image/png';
      if (fileName.endsWith('.gif')) contentType = 'image/gif';
      if (fileName.endsWith('.webp')) contentType = 'image/webp';
      
      debugPrint('📤 Photo validation passed');
      debugPrint('📤 File size: ${(fileBytes.length / 1024).toStringAsFixed(1)}KB');
      debugPrint('📤 Content type: $contentType');
      
      // Upload to backend Storage with enhanced error handling
      debugPrint('📤 Attempting to upload photo (Cloudinary)...');
      String photoUrl;
      
      try {
        // 🔥 Upload via unsigned preset (no Firebase Functions needed)
        photoUrl = await CloudinaryUploadService.uploadProfilePhoto(filePath, uid: user.id);
        debugPrint('✅ Photo uploaded successfully to: $photoUrl');
      } catch (uploadError) {
        debugPrint('❌ Upload failed: $uploadError');

        final errStr = uploadError.toString();

        // ── Cloud Function errors ──
        if (errStr.contains('unauthenticated')) {
          throw Exception('Please login again to upload photos.');
        }

        // ── Network / timeout ──
        if (errStr.contains('network') ||
            errStr.contains('connection') ||
            errStr.contains('timeout') ||
            errStr.contains('SocketException')) {
          throw Exception(
              'Network connection failed. Please check your internet connection and try again.');
        }

        // ── Re-throw everything else with original message so nothing is hidden ──
        throw Exception('Photo upload failed: $errStr');
      }
      
      final previousPhotoUrl = (user.profile?.profilePicture ?? '').trim();
      if (previousPhotoUrl.isNotEmpty) {
        await ProtectedImageCacheService.evictUrl(previousPhotoUrl);
      }

      final photoUpdatedAt = DateTime.now();
      final versionMs = photoUpdatedAt.millisecondsSinceEpoch;
      final displayPhotoUrl = bustProfilePhotoCache(photoUrl, versionMs: versionMs);

      // Update user profile with new photo URL
      final currentProfile = user.profile;
      if (currentProfile != null) {
        debugPrint('📤 Updating user profile with new photo URL...');
        
        final finalProfile = currentProfile.copyWith(
          profilePicture: displayPhotoUrl,
          photoLastUpdated: photoUpdatedAt,
        );

        // Persist to Firestore BEFORE UI success — Cloudinary-only is not enough
        // when the app reloads from Firestore. Only photo keys (not full toMap).
        final identityService = IdentityService();
        final authUid = await identityService.getFirebaseAuthUid();
        final persist = await authService.updateUserProfile({
          'profile_picture': displayPhotoUrl,
          'profilePicture': displayPhotoUrl,
          'photo_url': displayPhotoUrl,
          'photo_provider': 'cloudinary',
          'photo_last_updated': FieldValue.serverTimestamp(),
          if (authUid?.isNotEmpty == true) 'auth_uid': authUid,
          'profile': {
            'profile_picture': displayPhotoUrl,
            'profilePicture': displayPhotoUrl,
            'photo_last_updated': FieldValue.serverTimestamp(),
          },
        });
        if (!persist.success) {
          throw Exception(persist.message);
        }
        
        // ✅ Close loading dialog immediately
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // ✅ Update in-memory user so UI matches Firestore
        final currentUser = authService.currentUser;
        if (currentUser != null) {
          final updatedUser = currentUser.copyWith(profile: finalProfile);
          authService.updateCurrentUserProfileLocally(updatedUser);
        }

        await ProtectedImageCacheService.evictUrl(displayPhotoUrl);
        await ProtectedImageCacheService.evictUrl(photoUrl);
        await ProtectedImageCacheService.clearProtectedImageCache();

        if (mounted) {
          _showSuccessMessage('Profile photo updated successfully ✅');
          setState(() {});
        }
        debugPrint('✅ Photo upload process completed successfully');
      } else {
        throw Exception('User profile not found. Please complete your profile first.');
      }
    } catch (e) {
      if (!mounted) return;
      // Close loading dialog if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      debugPrint('❌ Error uploading photo: $e');
      
      // Show user-friendly error message
      String userMessage = 'Failed to upload photo';
      
      if (e.toString().contains('size too large')) {
        userMessage = 'Photo size too large. Please select a photo smaller than 5MB.';
      } else if (e.toString().contains('Invalid photo format')) {
        userMessage = 'Invalid photo format. Please select JPG, PNG, GIF, or WebP.';
      } else if (e.toString().contains('storage is temporarily unavailable') ||
                   e.toString().contains('storage service is experiencing issues') ||
                   e.toString().contains('service is not properly configured')) {
        userMessage = 'Photo storage is temporarily unavailable. This usually means storage buckets need to be set up. Please try again later or contact support for assistance.';
      } else if (e.toString().contains('Permission denied') ||
                   e.toString().contains('permission') ||
                   e.toString().contains('access denied')) {
        userMessage = 'Permission denied. Please check your account settings.';
      } else if (e.toString().contains('Network connection failed')) {
        userMessage = 'Network connection failed. Please check your internet and try again.';
      } else if (e.toString().contains('User not found')) {
        userMessage = 'Session expired. Please login again.';
      } else if (e.toString().contains('profile not found')) {
        userMessage = 'Profile not found. Please complete your profile first.';
      } else if (e.toString().contains('cloudinary_upload_failed') ||
          e.toString().contains('Upload preset not found') ||
          e.toString().contains('cloudinary_preset_error') ||
          e.toString().contains('cloudinary_not_configured')) {
        userMessage = e.toString().replaceFirst('Exception: ', '');
        if (userMessage.length > 600) {
          userMessage = '${userMessage.substring(0, 600)}…';
        }
      } else {
        userMessage = 'Photo upload failed: ${e.toString()}';
      }
      
      _showErrorDialog(userMessage);
    }
  }
}
