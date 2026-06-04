import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/user.dart' as app_models;
import '../../services/auth_service.dart';
import '../../features/auth/local_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_transitions.dart';
import '../../utils/app_version.dart';
import '../../core/app_router.dart';
import '../auth/existing_user_login_screen.dart';
import '../../widgets/app_header.dart';
import '../../core/support_links.dart';
import '../../widgets/common/labeled_adaptive_switch.dart';
import '../../services/app_recommendation_service.dart';
import '../../services/theme_service.dart';
import '../../services/navigation_service.dart';
import '../../legacy/compatibility.dart';

/// Settings screen — internal tabs like Interests screen
class SettingsScreen extends StatefulWidget {
  final int initialTabIndex;
  const SettingsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _appVersion = AppVersion.version;
  String _buildNumber = AppVersion.buildNumber;
  bool _reloadAttempted = false;
  late final VoidCallback _tabListener;
  
  // Search functionality
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounceTimer;

  // Tab definitions
  final List<_TabDef> _tabs = const [
    _TabDef('Account', Icons.person_outline),
    _TabDef('Preferences', Icons.tune_outlined),
    _TabDef('Subscription', Icons.workspace_premium_outlined),
    _TabDef('Explore', Icons.explore_outlined),
    _TabDef('Support', Icons.help_outline),
    _TabDef('About', Icons.info_outline),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabListener = () => setState(() {});
    _tabController.addListener(_tabListener);
    _loadPackageInfo();
    
    // Ensure user data is complete (generate missing profile_id for legacy users)
    _ensureUserData();
  }
  
  /// Ensure user has profile_id - generate if missing (for legacy users)
  Future<void> _ensureUserData() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Let auth load first
    if (!mounted) return;
    
    final authService = context.read<AuthController>();
    final user = authService.currentUser;
    
    if (user == null) {
      debugPrint('⚙️ Settings: No user logged in');
      return;
    }
    
    // Check if profile_id is missing
    if (user.profileId.isEmpty) {
      debugPrint('⚙️ Settings: User missing profile_id, generating...');
      
      // Get gender from profile or default to male
      final gender = user.profile?.gender.toString() ?? 'male';
      
      // Generate and save profile_id
      final newProfileId = await authService.ensureProfileId(user.id, gender);
      
      if (newProfileId.isNotEmpty && mounted) {
        debugPrint('✅ Settings: Generated profile_id $newProfileId');
        // Force refresh user data
        await authService.restoreExistingSession(user.mobileNumber);
        if (mounted) {
          setState(() {}); // Rebuild with new data
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_tabListener);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    }
  }

  /// Reload user data from Firestore if fields are empty
  Future<void> _reloadUserData() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      
      final authService = context.read<AuthController>();
      final user = authService.currentUser;
      if (user == null || user.mobileNumber.isEmpty) return;
      
      debugPrint('🔄 Settings: Reloading user data from Firestore...');
      final result = await authService.restoreExistingSession(user.mobileNumber);
      
      if (result.success && mounted) {
        debugPrint('✅ Settings: User data reloaded');
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Settings: Failed to reload user data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use watch to rebuild when AuthController notifies listeners
    final authService = context.watch<AuthController>();
    final user = authService.currentUser;
    final isPremium = user?.membership.isPremium ?? false;

    // Diagnostic: if user fields are empty but user exists, show debug info and try to reload
    if (user != null &&
        (user.profileId.isEmpty || user.mobileNumber.isEmpty) &&
        !_reloadAttempted) {
      _reloadAttempted = true;
      debugPrint('⚠️ SettingsScreen: User has empty fields!');
      debugPrint('   profileId: "${user.profileId}"');
      debugPrint('   mobileNumber: "${user.mobileNumber}"');
      debugPrint('   email: "${user.email}"');
      
      // Try to reload user data from Firestore
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reloadUserData();
        }
      });
    }

    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Column(
        children: [
          // Header
          AppHeader(
            title: 'Settings',
            showLogo: true,
            showSearch: true,
            onSearchTap: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                } else {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _searchFocusNode.requestFocus();
                  });
                }
              });
            },
            isSearchActive: _showSearch,
          ),

          // Search bar
          if (_showSearch)
            Container(
              color: AC.surface(context),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: TextStyle(color: AC.text(context)),
                onChanged: (value) {
                  _searchDebounceTimer?.cancel();
                  _searchDebounceTimer = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _searchQuery = value.toLowerCase().trim()),
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Search settings...',
                  hintStyle: TextStyle(color: AC.textMuted(context)),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AC.surface2(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

          // Tab Bar
          Container(
            color: AC.surface(context),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primaryOrange,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelColor: AC.text(context),
              unselectedLabelColor: AC.textSub(context),
              labelStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
              unselectedLabelStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),

          // Tab Content
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults(context)
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _AccountTab(user: user),
                      const _PreferencesTab(),
                      _SubscriptionTab(user: user, isPremium: isPremium),
                      const _ExploreTab(),
                      const _SupportTab(),
                      _AboutTab(appVersion: _appVersion, buildNumber: _buildNumber, onLogout: () => _showLogoutDialog(context, authService)),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final allItems = _getAllSearchableItems(context);
    final filtered = allItems.where((item) =>
        item.label.toLowerCase().contains(_searchQuery) ||
        item.subtitle.toLowerCase().contains(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: AC.textMuted(context)),
            const SizedBox(height: 16),
            Text('No settings found for "$_searchQuery"',
                style: TextStyle(color: AC.textSub(context), fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = filtered[i];
        return _SettingsCard(
          icon: item.icon,
          iconColor: item.iconColor,
          title: item.label,
          subtitle: item.subtitle,
          onTap: () {
            _tabController.animateTo(item.tabIndex);
            setState(() {
              _showSearch = false;
              _searchQuery = '';
              _searchController.clear();
            });
            Future.delayed(const Duration(milliseconds: 300), item.onTap);
          },
        );
      },
    );
  }

  List<_SearchItem> _getAllSearchableItems(BuildContext context) {
    final user = context.read<AuthController>().currentUser;
    final isPremium = user?.membership.isPremium ?? false;
    
    return [
      // Account (tab 0)
      _SearchItem('Edit Profile', 'Update your profile', Icons.person_outline, 0,
          () => NavHelper.push(context, Routes.profileWizard, args: {'isEditMode': true})),
      _SearchItem('Profile Privacy', 'Control visibility', Icons.visibility_outlined, 0,
          () => NavHelper.push(context, Routes.privacySettings)),
      _SearchItem('Change MPIN', 'Update security PIN', Icons.pin_outlined, 0,
          () => NavHelper.push(context, Routes.changeMpin)),
      _SearchItem('Biometric Login', 'Face ID / Fingerprint', Icons.fingerprint, 0,
          () => _showBiometricDialog(context)),
      
      // Preferences (tab 1)
      _SearchItem('Dark Mode', 'Toggle theme', Icons.dark_mode, 1,
          () => context.read<ThemeService>().toggleTheme(), iconColor: AppTheme.primaryOrange),
      _SearchItem('Font Size', 'Adjust text size', Icons.text_fields, 1,
          () => NavHelper.push(context, Routes.fontSettings)),
      _SearchItem('Matching Preferences', 'Ashtakoot settings', Icons.auto_awesome, 1,
          () => NavHelper.push(context, Routes.matchingPreferences)),
      
      // Subscription (tab 2) - Search Filters stays here with filter count
      _SearchItem('Premium Membership', isPremium ? 'Active' : 'Upgrade now', 
          Icons.workspace_premium, 2, () => NavHelper.push(context, Routes.premiumUpgrade),
          iconColor: AppTheme.primaryGold),
      
      // Explore (tab 3)
      _SearchItem('Success Stories', 'Couples who found love', Icons.favorite, 3,
          () => NavHelper.push(context, Routes.successStories), iconColor: AppTheme.kumkumRed),
      
      // Support (tab 4)
      _SearchItem('Help & Support', 'FAQs and guides', Icons.help_outline, 4,
          () => NavHelper.push(context, Routes.helpSupport)),
      _SearchItem('Chat with Support', 'In-app help desk', Icons.support_agent, 4,
          () => NavHelper.push(context, Routes.supportChat)),
      _SearchItem('WhatsApp Support', SupportLinks.supportPhoneDisplay, Icons.chat, 4,
          () => SupportLinks.openWhatsAppSupport(context), iconColor: AppTheme.sacredGreen),
      _SearchItem('Recommend App', 'Share with friends', Icons.share, 4,
          () => AppRecommendationService.showRecommendationDialog(context)),
      
      // About (tab 5)
      _SearchItem('About App', 'Version info', Icons.info_outline, 5,
          () => NavHelper.push(context, Routes.about)),
      _SearchItem('Terms & Conditions', 'Read terms', Icons.description, 5,
          () => NavHelper.push(context, Routes.terms)),
      _SearchItem('Privacy Policy', 'Data protection', Icons.privacy_tip, 5,
          () => NavHelper.push(context, Routes.privacyPolicy)),
      _SearchItem('Payment & Refund', 'Billing info', Icons.payments, 5,
          () => NavHelper.push(context, Routes.paymentRefundPolicy)),
      _SearchItem('Delete Profile', 'Remove account permanently', Icons.delete_forever, 5,
          () => NavHelper.push(context, Routes.deleteProfile), iconColor: AppTheme.kumkumRed),
      _SearchItem('Logout', 'Sign out from your account', Icons.logout, 5,
          () => _showLogoutDialog(context, context.read<AuthController>()), iconColor: AppTheme.kumkumRed),
    ];
  }

  Future<void> _showBiometricDialog(BuildContext context) async {
    final userId = context.read<AuthController>().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    
    final service = LocalAuthService();
    final available = await service.canUseBiometrics();
    final enabled = await service.isEnabledForUser(userId);
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biometric Login'),
        content: Text(available 
            ? 'Biometric login is ${enabled ? "enabled" : "disabled"}'
            : 'Biometrics not available on this device'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (available)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (!enabled) {
                  final verified = await service.authenticate(
                    reason: 'Verify to enable biometric login',
                  );
                  if (verified) await service.setEnabledForUser(userId, true);
                } else {
                  await service.setEnabledForUser(userId, false);
                }
                if (!mounted) return;
                setState(() {});
              },
              child: Text(enabled ? 'Disable' : 'Enable'),
            ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthController authService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.logout, color: AppTheme.kumkumRed),
          const SizedBox(width: 12),
          const Text('Logout'),
        ]),
        content: const Text(
          'Are you sure you want to sign out?\n\nYou can use MPIN or biometric to unlock this account again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              NavigationService().navigatorKey.currentState?.pushAndRemoveUntil(
                    AppTransitions.slide(const ExistingUserLoginScreen()),
                    (_) => false,
                  );
              unawaited(authService.logout());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kumkumRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

class _TabDef {
  final String label;
  final IconData icon;
  const _TabDef(this.label, this.icon);
}

class _SearchItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final int tabIndex;
  final VoidCallback onTap;
  final Color? iconColor;
  
  _SearchItem(this.label, this.subtitle, this.icon, this.tabIndex, this.onTap, {this.iconColor});
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED UI COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

Widget _sectionHeader(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
  child: Text(title.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AC.textSub(context), letterSpacing: 1, fontSize: 12, fontWeight: FontWeight.w700)),
);

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsCard({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AC.shadow(context), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
        tileColor: Colors.transparent,
        splashColor: AppTheme.primaryOrange.withAlpha(40),
        hoverColor: AppTheme.primaryOrange.withAlpha(20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: iconColor?.withAlpha(15) ?? AC.surface2(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor ?? AC.textSub(context), size: 22),
        ),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AC.text(context))),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: AC.textSub(context))),
        trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right, color: AC.textMuted(context)) : null),
        onTap: onTap,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — ACCOUNT
// ═══════════════════════════════════════════════════════════════════════════

class _AccountTab extends StatelessWidget {
  final app_models.User? user;
  const _AccountTab({this.user});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'Profile Info'),
        _SettingsCard(
          icon: Icons.badge_outlined,
          title: 'Profile ID',
          subtitle: user?.profileId ?? 'Generating...',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (user?.membership.isPremium ?? false) 
                  ? AppTheme.primaryOrange 
                  : AppTheme.primaryOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              (user?.membership.isPremium ?? false) ? 'PREMIUM' : 'FREE',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: (user?.membership.isPremium ?? false) ? Colors.white : AppTheme.primaryOrange,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.phone_outlined,
          title: 'Mobile',
          subtitle: '+91 ${user?.mobileNumber ?? 'N/A'}',
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.email_outlined,
          title: 'Email',
          subtitle: user?.email ?? 'N/A',
        ),

        _sectionHeader(context, 'Manage'),
        _SettingsCard(
          icon: Icons.edit,
          title: 'Edit Profile',
          subtitle: 'Update your profile information',
          onTap: () => NavHelper.push(context, Routes.profileWizard, args: {'isEditMode': true}),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.visibility_outlined,
          title: 'Profile Privacy',
          subtitle: 'Control who can see your profile',
          onTap: () => NavHelper.push(context, Routes.privacySettings),
        ),

        _sectionHeader(context, 'Security'),
        _SettingsCard(
          icon: Icons.pin_outlined,
          title: 'Change MPIN',
          subtitle: 'Update your 4-digit security PIN',
          onTap: () => NavHelper.push(context, Routes.changeMpin),
        ),
        const SizedBox(height: 8),
        _BiometricCard(),
      ],
    );
  }
}

class _BiometricCard extends StatefulWidget {
  @override
  State<_BiometricCard> createState() => _BiometricCardState();
}

class _BiometricCardState extends State<_BiometricCard> {
  bool? _enabled;
  bool? _available;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = context.read<AuthController>().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final service = LocalAuthService();
    final avail = await service.canUseBiometrics();
    final en = await service.isEnabledForUser(userId);
    if (mounted) setState(() { _available = avail; _enabled = en; });
  }

  Future<void> _toggle(bool value) async {
    final userId = context.read<AuthController>().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final service = LocalAuthService();
    if (value) {
      final verified = await service.authenticate(reason: 'Verify to enable');
      if (!verified) return;
    }
    await service.setEnabledForUser(userId, value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_available == null) {
      return _SettingsCard(
        icon: Icons.fingerprint,
        title: 'Biometric Login',
        subtitle: 'Checking...',
      );
    }
    return _SettingsCard(
      icon: Icons.fingerprint,
      title: 'Biometric Login',
      subtitle: _available! ? (_enabled! ? 'Enabled' : 'Disabled') : 'Not available',
      trailing: _available! ? _buildLabeledSwitch(
        context: context,
        value: _enabled ?? false,
        onChanged: _toggle,
      ) : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — PREFERENCES
// ═══════════════════════════════════════════════════════════════════════════

class _PreferencesTab extends StatelessWidget {
  const _PreferencesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'Appearance'),
        _SettingsCard(
          icon: Icons.dark_mode,
          iconColor: AppTheme.primaryOrange,
          title: 'Dark Mode',
          subtitle: 'Toggle dark theme appearance',
          trailing: _buildLabeledSwitch(
            context: context,
            value: context.watch<ThemeService>().isDarkMode,
            onChanged: (_) => context.read<ThemeService>().toggleTheme(),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.text_fields,
          title: 'Font Size',
          subtitle: 'Adjust text size across the app',
          onTap: () => NavHelper.push(context, Routes.fontSettings),
        ),

        _sectionHeader(context, 'Matching'),
        _SettingsCard(
          icon: Icons.auto_awesome,
          iconColor: AppTheme.primaryGold,
          title: 'Matching Preferences',
          subtitle: 'Ashtakoot & compatibility settings',
          onTap: () => NavHelper.push(context, Routes.matchingPreferences),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 — SUBSCRIPTION
// ═══════════════════════════════════════════════════════════════════════════

class _SubscriptionTab extends StatelessWidget {
  final app_models.User? user;
  final bool isPremium;
  const _SubscriptionTab({this.user, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final filterPrefs = context.watch<FilterService>().current;
    final filterCount = filterPrefs?.activeFilterCount ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'Your Plan'),
        _SettingsCard(
          icon: Icons.workspace_premium,
          iconColor: isPremium ? AppTheme.primaryGold : AC.textSub(context),
          title: isPremium ? 'Premium Active' : 'Free Plan',
          subtitle: isPremium 
              ? '${user?.membership.daysRemaining ?? 0} days remaining'
              : 'Upgrade to unlock all features',
          trailing: isPremium
              ? Icon(Icons.check_circle, color: AppTheme.sacredGreen)
              : ElevatedButton(
                  onPressed: () => NavHelper.push(context, Routes.premiumUpgrade),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Upgrade', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
          onTap: () => NavHelper.push(context, Routes.premiumUpgrade),
        ),

        _sectionHeader(context, 'Active Filters'),
        _SettingsCard(
          icon: Icons.tune,
          iconColor: filterCount > 0 ? AppTheme.primaryOrange : AC.textSub(context),
          title: 'Search Filters',
          subtitle: filterCount == 0 
              ? 'No filters applied'
              : '$filterCount filter${filterCount == 1 ? '' : 's'} active',
          trailing: filterCount > 0
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange,
                    shape: BoxShape.circle,
                  ),
                  child: Text('$filterCount', style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                )
              : null,
          onTap: () => NavHelper.push(context, Routes.filterSettings),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 4 — EXPLORE
// ═══════════════════════════════════════════════════════════════════════════

class _ExploreTab extends StatelessWidget {
  const _ExploreTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'Inspiration'),
        _SettingsCard(
          icon: Icons.favorite,
          iconColor: AppTheme.kumkumRed,
          title: 'Success Stories',
          subtitle: 'Couples who found love on Mana Vivaaha Vedika',
          onTap: () => NavHelper.push(context, Routes.successStories),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 5 — SUPPORT
// ═══════════════════════════════════════════════════════════════════════════

class _SupportTab extends StatelessWidget {
  const _SupportTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'Help'),
        _SettingsCard(
          icon: Icons.help_outline,
          title: 'Help & Support',
          subtitle: 'FAQs, guides & contact us',
          onTap: () => NavHelper.push(context, Routes.helpSupport),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.support_agent,
          iconColor: AppTheme.primaryMaroon,
          title: 'Chat with Support',
          subtitle: 'In-app help desk — message our team',
          onTap: () => NavHelper.push(context, Routes.supportChat),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.chat,
          iconColor: AppTheme.sacredGreen,
          title: 'WhatsApp Support',
          subtitle: SupportLinks.supportPhoneDisplay,
          onTap: () => SupportLinks.openWhatsAppSupport(context),
        ),

        _sectionHeader(context, 'Share'),
        _SettingsCard(
          icon: Icons.share,
          title: 'Recommend App',
          subtitle: 'Share with friends & family',
          onTap: () => AppRecommendationService.showRecommendationDialog(context),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 6 — ABOUT
// ═══════════════════════════════════════════════════════════════════════════

class _AboutTab extends StatelessWidget {
  final String appVersion;
  final String buildNumber;
  final VoidCallback onLogout;
  const _AboutTab({required this.appVersion, required this.buildNumber, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _sectionHeader(context, 'App'),
        _SettingsCard(
          icon: Icons.info_outline,
          title: 'About App',
          subtitle: 'Version $appVersion ($buildNumber)',
          onTap: () => NavHelper.push(context, Routes.about),
        ),
        _sectionHeader(context, 'Legal'),
        _SettingsCard(
          icon: Icons.description,
          title: 'Terms & Conditions',
          subtitle: 'Read our terms of service',
          onTap: () => NavHelper.push(context, Routes.terms),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.privacy_tip,
          title: 'Privacy Policy',
          subtitle: 'How we protect your data',
          onTap: () => NavHelper.push(context, Routes.privacyPolicy),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          icon: Icons.payments,
          title: 'Payment & Refund Policy',
          subtitle: 'Billing & subscription info',
          onTap: () => NavHelper.push(context, Routes.paymentRefundPolicy),
        ),

        _sectionHeader(context, 'Danger Zone'),
        Container(
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.kumkumRed.withAlpha(100), width: 1),
            boxShadow: [BoxShadow(color: AC.shadow(context), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              tileColor: Colors.transparent,
              splashColor: AppTheme.kumkumRed.withAlpha(40),
              hoverColor: AppTheme.kumkumRed.withAlpha(20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.delete_forever, color: AppTheme.kumkumRed, size: 22),
              ),
              title: Text('Delete Profile', style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.kumkumRed)),
              subtitle: Text('Permanently remove account', style: TextStyle(
                  fontSize: 13, color: AC.textSub(context))),
              trailing: Icon(Icons.chevron_right, color: AppTheme.kumkumRed.withAlpha(150)),
              onTap: () => NavHelper.push(context, Routes.deleteProfile),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Logout button
        Container(
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: AC.shadow(context), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              tileColor: Colors.transparent,
              splashColor: AppTheme.kumkumRed.withAlpha(40),
              hoverColor: AppTheme.kumkumRed.withAlpha(20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.logout, color: AppTheme.kumkumRed, size: 22),
              ),
              title: Text('Logout',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.kumkumRed)),
              subtitle: Text('Sign out from your account', style: TextStyle(fontSize: 13, color: AC.textSub(context))),
            trailing: Icon(Icons.chevron_right, color: AppTheme.kumkumRed.withAlpha(150)),
            onTap: onLogout,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LABELED SWITCH HELPER (matches privacy settings style)
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildLabeledSwitch({
  required BuildContext context,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return LabeledAdaptiveSwitch(
    value: value,
    onChanged: onChanged,
  );
}
