import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../services/community_reference_service.dart';
import '../services/premium_entitlement_service.dart';
import '../services/access_request_broadcast.dart';
import 'request_action_bar.dart';
import '../core/request_ui_contract.dart';
import '../core/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CommunityReferencesWidget
//
// Mirrors BirthDetailsWidget behaviour exactly:
//
//  • References are ALWAYS blurred (•••) until the owner grants access.
//  • FREE users   → blurred rows + "Premium Members Only" lock message.
//                   Cannot send a request.
//  • PREMIUM users (requester):
//      - No request yet → "Request Community References" button
//      - Pending        → "Request Sent — Awaiting Owner Approval" badge
//      - Granted        → actual references shown in clear text  ✓
//      - Denied         → "Request Declined" + option to re-request
//  • Whether or not the profile has references set, the same premium gate
//    is shown to free users (no early "not available" shortcut that bypasses
//    the gate).
//  • Profile OWNER receives a notification with Grant / Deny buttons.
//  • NO admin involvement at any point.
// ─────────────────────────────────────────────────────────────────────────────
class CommunityReferencesWidget extends StatefulWidget {
  final UserProfile profile;
  final User? currentUser;
  /// The Firestore document ID of the profile owner (User.id, not profileId)
  final String ownerUserId;
  /// The display profile ID of the owner (e.g. MG28088) — used in notifications
  final String ownerProfileId;

  const CommunityReferencesWidget({
    super.key,
    required this.profile,
    required this.currentUser,
    required this.ownerUserId,
    required this.ownerProfileId,
  });

  @override
  State<CommunityReferencesWidget> createState() => _CommunityReferencesWidgetState();
}

class _CommunityReferencesWidgetState extends State<CommunityReferencesWidget> {
  String? _status;   // null | 'pending' | 'granted' | 'denied' | 'revoked'

  /// Resend after owner declined or revoked access (backend requires forceResend).
  bool get _shouldForceResend {
    final s = (_status ?? '').toLowerCase();
    return s == 'denied' ||
        s == 'revoked' ||
        s == 'rejected' ||
        s == 'declined';
  }

  bool _loading = true;
  bool _sending = false;
  bool _withdrawing = false;
  bool _reminding = false;
  StreamSubscription<String?>? _statusSub;
  Timer? _attachDebounce;
  String? _lastRequesterId;
  String? _lastOwnerId;

  bool get _isPremium => widget.currentUser?.membership.isPremium ?? false;
  bool get _isOwnProfile {
    final v = widget.currentUser;
    if (v == null) return false;
    final owner = widget.ownerUserId;
    if (owner.isEmpty) return false;
    if (v.id == owner) return true;
    final au = v.firebaseAuthUid;
    return au.isNotEmpty && au == owner;
  }

  String _requesterIdOrEmpty() => widget.currentUser?.id.trim() ?? '';

  Future<String> _requesterDocIdForCallables() async {
    final fromUser = _requesterIdOrEmpty();
    if (fromUser.isNotEmpty) return fromUser;
    final fromAuth = widget.currentUser?.firebaseAuthUid.trim() ?? '';
    if (fromAuth.isNotEmpty) return fromAuth;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('current_user_id') ?? '').trim();
  }

  static final Set<String> _loggedRequestDocIds = <String>{};

  void _debugRequestIdentity(String requesterId) {
    if (!kDebugMode) return;
    final ownerId = widget.ownerUserId.trim();
    final docId = requesterId.isNotEmpty && ownerId.isNotEmpty
        ? '${requesterId}_$ownerId'
        : '';
    if (docId.isEmpty || !_loggedRequestDocIds.add(docId)) return;
    debugPrint(
      '🧬 CommunityReferencesWidget IDs => requesterId=$requesterId ownerId=$ownerId docId=$docId',
    );
  }
  
  bool get _hasReferences => 
      (widget.profile.knownReference != null && widget.profile.knownReference!.isNotEmpty) ||
      (widget.profile.knownReference2 != null && widget.profile.knownReference2!.isNotEmpty);

  void _scheduleAttachStatusStream() {
    _attachDebounce?.cancel();
    _attachDebounce = Timer(const Duration(milliseconds: 100), () {
      _attachDebounce = null;
      if (mounted) _attachStatusStreamIfReady();
    });
  }

  void _onAccessRequestPulse() {
    if (!mounted) return;
    _scheduleAttachStatusStream();
  }

  @override
  void initState() {
    super.initState();
    AccessRequestBroadcast.tick.addListener(_onAccessRequestPulse);
    _attachStatusStreamIfReady();
  }

  @override
  void dispose() {
    AccessRequestBroadcast.tick.removeListener(_onAccessRequestPulse);
    _attachDebounce?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleAttachStatusStream();
  }

  @override
  void didUpdateWidget(covariant CommunityReferencesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = oldWidget.currentUser?.id != widget.currentUser?.id;
    final ownerChanged = oldWidget.ownerUserId != widget.ownerUserId;
    if (userChanged || ownerChanged) {
      _statusSub?.cancel();
      setState(() {
        _loading = true;
        _status = null;
      });
      _attachStatusStreamIfReady();
    }
  }

  Future<void> _attachStatusStreamIfReady() async {
    // Wait until requester profile doc id is available.
    if (widget.currentUser == null) {
      return;
    }
    // Owner sees their own references — no access-request logic needed.
    if (_isOwnProfile) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    // Guard against missing owner ID — would create a permanently-loading
    // spinner if ownerUserId is empty.
    final ownerDocId = await CommunityReferenceService()
        .resolveUserDocId(widget.ownerUserId.trim());
    if (ownerDocId.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    final requesterRaw = await _requesterDocIdForCallables();
    final requesterId =
        await CommunityReferenceService().resolveUserDocId(requesterRaw);
    if (requesterId.isEmpty) return;
    _debugRequestIdentity(requesterId);

    // Guard against re-subscribing to the same stream (prevents flickering).
    if (_lastRequesterId == requesterId &&
        _lastOwnerId == ownerDocId &&
        _statusSub != null) {
      return;
    }

    _lastRequesterId = requesterId;
    _lastOwnerId = ownerDocId;

    _statusSub?.cancel();
    _statusSub = CommunityReferenceService()
        .watchAccessStatus(requesterId: requesterId, ownerId: ownerDocId)
        .listen((liveStatus) {
      if (!mounted) return;
      setState(() {
        _status = liveStatus;
        _loading = false;
      });
    }, onError: (e) {
      debugPrint('❌ CommunityReferencesWidget status stream failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  Future<void> _sendRequest() async {
    if (_sending) return;
    final serverPremium = await PremiumEntitlementService.isEntitled(
      feature: PremiumEntitlementService.featureCommunityReference,
      localMembershipHint: widget.currentUser?.membership,
    );
    if (!serverPremium) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community reference requests are available for Premium members only.'),
            backgroundColor: AppTheme.primaryOrange,
          ),
        );
        Navigator.pushNamed(context, Routes.premiumUpgrade);
      }
      return;
    }
    final requester = widget.currentUser;
    if (requester == null) return;

    setState(() => _sending = true);
    try {
      final requesterRaw = await _requesterDocIdForCallables();
      final requesterId =
          await CommunityReferenceService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      final ownerDocId =
          await CommunityReferenceService().resolveUserDocId(widget.ownerUserId.trim());
      if (ownerDocId.isEmpty) {
        throw Exception('Missing owner profileDocId');
      }
      debugPrint('🚀 CommunityReferencesWidget SEND REQUEST pressed');
      _debugRequestIdentity(requesterId);
      final forceResend = _shouldForceResend;
      await CommunityReferenceService().sendRequest(
        requesterId: requesterId,
        requesterProfileId: requester.profileId,
        requesterName: requester.profile?.fullName ?? 'Unknown',
        ownerId: ownerDocId,
        ownerProfileId: widget.ownerProfileId,
        ownerName: widget.profile.fullName,
        forceResend: forceResend,
      );
      if (!mounted) return;
      setState(() {
        _status = 'pending';
        _sending = false;
      });
      if (forceResend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community reference request sent again'),
            backgroundColor: AppTheme.sacredGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Community request failed: $e');
      if (mounted) {
        setState(() => _sending = false);
      }
      // Show error in next frame to avoid deactivated widget issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          final scaffold = ScaffoldMessenger.of(context);
          scaffold.showSnackBar(SnackBar(
            content: Text('${RequestUiContract.sendRequestFailed}: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ));
        }
      });
    }
  }

  Future<void> _withdrawRequest() async {
    if (_withdrawing) return;
    final requester = widget.currentUser;
    if (requester == null) return;
    final ownerId =
        await CommunityReferenceService().resolveUserDocId(widget.ownerUserId.trim());
    if (!mounted) return;
    if (ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot withdraw: missing profile owner id'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    setState(() => _withdrawing = true);
    try {
      final requesterRaw = await _requesterDocIdForCallables();
      final requesterId =
          await CommunityReferenceService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      _debugRequestIdentity(requesterId);
      final requestDocId = '${requesterId}_$ownerId';
      await _statusSub?.cancel();
      await CommunityReferenceService().withdrawRequest(
        requesterId: requesterId,
        ownerId: ownerId,
        requestId: requestDocId,
      );
      if (!mounted) return;
      setState(() {
        _status = null;
        _withdrawing = false;
        _loading = false;
      });
      _scheduleAttachStatusStream();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Community reference request withdrawn'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _withdrawing = false);
      _scheduleAttachStatusStream();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${RequestUiContract.withdrawFailed}: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Future<void> _sendReminder() async {
    if (_reminding) return;
    final requester = widget.currentUser;
    if (requester == null) return;

    setState(() => _reminding = true);
    try {
      final requesterRaw = await _requesterDocIdForCallables();
      final requesterId =
          await CommunityReferenceService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      final ownerDocId =
          await CommunityReferenceService().resolveUserDocId(widget.ownerUserId.trim());
      if (ownerDocId.isEmpty) {
        throw Exception('Missing owner profileDocId');
      }
      _debugRequestIdentity(requesterId);
      await CommunityReferenceService().sendReminder(
        requesterId: requesterId,
        requesterProfileId: requester.profileId,
        requesterName: requester.profile?.fullName ?? 'Unknown',
        ownerId: ownerDocId,
        ownerProfileId: widget.ownerProfileId,
        ownerName: widget.profile.fullName,
      );
      if (!mounted) return;
      setState(() => _reminding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(RequestUiContract.reminderSent),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _reminding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${RequestUiContract.reminderFailed}: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If this is the user's own profile, show their own references in clear text
    if (_isOwnProfile) return _buildOwnReferences(isDark);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDark),
          const SizedBox(height: 10),

          // ── Reference rows ─────────────────────────────────────────────
          // 🔥 CRITICAL FIX: Must be both granted AND premium to see actual data
          // When premium expires, previously granted access is immediately locked
          if (_status == 'granted' && _hasReferences && _isPremium) ...[
            // Actual data — shown only after owner grants access AND user is premium
            if (widget.profile.knownReference != null && widget.profile.knownReference!.isNotEmpty)
              _detailRow(context, 'Reference Person 1', widget.profile.knownReference!, isDark),
            if (widget.profile.knownReference2 != null && widget.profile.knownReference2!.isNotEmpty)
              _detailRow(context, 'Reference Person 2', widget.profile.knownReference2!, isDark),
          ] else if (!_hasReferences) ...[
            // No references — show placeholder blurred rows
            _blurRow(context, 'Reference Person 1', '• • • • • • • •', isDark),
            _blurRow(context, 'Reference Person 2', '• • • • • • • •', isDark),
          ] else ...[
            // Has references but not yet granted — blurred
            _blurRow(context, 'Reference Person 1', '• • • • • • • •', isDark),
            _blurRow(context, 'Reference Person 2', '• • • • • • • •', isDark),
          ],

          const SizedBox(height: 12),

          // ── Action area ─────────────────────────────────────────────────
          if (_loading)
            const Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            _buildActionArea(isDark),
        ],
      ),
    );
  }

  // ── Header row ────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Icon(
          _status == 'granted'
              ? Icons.verified_outlined
              : Icons.lock_outline_rounded,
          size: 15,
          color: _status == 'granted'
              ? AppTheme.sacredGreen
              : AppTheme.primaryGold,
        ),
        SizedBox(width: 6),
        Text(
          _status == 'granted'
              ? 'Community References (Access Granted)'
              : _status == 'revoked'
                  ? 'Community References (Access Revoked)'
                  : 'Community References (Private)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark,
          ),
        ),
        const Spacer(),
        if (_isPremium && _status != 'granted')
          _premiumBadge(),
      ],
    );
  }

  Widget _premiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 11, color: AppTheme.primaryGold),
          const SizedBox(width: 3),
          Text('Premium',
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.primaryGold,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Action area — switches based on status + premium ─────────────────────
  Widget _buildActionArea(bool isDark) {
    if (widget.ownerUserId.trim().isEmpty) {
      return _buildUnavailableState(isDark);
    }
    // Not premium → upgrade gate
    if (!_isPremium) return _buildFreeGate(isDark);

    switch (_status) {
      case 'granted':
        return _buildGrantedBadge(isDark);
      case 'pending':
        return _buildPendingBadge(isDark);
      case 'denied':
        return _buildDeniedState(isDark);
      case 'revoked':
        return _buildRevokedState(isDark);
      default:
        // null — no request yet
        return _buildRequestButton(isDark);
    }
  }

  Widget _buildUnavailableState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.kumkumRed.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.kumkumRed.withAlpha(40)),
      ),
      child: Text(
        'Request unavailable: profile owner ID missing. Please reopen profile.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : AppTheme.kumkumRed,
        ),
      ),
    );
  }

  // No request yet — show button
  Widget _buildRequestButton(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No request yet',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AC.textSub(context),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _sendRequest,
            icon: _sending
                ? SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AC.card(context)))
                : Icon(Icons.send_outlined, size: 16),
            label: Text(
              _sending ? 'Sending Request…' : 'Request Community References',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Owner will be notified and can grant or deny access',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              color: AppTheme.textLight),
        ),
      ],
    );
  }

  // Request sent — awaiting owner response
  Widget _buildPendingBadge(bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.orange),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  RequestUiContract.pendingAwaitingApproval,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: RequestActionBar(
            first: RequestActionItem(
              label: _withdrawing ? RequestUiContract.withdrawing : RequestUiContract.withdraw,
              icon: Icons.undo,
              isLoading: _withdrawing,
              onPressed: _withdrawing || _reminding ? null : _withdrawRequest,
            ),
            second: RequestActionItem(
              label: _reminding ? RequestUiContract.sending : RequestUiContract.reminder,
              icon: Icons.notifications_active_outlined,
              isLoading: _reminding,
              color: AppTheme.primaryOrange,
              onPressed: _withdrawing || _reminding ? null : _sendReminder,
            ),
          ),
        ),
      ],
    );
  }

  // Access granted — shown alongside actual details above
  Widget _buildGrantedBadge(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.sacredGreen.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.sacredGreen.withAlpha(80)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.check_circle_outline, size: 16,
              color: AppTheme.sacredGreen),
          SizedBox(width: 8),
          Text(
            RequestUiContract.accessGrantedByOwner,
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.sacredGreen,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // Request was denied
  Widget _buildDeniedState(bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.kumkumRed.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.kumkumRed.withAlpha(60)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.cancel_outlined, size: 16, color: AppTheme.kumkumRed),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  RequestUiContract.requestDeclinedByOwner,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kumkumRed,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _sending ? null : _sendRequest,
          icon: _sending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 14),
          label: Text(
            _sending ? 'Sending…' : RequestUiContract.sendAgain,
            style: const TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryOrange),
        ),
      ],
    );
  }

  // Access was revoked (treated as locked).
  Widget _buildRevokedState(bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.kumkumRed.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.kumkumRed.withAlpha(60)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.cancel_outlined, size: 16, color: AppTheme.kumkumRed),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Access revoked by owner',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.kumkumRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _sending ? null : _sendRequest,
          icon: _sending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 14),
          label: Text(
            _sending ? 'Sending…' : RequestUiContract.sendAgain,
            style: const TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryOrange,
          ),
        ),
      ],
    );
  }

  // Free user
  Widget _buildFreeGate(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AC.surface2(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AC.border(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, size: 16,
              color: AppTheme.textMedium),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(RequestUiContract.premiumMembersOnly,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark)),
                SizedBox(height: 2),
                Text('Upgrade to Premium to request community references',
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            AppTheme.textMedium)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, Routes.premiumUpgrade),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  // Own profile — see own references
  Widget _buildOwnReferences(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.sacredGreen.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.sacredGreen.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline,
                  size: 15, color: AppTheme.sacredGreen),
              SizedBox(width: 6),
              Text('Your Community References',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.profile.knownReference != null && widget.profile.knownReference!.isNotEmpty)
            _detailRow(context, 'Reference Person 1', widget.profile.knownReference!, isDark)
          else
            _detailRow(context, 'Reference Person 1', 'Not provided', isDark),
          if (widget.profile.knownReference2 != null && widget.profile.knownReference2!.isNotEmpty)
            _detailRow(context, 'Reference Person 2', widget.profile.knownReference2!, isDark)
          else if (widget.profile.knownReference != null && widget.profile.knownReference!.isNotEmpty)
            _detailRow(context, 'Reference Person 2', 'Not provided', isDark),
        ],
      ),
    );
  }

  // ── Row helpers ───────────────────────────────────────────────────────────
  Widget _detailRow(
      BuildContext context, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.textMediumOnDark : AppTheme.textMedium)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _blurRow(
      BuildContext context, String label, String blurred, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.textMediumOnDark : AppTheme.textMedium)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AC.border(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(blurred,
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textLight,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
