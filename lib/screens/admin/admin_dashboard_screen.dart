import 'dart:async'; // 🔥 For search debounce Timer
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/membership.dart';
import '../../models/verification.dart';
import '../../models/advanced_filter.dart';
import '../../services/admin_service.dart';
import '../../services/admin_session_bootstrap.dart';
import '../../services/auth_service.dart';
import '../../services/navigation_service.dart';
import '../../services/presence_service.dart';
import '../../core/identity_service.dart';
import '../../core/contract.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/online_status_indicator.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/user_badges_row.dart';
import '../../widgets/report_user_dialog.dart';
import '../../widgets/advanced_filter_sheet.dart';
import '../../utils/safe_data_extractor.dart';
import 'otp_security_dashboard.dart';
import 'admin_subscription_plans_screen.dart';
import 'admin_moderation_tab.dart';
import 'admin_support_inbox_tab.dart';

/// Admin Dashboard Screen — user management, memberships, document verification.
///
/// ACCESS CONTROL: Enforced entirely by AdminGate (3-layer security):
///   Layer 1 — Firestore is_admin flag
///   Layer 2 — Separate 6-digit Admin MPIN (FlutterSecureStorage)
///   Layer 3 — 5-minute session timeout with auto-lock
///
/// AdminDashboardScreen itself performs NO auth check. If the screen is mounted
/// it means AdminGate already verified all three layers. Doing a second
/// Firestore is_admin read here was redundant and caused a blank/spinner on
/// the Overview tab whenever the read was slow or failed (showing "Access
/// Denied" even for a legitimate admin).
///
/// FIX (Bug 1 + 2): Removed ALL insecure admin bypasses:
///   - uid.length > 20  (granted every Firebase user admin access — UIDs are 28 chars)
///   - userPhone.contains('8985936678')  (hardcoded phone number in client bundle)
///   - uid.contains('admin')
///   - uid.contains('8985936678')
///
/// FIX (Bug 5): Admin Profile tab now loads real data from Firestore
/// (mobile number, name, profile_id) instead of FirebaseAuth.currentUser.email
/// which is always null for anonymous-auth users.
///
/// FIX (Admin home page blank): Removed _checkAdminAccess() and the
/// _isAuthorized / _checkingAuth gate that was blocking the build() until a
/// redundant Firestore read finished. Data loading now starts immediately in
/// initState so the Overview tab populates on first render.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  
  // 🔥 NEW: Advanced filter for user search
  AdvancedFilter _advancedFilter = AdvancedFilter.empty();
  
  // 🔥 Search debounce timer for performance (5K+ users)
  Timer? _searchDebounce;

  // Admin profile data from Firestore
  Map<String, dynamic>? _adminProfileData;
  bool _loadingAdminProfile = false;

  // 🔥 Loading flags for actions to prevent double-taps
  final Set<String> _loadingActions = {};
  bool _isActionLoading(String action) => _loadingActions.contains(action);
  bool _beginActionLoading(String action) {
    if (_loadingActions.contains(action)) return false;
    _loadingActions.add(action);
    if (mounted) setState(() {});
    return true;
  }

  void _setActionLoading(String action, bool loading) {
    if (loading) {
      _beginActionLoading(action);
      return;
    }
    _loadingActions.remove(action);
    if (mounted) setState(() {});
  }
  
  /// 🔥 Debounced search update for performance
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = value.trim());
      }
    });
  }

  DateTime? _parseAnyDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  String _asText(dynamic raw, {String fallback = ''}) {
    if (raw == null) return fallback;
    final v = raw.toString().trim();
    return v.isEmpty ? fallback : v;
  }

  num _asNum(dynamic raw, {num fallback = 0}) {
    if (raw == null) return fallback;
    if (raw is num) return raw;
    final parsed = num.tryParse(raw.toString().trim());
    return parsed ?? fallback;
  }

  int _asInt(dynamic raw, {int fallback = 0}) {
    return _asNum(raw, fallback: fallback).toInt();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 12, vsync: this);
    // AdminGate has already verified the user before mounting this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadAdminProfileDataFromPrefs();
      if (!mounted) return;
      await _loadData();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel(); // 🔥 Cancel pending search
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Admin Logout ──────────────────────────────────────────────────────────
  Future<void> _adminLogout(BuildContext ctx) async {
    final fbUidBeforeLogout = FirebaseAuth.instance.currentUser?.uid;
    if (ctx.mounted) {
      Navigator.pushNamedAndRemoveUntil(ctx, '/auth-selection', (r) => false);
    }
    final auth = Provider.of<AuthService>(ctx, listen: false);
    unawaited(() async {
      // Delete admin session marker in background; logout route is already applied.
      try {
        if (fbUidBeforeLogout != null && fbUidBeforeLogout.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('admin_sessions')
              .doc(fbUidBeforeLogout)
              .delete();
          debugPrint('✅ admin_sessions doc deleted for uid=$fbUidBeforeLogout');
        }
      } catch (e) {
        debugPrint('⚠️ admin_sessions delete failed (non-fatal): $e');
      }
      await auth.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_login_verified');
      await prefs.remove('admin_session_active');
      NavigationService().invalidateCaches();
    }());
  }

  Future<void> _loadData() async {
    // AdminGate has already verified admin access before this screen is mounted.
    // We do NOT repeat the auth check here — doing so caused the blank/black
    // screen because verifyAdminStatus was looking up the wrong Firestore doc
    // (anonymous Firebase UID vs the stored app user ID).
    // Just load the data directly.
    final adminService = Provider.of<AdminService>(context, listen: false);
    debugPrint('✅ AdminDashboard: loading data (AdminGate already verified)');
    await adminService.initialize();
    await adminService.getStatistics();
  }

  // FIX (Bug 5): Load admin profile info from Firestore — anonymous Firebase
  // Auth users have no email / display name. Use the app's own user document.
  Future<void> _loadAdminProfileDataFromPrefs() async {
    if (!mounted) return;
    setState(() => _loadingAdminProfile = true);
    try {
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final userId = await identityService.getUserId();
      
      final storedUserId = userId;
      if (storedUserId.isEmpty) return;

      // ADMIN FIX (safety net): ensure auth_uid in the Firestore doc matches
      // the current Firebase session before the doc read. The login screen now
      // awaits this sync, but if the session was restored from SharedPreferences
      // (cold-start) without going through the login screen, auth_uid may be
      // stale → permission-denied → dashboard blank / treated as ordinary user.
      final fbUid = FirebaseAuth.instance.currentUser?.uid;
      if (fbUid != null && fbUid.isNotEmpty) {
        try {
          final userRef = FirebaseFirestore.instance.collection(Collections.users).doc(storedUserId);
          final existingDoc = await userRef.get();
          if (existingDoc.exists) {
            final existing = existingDoc.data() ?? <String, dynamic>{};
            final currentAuthUid = (existing['auth_uid'] as String? ?? '').trim();
            if (currentAuthUid.isEmpty || currentAuthUid == fbUid) {
              await userRef.set(
                {
                  'auth_uid': fbUid,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                SetOptions(merge: true),
              );
              debugPrint('✅ AdminDashboard: auth_uid sync safe for $storedUserId');
            } else {
              debugPrint(
                '⚠️ AdminDashboard: auth_uid mismatch for $storedUserId; skipping overwrite',
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ AdminDashboard: auth_uid sync failed (continuing): $e');
        }
      }

      await AdminSessionBootstrap.ensureAccess(userDocId: storedUserId);

      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(storedUserId)
          .get();
      if (mounted && doc.exists) {
        final raw = doc.data();
        if (raw == null) {
          debugPrint('⚠️ AdminDashboard: user doc exists but data is null');
          return;
        }
        final data = Map<String, dynamic>.from(raw);
        data['id'] = doc.id;
        setState(() => _adminProfileData = data);
      }
    } catch (e) {
      debugPrint('❌ Failed to load admin profile data: $e');
    } finally {
      if (mounted) setState(() => _loadingAdminProfile = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // AdminGate guarantees authorization before this widget is mounted.
    // No spinner or access-denied guard needed here.
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'mana Admin Dashboard',
        showLogo: true,
        additionalActions: [
          Semantics(
            label: 'Admin quick actions',
            hint: 'Opens shortcuts for payments, OTP security and system settings',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              tooltip: 'Quick actions: Payments, OTP, Settings',
              onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.payment),
                        title: const Text('Go to Payments'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _tabController.animateTo(7);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: const Text('Go to OTP Security'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _tabController.animateTo(8);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings),
                        title: const Text('Open System Settings'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showSystemSettings(context);
                        },
                      ),
                    ],
                  ),
                ),
              );
              },
            ),
          ),
          // Gear menu now has explicit system wiring + page-size controls
          Semantics(
            label: 'Admin settings menu',
            hint: 'Open system settings and page-size options',
            button: true,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Settings: System + page size',
              onSelected: (value) {
              final adminService = Provider.of<AdminService>(context, listen: false);
              if (value == 'system_settings') {
                _showSystemSettings(context);
                return;
              }
              if (value == 'otp_security') {
                _tabController.animateTo(8);
                return;
              }
              final size = int.tryParse(value);
              if (size != null) {
                adminService.setPageSize(size);
                adminService.refreshData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Page size: $size users')),
                );
              }
            },
              itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'system_settings',
                child: Text('System Settings'),
              ),
              const PopupMenuItem(
                value: 'otp_security',
                child: Text('Open OTP Security Tab'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: '20', child: Text('20 users/page')),
              const PopupMenuItem(value: '50', child: Text('50 users/page')),
              const PopupMenuItem(value: '100', child: Text('100 users/page')),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(children: [
        // Tab bar matching settings screen style
        Container(
          color: AC.card(context),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.primaryOrange,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelColor: AC.text(context),
            unselectedLabelColor: AppTheme.textMedium,
            labelStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1),
            unselectedLabelStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Profile'),
              Tab(text: 'Pending'),
              Tab(text: 'Verified'),
              Tab(text: 'Documents'),
              Tab(text: 'All Users'),
              Tab(text: 'Active'),
              Tab(text: 'Payments'),
              Tab(text: 'Plans'),
              Tab(text: 'OTP Security'),
              Tab(text: 'Moderation'),
              Tab(text: 'Support'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _safeTab('Overview', _buildOverviewTab),
              _safeTab('Profile', _buildAdminProfileTab),
              _safeTab('Pending', _buildPendingUsersTab),
              _safeTab('Verified', _buildVerifiedUsersTab),
              _safeTab('Documents', _buildDocumentsTab),
              _safeTab('All Users', _buildAllUsersTab),
              _safeTab('Active', _buildActiveMembersTab),
              _safeTab('Payments', _buildPaymentRequestsTab),
              _safeTab('Plans', () => const AdminSubscriptionPlansScreen()),
              _safeTab('OTP Security', () => const OtpSecurityDashboard(embedded: true)),
              _safeTab('Moderation', () => const AdminModerationTab()),
              _safeTab('Support', () => const AdminSupportInboxTab()),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _safeTab(String tabName, Widget Function() builder) {
    return Builder(
      builder: (context) {
        try {
          return builder();
        } catch (e, st) {
          debugPrint('❌ Admin tab [$tabName] crashed: $e\n$st');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.kumkumRed, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    '$tabName tab failed to load.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.kumkumRed,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _safeItemCard(Widget Function() builder) {
    try {
      return builder();
    } catch (e, st) {
      debugPrint('❌ Admin row render failed: $e\n$st');
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.kumkumRed),
          title: const Text('This record could not be rendered'),
          subtitle: const Text('Skipped invalid data row'),
        ),
      );
    }
  }

  // ── ADMIN PROFILE TAB ──────────────────────────────────────────────────────
  // FIX (Bug 5): Shows real Firestore data instead of always-null email.
  Widget _buildAdminProfileTab() {
    if (_loadingAdminProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _adminProfileData;
    final firstName = _asText(data?['first_name']);
    final lastName = _asText(data?['last_name']);
    final fullName = [firstName, lastName]
        .where((s) => s.isNotEmpty)
        .join(' ');
    final displayName =
        fullName.isNotEmpty ? fullName : 'Administrator';
    final mobile = _asText(data?['mobile_number'], fallback: 'N/A');
    final profileIdRaw =
        SafeDataExtractor.getProfileId(Map<String, dynamic>.from(data ?? {}));
    final profileId = profileIdRaw.isNotEmpty ? profileIdRaw : 'N/A';
    // FIX: Show the actual app user doc ID, not the anonymous Firebase UID
    final uid = _asText(
      _adminProfileData?['id'],
      fallback: FirebaseAuth.instance.currentUser?.uid ?? 'N/A',
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin Profile',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),

          // Admin Info Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.kumkumRed,
                        radius: 28,
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'A',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('System Administrator',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: AppTheme.textMedium)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildProfileDetail('Mobile', mobile),
                  _buildProfileDetail('Profile ID', profileId),
                  _buildProfileDetail('UID', uid),
                  _buildProfileDetail('Access Level', 'Full Administrator'),
                  _buildProfileDetail('Permissions', 'All System Access'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Admin Actions Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin Actions',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.refresh,
                        color: AppTheme.kumkumRed),
                    title: const Text('Refresh Data'),
                    subtitle:
                        const Text('Reload all admin statistics'),
                    onTap: () async {
                      await _loadData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Admin data refreshed')),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings,
                        color: AppTheme.primaryOrange),
                    title: const Text('System Settings'),
                    subtitle: const Text('Configure system parameters'),
                    onTap: () => _showSystemSettings(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Admin Logout'),
                    subtitle: const Text('Return to main login screen'),
                    onTap: () => _adminLogout(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  // ── OVERVIEW TAB ───────────────────────────────────────────
  // Statistics come from AdminService streams / tab bodies, not a one-shot map.
  // with Consumer<AdminService> so counts update live whenever AdminService
  // calls notifyListeners() after any user action or refresh.
  Widget _buildOverviewTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, _) {
        if (adminService.isLoading && adminService.allUsers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Read live counts directly from AdminService lists
        final totalInt    = adminService.allUsers.length;
        final verifiedInt = adminService.verifiedUsers.length;
        final pendingInt  = adminService.pendingUsers.length;
        final pendingDocs = adminService.pendingVerifications.length;
        final premiumInt  = adminService.activeMembers.length;
        final freeInt     = totalInt - premiumInt;
        // Count users online in last 5 minutes (approximate live)
        final onlineInt   = adminService.allUsers.where((u) {
          final last = _parseAnyDate(u['last_active']);
          if (last == null) return false;
          try {
            return DateTime.now().difference(last).inMinutes < 5;
          } catch (_) { return false; }
        }).length;

        final total    = totalInt.toString();
        final verified = verifiedInt.toString();
        final pending  = pendingInt.toString();
        final pendingV = pendingDocs.toString();
        final rate = totalInt > 0
            ? '${((verifiedInt / totalInt) * 100).toStringAsFixed(1)}%'
            : '0.0%';

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System Overview',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 3 : 2,
                childAspectRatio: MediaQuery.sizeOf(context).width > 900 ? 1.8 : 1.5,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _buildStatCard('Total Users', total,
                      Icons.people, Colors.blue),
                  _buildStatCard('Online Now', onlineInt.toString(),
                      Icons.online_prediction, Colors.green.shade700),
                  _buildStatCard('Verified Users', verified,
                      Icons.verified_user, Colors.green),
                  _buildStatCard('Pending Users', pending,
                      Icons.pending, Colors.orange),
                  _buildStatCard('Premium Users', premiumInt.toString(),
                      Icons.workspace_premium, Colors.purple),
                  _buildStatCard('Free Users', freeInt.toString(),
                      Icons.person_outline, Colors.grey.shade600),
                  _buildStatCard('Pending Docs', pendingV,
                      Icons.description, Colors.red),
                  _buildStatCard('Verify Rate', rate,
                      Icons.trending_up, Colors.teal),
                  _buildStatCard('Active Members',
                      adminService.activeMembers.length.toString(),
                      Icons.card_membership, Colors.purple.shade800),
                  _buildStatCard('Pending Payments',
                      adminService.paymentRequests
                          .where((r) => _asText(r['status']).toLowerCase() == 'pending')
                          .length
                          .toString(),
                      Icons.payment, Colors.indigo),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                          fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ]),
      ),
    );
  }

  // ── PENDING USERS TAB ──────────────────────────────────────────────────────
  Widget _buildPendingUsersTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, child) {
        // FIX: Only show spinner on very first load (list empty + loading).
        // With live streams, isLoading briefly goes true on refreshData() —
        // showing a full spinner would flash away an already-populated list.
        if (adminService.isLoading && adminService.pendingUsers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (adminService.pendingUsers.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.pending_outlined, size: 52,
                  color: Colors.orange.withAlpha(140)),
              const SizedBox(height: 12),
              Text('No Pending Users',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: AppTheme.textMedium)),
              const SizedBox(height: 6),
              Text('New registrations needing approval will appear here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMedium)),
            ]),
          );
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('${adminService.pendingUsers.length} pending',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.orange, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Live', style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.orange, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: adminService.pendingUsers.length,
              itemBuilder: (context, index) {
                final user =
                    adminService.pendingUsers[index] as Map<String, dynamic>;
                return _safeItemCard(() => _buildUserCard(user, isPending: true));
              },
            ),
          ),
        ]);
      },
    );
  }

  // ── VERIFIED USERS TAB ─────────────────────────────────────────────────────
  Widget _buildVerifiedUsersTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, child) {
        if (adminService.isLoading && adminService.verifiedUsers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (adminService.verifiedUsers.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_user_outlined, size: 52,
                  color: Colors.green.withAlpha(140)),
              const SizedBox(height: 12),
              Text('No Verified Members',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: AppTheme.textMedium)),
              const SizedBox(height: 6),
              Text('Approved members will appear here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMedium)),
            ]),
          );
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('${adminService.verifiedUsers.length} verified',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Live', style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: adminService.verifiedUsers.length,
              itemBuilder: (context, index) {
                final user =
                    adminService.verifiedUsers[index] as Map<String, dynamic>;
                return _safeItemCard(() => _buildUserCard(user, isPending: false));
              },
            ),
          ),
        ]);
      },
    );
  }

  // ── DOCUMENTS TAB ──────────────────────────────────────────────────────────
  Widget _buildDocumentsTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, child) {
        if (adminService.isLoading && adminService.pendingVerifications.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (adminService.pendingVerifications.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.description_outlined, size: 52,
                  color: Colors.red.withAlpha(140)),
              const SizedBox(height: 12),
              Text('No Pending Documents',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: AppTheme.textMedium)),
              const SizedBox(height: 6),
              Text('Documents submitted for verification will appear here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMedium)),
            ]),
          );
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('${adminService.pendingVerifications.length} pending',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Live', style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.red, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: adminService.pendingVerifications.length,
              itemBuilder: (context, index) {
                return _safeItemCard(
                  () => _buildDocumentCard(adminService.pendingVerifications[index]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  // ── ALL USERS TAB — with Load More ─────────────────────────────────────────
  // FIX (Bug 6): Added pagination — loads 50 at a time with a "Load More" button.
  Widget _buildAllUsersTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, child) {
        if (adminService.isLoading && adminService.allUsers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Filter by search query
        var filtered = _searchQuery.isEmpty
            ? adminService.allUsers.cast<Map<String, dynamic>>()
            : adminService.allUsers
                .cast<Map<String, dynamic>>()
                .where((u) {
                  final q = _searchQuery.toLowerCase();
                  return ((u['first_name'] as String? ?? '').toLowerCase().contains(q)) ||
                      ((u['last_name'] as String? ?? '').toLowerCase().contains(q)) ||
                      ((u['mobile_number'] as String? ?? '').contains(q)) ||
                      (SafeDataExtractor.getProfileId(u).toLowerCase().contains(q));
                }).toList();
        
        // 🔥 NEW: Apply advanced filters
        if (_advancedFilter.isActive) {
          filtered = _applyAdvancedFilters(filtered);
        }

        if (adminService.allUsers.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        final itemCount = filtered.length + (adminService.hasMoreUsers && _searchQuery.isEmpty ? 1 : 0);

        return Column(children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, mobile or profile ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                isDense: true,
              ),
              onChanged: _onSearchChanged, // 🔥 Debounced for performance
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('${filtered.length} user${filtered.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              // 🔥 NEW: Advanced filter button
              AdvancedFilterButton(
                currentFilter: _advancedFilter,
                onApply: (filter) => setState(() => _advancedFilter = filter),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => adminService.refreshData(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index >= filtered.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: adminService.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            onPressed: () => adminService.loadMoreUsers(),
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Load More Users'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.kumkumRed,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  );
                }
                return _safeItemCard(
                  () => _buildUserCard(filtered[index], isPending: false, showActions: true),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  // ── ACTIVE MEMBERS TAB ─────────────────────────────────────────────────────
  // Live list of users with an active (non-expired) platinum membership.
  // Recomputed automatically whenever the allUsers stream fires.
  Widget _buildActiveMembersTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, _) {
        if (adminService.isLoading && adminService.activeMembers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = adminService.activeMembers.cast<Map<String, dynamic>>();

        if (members.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium,
                    size: 56, color: Colors.purple.withAlpha(120)),
                const SizedBox(height: 16),
                Text('No Active Platinum Members',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: AppTheme.textMedium)),
                const SizedBox(height: 8),
                Text('Members with a valid platinum plan will appear here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppTheme.textMedium)),
              ],
            ),
          );
        }

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Icon(Icons.workspace_premium, size: 18, color: Colors.purple),
              const SizedBox(width: 6),
              Text(
                '${members.length} active platinum member${members.length == 1 ? "" : "s"}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.green.withAlpha(140),
                    blurRadius: 6, spreadRadius: 1,
                  )],
                ),
              ),
              const SizedBox(width: 6),
              Text('Live', style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final user = members[index];
                final expires = _parseAnyDate(user['membership_expires_at']);
                final daysLeft = expires != null
                    ? expires.difference(DateTime.now()).inDays
                    : 0;
                // 🔥 CRITICAL: Extract userId for membership actions menu
                final String userId = _extractUserId(user);

                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.purple.withAlpha(20),
                      child: const Icon(Icons.workspace_premium,
                          color: Colors.purple, size: 22),
                    ),
                    title: Text(
                      [user['first_name'] ?? '', user['last_name'] ?? '']
                          .where((s) => s.isNotEmpty).join(' ').trim()
                          .isNotEmpty
                        ? [user['first_name'] ?? '', user['last_name'] ?? '']
                            .where((s) => s.isNotEmpty).join(' ')
                        : 'Unknown User',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      (user['mobile_number'] as String? ?? '').isNotEmpty
                          ? user['mobile_number']
                          : (user['email'] as String? ?? '—'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.purple.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('PLATINUM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.purple,
                              )),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          daysLeft > 0 ? '$daysLeft days left' : 'Expires today',
                          style: TextStyle(
                            fontSize: 11,
                            color: daysLeft <= 7 ? Colors.orange : AppTheme.textMedium,
                            fontWeight: daysLeft <= 7 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 🔥 CLEANER UX: Single menu with all membership actions
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 18, 
                            color: _isActionLoading(userId) ? Colors.grey : AppTheme.primaryOrange),
                          tooltip: 'Membership Actions',
                          onSelected: _isActionLoading(userId) ? null : (value) {
                            if (value == 'extend') _handleExtendPremiumTap(user);
                            if (value == 'manage') _handleManageMembershipTap(user);
                            if (value == 'clear_views') _clearUserProfileViews(user);
                            if (value == 'remove') _handleRemoveMembership(user);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'extend',
                              child: Row(children: [
                                const Icon(Icons.add_circle_outline, size: 18, color: Colors.green),
                                const SizedBox(width: 8),
                                const Text('Extend Premium'),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'manage',
                              child: Row(children: [
                                const Icon(Icons.workspace_premium, size: 18, color: Colors.purple),
                                const SizedBox(width: 8),
                                const Text('Manage Membership'),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'clear_views',
                              child: Row(children: [
                                const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Text('Clear Profile Views'),
                              ]),
                            ),
                            // 🔥 NEW: Quick remove option
                            PopupMenuItem(
                              value: 'remove',
                              child: Row(children: [
                                const Icon(Icons.remove_circle, size: 18, color: Colors.red),
                                const SizedBox(width: 8),
                                const Text('Remove Membership', style: TextStyle(color: Colors.red)),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _showUserDetails(user),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user,
      {required bool isPending, bool showActions = false}) {
    final firstName = _asText(user['first_name']);
    final lastName  = _asText(user['last_name']);
    final fullName  = '$firstName $lastName'.trim().isNotEmpty
        ? '$firstName $lastName'.trim()
        : 'Unknown User';
    final userId    = _asText(user['id']);
    final photoUrl  = _asText(user['profile_picture'], fallback: _asText(user['photo_url']));
    final photoUrlOrNull = photoUrl.isEmpty ? null : photoUrl;
    final mobile    = _asText(user['mobile_number']);
    final profileId = SafeDataExtractor.getProfileId(user);
    final status    = _asText(user['membership_status'], fallback: 'active');
    final isVerified = user['is_verified'] == true;
    final createdAt  = _asText(user['created_at']);
    final tier       = _asText(user['membership_tier'], fallback: 'free');
    final isPlatinum = tier.toLowerCase() == 'platinum';
    final presenceUserId = _extractUserId(user);

    // Key profile fields for at-a-glance admin view
    final gender     = _asText(user['gender']);
    final age        = _ageFromDob(user['date_of_birth']);
    final nakshatra  = _asText(user['nakshatra']);
    final rasi       = _asText(user['rasi']);
    final gothram    = _asText(user['gothram']);
    final sect       = _asText(user['sect']);
    final occupation = _asText(user['occupation']);
    final city       = _asText(user['city']);
    final stateVal   = _asText(user['state']);
    final location   = [city, stateVal].where((s) => s.isNotEmpty).join(', ');
    // Compute completion from actual profile fields when stored value is 0/null
    // 🔥 IMPROVED: Cleaner nullable cast pattern - handles null + type safely
    final completion = _asNum(user['profile_completion_percentage']).toDouble();
    final effectiveCompletion = completion == 0
        ? _computeCompletionFromFields(user)
        : completion;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Top row: avatar + name + badges ──
          Row(children: [
            SimplePhotoAvatar(photoUrl: photoUrlOrNull, name: fullName, size: 40, circle: true),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                if (isPlatinum) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('PLATINUM',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                            color: Colors.purple)),
                  ),
                ],
              ]),
              if (profileId.isNotEmpty)
                Text(profileId, style: const TextStyle(
                    fontSize: 11, color: AppTheme.primaryGold,
                    fontWeight: FontWeight.w600)),
              if (mobile.isNotEmpty)
                Text(mobile, style: const TextStyle(
                    fontSize: 12, color: AppTheme.textMedium)),
              // 🔥 NEW: User badges row (Premium, Verified, New, etc.)
              UserBadgesRow.fromUserData(user, badgeSize: 20, showLabels: false),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (isPending)
                const Chip(label: Text('Pending',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.orange, padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)
              else if (isVerified)
                const Chip(label: Text('Verified',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.green, padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              if (createdAt.isNotEmpty)
                Text('Joined ${_datePart(createdAt)}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textMedium)),
              if (presenceUserId.isNotEmpty)
                LivePresenceLabel(
                  userId: presenceUserId,
                  compact: true,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ]),
          ]),

          // ── Profile summary chips ──
          if ([gender, age, nakshatra, rasi, gothram, sect, occupation, location]
              .any((s) => s.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (gender.isNotEmpty)    _chip(Icons.person_outline, gender),
              if (age.isNotEmpty)       _chip(Icons.cake_outlined, age),
              if (occupation.isNotEmpty) _chip(Icons.work_outline, occupation),
              if (location.isNotEmpty)  _chip(Icons.location_on_outlined, location),
              if (sect.isNotEmpty)      _chip(Icons.temple_hindu_outlined, sect),
              if (gothram.isNotEmpty)   _chip(Icons.family_restroom, 'Gothram: $gothram'),
              if (nakshatra.isNotEmpty) _chip(Icons.star_outline, nakshatra),
              if (rasi.isNotEmpty)      _chip(Icons.brightness_2_outlined, rasi),
            ]),
          ],

          // ── Completion bar ──
          ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('Profile', style: TextStyle(fontSize: 10,
                color: AppTheme.textMedium)),
            const SizedBox(width: 6),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // 🔥 FIX: Use effectiveCompletion (computed from fields if 0)
                value: (effectiveCompletion.toDouble()) / 100,
                minHeight: 5,
                backgroundColor: Colors.grey.withAlpha(40),
                color: effectiveCompletion >= 80 ? Colors.green : AppTheme.primaryOrange,
              ),
            )),
            const SizedBox(width: 6),
            // 🔥 FIX: Display effectiveCompletion
            Text('${effectiveCompletion.toInt()}%', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: effectiveCompletion >= 80 ? Colors.green : AppTheme.primaryOrange)),
          ]),
        ],

          // ── Action buttons ──
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ElevatedButton(
                onPressed: () => _showRejectDialog(user),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: userId.isNotEmpty ? () => _approveUser(userId) : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: const Text('Approve'),
              ),
            ]),
          ],
          if (showActions)
            Wrap(alignment: WrapAlignment.end, children: [
              IconButton(
                onPressed: () => _showUserDetails(user),
                icon: const Icon(Icons.info_outline),
                tooltip: 'View Full Profile',
                color: Colors.blue,
              ),
              IconButton(
                onPressed: userId.isNotEmpty ? () => _showMembershipDialog(user) : null,
                icon: const Icon(Icons.workspace_premium),
                tooltip: 'Manage Membership',
                color: Colors.purple,
              ),
              IconButton(
                onPressed: userId.isNotEmpty ? () => _clearUserProfileViews(user) : null,
                icon: const Icon(Icons.visibility_off_outlined),
                tooltip: 'Clear profile view history',
                color: Colors.teal,
              ),
              if (status == 'active')
                IconButton(
                  onPressed: userId.isNotEmpty ? () => _suspendUser(userId) : null,
                  icon: const Icon(Icons.block),
                  tooltip: 'Suspend',
                  color: Colors.orange,
                ),
              if (status == 'suspended')
                IconButton(
                  onPressed: userId.isNotEmpty ? () => _reactivateUser(userId) : null,
                  icon: const Icon(Icons.check_circle),
                  tooltip: 'Reactivate',
                  color: Colors.green,
                ),
              IconButton(
                onPressed: () => _showDeleteDialog(user),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                color: Colors.red,
              ),
              // 🔥 NEW: Quick block/report menu for safety
              BlockReportMenu(
                targetUserId: userId,
                targetUserName: fullName,
                onBlocked: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$fullName blocked from admin view')),
                  );
                },
                onReported: () {
                  // Report recorded - admin will review
                },
              ),
            ]),
        ]),
      ),
    );
  }

  /// Small icon+text chip for profile field display in user cards
  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryOrange.withAlpha(12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryOrange.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AppTheme.primaryOrange),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(
            fontSize: 11, color: AppTheme.primaryOrange,
            fontWeight: FontWeight.w500)),
      ]),
    );
  }

  /// Calculate age string from date_of_birth field
  /// Compute profile completion % from raw Firestore fields when stored value is 0.
  int _computeCompletionFromFields(Map<String, dynamic> u) {
    const tracked = [
      'first_name', 'last_name', 'date_of_birth', 'nakshatra', 'rasi',
      'gothram', 'sect', 'occupation', 'education', 'city', 'state',
      'marital_status', 'family_type', 'food_habit', 'about_me',
      'profile_picture', 'father_name', 'mother_name', 'income_range', 'height',
    ];
    int filled = 0;
    for (final f in tracked) {
      // Also check inside nested 'profile' map if root key is missing
      dynamic val = u[f];
      if (val == null) {
        final nested = u['profile'];
        if (nested is Map) val = nested[f];
      }
      if (val != null && val.toString().trim().isNotEmpty) filled++;
    }
    return ((filled / tracked.length) * 100).round();
  }

  String _ageFromDob(dynamic dob) {
    if (dob == null) return '';
    final dt = DateTime.tryParse(dob.toString());
    if (dt == null) return '';
    final age = DateTime.now().year - dt.year -
        (DateTime.now().isBefore(DateTime(DateTime.now().year, dt.month, dt.day)) ? 1 : 0);
    return '$age yrs';
  }

  String _asNonEmptyString(dynamic value) {
    if (value == null) return '';
    final str = value.toString().trim();
    return str;
  }

  String _extractUserId(Map<String, dynamic> user) {
    // Use only identifiers that can resolve to users/{docId}.
    // Never use profile_id directly for writes.
    final idCandidates = <dynamic>[
      user['id'],
      user['user_id'],
      user['userId'],
      user['uid'],
      user['auth_uid'],
    ];

    for (final candidate in idCandidates) {
      final resolved = _asNonEmptyString(candidate);
      if (resolved.isNotEmpty) return resolved;
    }
    return '';
  }

  void _handleExtendPremiumTap(Map<String, dynamic> user) {
    // 🔥 CRITICAL: Only use REAL Firestore document ID - NO fake IDs
    final userId = _extractUserId(user);
    
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Invalid user ID. Cannot extend membership. Please refresh data.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }
    
    _showPremiumDialog({...user, 'id': userId});
  }

  void _handleManageMembershipTap(Map<String, dynamic> user) {
    // 🔥 CRITICAL: Only use REAL Firestore document ID - NO fake IDs
    final userId = _extractUserId(user);
    
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Invalid user ID. Cannot manage membership. Please refresh data.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }
    
    _showMembershipDialog({...user, 'id': userId});
  }

  /// 🔥 Quick remove membership (one-tap from menu)
  void _handleRemoveMembership(Map<String, dynamic> user) async {
    final userId = _extractUserId(user);
    final firstName = _asText(user['first_name']);
    final lastName = _asText(user['last_name']);
    final fullName = '$firstName $lastName'.trim();
    
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Invalid user ID. Cannot remove membership.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.remove_circle, color: Colors.red),
          SizedBox(width: 8),
          Text('Remove Membership'),
        ]),
        content: Text('Remove platinum membership from ${fullName.isNotEmpty ? fullName : 'this user'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    if (!mounted) return;

    // Use safe action helper for consistency
    final adminService = Provider.of<AdminService>(context, listen: false);
    await _safeAdminAction(
      actionKey: 'remove_membership_$userId',
      userId: userId,
      action: () => adminService.updateUserMembership(
        userId, 
        Membership(tier: MembershipTier.free, expiryDate: null),
      ),
      successMsg: '✅ Membership removed from ${fullName.isNotEmpty ? fullName : 'user'}',
      errorMsg: '❌ Failed to remove membership',
    );
  }

  // ── DOCUMENT CARD ──────────────────────────────────────────────────────────
  Widget _buildDocumentCard(ProfileVerification verification) {
    final typeLabel = verification.type.name;
    final submitted =
        verification.submittedAt?.toIso8601String().split('T')[0] ?? '';
    final docUrl = verification.documentUrl;
    final adminService = context.read<AdminService>();
    Map<String, dynamic>? matchedUser;
    for (final raw in adminService.allUsers) {
      final user = raw as Map<String, dynamic>;
      final id = _extractUserId(user);
      if (id == verification.userId) {
        matchedUser = user;
        break;
      }
    }
    final firstName = _asText(matchedUser?['first_name']);
    final lastName = _asText(matchedUser?['last_name']);
    final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    final userDisplayName =
        fullName.isNotEmpty ? fullName : 'User ${verification.userId}';
    final profileId = matchedUser != null
        ? SafeDataExtractor.getProfileId(matchedUser)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SimplePhotoAvatar(
                  photoUrl: null,
                  name: userDisplayName.isNotEmpty
                      ? userDisplayName[0].toUpperCase()
                      : 'U',
                  size: 40,
                  circle: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userDisplayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold)),
                        Text(
                          profileId.isNotEmpty
                              ? 'ID: $profileId'
                              : 'User ID: ${verification.userId}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text('Type: $typeLabel',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium),
                        if (submitted.isNotEmpty)
                          Text('Submitted: $submitted',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall),
                      ]),
                ),
                const Chip(
                  label: Text('Pending',
                      style: TextStyle(color: Colors.white)),
                  backgroundColor: Colors.orange,
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: docUrl != null && docUrl.isNotEmpty
                        ? () => _viewDocument(docUrl)
                        : null,
                    child: const Text('View Document'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _showRejectDocumentDialog(verification),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _approveDocument(verification.id),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                    child: const Text('Approve'),
                  ),
                ),
              ]),
            ]),
      ),
    );
  }

  // ── ACTIONS ────────────────────────────────────────────────────────────────
  // 🔥 Helper for safe async admin actions with loading + error handling + audit logging
  Future<void> _safeAdminAction({
    required String actionKey,
    required String userId,
    required Future<bool> Function() action,
    required String successMsg,
    required String errorMsg,
  }) async {
    // Prevent double-taps
    if (!_beginActionLoading(actionKey)) return;
    
    // Check mounted before starting
    if (!mounted) return;
    
    final String adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final timestamp = DateTime.now();
    
    try {
      final success = await action();
      
      // 🔥 CRITICAL: Check mounted after EVERY await
      if (!mounted) return;
      
      // 🔐 AUDIT LOG: Log successful action
      unawaited(_logAdminAction(
        action: actionKey,
        targetUserId: userId,
        adminUid: adminUid,
        timestamp: timestamp,
        success: true,
      ));
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? successMsg : errorMsg),
        backgroundColor: success ? Colors.green : AppTheme.kumkumRed,
      ));
    } catch (e, stackTrace) {
      debugPrint('❌ Admin action [$actionKey] failed: $e');
      debugPrint('Stack: $stackTrace');
      
      // 🔥 CRASH REPORTING: Record to Crashlytics in production
      _reportError(e, stackTrace, reason: 'admin_action_$actionKey');
      
      // 🔐 AUDIT LOG: Log failed action
      unawaited(_logAdminAction(
        action: actionKey,
        targetUserId: userId,
        adminUid: adminUid,
        timestamp: timestamp,
        success: false,
        error: e.toString(),
      ));
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$errorMsg: $e'),
        backgroundColor: AppTheme.kumkumRed,
      ));
    } finally {
      _setActionLoading(actionKey, false);
    }
  }

  /// 🔐 Write admin audit log to Firestore
  Future<void> _logAdminAction({
    required String action,
    required String targetUserId,
    required String adminUid,
    required DateTime timestamp,
    required bool success,
    String? error,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('admin_logs').add({
        'action': action,
        'target_user_id': targetUserId,
        'admin_uid': adminUid,
        'timestamp': FieldValue.serverTimestamp(),
        'success': success,
        if (error != null) 'error': error,
        'platform': 'admin_dashboard',
      });
      debugPrint('🔐 Audit log: $action on $targetUserId');
    } catch (e) {
      // Don't fail the action if logging fails
      debugPrint('⚠️ Failed to write audit log: $e');
    }
  }

  /// 🔥 Report error to crash reporting service
  void _reportError(dynamic error, StackTrace stackTrace, {required String reason}) {
    // In production, this would report to Firebase Crashlytics or similar
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
    debugPrint('📤 Error reported [$reason]: $error');
  }

  Future<void> _approveUser(String userId) async {
    final adminService = Provider.of<AdminService>(context, listen: false);
    
    await _safeAdminAction(
      actionKey: 'approve_$userId',
      userId: userId,
      action: () => adminService.approveUserMembership(userId),
      successMsg: '✅ User approved successfully',
      errorMsg: '❌ Failed to approve user',
    );
  }

  Future<void> _suspendUser(String userId) async {
    // Show confirm dialog first (outside of loading state)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.block, color: Colors.orange),
          SizedBox(width: 8),
          Text('Suspend User'),
        ]),
        content: const Text(
            'Are you sure you want to suspend this user? They will not be able to access the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    
    final adminService = Provider.of<AdminService>(context, listen: false);
    await _safeAdminAction(
      actionKey: 'suspend_$userId',
      userId: userId,
      action: () => adminService.suspendUser(userId, 'Suspended by admin'),
      successMsg: '✅ User suspended',
      errorMsg: '❌ Failed to suspend user',
    );
  }

  Future<void> _reactivateUser(String userId) async {
    final adminService = Provider.of<AdminService>(context, listen: false);
    await _safeAdminAction(
      actionKey: 'reactivate_$userId',
      userId: userId,
      action: () => adminService.reactivateUser(userId),
      successMsg: '✅ User reactivated',
      errorMsg: '❌ Failed to reactivate user',
    );
  }

  Future<void> _approveDocument(String verificationId) async {
    final adminService = Provider.of<AdminService>(context, listen: false);
    await _safeAdminAction(
      actionKey: 'approve_doc_$verificationId',
      userId: verificationId,
      action: () => adminService.verifyDocument(verificationId, true, null),
      successMsg: '✅ Document approved',
      errorMsg: '❌ Failed to approve document',
    );
  }

  Future<void> _clearUserProfileViews(Map<String, dynamic> user) async {
    final userId = _extractUserId(user);
    final firstName = _asText(user['first_name']);
    final lastName = _asText(user['last_name']);
    final fullName = '$firstName $lastName'.trim();
    final label = fullName.isNotEmpty ? fullName : 'this user';

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Invalid user ID. Cannot clear profile view history.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.visibility_off_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Clear Profile Views'),
          ],
        ),
        content: Text(
          'Clear "Who saw your profile" history for $label?\n\nThis removes all recorded viewers for this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final adminService = Provider.of<AdminService>(context, listen: false);
    final deletedCount = await adminService.clearProfileViewHistory(userId);
    if (!mounted) return;

    if (deletedCount >= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedCount > 0
                ? '✅ Cleared $deletedCount profile view record${deletedCount == 1 ? '' : 's'} for $label'
                : 'No profile view records found for $label',
          ),
          backgroundColor: deletedCount > 0
              ? AppTheme.sacredGreen
              : AppTheme.primaryOrange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to clear profile view history for $label'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  // ── DIALOGS ────────────────────────────────────────────────────────────────
  void _showRejectDialog(Map<String, dynamic> user) {
    final firstName = _asText(user['first_name']);
    final lastName = _asText(user['last_name']);
    final fullName = '$firstName $lastName'.trim();
    final userId = _asText(user['id']);
    
    // 🔥 CRITICAL: Controller OUTSIDE StatefulBuilder - created ONCE
    final reasonController = TextEditingController();
    bool isDisposed = false;
    
    void safeDispose() {
      if (!isDisposed) {
        reasonController.dispose();
        isDisposed = true;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject User'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Reject $fullName?'),
          const SizedBox(height: 16),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              hintText: 'Reason for rejection',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              safeDispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final String reason = reasonController.text.trim();
              safeDispose();
              Navigator.pop(ctx);
              
              if (userId.isEmpty) return;
              
              final adminService = Provider.of<AdminService>(context, listen: false);
              final success = await adminService.rejectUser(
                userId, 
                reason.isNotEmpty ? reason : 'Rejected by admin',
              );
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(success ? '✅ User rejected' : '❌ Failed to reject user'),
                backgroundColor: success ? Colors.red : AppTheme.kumkumRed,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    ).then((_) => safeDispose()); // Safety net disposal
  }

  void _showRejectDocumentDialog(ProfileVerification verification) {
    // 🔥 CRITICAL: Controller OUTSIDE StatefulBuilder - created ONCE
    final reasonController = TextEditingController();
    bool isDisposed = false;
    
    void safeDispose() {
      if (!isDisposed) {
        reasonController.dispose();
        isDisposed = true;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Document'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Reject ${verification.type.name} document for user ${verification.userId}?'),
          const SizedBox(height: 16),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              hintText: 'Reason for rejection',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              safeDispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final String reason = reasonController.text;
              safeDispose();
              Navigator.pop(ctx);
              
              final adminService = Provider.of<AdminService>(context, listen: false);
              final success = await adminService.verifyDocument(
                verification.id, false, reason);
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(success ? '✅ Document rejected' : '❌ Failed to reject document'),
                backgroundColor: success ? Colors.orange : AppTheme.kumkumRed,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    ).then((_) => safeDispose()); // Safety net disposal
  }

  void _showDeleteDialog(Map<String, dynamic> user) {
    final firstName = _asText(user['first_name']);
    final lastName = _asText(user['last_name']);
    final fullName = '$firstName $lastName'.trim();
    final userId = _asText(user['id']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
            'Are you sure you want to delete $fullName? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (userId.isEmpty) return;
              final adminService =
                  Provider.of<AdminService>(context, listen: false);
              final success = await adminService.deleteUser(userId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(success
                    ? 'User deleted'
                    : 'Failed to delete user'),
                backgroundColor:
                    success ? Colors.green : AppTheme.kumkumRed,
              ));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPremiumDialog(Map<String, dynamic> user) {
    final userId    = _asText(user['id']);
    final firstName = _asText(user['first_name']);
    final lastName  = _asText(user['last_name']);
    final fullName  = '$firstName $lastName'.trim();
    final currentTier = _asText(user['membership_tier'], fallback: 'free');
    final isPlatinum  = currentTier.toLowerCase() == 'platinum';

    // Determine the base expiry to extend FROM:
    // • If currently platinum → extend from existing expiry (not today)
    // • If free → start from today
    final existingExpiry = isPlatinum
        ? (SafeDataExtractor.parseFirestoreDate(user['membership_expires_at']) ??
            DateTime.tryParse(user['membership_expires_at']?.toString() ?? '') ??
            DateTime.now())
        : DateTime.now();

    // Days state — lives inside StatefulBuilder so preview updates live
    int days = 30;
    bool isExtending = false; // 🔥 CRITICAL: Loading state OUTSIDE builder
    // 🔥 CRITICAL: Controller declared OUTSIDE, initialized inside with ??=
    TextEditingController? daysCtrl;
    bool isCtrlDisposed = false;
    void safeDisposeCtrl() {
      if (!isCtrlDisposed && daysCtrl != null) {
        daysCtrl!.dispose();
        isCtrlDisposed = true;
      }
    }

    DateTime calcNewExpiry(int d, DateTime base) =>
        base.isBefore(DateTime.now())
            ? DateTime.now().add(Duration(days: d))   // expired — extend from today
            : base.add(Duration(days: d));  // still active — extend from existing

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // 🔥 CRITICAL: Controller created ONCE with ??= guard
          daysCtrl ??= TextEditingController(text: '$days');
          // Sync controller text if days changed via quick-pick (before build)
          if (daysCtrl != null && daysCtrl!.text != '$days') {
            daysCtrl!.text = '$days';
          }
          final newExpiry = calcNewExpiry(days, existingExpiry);
          final daysLeftLabel = isPlatinum
              ? (() {
                  final dl = existingExpiry.difference(DateTime.now()).inDays;
                  return dl > 0 ? '($dl days remaining)' : '(expired)';
                })()
              : '';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.workspace_premium, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('Extend Premium: $fullName',
                  style: const TextStyle(fontSize: 16))),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current status
                Row(children: [
                  const Text('Current: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  Chip(
                    label: Text(isPlatinum ? 'PLATINUM' : 'FREE',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    backgroundColor: isPlatinum ? Colors.purple : Colors.grey,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (daysLeftLabel.isNotEmpty) ...[ 
                    const SizedBox(width: 8),
                    Text(daysLeftLabel,
                        style: TextStyle(fontSize: 11,
                            color: existingExpiry.isAfter(DateTime.now())
                                ? Colors.orange : Colors.red)),
                  ],
                ]),
                const SizedBox(height: 4),
                // Base date being extended from
                Text(
                  isPlatinum
                      ? 'Extending from: ${existingExpiry.day}/${existingExpiry.month}/${existingExpiry.year}'
                      : 'Starting from: today',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 14),
                // Days input
                TextField(
                  controller: daysCtrl!,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days to extend',
                    hintText: 'e.g. 30, 90, 365',
                    border: OutlineInputBorder(),
                    suffixText: 'days',
                  ),
                  onChanged: (val) {
                    // Update days AND trigger preview refresh via setLocal
                    final parsed = int.tryParse(val.trim());
                    if (parsed != null && parsed > 0) {
                      setLocal(() => days = parsed);
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Live preview of new expiry
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withAlpha(60)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event_available, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New expiry: ${newExpiry.day}/${newExpiry.month}/${newExpiry.year}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: Colors.green),
                      ),
                    ),
                  ]),
                ),
                // Quick-pick buttons
                const SizedBox(height: 10),
                Wrap(spacing: 6, children: [
                  for (final d in [30, 90, 180, 365])
                    ActionChip(
                      label: Text('$d d', style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        daysCtrl?.text = '$d';
                        setLocal(() => days = d);
                      },
                      backgroundColor: days == d
                          ? Colors.green.withAlpha(30)
                          : null,
                      side: BorderSide(
                          color: days == d ? Colors.green : Colors.grey.shade300),
                    ),
                ]),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  safeDisposeCtrl(); // ✅ Dispose on cancel
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isExtending ? null : () async {
                  setLocal(() => isExtending = true); // 🔥 Show loading
                  safeDisposeCtrl(); // ✅ Dispose before async
                  Navigator.pop(ctx);
                  if (!mounted) return; // 🔥 CRITICAL: Check after pop
                  if (userId.isEmpty) {
                    setLocal(() => isExtending = false);
                    return;
                  }
                  // Use the correctly computed new expiry (extending from existing)
                  final newExp = calcNewExpiry(days, existingExpiry);
                  final adminService = Provider.of<AdminService>(context, listen: false);
                  final membership = Membership(
                    tier: MembershipTier.platinum,
                    expiryDate: newExp,
                    startDate: DateTime.now(),
                  );
                  final success = await adminService.updateUserMembership(userId, membership);
                  
                  // 🔥 CRITICAL: Refresh UI so change is visible immediately
                  if (success) await adminService.refreshData();
                  
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success
                        ? '✅ Extended $days days → expires ${newExp.day}/${newExp.month}/${newExp.year}'
                        : '❌ Failed to extend premium'),
                    backgroundColor: success ? Colors.green : AppTheme.kumkumRed,
                  ));
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white),
                icon: isExtending 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: Text(isExtending ? 'Extending...' : 'Extend $days days'),
              ),
            ],
          );
        },
      ),
    ).then((_) => safeDisposeCtrl()); // Safety net disposal
  }

  void _showMembershipDialog(Map<String, dynamic> user) {
    final userId      = _asText(user['id']);
    final firstName   = _asText(user['first_name']);
    final lastName    = _asText(user['last_name']);
    final fullName    = '$firstName $lastName'.trim();
    final mobile      = _asText(user['mobile_number']);
    final profileId   = SafeDataExtractor.getProfileId(user);
    final currentTier = _asText(user['membership_tier'], fallback: 'free');
    final isPlatinum  = currentTier.toLowerCase() == 'platinum';

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Invalid user ID — cannot update membership'),
        backgroundColor: AppTheme.kumkumRed,
      ));
      return;
    }

    // Parse existing expiry (shown in the dialog so admin can see what they are editing)
    final existingExpiry = isPlatinum
        ? (SafeDataExtractor.parseFirestoreDate(user['membership_expires_at']) ??
            DateTime.tryParse(user['membership_expires_at']?.toString() ?? ''))
        : null;

    // Default new expiry to existing (if platinum) or +30 days (if free)
    DateTime selectedExpiry = existingExpiry ??
        DateTime.now().add(const Duration(days: 30));
    bool isProcessing = false; // 🔥 CRITICAL: Loading state OUTSIDE builder

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) {
          final daysUntilExpiry = selectedExpiry.difference(DateTime.now()).inDays;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.workspace_premium, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(child: Text('Manage Membership',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── User info ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName.isNotEmpty ? fullName : 'Unknown User',
                            style: const TextStyle(fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        if (profileId.isNotEmpty)
                          Text(profileId, style: const TextStyle(
                              fontSize: 11, color: AppTheme.primaryGold,
                              fontWeight: FontWeight.w600)),
                        if (mobile.isNotEmpty)
                          Text(mobile, style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMedium)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Current status ──────────────────────────────────────
                  Row(children: [
                    const Text('Status: ',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Chip(
                      label: Text(isPlatinum ? 'PLATINUM' : 'FREE',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor: isPlatinum ? Colors.purple : Colors.grey,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (isPlatinum && existingExpiry != null) ...[ 
                      const SizedBox(width: 8),
                      Text(
                        existingExpiry.isAfter(DateTime.now())
                            ? '${existingExpiry.difference(DateTime.now()).inDays}d left'
                            : 'EXPIRED',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: existingExpiry.isAfter(DateTime.now())
                                ? Colors.orange : Colors.red),
                      ),
                    ],
                  ]),

                  if (isPlatinum && existingExpiry != null) ...[ 
                    Text(
                      'Current expiry: ${existingExpiry.day}/${existingExpiry.month}/${existingExpiry.year}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                  const Divider(height: 20),

                  // ── New expiry picker ───────────────────────────────────
                  const Text('Set new expiry date:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 10),

                  // Calendar button — shows currently selected date
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx2,
                          initialDate: selectedExpiry.isAfter(DateTime.now())
                              ? selectedExpiry
                              : DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                          helpText: 'Select new expiry date',
                          confirmText: 'SET DATE',
                        );
                        if (picked != null) setLocal(() => selectedExpiry = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        '${selectedExpiry.day}/${selectedExpiry.month}/${selectedExpiry.year}',
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple,
                        side: const BorderSide(color: Colors.purple),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Quick-select duration shortcuts
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final entry in {
                      '30d': 30, '3M': 90, '6M': 180, '1Y': 365,
                    }.entries)
                      ActionChip(
                        label: Text(entry.key,
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () => setLocal(() =>
                            selectedExpiry = DateTime.now()
                                .add(Duration(days: entry.value))),
                        backgroundColor: null,
                        side: const BorderSide(color: Colors.purple, width: 0.8),
                      ),
                  ]),
                  const SizedBox(height: 10),

                  // New expiry preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withAlpha(60)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.event_available, size: 16,
                          color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Expires: ${selectedExpiry.day}/${selectedExpiry.month}/${selectedExpiry.year}'
                        '  ($daysUntilExpiry days from today)',
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: Colors.purple),
                      )),
                    ]),
                  ),
                ],
              ),
            ),
            actions: [
              // Set Free button
              TextButton.icon(
                onPressed: isProcessing ? null : () async {
                  final confirmed = await showDialog<bool>(
                    context: ctx2,
                    builder: (c) => AlertDialog(
                      title: const Text('Revert to Free?'),
                      content: Text(
                          'This will remove platinum membership from $fullName immediately.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white),
                          child: const Text('Revert to Free'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (!ctx.mounted) return;
                  
                  setLocal(() => isProcessing = true); // 🔥 Show loading
                  Navigator.pop(ctx);
                  if (!mounted) return; // 🔥 CRITICAL: Check after pop
                  
                  final adminService = Provider.of<AdminService>(context, listen: false);
                  final m = Membership(tier: MembershipTier.free, expiryDate: null);
                  final ok = await adminService.updateUserMembership(userId, m);
                  
                  // 🔥 CRITICAL: Refresh UI so change is visible immediately
                  if (ok) await adminService.refreshData();
                  
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '✅ $fullName reverted to Free'
                        : '❌ Failed to revert to Free'),
                    backgroundColor: ok ? Colors.grey : AppTheme.kumkumRed,
                  ));
                  setLocal(() => isProcessing = false);
                },
                icon: isProcessing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                    : const Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
                label: Text(isProcessing ? 'Processing...' : 'Set Free',
                    style: const TextStyle(color: Colors.red)),
              ),

              // Grant/Update Platinum button
              ElevatedButton.icon(
                onPressed: isProcessing ? null : () async {
                  setLocal(() => isProcessing = true); // 🔥 Show loading
                  Navigator.pop(ctx);
                  if (!mounted) return; // 🔥 CRITICAL: Check after pop
                  if (userId.isEmpty) {
                    setLocal(() => isProcessing = false);
                    return;
                  }
                  final adminService = Provider.of<AdminService>(context, listen: false);
                  final m = Membership(
                      tier: MembershipTier.platinum,
                      expiryDate: selectedExpiry,
                      startDate: DateTime.now());
                  final ok = await adminService.updateUserMembership(userId, m);
                  
                  // 🔥 CRITICAL: Refresh UI so change is visible immediately
                  if (ok) await adminService.refreshData();
                  
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '✅ Platinum set — expires ${selectedExpiry.day}/${selectedExpiry.month}/${selectedExpiry.year}'
                        : '❌ Failed to update membership'),
                    backgroundColor: ok ? Colors.purple : AppTheme.kumkumRed,
                  ));
                  setLocal(() => isProcessing = false);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white),
                icon: isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.workspace_premium, size: 18),
                label: Text(isProcessing ? 'Updating...' : (isPlatinum ? 'Update Platinum' : 'Grant Platinum')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) => _UserDetailsDialog(user: user),
    );
  }

  Future<void> _viewDocument(String documentUrl) async {
    if (documentUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document URL available')),
      );
      return;
    }
    try {
      final uri = Uri.parse(documentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: show URL so admin can copy it
        if (mounted) _showDocumentUrlDialog(documentUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open document: $e'),
              backgroundColor: AppTheme.kumkumRed),
        );
      }
    }
  }

  void _showDocumentUrlDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Document URL'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Could not open automatically. Copy the URL below:'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(url,
                style: const TextStyle(fontSize: 12, color: Colors.blue)),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
            child: const Text('Copy URL'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  // ── PAYMENT REQUESTS TAB ──────────────────────────────────────────────────
  /// Shows all payment_requests sorted newest-first. Pending ones have
  /// Approve / Reject buttons. Approved/Rejected entries are read-only.
  Widget _buildPaymentRequestsTab() {
    return Consumer<AdminService>(
      builder: (context, adminService, _) {
        if (adminService.isLoading && adminService.paymentRequests.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final all      = adminService.paymentRequests;
        final pending  = all.where((r) => _asText(r['status']).toLowerCase() == 'pending').toList();
        final approved = all.where((r) => _asText(r['status']).toLowerCase() == 'approved').toList();
        final rejected = all.where((r) => _asText(r['status']).toLowerCase() == 'rejected').toList();

        if (all.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.payment_outlined, size: 52,
                  color: Colors.indigo.withAlpha(140)),
              const SizedBox(height: 12),
              Text('No Payment Requests',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: AppTheme.textMedium)),
              const SizedBox(height: 6),
              Text('Premium upgrade requests will appear here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMedium)),
            ]),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // ── Summary chips ──
            Wrap(spacing: 8, children: [
              _paymentChip('Pending',  pending.length,  Colors.orange),
              _paymentChip('Approved', approved.length, Colors.green),
              _paymentChip('Rejected', rejected.length, Colors.red),
            ]),
            const SizedBox(height: 16),

            // ── Pending section ──
            if (pending.isNotEmpty) ...[
              _sectionHeader('Pending Approval', Colors.orange, Icons.hourglass_top),
              ...pending.map((r) => _safeItemCard(() => _buildPaymentCard(r, adminService))),
              const SizedBox(height: 8),
            ],

            // ── Approved section ──
            if (approved.isNotEmpty) ...[
              _sectionHeader('Approved', Colors.green, Icons.check_circle_outline),
              ...approved.map((r) => _safeItemCard(() => _buildPaymentCard(r, adminService))),
              const SizedBox(height: 8),
            ],

            // ── Rejected section ──
            if (rejected.isNotEmpty) ...[
              _sectionHeader('Rejected', Colors.red, Icons.cancel_outlined),
              ...rejected.map((r) => _safeItemCard(() => _buildPaymentCard(r, adminService))),
            ],
          ],
        );
      },
    );
  }

  Widget _paymentChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withAlpha(30),
        child: Text('$count',
            style: TextStyle(fontSize: 11, color: color,
                fontWeight: FontWeight.bold)),
      ),
      label: Text(label,
          style: TextStyle(fontSize: 12, color: color,
              fontWeight: FontWeight.w600)),
      backgroundColor: color.withAlpha(15),
      side: BorderSide(color: color.withAlpha(60)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _sectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: color)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withAlpha(60))),
      ]),
    );
  }

  Widget _buildPaymentCard(
      Map<String, dynamic> request, AdminService adminService) {
    final requestId  = _asText(request['id']);
    final userName   = _asText(request['user_name'], fallback: 'Unknown');
    final mobile     = _asText(request['mobile_number'], fallback: '—');
    final planName   = _asText(request['plan_name'], fallback: '—');
    final amount     = request['amount'];
    final utr        = _asText(request['utr'], fallback: '—');
    final statusRaw  = _asText(request['status'], fallback: 'pending');
    final status = statusRaw.isEmpty ? 'pending' : statusRaw;
    final submittedAt = _asText(request['submitted_at']);
    final approvedAt  = _asText(request['approved_at']);
    final rejectionReason = _asText(request['rejection_reason']);
    final days = _asInt(request['plan_days'], fallback: 30);

    final isPending  = status == 'pending';
    final isApproved = status == 'approved';
    final statusColor = isPending
        ? Colors.orange
        : isApproved
            ? Colors.green
            : Colors.red;
    final statusIcon = isPending
        ? Icons.hourglass_top
        : isApproved
            ? Icons.check_circle
            : Icons.cancel;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: statusColor.withAlpha(60))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row ──
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: statusColor.withAlpha(20),
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                style: TextStyle(color: statusColor,
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15)),
              Text(mobile,
                  style: TextStyle(fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withAlpha(80)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(status.isNotEmpty
                        ? '${status[0].toUpperCase()}${status.substring(1)}'
                        : 'Pending',
                    style: TextStyle(fontSize: 11, color: statusColor,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Details grid ──
          Wrap(spacing: 24, runSpacing: 6, children: [
            _payDetail('Plan', planName),
            _payDetail('Amount', '₹$amount'),
            _payDetail('Duration', '$days days'),
            _payDetail('UTR', utr),
            if (submittedAt.isNotEmpty)
              _payDetail('Submitted', _shortDate(submittedAt)),
            if (isApproved && approvedAt.isNotEmpty)
              _payDetail('Approved on', _shortDate(approvedAt)),
            if (!isPending && !isApproved && rejectionReason.isNotEmpty)
              _payDetail('Reason', rejectionReason),
          ]),

          // ── Action buttons (pending only) ──
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _showRejectPaymentDialog(request, adminService),
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: requestId.isNotEmpty
                    ? () => _confirmApprovePayment(request, adminService)
                    : null,
                icon: const Icon(Icons.check, size: 15),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _payDetail(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 10, color: AppTheme.textMedium,
              fontWeight: FontWeight.w600)),
      Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }

  String _shortDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso.split('T').first;
    }
  }

  String _datePart(String raw) {
    final parsed = _parseAnyDate(raw);
    if (parsed == null) {
      return raw.contains('T') ? raw.split('T').first : raw;
    }
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  Future<void> _confirmApprovePayment(
      Map<String, dynamic> request, AdminService adminService) async {
    final userName = _asText(request['user_name'], fallback: 'this user');
    final planName = _asText(request['plan_name'], fallback: 'plan');
    final amount   = request['amount'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.workspace_premium, color: Colors.green),
          SizedBox(width: 8),
          Text('Approve Payment'),
        ]),
        content: Text(
          'Approve ₹$amount payment by $userName for "$planName"?\n\n'
          'This will immediately grant them platinum membership.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            child: const Text('Yes, Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await adminService.approvePaymentRequest(request);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✅ Payment approved — platinum granted to $userName'
          : 'Failed to approve payment. Please try again.'),
      backgroundColor: ok ? Colors.green : AppTheme.kumkumRed,
    ));
  }

  void _showRejectPaymentDialog(
      Map<String, dynamic> request, AdminService adminService) {
    final requestId = _asText(request['id']);
    final userName  = _asText(request['user_name'], fallback: 'this user');
    
    // 🔥 CRITICAL: Controller OUTSIDE StatefulBuilder - created ONCE
    final reasonController = TextEditingController();
    bool isDisposed = false;
    
    void safeDispose() {
      if (!isDisposed) {
        reasonController.dispose();
        isDisposed = true;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cancel, color: Colors.red),
          SizedBox(width: 8),
          Text('Reject Payment'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Reject payment request from $userName?',
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 16),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              hintText: 'Reason for rejection (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              safeDispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final String reason = reasonController.text.trim();
              safeDispose();
              Navigator.pop(ctx);
              
              if (requestId.isEmpty) return;
              final ok = await adminService.rejectPaymentRequest(requestId, reason);
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? '✅ Payment request rejected'
                    : '❌ Failed to reject'),
                backgroundColor: ok ? Colors.orange : AppTheme.kumkumRed,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    ).then((_) => safeDispose()); // Safety net disposal
  }

  // ── SYSTEM SETTINGS DIALOG ─────────────────────────────────────────────────
  void _showSystemSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _SystemSettingsDialog(
        onLogout: () {
          Navigator.pop(ctx);
          _adminLogout(context);
        },
      ),
    );
  }

  // 🔥 NEW: Apply advanced filters to user list
  List<Map<String, dynamic>> _applyAdvancedFilters(
      List<Map<String, dynamic>> users) {
    debugPrint('🔍 Applying advanced filter: $_advancedFilter');
    final filtered = users.where((user) {
      // Education filter
      if (_advancedFilter.educationLevel != null) {
        final userEdu = (user['education'] ?? user['highest_education'] ?? '')
            .toString()
            .toLowerCase();
        if (!userEdu.contains(_advancedFilter.educationLevel!.toLowerCase())) {
          return false;
        }
      }

      // Occupation filter
      if (_advancedFilter.occupation != null) {
        final userJob = (user['occupation'] ?? '').toString().toLowerCase();
        if (!userJob.contains(_advancedFilter.occupation!.toLowerCase())) {
          return false;
        }
      }

      // Salary filter
      if (_advancedFilter.minSalary != null || _advancedFilter.maxSalary != null) {
        final userSalary = _asNum(user['annual_income'] ?? user['salary'], fallback: 0);
        if (_advancedFilter.minSalary != null &&
            userSalary < _advancedFilter.minSalary!) {
          return false;
        }
        if (_advancedFilter.maxSalary != null &&
            userSalary > _advancedFilter.maxSalary!) {
          return false;
        }
      }

      // Diet filter
      if (_advancedFilter.diet != null) {
        final userDiet = (user['diet'] ?? '').toString().toLowerCase();
        if (userDiet != _advancedFilter.diet!.toLowerCase()) {
          return false;
        }
      }

      // Marital status filter
      if (_advancedFilter.maritalStatus != null) {
        final userStatus = (user['marital_status'] ?? '').toString().toLowerCase();
        if (userStatus != _advancedFilter.maritalStatus!.toLowerCase()) {
          return false;
        }
      }

      // Religion filter
      if (_advancedFilter.religion != null) {
        final userReligion = (user['religion'] ?? '').toString().toLowerCase();
        if (userReligion != _advancedFilter.religion!.toLowerCase()) {
          return false;
        }
      }

      // Caste filter
      if (_advancedFilter.caste != null) {
        final userCaste = (user['caste'] ?? '').toString().toLowerCase();
        if (!userCaste.contains(_advancedFilter.caste!.toLowerCase())) {
          return false;
        }
      }

      // Mother tongue filter
      if (_advancedFilter.motherTongue != null) {
        final userLang = (user['mother_tongue'] ?? '').toString().toLowerCase();
        if (!userLang.contains(_advancedFilter.motherTongue!.toLowerCase())) {
          return false;
        }
      }

      // Verified only filter
      if (_advancedFilter.verifiedOnly == true) {
        if (user['is_verified'] != true && user['document_verified'] != true) {
          return false;
        }
      }

      // Premium only filter
      if (_advancedFilter.premiumOnly == true) {
        final tier = (user['membership_tier'] ?? '').toString().toLowerCase();
        if (tier != 'platinum' && tier != 'premium' && tier != 'gold') {
          return false;
        }
      }

      // With photo filter
      if (_advancedFilter.withPhoto == true) {
        final hasPhoto = user['profile_picture'] != null ||
            user['photo_url'] != null ||
            user['photos'] != null;
        if (!hasPhoto) return false;
      }

      // With horoscope filter
      if (_advancedFilter.withHoroscope == true) {
        final hasHoroscope = user['birth_chart'] != null ||
            user['nakshatra'] != null ||
            user['rasi'] != null;
        if (!hasHoroscope) return false;
      }

      // Last active filter
      if (_advancedFilter.lastActive != null) {
        final lastDate = _parseAnyDate(user['last_active']);
        if (lastDate == null) return false;
        try {
          final now = DateTime.now();
          final diff = now.difference(lastDate);

          switch (_advancedFilter.lastActive) {
            case '24h':
              if (diff.inHours > 24) return false;
              break;
            case '7d':
              if (diff.inDays > 7) return false;
              break;
            case '30d':
              if (diff.inDays > 30) return false;
              break;
          }
        } catch (_) {
          return false;
        }
      }

      // Joined date filter
      if (_advancedFilter.joinedDate != null) {
        final created = _parseAnyDate(user['created_at']);
        if (created == null) return false;
        try {
          final now = DateTime.now();
          final diff = now.difference(created);

          switch (_advancedFilter.joinedDate) {
            case 'today':
              if (diff.inDays > 0) return false;
              break;
            case 'week':
              if (diff.inDays > 7) return false;
              break;
            case 'month':
              if (diff.inDays > 30) return false;
              break;
          }
        } catch (_) {
          return false;
        }
      }

      return true;
    }).toList();
    debugPrint('✅ Filter result: ${filtered.length} of ${users.length} users matched');
    return filtered;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full User Details Dialog — shows every profile field admin needs to see
// ─────────────────────────────────────────────────────────────────────────────
class _UserDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> user;
  const _UserDetailsDialog({required this.user});

  String _profileIdLine() {
    final id = SafeDataExtractor.getProfileId(user);
    return id.isEmpty ? '—' : id;
  }

  String _s(String key, [String fallback = '—']) {
    final v = user[key];
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _list(String key) {
    final v = user[key];
    if (v == null) return '—';
    if (v is List) return v.join(', ');
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  String _bool(String key) {
    final v = user[key];
    if (v == null) return '—';
    return (v == true || v == 'true') ? 'Yes' : 'No';
  }

  String _date(String key) {
    final v = _s(key);
    if (v == '—') return '—';
    return v.split('T').first;
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _s('first_name');
    final lastName  = _s('last_name');
    final fullName  = [firstName, lastName].where((s) => s != '—').join(' ');
    final isVerified = user['is_verified'] == true;

    final mq = MediaQuery.sizeOf(context);
    // Cap scroll region so short profiles keep a compact dialog; long profiles scroll.
    // LimitedBox applies when the Column gives unbounded max height to this child.
    final maxScrollHeight = mq.height * 0.72;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: min(560.0, mq.width - 32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
          decoration: BoxDecoration(
            color: AppTheme.kumkumRed.withAlpha(12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: AppTheme.kumkumRed.withAlpha(30),
              radius: 24,
              child: Text(
                fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: AppTheme.kumkumRed),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fullName.isNotEmpty ? fullName : 'User Profile',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Row(children: [
                Text(_profileIdLine(), style: const TextStyle(
                    fontSize: 12, color: AppTheme.primaryGold,
                    fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isVerified ? Colors.green.withAlpha(20) : Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isVerified ? Colors.green : Colors.orange),
                  ),
                  child: Text(isVerified ? '✓ Verified' : 'Pending',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: isVerified ? Colors.green : Colors.orange)),
                ),
              ]),
            ])),
            IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
        ),

        // ── Scrollable content ──
        LimitedBox(
          maxHeight: maxScrollHeight,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              _section(context, '🔐 Account', [
                _row('Mobile',      _s('mobile_number')),
                _row('Alt Mobile',  _s('alternative_mobile_number')),
                _row('Membership',  _s('membership_tier').toUpperCase()),
                _row('Mem. Expires', _date('membership_expires_at')),
                _row('Status',      _s('membership_status')),
                _row('Joined',      _date('created_at')),
                _row('Last Login',  _date('last_login_at')),
                _row('Profile Complete', _bool('is_profile_complete')),
                _row('Completion %', '${user['profile_completion_percentage'] ?? '—'}%'),
                _row('Created By',  _s('profile_created_by')),
                _row('Creator Relation', _s('profile_created_by_relation')),
              ]),

              _section(context, '👤 Basic Info', [
                _row('Gender',          _s('gender')),
                _row('Date of Birth',   _date('date_of_birth')),
                _row('Height',          _s('height')),
                _row('Weight',          _s('weight')),
                _row('Complexion',      _s('complexion')),
                _row('Body Type',       _s('body_type')),
                _row('Physical Status', _s('physical_status')),
                _row('Marital Status',  _s('marital_status')),
              ]),

              _section(context, '🌟 Birth & Astrology', [
                _row('Time of Birth',       _s('time_of_birth')),
                _row('Place of Birth',      _s('place_of_birth')),
                _row('Birth State',         _s('place_of_birth_state')),
                _row('Birth Country',       _s('place_of_birth_country')),
                _row('Nakshatra',           _s('nakshatra')),
                _row('Pada',               _s('pada')),
                _row('Rasi',               _s('rasi')),
                _row('Manglik',            _s('manglik_status')),
                _row('Has Horoscope',      _bool('has_horoscope')),
              ]),

              _section(context, '🕉️ Religious', [
                _row('Sect',     _s('sect')),
                _row('Sub-Sect', _s('sub_sect')),
                _row('Gothram', _s('gothram')),
              ]),

              _section(context, '🎓 Education & Career', [
                _row('Education',        _s('education')),
                _row('Specialization',   _s('specialization')),
                _row('Edu. Status',      _s('education_status')),
                _row('University',       _s('university_name')),
                _row('Edu. City',        _s('education_location_city')),
                _row('Edu. State',       _s('education_location_state')),
                _row('Edu. Country',     _s('education_location_country')),
                _row('Add. Qualif.',     _s('additional_qualifications')),
                _row('Qualif. Notes',    _s('qualification_notes')),
                _row('Occupation',       _s('occupation')),
                _row('Employment Type',  _s('employment_type')),
                _row('Company',          _s('company_name')),
                _row('Income Range',     _s('income_range')),
              ]),

              _section(context, '👨‍👩‍👧 Family', [
                _row('Father Name',       _s('father_name')),
                _row('Father Occupation', _s('father_occupation')),
                _row('Father Note',       _s('father_note')),
                _row('Mother Name',       _s('mother_name')),
                _row('Mother Occupation', _s('mother_occupation')),
                _row('Mother Note',       _s('mother_note')),
                _row('Mother Surname',    _s('mother_surname')),
                _row('Brothers',          '${user['brothers'] ?? '—'} (${user['brothers_married'] ?? 0} married)'),
                _row('Sisters',           '${user['sisters'] ?? '—'} (${user['sisters_married'] ?? 0} married)'),
                _row('Family Type',       _s('family_type')),
                _row('Family Status',     _s('family_status')),
                _row('Family Values',     _s('family_values')),
                _row('About Family',      _s('about_family')),
                _row('Family Origin',     _s('family_origin_city') == '—'
                    ? _s('family_origin_state')
                    : '${_s('family_origin_city')}, ${_s('family_origin_state')}'),
                _row('Known Ref. 1',      _s('known_reference')),
                _row('Known Ref. 2',      _s('known_reference_2')),
              ]),

              _section(context, '📍 Location', [
                _row('City',              _s('city')),
                _row('State',             _s('state')),
                _row('Country',           _s('country')),
                _row('Native Place City', _s('native_place_city')),
                _row('Native State',      _s('native_place_state')),
                _row('Native Country',    _s('native_place_country')),
                _row('Citizenship',       _s('citizenship')),
                _row('Settled Abroad',    _s('settled_abroad')),
                _row('Willing Relocate',  _bool('willing_to_relocate')),
                _row('Relocate Pref.',    _s('relocate_preference')),
              ]),

              _section(context, '🌿 Lifestyle', [
                _row('Food Habit',    _s('food_habit')),
                _row('Smoking',       _s('smoking_habit')),
                _row('Drinking',      _s('drinking_habit')),
                _row('Languages',     _list('languages')),
                _row('Hobbies',       _list('hobbies')),
                _row('Interests',     _list('interests')),
                _row('About Me',      _s('about_me')),
              ]),

              _section(context, '💑 Partner Preferences', [
                _row('Age Range',       '${user['partner_age_min'] ?? '—'} – ${user['partner_age_max'] ?? '—'}'),
                _row('Height Range',    '${_s('partner_height_min')} – ${_s('partner_height_max')}'),
                _row('Education',       _list('partner_education')),
                _row('Occupation',      _list('partner_occupation')),
                _row('Income Min',      _s('partner_income_min')),
                _row('Marital Status',  _list('partner_marital_status')),
                _row('Locations',       _list('partner_locations')),
                _row('Manglik Pref.',   _bool('partner_manglik_preference')),
                _row('Expectations',    _s('partner_expectations')),
                _row('Preferences',     _s('partner_preferences')),
              ]),
            ]),
          ),
        ),

        // ── Footer ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    // Filter out rows where value is '—' to keep sections clean
    final meaningful = rows.where((w) {
      if (w is _DetailRow) return w.value != '—';
      return true;
    }).toList();
    if (meaningful.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Row(children: [
          Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: AppTheme.primaryOrange)),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ]),
      ),
      ...meaningful,
    ]);
  }

  Widget _row(String label, String value) => _DetailRow(label: label, value: value);
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(
              fontSize: 12, color: AppTheme.textMedium,
              fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// System Settings Dialog — persists to Firestore admin_settings document
// ─────────────────────────────────────────────────────────────────────────────
class _SystemSettingsDialog extends StatefulWidget {
  final VoidCallback onLogout;
  const _SystemSettingsDialog({required this.onLogout});

  @override
  State<_SystemSettingsDialog> createState() => _SystemSettingsDialogState();
}

class _SystemSettingsDialogState extends State<_SystemSettingsDialog> {
  bool _maintenanceMode = false;
  bool _newRegistrations = true;
  bool _emailNotifications = true;
  int _sessionTimeout = 5;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('global')
          .get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _maintenanceMode =
              SafeDataExtractor.coerceBool(d['maintenance_mode'], false);
          _newRegistrations =
              SafeDataExtractor.coerceBool(d['new_registrations'], true);
          _emailNotifications =
              SafeDataExtractor.coerceBool(d['email_notifications'], true);
          _sessionTimeout = SafeDataExtractor.coerceInt(
            d['session_timeout_min'],
            5,
            min: 1,
            max: 30,
          );
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('admin_session_timeout_min', _sessionTimeout);

      final identityService = IdentityService();
      final userDocId = await identityService.getUserId();
      if (userDocId.isNotEmpty) {
        await AdminSessionBootstrap.ensureAccess(userDocId: userDocId);
      }

      await FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('global')
          .set({
        'maintenance_mode':     _maintenanceMode,
        'new_registrations':    _newRegistrations,
        'email_notifications':  _emailNotifications,
        'session_timeout_min':  _sessionTimeout,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved'),
            backgroundColor: AppTheme.sacredGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'),
              backgroundColor: AppTheme.kumkumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.settings, color: AppTheme.primaryOrange, size: 22),
        ),
        const SizedBox(width: 12),
        const Text('System Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Divider(height: 24),

          // Maintenance mode
          _settingRow(
            icon: Icons.construction_rounded,
            iconColor: Colors.orange,
            title: 'Maintenance Mode',
            subtitle: 'Prevent user access during updates',
            value: _maintenanceMode,
            onChanged: (v) => setState(() => _maintenanceMode = v),
          ),

          // New registrations
          _settingRow(
            icon: Icons.person_add_rounded,
            iconColor: AppTheme.sacredGreen,
            title: 'New Registrations',
            subtitle: 'Allow new users to register',
            value: _newRegistrations,
            onChanged: (v) => setState(() => _newRegistrations = v),
          ),

          // Email notifications
          _settingRow(
            icon: Icons.email_rounded,
            iconColor: Colors.blue,
            title: 'Email Notifications',
            subtitle: 'Send system emails to users',
            value: _emailNotifications,
            onChanged: (v) => setState(() => _emailNotifications = v),
          ),

          const Divider(height: 24),

          // Session timeout
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.kumkumRed.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.timer_rounded,
                  color: AppTheme.kumkumRed, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Session Timeout',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('$_sessionTimeout minutes of inactivity',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMedium)),
              ]),
            ),
          ]),
          Slider(
            value: _sessionTimeout.toDouble(),
            min: 1, max: 30, divisions: 29,
            activeColor: AppTheme.primaryOrange,
            label: '$_sessionTimeout min',
            onChanged: (v) => setState(() => _sessionTimeout = v.round()),
          ),

          const Divider(height: 8),

          // App info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              _infoRow('App Version', '1.0.0'),
              _infoRow('Build', 'Release'),
              _infoRow('Database', 'Firebase Firestore'),
              _infoRow('Auth', 'Firebase Anonymous'),
            ]),
          ),
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Settings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textMedium,
              side: const BorderSide(color: AppTheme.surfaceLight2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _settingRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textMedium)),
        ])),
        // Labeled switch: OFF [switch] ON (like user screens)
        _buildLabeledSwitch(context, value: value, onChanged: onChanged),
      ]),
    );
  }

  /// OFF / ON labels + adaptive switch (matches user screens design)
  Widget _buildLabeledSwitch(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = AppTheme.primaryOrange;
    final muted = AC.textMuted(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'OFF',
          style: TextStyle(
            fontSize: 12,
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
            activeThumbColor: Colors.white,
            activeTrackColor: accent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: muted.withAlpha(120),
          ),
        ),
        Text(
          'ON',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: value ? accent : muted,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 100,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textMedium))),
      Text(value,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}
