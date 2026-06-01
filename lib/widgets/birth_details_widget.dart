import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../services/birth_details_service.dart';
import '../services/premium_entitlement_service.dart';
import '../services/access_request_broadcast.dart';
import 'request_action_bar.dart';
import '../core/request_ui_contract.dart';
import '../core/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BirthDetailsWidget
//
// Rules:
//  • Birth details are ALWAYS blurred until access is granted.
//  • FREE users  → see a "Premium Required" lock — cannot request.
//  • PREMIUM users (requester):
//      - No request yet   → "Request Birth Details" button
//      - Pending          → "Request Sent — Awaiting Owner Approval" badge
//      - Granted          → actual birth details shown in clear text  ✓
//      - Denied           → "Request Declined" with option to re-request
//  • Profile OWNER receives a notification with Grant / Deny buttons.
//    When they respond, the requester's widget updates on next open.
//  • NO admin involvement at any point.
// ─────────────────────────────────────────────────────────────────────────────
class BirthDetailsWidget extends StatefulWidget {
  final UserProfile profile;
  final User? currentUser;
  /// The Firestore document ID of the profile owner (User.id, not profileId)
  final String ownerUserId;
  /// The display profile ID of the owner (e.g. MG28088) — used in notifications
  final String ownerProfileId;

  const BirthDetailsWidget({
    super.key,
    required this.profile,
    required this.currentUser,
    required this.ownerUserId,
    required this.ownerProfileId,
  });

  @override
  State<BirthDetailsWidget> createState() => _BirthDetailsWidgetState();
}

class _BirthDetailsWidgetState extends State<BirthDetailsWidget> {
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
  /// Owner row may be keyed by Firestore doc id or (legacy) Auth UID on some paths.
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

  /// Profile screen can render before [User.id] is hydrated; prefs holds canonical doc id.
  Future<String> _requesterDocIdForCallables() async {
    final fromUser = _requesterIdOrEmpty();
    if (fromUser.isNotEmpty) return fromUser;
    final fromAuth = widget.currentUser?.firebaseAuthUid.trim() ?? '';
    if (fromAuth.isNotEmpty) return fromAuth;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('current_user_id') ?? '').trim();
  }

  void _debugRequestIdentity(String requesterId) {
    final ownerId = widget.ownerUserId.trim();
    final docId = requesterId.isNotEmpty && ownerId.isNotEmpty
        ? '${requesterId}_$ownerId'
        : '';
    debugPrint(
        '🧬 BirthDetailsWidget IDs => requesterId=$requesterId ownerId=$ownerId docId=$docId');
  }

  /// Collapses withdraw + [AccessRequestBroadcast] into one re-subscribe (fewer races / less jank).
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
  void didUpdateWidget(covariant BirthDetailsWidget oldWidget) {
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
    if (_isOwnProfile) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final ownerDocId =
        await BirthDetailsService().resolveUserDocId(widget.ownerUserId.trim());
    if (ownerDocId.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    final requesterRaw = await _requesterDocIdForCallables();
    final requesterId = await BirthDetailsService().resolveUserDocId(requesterRaw);
    if (requesterId.isEmpty) return;
    _debugRequestIdentity(requesterId);

    // Guard against re-subscribing to the same stream (prevents flickering)
    if (_lastRequesterId == requesterId && _lastOwnerId == ownerDocId && _statusSub != null) {
      return;
    }

    _lastRequesterId = requesterId;
    _lastOwnerId = ownerDocId;

    _statusSub?.cancel();
    _statusSub = BirthDetailsService()
        .watchAccessStatus(requesterId: requesterId, ownerId: ownerDocId)
        .listen((liveStatus) {
      if (!mounted) return;
      setState(() {
        _status = liveStatus;
        _loading = false;
      });
    }, onError: (e) {
      debugPrint('❌ BirthDetailsWidget status stream failed: $e');
      if (!mounted) return;
      // Don't keep loading forever on error - set to null so user can retry
      setState(() {
        _status = null;
        _loading = false;
      });
    });
  }

  Future<void> _sendRequest() async {
    if (_sending) return;
    final serverPremium = await PremiumEntitlementService.isEntitled(
      feature: PremiumEntitlementService.featureBirthDetails,
      localMembershipHint: widget.currentUser?.membership,
    );
    if (!serverPremium) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Birth details requests are available for Premium members only.'),
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
      final requesterId = await BirthDetailsService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      debugPrint('🚀 BirthDetailsWidget SEND REQUEST pressed');
      _debugRequestIdentity(requesterId);
      final ownerDocId =
          await BirthDetailsService().resolveUserDocId(widget.ownerUserId);
      if (ownerDocId.isEmpty) {
        throw Exception('Missing owner profileDocId');
      }
      final forceResend = _shouldForceResend;
      await BirthDetailsService().sendRequest(
        requesterId:         requesterId,
        requesterProfileId:  requester.profileId,
        requesterName:       requester.profile?.fullName ?? 'Unknown',
        ownerId:             ownerDocId,
        ownerProfileId:      widget.ownerProfileId,
        ownerName:           widget.profile.fullName,
        forceResend:         forceResend,
      );
      if (!mounted) return;
      setState(() {
        _status = 'pending';
        _sending = false;
      });
      if (forceResend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Birth details request sent again'),
            backgroundColor: AppTheme.sacredGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${RequestUiContract.sendRequestFailed}: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ));
      }
    }
  }

  Future<void> _withdrawRequest() async {
    if (_withdrawing) return;
    final requester = widget.currentUser;
    if (requester == null) return;
    final ownerId =
        await BirthDetailsService().resolveUserDocId(widget.ownerUserId.trim());
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
      final requesterId = await BirthDetailsService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      _debugRequestIdentity(requesterId);
      final requestDocId = '${requesterId}_$ownerId';
      await _statusSub?.cancel();
      await BirthDetailsService().withdrawRequest(
        requesterId: requesterId,
        ownerId: ownerId,
        requestId: requestDocId,
      );
      if (!mounted) return;
      // Callable already confirmed delete — avoid extra get() (lag + occasional stale read).
      setState(() {
        _status = null;
        _withdrawing = false;
        _loading = false;
      });
      _scheduleAttachStatusStream();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Birth details request withdrawn'),
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
      final requesterId = await BirthDetailsService().resolveUserDocId(requesterRaw);
      if (requesterId.isEmpty) {
        throw Exception('Missing requester profileDocId');
      }
      _debugRequestIdentity(requesterId);
      final ownerDocId =
          await BirthDetailsService().resolveUserDocId(widget.ownerUserId);
      if (ownerDocId.isEmpty) {
        throw Exception('Missing owner profileDocId');
      }
      await BirthDetailsService().sendReminder(
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

    // If this is the user's own profile, show their own details in clear text
    if (_isOwnProfile) return _buildOwnDetails(isDark);

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

          // ── Birth detail rows ─────────────────────────────────────────────
          // 🔥 CRITICAL FIX: Must be both granted AND premium to see actual data
          // When premium expires, previously granted access is immediately locked
          if (_status == 'granted' && _isPremium) ...[
            // Actual data — shown only after owner grants access AND user is premium
            _detailRow(context, 'Date of Birth',
                _formatDate(widget.profile.dateOfBirth), isDark),
            if (widget.profile.timeOfBirth != null)
              _detailRow(context, 'Time of Birth',
                  widget.profile.timeOfBirth!, isDark),
            if (widget.profile.placeOfBirth != null)
              _detailRow(context, 'Place of Birth',
                  widget.profile.placeOfBirth!, isDark),
            if (widget.profile.placeOfBirthState != null)
              _detailRow(context, 'State',
                  widget.profile.placeOfBirthState!, isDark),
          ] else ...[
            // Blurred placeholders for everyone else
            _blurRow(context, 'Date of Birth',   '••  /  ••  /  ••••', isDark),
            if (widget.profile.timeOfBirth != null)
              _blurRow(context, 'Time of Birth',  '••:•• ••', isDark),
            if (widget.profile.placeOfBirth != null)
              _blurRow(context, 'Place of Birth', '• • • • • • • •', isDark),
          ],

          const SizedBox(height: 12),

          // ── Action area ───────────────────────────────────────────────────
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
              ? 'Birth Details (Access Granted)'
              : _status == 'revoked'
                  ? 'Birth Details (Access Revoked)'
                  : 'Birth Details (Private)',
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
              _sending ? 'Sending Request…' : 'Request Birth Details',
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
            collapseBreakpoint: 0,
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

  // Access was revoked (treated as locked, requester can't see data).
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
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryOrange),
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
                Text('Upgrade to Premium to request access to birth details',
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

  // Own profile — see own details
  Widget _buildOwnDetails(bool isDark) {
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
              Icon(Icons.person_outline,
                  size: 15, color: AppTheme.sacredGreen),
              SizedBox(width: 6),
              Text('Your Birth Details',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 10),
          _detailRow(context, 'Date of Birth',
              _formatDate(widget.profile.dateOfBirth), isDark),
          if (widget.profile.timeOfBirth != null)
            _detailRow(
                context, 'Time of Birth', widget.profile.timeOfBirth!, isDark),
          if (widget.profile.placeOfBirth != null)
            _detailRow(context, 'Place of Birth',
                widget.profile.placeOfBirth!, isDark),
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
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.textDarkOnDark : AppTheme.textDark)),
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

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')} / '
        '${d.month.toString().padLeft(2, '0')} / ${d.year}';
  }
}
