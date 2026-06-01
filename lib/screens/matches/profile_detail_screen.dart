import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/soft_touch.dart';

import '../../core/app_router.dart';
import '../../features/profile/profile_repository.dart';
import '../../repositories/interest_analytics_repository.dart';
import '../../core/interest_route_guard.dart';
import '../../data/reference_data.dart';
import '../../models/user.dart';
import '../../legacy/compatibility.dart';
import '../../services/access_request_broadcast.dart';
import '../../core/backend/firestore_service.dart';
import '../../services/birth_details_service.dart';
import '../../services/block_service.dart';
import '../../services/photo_service.dart';
import '../../utils/firestore_timestamp_utils.dart';
import '../../core/request_ui_contract.dart';
import '../../services/premium_entitlement_service.dart';
import '../../services/privacy_enforcement_service.dart';
import '../../widgets/security/server_premium_gate.dart';
import '../../services/star_compatibility_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_animations.dart';
import '../../utils/contact_utils.dart';
import '../../utils/error_handler.dart';
import '../../widgets/app_header.dart';
import '../../widgets/birth_details_widget.dart';
import '../../widgets/celebration_effects.dart';
import '../../widgets/community_references_widget.dart';
import '../../widgets/membership_badge_chip.dart';
import '../../services/security/profile_photo_proxy_service.dart';
import '../../widgets/security/profile_photo_security_context.dart';
import '../../widgets/security/protected_profile_photo.dart';
import '../../services/security/protected_image_cache_service.dart';
import '../../services/security/device_security_service.dart';
import '../../utils/profile_photo_url_resolver.dart';

/// Detailed profile view screen with Ashtakoot matching
class ProfileDetailScreen extends StatefulWidget {
  final String? userId;
  final User? user;
  final String? heroTag;

  /// When non-null, popping is driven by [InterestRouteGuard] when this interest
  /// doc disappears or reaches withdrawn/inactive/deleted (either party).
  final String? routeGuardInterestDocId;

  const ProfileDetailScreen({
    super.key,
    this.userId,
    this.user,
    this.heroTag,
    this.routeGuardInterestDocId,
  }) : assert(userId != null || user != null, 
    'Either userId or user must be provided');

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  bool _photoStatePermissionWarned = false;
  bool? _isLiked;
  bool _isCheckingLike = false;
  bool? _hasSentInterest;
  bool _isSendingInterest = false;
  late ScrollController _scrollController;
  bool _showScrollToTop = false;
  User? _user;
  bool _isLoading = true;
  String? _error;
  bool _hasPendingPhotoRequest = false;
  String? _sentInterestStatus;
  String? _interestButtonLabelOverride;
  Timer? _interestButtonLabelTimer;
  bool _canViewPrivatePhoto = false;
  InterestService? _interestSvc;
  Map<String, dynamic>? _targetUserPrivacyDoc;
  final PrivacyEnforcementService _privacyService = PrivacyEnforcementService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _targetUserPrivacySub;
  bool? _lastTargetIsPhotoPrivate;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _photoRequestStatusSub;
  String? _photoRequestStatusListenKey;

  bool _interestRouteGuardSawMatchingRow = false;
  bool _deviceSecurityPromptScheduled = false;
  bool _serverPhotoPremium = false;
  AshtakootResult? _ashtakootResult;
  String? _ashtakootCacheKey;

  void _onInterestPoolChanged() {
    if (!mounted || _user == null) return;
    _checkInterestStatus();
    _maybePopInterestRouteGuard();
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshMembershipData());
      unawaited(_loadServerPhotoPremium());
    });
  }

  Future<void> _loadServerPhotoPremium() async {
    if (!mounted) return;
    final membership = context.read<AuthService>().currentUser?.membership;
    final ok = await PremiumEntitlementService.isEntitled(
      feature: PremiumEntitlementService.featureViewPrivatePhoto,
      localMembershipHint: membership,
    );
    if (mounted) setState(() => _serverPhotoPremium = ok);
  }

  @override
  void didUpdateWidget(covariant ProfileDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeGuardInterestDocId != widget.routeGuardInterestDocId) {
      _interestRouteGuardSawMatchingRow = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deviceSecurityPromptScheduled) return;
    _deviceSecurityPromptScheduled = true;
    final auth = context.read<AuthService>().currentUser;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await DeviceSecurityService.ensureCompromisedWarningAcknowledged(
        context,
        userId: auth?.id,
        profileId: auth?.profileId,
      );
      if (mounted) setState(() {});
    });
  }

  /// Refresh membership data to catch admin updates
  Future<void> _refreshMembershipData() async {
    try {
      final authService = context.read<AuthService>();
      await authService.refreshMembershipData();
    } catch (e) {
      debugPrint('Failed to refresh membership data: $e');
    }
  }

  Future<void> _loadProfile() async {
    try {
      setState(() => _isLoading = true);

      if (widget.user != null) {
        _user = widget.user;
      } else if (widget.userId != null) {
        final authService = context.read<AuthService>();
        final raw = widget.userId!.trim();
        _user = await authService.getUserByAnyId(raw);
      }

      if (!mounted) return;
      if (_user == null) {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
        return;
      }

      final viewer = context.read<AuthService>().currentUser;
      _targetUserPrivacyDoc =
          await ProfileRepository().getUserDocumentDataCacheFirst(_user!.id);
      if (viewer != null &&
          !_privacyService.canViewerSeeProfile(
            viewer: viewer,
            candidate: _user!,
            candidateDoc: _targetUserPrivacyDoc,
          )) {
        setState(() {
          _error = 'This profile is private based on member privacy settings.';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      _ensureTargetUserPrivacyListener();
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: discarded_futures
        _loadProfileSecondaryData();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error loading profile: $e';
        _isLoading = false;
      });
    }
  }

  /// Non-blocking work after the profile shell is visible.
  Future<void> _loadProfileSecondaryData() async {
    if (!mounted || _user == null) return;
    final analyticsService = context.read<ProfileAnalyticsService>();
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;

    if (currentUser != null && currentUser.profileId != _user!.profileId) {
      unawaited(
        analyticsService
            .recordProfileView(
              viewerId: currentUser.id,
              viewedUserId: _user!.id,
            )
            .catchError((Object e) {
          debugPrint('❌ Failed to record profile view: $e');
        }),
      );
    }

    if (!mounted) return;
    final interestSvc = context.read<InterestService>();
    final uid = currentUser?.id ?? '';
    if (uid.isNotEmpty) {
      _interestSvc?.removeListener(_onInterestPoolChanged);
      _interestSvc = interestSvc;
      interestSvc.addListener(_onInterestPoolChanged);
      final poolWarm = interestSvc.interestsReceived.isNotEmpty ||
          interestSvc.interestsSent.isNotEmpty;
      if (!poolWarm) {
        unawaited(interestSvc.loadInterests(uid));
      }
    }

    _checkLikeStatus();
    _checkInterestStatus();
    _maybePopInterestRouteGuard();
    unawaited(_refreshPhotoRequestState());
  }

  bool _isTargetPhotoPrivate(UserProfile profile) {
    return PrivacyEnforcementService.isPhotoHiddenForProfile(
      profile: profile,
      userDoc: _targetUserPrivacyDoc,
    );
  }

  bool _viewerCanSendPhotoRequest(AuthService authService) {
    final viewerPremium =
        authService.currentUser?.membership.isPremium ?? false;
    return _serverPhotoPremium || viewerPremium;
  }

  Future<void> _refreshPhotoRequestState() async {
    final currentUser = context.read<AuthService>().currentUser;
    final targetUserId = _user?.id ?? '';
    if (currentUser == null || targetUserId.isEmpty) return;
    try {
      final resolver = BirthDetailsService();
      final fromDocId =
          await resolver.resolveUserDocId(currentUser.id);
      final toDocId = await resolver.resolveUserDocId(targetUserId);
      final requesterId =
          fromDocId.isNotEmpty ? fromDocId : currentUser.id.trim();
      final ownerId = toDocId.isNotEmpty ? toDocId : targetUserId.trim();

      _ensurePhotoRequestStatusListener(
        requesterId: requesterId,
        ownerId: ownerId,
      );

      final sent = await FirestoreService().getPhotoRequestsSent(requesterId);
      final targetProfileId = (_user?.profileId ?? '').trim();
      final related = sent.where((r) {
        final toUser = (r['to_user_id'] as String? ?? '').trim();
        final toProfile = (r['to_profile_id'] as String? ?? '').trim();
        return toUser == ownerId ||
            toUser == targetUserId ||
            (targetProfileId.isNotEmpty && toProfile == targetProfileId);
      }).toList()
        ..sort(compareRequestRowsNewestFirst);
      final latestStatus = related.isNotEmpty
          ? (related.first['status']?.toString() ?? '').trim().toLowerCase()
          : '';
      final hasPending = latestStatus == 'pending';
      var approved = false;
      try {
        approved = await FirestoreService().canViewPhoto(
          requesterId,
          ownerId,
        );
      } catch (e) {
        final isPermissionDenied = e is FirebaseException &&
            e.code == 'permission-denied';
        if (isPermissionDenied && !_photoStatePermissionWarned) {
          _photoStatePermissionWarned = true;
          debugPrint(
            '⚠️ _refreshPhotoRequestState canViewPhoto permission-denied '
            '(requester=$requesterId owner=$ownerId); using pending-only fallback',
          );
        } else if (!isPermissionDenied) {
          debugPrint('⚠️ _refreshPhotoRequestState canViewPhoto failed: $e');
        }
      }
      if (mounted) {
        setState(() {
          _hasPendingPhotoRequest = hasPending;
          _canViewPrivatePhoto = approved;
        });
      }
    } catch (e) {
      debugPrint('⚠️ _refreshPhotoRequestState failed: $e');
    }
  }

  void _ensurePhotoRequestStatusListener({
    required String requesterId,
    required String ownerId,
  }) {
    final requester = requesterId.trim();
    final owner = ownerId.trim();
    if (requester.isEmpty || owner.isEmpty) return;

    final key = '$requester|$owner';
    if (key == _photoRequestStatusListenKey) return;

    _photoRequestStatusListenKey = key;
    _photoRequestStatusSub?.cancel();

    _photoRequestStatusSub = FirebaseFirestore.instance
        .collection('photo_requests')
        .where('from_user_id', isEqualTo: requester)
        .where('to_user_id', isEqualTo: owner)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final row = snap.docs.isNotEmpty ? snap.docs.first.data() : null;
        final status = row?['status']?.toString().trim().toLowerCase() ?? '';
        final canView = status == 'accepted' ||
            status == 'granted' ||
            status == 'approved';

        final nextPending = status == 'pending';
        if (nextPending != _hasPendingPhotoRequest || canView != _canViewPrivatePhoto) {
          AccessRequestBroadcast.notifyChanged();
        }

        setState(() {
          _hasPendingPhotoRequest = nextPending;
          _canViewPrivatePhoto = canView;
        });
      },
      onError: (e) {
        debugPrint('⚠️ photo request listener failed: $e');
      },
    );
  }

  bool _readIsPhotoPrivateFromDoc(Map<String, dynamic>? doc) {
    if (doc == null) return false;
    final rootVal =
        doc['is_photo_private'] ?? doc['isPhotoPrivate'] ?? doc['photo_private'];
    final profile = doc['profile'];
    final nestedVal = profile is Map
        ? (profile['is_photo_private'] ??
            profile['isPhotoPrivate'] ??
            profile['photo_private'])
        : null;
    return rootVal == true || nestedVal == true;
  }

  void _ensureTargetUserPrivacyListener() {
    final targetUserId = _user?.id ?? '';
    if (targetUserId.isEmpty) return;

    _lastTargetIsPhotoPrivate = _readIsPhotoPrivateFromDoc(_targetUserPrivacyDoc);
    _targetUserPrivacySub?.cancel();

    _targetUserPrivacySub = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUserId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final nextDoc = snap.data();
        if (nextDoc == null) return;

        final nextPrivate = _readIsPhotoPrivateFromDoc(nextDoc);
        final prevPrivate =
            _lastTargetIsPhotoPrivate ?? _readIsPhotoPrivateFromDoc(_targetUserPrivacyDoc);

        // Update the cached privacy doc so hero/photo UI can recompute instantly.
        setState(() {
          _targetUserPrivacyDoc = nextDoc;
          _lastTargetIsPhotoPrivate = nextPrivate;
        });

        if (prevPrivate != nextPrivate) {
          // Force proxied-photo cache bust + UI refresh.
          AccessRequestBroadcast.notifyChanged();
          unawaited(ProtectedImageCacheService.clearProtectedImageCache());
        }

        // Recompute the "can view private photo" decision using current privacy.
        unawaited(_refreshPhotoRequestState());
      },
      onError: (e) {
        debugPrint('⚠️ target privacy listener failed: $e');
      },
    );
  }

  Future<void> _handleHeroPhotoTap(
    BuildContext context,
    AuthService authService,
    UserProfile profile, {
    required bool hasPhoto,
    required bool photoEntitled,
    required bool privacyAllowsPhoto,
    required bool canView,
    required bool isPrivate,
  }) async {
    if (authService.currentUser == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to request photo access.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    if (canView) {
      final url = _resolvedTargetPhotoUrl(profile);
      if (url.isNotEmpty || (_user?.id ?? '').trim().isNotEmpty) {
        _showFullPhoto(context, url);
      }
      return;
    }

    if (!hasPhoto) return;

    if (!photoEntitled) {
      _showPremiumRequired(
        context,
        isPrivate ? 'Request Photo Access' : 'View Profile Photos',
      );
      return;
    }

    if (isPrivate && !_canViewPrivatePhoto) {
      if (!_viewerCanSendPhotoRequest(authService)) {
        _showPremiumRequired(context, 'Request Photo Access');
        return;
      }
      await _openPhotoRequestFlow(context, authService);
      return;
    }

    if (!privacyAllowsPhoto) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo is hidden by member privacy controls.'),
        ),
      );
    }
  }

  Future<void> _openPhotoRequestFlow(
    BuildContext context,
    AuthService authService, {
    bool forceResend = false,
  }) async {
    if (authService.currentUser == null || _user == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to request photo access.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    if (!_viewerCanSendPhotoRequest(authService)) {
      _showPremiumRequired(context, 'Request Photo Access');
      return;
    }

    await _refreshPhotoRequestState();
    if (!mounted) return;

    if (_hasPendingPhotoRequest && !forceResend) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photo request already pending. Tap the photo again to send a reminder.',
          ),
        ),
      );
      return;
    }
    if (forceResend) {
      final resolver = BirthDetailsService();
      final fromDocId = await resolver.resolveUserDocId(
        authService.currentUser!.id,
      );
      final toDocId = await resolver.resolveUserDocId(_user!.id);
      final requestId = '${fromDocId.isNotEmpty ? fromDocId : authService.currentUser!.id.trim()}_'
          '${toDocId.isNotEmpty ? toDocId : _user!.id.trim()}';
      try {
        await InterestAnalyticsRepository()
            .mergePhotoRequestReminder(requestId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder sent for your photo request.'),
            backgroundColor: AppTheme.sacredGreen,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send reminder: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } else {
      await PhotoService.showPhotoRequestDialog(
        context: context,
        requestingUser: authService.currentUser!,
        targetUser: _user!,
      );
      if (!mounted) return;
    }
    if (!mounted) return;
    await _refreshPhotoRequestState();
  }

Future<void> _checkInterestStatus() async {
    final currentUser = context.read<AuthService>().currentUser;
    final targetUserId = _user?.id ?? '';
    final targetAuthUid = _user?.firebaseAuthUid ?? targetUserId;
    final targetProfileId = _user?.profileId ?? '';
    if (currentUser == null || targetUserId.isEmpty) return;

    void applyStatus(String st, {required bool hasRow}) {
      final raw = st.toLowerCase();
      final s = raw == 'sent' ? 'pending' : raw;
      final blocksUi = s == 'pending' || s == 'accepted';
      if (!mounted) return;
      setState(() {
        _sentInterestStatus = s;
        _hasSentInterest = hasRow && blocksUi;
      });
    }

    final interestService = context.read<InterestService>();
    final sentRow = interestService.interestsSent
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (i) {
            final toUserId = i?['to_user_id'] as String? ?? '';
            final toProfileId = i?['to_profile_id'] as String? ?? '';
            return toProfileId == targetProfileId ||
                toUserId == targetAuthUid ||
                toUserId == targetUserId;
          },
          orElse: () => null,
        );

    if (sentRow != null) {
      final st = (sentRow['status'] as String? ?? 'pending').trim().toLowerCase();
      applyStatus(st, hasRow: true);
      return;
    }

    // Firestore uses users/{docId} in from_user_id / to_user_id (not Auth UID).
    try {
      final fromDocId = currentUser.id;
      Map<String, dynamic>? existing;

      final composite =
          await FirestoreService().getInterestByDocId('${fromDocId}_$targetUserId');
      if (composite != null) {
        existing = composite;
      } else {
        existing = await FirestoreService().getInterest(fromDocId, targetUserId);
      }
      if (existing == null) {
        if (mounted) {
          setState(() {
            // Keep optimistic pending state until we get a definitive backend state.
            // This prevents UI flicker back to "Send Interest" right after sending.
            final localStatus = (_sentInterestStatus ?? '').toLowerCase();
            final localPending =
                localStatus == 'pending' || localStatus == 'sent';
            _hasSentInterest = localPending ? true : false;
            _sentInterestStatus = localPending ? 'pending' : '';
          });
        }
        return;
      }
      final st = (existing['status'] as String? ?? '').trim().toLowerCase();
      applyStatus(st, hasRow: true);
    } catch (e) {
      debugPrint('⚠️ _checkInterestStatus failed: $e');
    }
  }

  Future<void> _checkLikeStatus() async {
    if (_isCheckingLike) return;
    
    debugPrint('🔖 ProfileDetail: checking like status');

    setState(() => _isCheckingLike = true);

    try {
      final likeService = context.read<LikeService>();
      final targetUserId = _user?.id ?? '';

      // Check if current user liked this profile
      if (targetUserId.isNotEmpty) {
        final confirmed = await likeService.hasLikedUser(targetUserId);
        if (mounted) setState(() { _isLiked = confirmed; _isCheckingLike = false; });
      } else {
        if (mounted) setState(() { _isLiked = false; _isCheckingLike = false; });
      }
    } catch (e) {
      debugPrint('⚠️ Error checking like status: $e');
      if (mounted) setState(() { _isLiked = false; _isCheckingLike = false; });
    }
  }

  Future<void> _toggleLikeStable() async {
    SoftTouch.impact();
    bool? rollbackLiked;
    try {
      final authService = context.read<AuthService>();
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        if (mounted) {
          AppError.showError(context, 'Please login to like profiles');
        }
        return;
      }

      if (currentUser.profileId == (_user?.profileId ?? '')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You cannot like your own profile'),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
        }
        return;
      }

      final likeService = context.read<LikeService>();
      final targetUserId = _user?.id ?? '';
      if (targetUserId.isEmpty || _isCheckingLike) return;

      final wasLiked = _isLiked ?? false;
      rollbackLiked = wasLiked;
      // Optimistic UI: label/icon updates immediately; revert if the request fails.
      setState(() {
        _isLiked = !wasLiked;
        _isCheckingLike = true;
      });
      await Future<void>.delayed(Duration.zero);

      final res = wasLiked
          ? await likeService.unlikeProfile(targetUserId: targetUserId)
          : await likeService.likeProfile(targetUserId: targetUserId);
      final err = res['error'] ?? res['errorCode'];
      final errorCode = (res['errorCode'] ?? '').toString().toLowerCase();
      final alreadyExists = errorCode.contains('already');
      final success = (err == null &&
              (wasLiked ||
                  res['liked'] == true ||
                  res['likeId'] != null ||
                  (res['success'] == true))) ||
          (!wasLiked && alreadyExists);

      if (!mounted) return;
      setState(() {
        _isCheckingLike = false;
        if (success) {
          if (!wasLiked && alreadyExists) {
            _isLiked = true;
          }
        } else {
          _isLiked = wasLiked;
        }
      });

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (_isLiked ?? false)
                  ? '${_user?.profile?.firstName} added to likes'
                  : '${_user?.profile?.firstName} removed from likes',
            ),
            backgroundColor:
                (_isLiked ?? false) ? AppTheme.sacredGreen : AppTheme.textMedium,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        AppError.showError(
          context,
          (res['message'] as String?) ??
              (res['error'] as String?) ??
              'Failed to update like',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingLike = false;
        if (rollbackLiked != null) {
          _isLiked = rollbackLiked;
        }
      });
      AppError.showError(context, AppError.firebaseWriteMessage(e));
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

  void _maybePopInterestRouteGuard() {
    final docId = widget.routeGuardInterestDocId?.trim();
    if (docId == null || docId.isEmpty || _interestSvc == null || !mounted) {
      return;
    }
    final svc = _interestSvc!;
    final sent =
        svc.interestsSent.cast<Map<String, dynamic>>().toList(growable: false);
    final recv = svc.interestsReceived
        .cast<Map<String, dynamic>>()
        .toList(growable: false);

    final pooled = InterestRouteGuard.findInterestRowAcrossPools(
      interestDocId: docId,
      interestsSent: sent,
      interestsReceived: recv,
    );
    if (pooled != null) _interestRouteGuardSawMatchingRow = true;

    final shouldPop = InterestRouteGuard.shouldPopProfileForInterestDoc(
      interestDocId: docId,
      interestsSent: sent,
      interestsReceived: recv,
      hasPreviouslySeenInterestRow: _interestRouteGuardSawMatchingRow,
    );
    if (!shouldPop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _interestSvc?.removeListener(_onInterestPoolChanged);
    _interestButtonLabelTimer?.cancel();
    _scrollController.dispose();
    _photoRequestStatusSub?.cancel();
    _targetUserPrivacySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.primaryOrange,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black26,
          toolbarHeight: AppHeader.kToolbarHeightWithLogo,
          title: const Text('Profile'),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE85D04)),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.primaryOrange,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black26,
          toolbarHeight: AppHeader.kToolbarHeightWithLogo,
          title: const Text('Profile'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 72,
                  color: AppTheme.primaryOrange.withAlpha(120)),
              const SizedBox(height: 16),
              Text('Error loading profile',
                  style: TextStyle(color: AC.textSub(context),
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: AC.textMuted(context))),
              const SizedBox(height: 24),
              ElevatedButton(
                // 🔥 FIX: Check canPop before popping, fallback to clearAndGo('/home')
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  } else {
                    NavHelper.clearAndGo(context, '/home');
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: AC.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.primaryOrange,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black26,
          toolbarHeight: AppHeader.kToolbarHeightWithLogo,
          title: const Text('Profile'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_outlined, size: 72,
                  color: AppTheme.primaryOrange.withAlpha(120)),
              const SizedBox(height: 16),
              Text('No profile data',
                  style: TextStyle(color: AC.textSub(context),
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Profile data could not be loaded.',
                  style: TextStyle(color: AC.textMuted(context))),
              const SizedBox(height: 24),
              ElevatedButton(
                // 🔥 FIX: Check canPop before popping, fallback to clearAndGo('/home')
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  } else {
                    NavHelper.clearAndGo(context, '/home');
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Legacy / partial Firestore rows: use synthetic profile so detail UI matches discovery.
    final profile = _user!.profileForDiscovery;
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    final currentProfile = currentUser?.profile;
    // Admin has access to all features (for testing)
    final isPremium = currentUser?.membership.isPremium ?? false;

    final ashtakootKey =
        '${currentProfile?.nakshatra ?? ''}|${profile.nakshatra}';
    if (_ashtakootCacheKey != ashtakootKey || _ashtakootResult == null) {
      _ashtakootCacheKey = ashtakootKey;
      _ashtakootResult = StarCompatibilityService.calculateAshtakoot(
        {
          'id': currentProfile?.id ?? '',
          'nakshatra': currentProfile?.nakshatra ?? '',
        },
        {
          'id': profile.id,
          'nakshatra': profile.nakshatra,
        },
      );
    }
    final ashtakoot = _ashtakootResult!;
    
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Container(
        decoration: BoxDecoration(
          color: AC.card(context),
        ),
        child: CustomScrollView(
          controller: _scrollController,
          physics: BouncingScrollPhysics(),
          slivers: [
            // ── Sticky App Bar: always shows name + profile ID ──────────
            SliverAppBar(
              pinned: true,
              // Keep flexible hero height after raising toolbar to match [SliverAppHeader] / Home.
              expandedHeight: 469,
              stretch: true,
              toolbarHeight: AppHeader.kToolbarHeightWithLogo,
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: Colors.black26,
              titleSpacing: 16,
              iconTheme: const IconThemeData(color: Colors.white, size: 24),
              actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
              // 🔥 FIX: Explicit leading back button with canPop fallback
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  } else {
                    NavHelper.clearAndGo(context, '/home');
                  }
                },
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withAlpha(50),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _user?.profileId ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      MembershipBadgeChip(
                        isPremium: _user?.membership.isPremium ?? false,
                        compact: true,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                // Three dots menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: AC.card(context),
                  onSelected: (value) {
                    if (value == 'block') {
                      _showBlockDialog(context, profile.fullName);
                    } else if (value == 'report') {
                      _showReportDialog(context);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(
                            context.read<BlockService>().isEitherBlocked(
                                  peerUserDocId: _user?.id ?? '',
                                  peerProfileId: _user?.profileId,
                                )
                                  ? Icons.lock_open
                                  : Icons.block,
                            size: 20,
                            color: context.read<BlockService>().isEitherBlocked(
                                  peerUserDocId: _user?.id ?? '',
                                  peerProfileId: _user?.profileId,
                                )
                                  ? AppTheme.sacredGreen
                                  : AppTheme.kumkumRed,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.read<BlockService>().isEitherBlocked(
                                  peerUserDocId: _user?.id ?? '',
                                  peerProfileId: _user?.profileId,
                                )
                                  ? 'Unblock Profile'
                                  : 'Block Profile',
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Row(
                        children: [
                          const Icon(Icons.flag, size: 20, color: AppTheme.kumkumRed),
                          const SizedBox(width: 12),
                          const Text('Report Profile'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: _buildHeroPhotoWithGap(context, profile, authService),
              ),
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20), // 👈 increased top gap
                child: Column(
                  children: [
                    // Profile Summary Card (Free for all users)
                    // Skip flutter_animate on web — avoids rare "Invalid argument: 400" paint errors.
                    _profileSummaryAnimated(context, profile),

                    const SizedBox(height: 32),

                    // Ashtakoot Compatibility Card
                    _buildAshtakootCard(context, ashtakoot, currentProfile?.nakshatra, profile.nakshatra, isPremium: isPremium),

                    const SizedBox(height: 20),

                    // Basic Info
                    _buildSection(
                      context,
                      title: 'Basic Information',
                      icon: Icons.person_outline,
                      children: [
                        _buildInfoRow(
                          'Profile Created By',
                          profile.profileCreatedBy ?? 'Self',
                        ),
                        if (profile.profileCreatedByRelation != null)
                          _buildInfoRow(
                            'Relation',
                            profile.profileCreatedByRelation!,
                          ),
                        _buildInfoRow('Name', profile.firstName),
                        _buildInfoRow('Surname', profile.lastName),
                        _buildInfoRow('Age', '${profile.age} years'),
                        // Birth details with privacy controls
                        _buildPrivateBirthInfo(context, profile),
                        _buildInfoRow('Height', profile.height ?? 'Not Disclosed'),
                        _buildInfoRow('Complexion', profile.complexion ?? 'Not Disclosed'),
                        _buildInfoRow('Body Type', profile.bodyType ?? 'Not Disclosed'),
                        _buildInfoRow('Marital Status', profile.maritalStatus ?? 'Never Married'),
                        if (profile.physicalStatus != null && profile.physicalStatus != 'Normal')
                          _buildInfoRow('Physical Status', profile.physicalStatus!),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Religious Info
                    _buildSection(
                      context,
                      title: 'Religious Details',
                      icon: Icons.temple_hindu_outlined,
                      isMandatory: true,
                      children: [
                        _buildInfoRow('Sect', profile.sect ?? 'Not Disclosed', isMandatory: true),
                        _buildInfoRow('Sub-Sect', profile.subSect ?? 'Not Disclosed'),
                        _buildInfoRow('Gothram', profile.gothram ?? 'Not Disclosed', isMandatory: true),
                        _buildInfoRow('Nakshatra', profile.nakshatra ?? 'Not Disclosed', isMandatory: true),
                        _buildInfoRow('Rasi', profile.rasi ?? 'Not Disclosed'),
                        if (profile.manglikStatus != null)
                          _buildInfoRow('Manglik', profile.manglikStatus!),
                        if (profile.hasHoroscope == true)
                          _buildInfoRow('Horoscope', 'Available'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Education & Career
                    _buildSection(
                      context,
                      title: 'Education & Career',
                      icon: Icons.school_outlined,
                      isMandatory: true,
                      children: [
                        _buildInfoRow('Education', profile.education ?? 'Not Disclosed', isMandatory: true),
                        if (profile.specialization != null)
                          _buildInfoRow('Specialization', profile.specialization!),
                        _buildInfoRow('Occupation', profile.occupation ?? 'Not Disclosed', isMandatory: true),
                        if (profile.occupation == ReferenceData.ownBusinessOccupation) ...[
                          if ((profile.businessDescription ?? '').trim().isNotEmpty)
                            _buildInfoRow(
                              'Business',
                              profile.businessDescription!.trim(),
                              isOptional: true,
                            ),
                        ] else ...[
                          if (profile.employmentType != null)
                            _buildInfoRow('Employment', profile.employmentType!),
                          if (profile.companyName != null)
                            _buildInfoRow('Company', profile.companyName!),
                        ],
                        _buildInfoRow('Income', profile.incomeRange ?? 'Not Disclosed'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Family Details with Siblings & Parents
                    _buildSection(
                      context,
                      title: 'Family Details',
                      icon: Icons.family_restroom,
                      children: [
                        _buildInfoRow('Family Type', profile.familyType ?? 'Not Disclosed'),
                        _buildInfoRow('Family Status', profile.familyStatus ?? 'Not Disclosed'),
                        _buildInfoRow('Family Values', profile.familyValues ?? 'Not Disclosed'),
                        if (profile.aboutFamily != null && profile.aboutFamily!.isNotEmpty)
                          _buildInfoRow('About Family', profile.aboutFamily!, isOptional: true),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Parents Details
                    _buildSection(
                      context,
                      title: 'Parents Details',
                      icon: Icons.people_outline,
                      isOptional: true,
                      children: [
                        if (profile.fatherName != null && profile.fatherName!.isNotEmpty)
                          _buildInfoRow(
                            "Father's Name",
                            profile.fatherName!,
                            isOptional: true,
                          ),
                        _buildInfoRow(
                          "Father's Occupation",
                          profile.fatherOccupation ?? 'Not Disclosed',
                          isOptional: true,
                        ),
                        if (profile.motherName != null && profile.motherName!.isNotEmpty)
                          _buildInfoRow(
                            "Mother's Name",
                            profile.motherName!,
                            isOptional: true,
                          ),
                        _buildInfoRow(
                          "Mother's Occupation",
                          profile.motherOccupation ?? 'Not Disclosed',
                          isOptional: true,
                        ),
                        if (profile.motherSurname != null && profile.motherSurname!.isNotEmpty)
                          _buildInfoRow(
                            "Mother's Surname (Maiden Name)",
                            profile.motherSurname!,
                            isOptional: true,
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Siblings Details
                    _buildSiblingsSection(context, profile),

                    const SizedBox(height: 16),

                    // Reference Details (Community References) - Locked for free users
                    // 🔥 CRITICAL FIX: Pass currentUser (logged-in user) not _user (profile being viewed)
                    // so premium check works correctly
                    CommunityReferencesWidget(
                      profile: profile,
                      currentUser: currentUser,
                      // Must be Firestore `users/{docId}` — same as BirthDetailsWidget (not route param / profileId).
                      ownerUserId: _user!.id,
                      ownerProfileId: _user?.profileId ?? '',
                    ),

                    const SizedBox(height: 16),

                    // Location
                    _buildSection(
                      context,
                      title: 'Location',
                      icon: Icons.location_on_outlined,
                      isMandatory: true,
                      children: [
                        _buildInfoRow('City', profile.city ?? 'Not Disclosed', isMandatory: true),
                        _buildInfoRow('State', profile.state ?? 'Not Disclosed', isMandatory: true),
                        _buildInfoRow('Country', profile.country ?? 'India'),
                        if (profile.nativePlace != null)
                          _buildInfoRow('Native Place', profile.nativePlace!),
                        if (profile.citizenship != null)
                          _buildInfoRow('Citizenship', profile.citizenship!),
                        if (profile.settledAbroad != null && profile.settledAbroad != 'No - Living in India')
                          _buildInfoRow('Settled', profile.settledAbroad!),
                        if (profile.willingToRelocate != null)
                          _buildInfoRow('Willing to Relocate', profile.willingToRelocate! ? 'Yes' : 'No'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Lifestyle
                    _buildSection(
                      context,
                      title: 'Lifestyle',
                      icon: Icons.restaurant_outlined,
                      children: [
                        _buildInfoRow('Food Habit', profile.foodHabit ?? 'Not Disclosed'),
                        _buildInfoRow('Smoking', profile.smokingHabit ?? 'No'),
                        _buildInfoRow('Drinking', profile.drinkingHabit ?? 'No'),
                      ],
                    ),

                    // Hobbies & Interests
                    if ((profile.hobbies != null && profile.hobbies!.isNotEmpty) ||
                        (profile.interests != null && profile.interests!.isNotEmpty) ||
                        (profile.languages != null && profile.languages!.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      _buildInterestsSection(context, profile)
                    ],

                    // About Me Section (Free for all users)
                    if (profile.aboutMe != null && profile.aboutMe!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSection(
                        context,
                        title: 'About Me',
                        icon: Icons.info_outline,
                        children: [
                          Text(
                            profile.aboutMe!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    if (authService.currentUser != null)
                      _buildContactSection(context, _user!, authService.currentUser!),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context, authService, isPremium),
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton(
              onPressed: _scrollToTop,
              backgroundColor: AppTheme.primaryOrange,
              mini: true,
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white,
                size: 20,
              ),
            )
          : null,
    );
  }

  Widget _buildBottomBar(BuildContext context, AuthService authService, bool isPremium) {
    if (_user == null) return const SizedBox.shrink();
    final targetUserId = _user?.id ?? '';
    final targetAuthUid = _user?.firebaseAuthUid ?? targetUserId;
    final targetProfileId = _user?.profileId ?? '';
    final sentInterests = context.watch<InterestService>().interestsSent;
    final latestSentRow = sentInterests
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (i) {
            final toUserId = i?['to_user_id'] as String? ?? '';
            final toProfileId = i?['to_profile_id'] as String? ?? '';
            return toProfileId == targetProfileId ||
                toUserId == targetAuthUid ||
                toUserId == targetUserId;
          },
          orElse: () => null,
        );
    final liveSentStatus =
        (latestSentRow?['status'] as String? ?? '').trim().toLowerCase();
    final cached = (_sentInterestStatus ?? '').trim().toLowerCase();
    final rawEffectiveStatus =
        liveSentStatus.isNotEmpty ? liveSentStatus : cached;
    final effectiveStatus =
        rawEffectiveStatus == 'sent' ? 'pending' : rawEffectiveStatus;
    final hasLivePendingInterest = effectiveStatus == 'pending';
    final hasInterestForUi =
        (_hasSentInterest == true) ||
        effectiveStatus == 'pending' ||
        effectiveStatus == 'accepted';
    final isReminderTapState =
        hasLivePendingInterest ||
        (_sentInterestStatus ?? '').trim().toLowerCase() == 'pending' ||
        (_sentInterestStatus ?? '').trim().toLowerCase() == 'sent';
    // Use _isLiked (set on tap) as the source of truth.
    // Fall back to the live service list only on first load (when null).
    // NEVER overwrite with addPostFrameCallback — that was resetting the button.
    final isLiked = _isLiked ?? false; // Simplified for clean version
    
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: AC.card(context),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSendingInterest
                    ? null
                    : () =>
                        _handleSendInterest(context, authService, isPremium),
                icon: _isSendingInterest
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        hasInterestForUi
                            ? (isReminderTapState
                                ? Icons.notifications_active_outlined
                                : Icons.favorite)
                            : Icons.favorite_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                label: Text(
                  _interestButtonLabelOverride ??
                      (hasInterestForUi ? 'Interested' : 'Send Interest'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasInterestForUi
                      ? const Color(0xFF1B5E20)
                      : AppTheme.primaryOrange,
                  disabledBackgroundColor: const Color(0xFF1B5E20),
                  disabledForegroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isCheckingLike ? null : _toggleLikeStable,
                icon: Icon(
                  isLiked ? Icons.heart_broken_outlined : Icons.bookmark_border,
                  color: Colors.white,
                  size: 20,
                ),
                label: Text(
                  isLiked ? 'Unlike' : 'Like',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: isLiked
                      ? const Color(0xFF1B5E20)
                      : AppTheme.primaryOrange,
                  side: BorderSide.none,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendInterest(
    BuildContext context,
    AuthService authService,
    bool isPremium,
  ) async {
    if (_isSendingInterest) return;
    final currentUser = authService.currentUser;
    if (currentUser == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to send interest'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
      return;
    }

    final serverPremium = await PremiumEntitlementService.isEntitled(
      feature: PremiumEntitlementService.featureSendInterest,
      localMembershipHint: currentUser.membership,
    );
    if (!serverPremium) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only Premium members can send interests.'),
            backgroundColor: AppTheme.primaryOrange,
          ),
        );
        Navigator.pushNamed(context, Routes.premiumUpgrade);
      }
      return;
    }

    // Don't allow sending interest to own profile
    if (currentUser.profileId == _user?.profileId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot send interest to your own profile'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
      return;
    }

    SoftTouch.impact();
    setState(() {
      _isSendingInterest = true;
    });
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    try {
      final interestService = context.read<InterestService>();
      final sentInterests = interestService.interestsSent.cast<Map<String, dynamic>?>();
      final targetUserId = _user?.id ?? '';
      final targetAuthUid = _user?.firebaseAuthUid ?? targetUserId;
      final targetProfileId = _user?.profileId ?? '';
      final latestSentRow = sentInterests.firstWhere(
        (i) {
          final toUserId = i?['to_user_id'] as String? ?? '';
          final toProfileId = i?['to_profile_id'] as String? ?? '';
          return toProfileId == targetProfileId ||
              toUserId == targetAuthUid ||
              toUserId == targetUserId;
        },
        orElse: () => null,
      );

      final isReminder = ((_sentInterestStatus ?? '').toLowerCase() == 'pending') ||
          ((latestSentRow?['status'] as String? ?? '').toLowerCase() == 'pending') ||
          ((latestSentRow?['status'] as String? ?? '').toLowerCase() == 'sent');

      Map<String, dynamic> result;
      if (isReminder && latestSentRow != null) {
        final interestId = (latestSentRow['interestId'] ??
                latestSentRow['id'] ??
                latestSentRow['interest_id'] ??
                '')
            .toString();
        if (interestId.isNotEmpty) {
          await interestService.sendInterestReminderForSentRow(interestId);
          result = {'success': true, 'message': RequestUiContract.reminderSent};
        } else {
          result = {
            'success': false,
            'message': RequestUiContract.reminderFailed,
          };
        }
      } else if (isReminder && latestSentRow == null) {
        // Sent row may not be in local cache yet; refresh once and retry reminder.
        await interestService.loadInterests(currentUser.id);
        final refreshedRow = interestService.interestsSent
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (i) {
                final toUserId = i?['to_user_id'] as String? ?? '';
                final toProfileId = i?['to_profile_id'] as String? ?? '';
                return toProfileId == targetProfileId ||
                    toUserId == targetAuthUid ||
                    toUserId == targetUserId;
              },
              orElse: () => null,
            );
        final interestId = (refreshedRow?['interestId'] ??
                refreshedRow?['id'] ??
                refreshedRow?['interest_id'] ??
                '')
            .toString();
        if (interestId.isNotEmpty) {
          await interestService.sendInterestReminderForSentRow(interestId);
          result = {'success': true, 'message': RequestUiContract.reminderSent};
        } else {
          // Fall back to send call; "already pending" is handled below as reminder path.
          result = await interestService.sendInterestWithResult(
            receiverId: _user?.id ?? '',
            message: 'Interest reminder',
          );
        }
      } else {
        result = await interestService.sendInterestWithResult(
          receiverId: _user?.id ?? '',
        );
      }

      if (context.mounted) {
        if (result['success'] == true) {
          setState(() {
            _hasSentInterest = true;
            _sentInterestStatus = 'pending';
            _interestButtonLabelOverride =
                isReminder ? 'Reminder Sent' : 'Interested';
          });
          _interestButtonLabelTimer?.cancel();
          _interestButtonLabelTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted) return;
            setState(() => _interestButtonLabelOverride = null);
          });

          // Reload with Firestore profile document id (same key used by LikeService).
          if (context.mounted) {
            final interestSvc = context.read<InterestService>();
            unawaited(interestSvc.refreshInterestsFromFirestore(
              userDocId: currentUser.id,
            ));
          }

          if (mounted) {
            unawaited(CelebrationEffects.showInterestBurst(context));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: AC.card(context)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isReminder
                            ? 'Reminder sent to ${_user?.profile?.firstName ?? _user?.profileId}!'
                            : 'Interested in ${_user?.profile?.firstName ?? _user?.profileId}!',
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppTheme.sacredGreen,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          final errorCode = (result['errorCode'] ?? '').toString().toLowerCase();
          final isAlreadyPending = errorCode.contains('already') &&
              ((result['error'] ?? '').toString().toLowerCase().contains('pending'));
          if (isAlreadyPending) {
            setState(() {
              _hasSentInterest = true;
              _sentInterestStatus = 'pending';
              _interestButtonLabelOverride = 'Reminder Sent';
            });
            _interestButtonLabelTimer?.cancel();
            _interestButtonLabelTimer = Timer(const Duration(seconds: 2), () {
              if (!mounted) return;
              setState(() => _interestButtonLabelOverride = null);
            });
            final interestId = (latestSentRow?['interestId'] ??
                    latestSentRow?['id'] ??
                    latestSentRow?['interest_id'] ??
                    '')
                .toString();
            if (interestId.isNotEmpty) {
              try {
                await interestService.sendInterestReminderForSentRow(interestId);
              } catch (_) {}
            }
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Already interested. Reminder sent.'),
                backgroundColor: AppTheme.primaryOrange,
              ),
            );
            return;
          }
          final errorMessage = (result['message'] ?? result['error'] ?? result['errorCode'])
                  as String? ??
              'Failed to send interest. Please try again.';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: AppTheme.kumkumRed,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending interest: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingInterest = false;
        });
      }
    }
  }

  /// Send interest via WhatsApp to the matched profile
  Future<void> _sendInterestViaWhatsApp([String? phoneNumber]) async {
    try {
      final authService = context.read<AuthService>();
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please login to send interest')),
          );
        }
        return;
      }

      final targetNumber = phoneNumber ?? _user?.mobileNumber ?? '';
      if (targetNumber.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact number not available')),
          );
        }
        return;
      }

      // Send interest via WhatsApp
      await ContactUtils.sendInterestViaWhatsApp(
        phoneNumber: targetNumber,
        profileId: _user?.profileId ?? '',
        profileName: _user?.profile?.fullName ?? '',
        requesterName: currentUser.profile?.fullName,
        requesterProfileId: currentUser.profileId,
      );

      // Also send interest through the app system
      if (!mounted) return;
      await _handleSendInterest(context, authService, currentUser.isPremium);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Interested — shared via WhatsApp!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending interest via WhatsApp: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send interest')),
        );
      }
    }
  }

  void _showPremiumRequired(BuildContext context, String feature) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Gold gradient header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryOrange, AppTheme.primaryOrange.withAlpha(180)],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(30),
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: const Icon(Icons.workspace_premium, size: 34, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Premium Feature',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    feature,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(220),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // ── Body
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                children: [
                  ...[
                    ('🔓', 'View clear profile photos'),
                    ('📞', 'Request & view contact details'),
                    ('👥', 'Access Community Heads'),
                    ('🔒', 'Incognito browsing mode'),
                  ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text(item.$1, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(item.$2,
                              style: TextStyle(fontSize: 14, color: AC.text(dialogContext),
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryOrange.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer_outlined, size: 16, color: AppTheme.primaryOrange),
                        const SizedBox(width: 8),
                        Text('Starting at just ₹99/month',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppTheme.primaryOrange)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        NavHelper.push(context, Routes.premiumUpgrade);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.workspace_premium, size: 20),
                          SizedBox(width: 8),
                          Text('Upgrade to Platinum',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Maybe later',
                        style: TextStyle(color: AC.textMuted(dialogContext), fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumLockedCard(
    BuildContext context, {
    required String title,
    required String description,
    IconData icon = Icons.lock_outline,
  }) {
    return GestureDetector(
      onTap: () => _showPremiumRequired(context, title),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AC.surface2(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AC.border(context),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 28,
                color: Color(0xFF757575),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AC.textSub(context),
                  ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, size: 16, color: AC.card(context)),
                  SizedBox(width: 8),
                  Text(
                    'Upgrade to Premium',
                    style: TextStyle(
                      color: AC.card(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAshtakootCard(
    BuildContext context,
    AshtakootResult ashtakoot,
    String? star1,
    String? star2, {
    bool isPremium = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getCompatibilityColor(ashtakoot.level).withAlpha(30),
            _getCompatibilityColor(ashtakoot.level).withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getCompatibilityColor(ashtakoot.level).withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _getCompatibilityColor(ashtakoot.level).withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      ashtakoot.level.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ashtakoot Matching',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ashtakoot.level.displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _getCompatibilityColor(ashtakoot.level),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${ashtakoot.percentage}%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _getCompatibilityColor(ashtakoot.level),
                      ),
                    ),
                    Text(
                      '${ashtakoot.score}/${ashtakoot.maxScore}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Progress Bar
        ],
      ),
    );
  }

  Color _getCompatibilityColor(CompatibilityLevel? level) {
    switch (level) {
      case CompatibilityLevel.excellent:
        return AppTheme.sacredGreen;
      case CompatibilityLevel.good:
        return const Color(0xFF8BC34A);
      case CompatibilityLevel.average:
        return Colors.orange;
      case CompatibilityLevel.belowAverage:
        return Colors.deepOrange;
      case CompatibilityLevel.notRecommended:
        return AppTheme.kumkumRed;
      case CompatibilityLevel.unknown:
        return AppTheme.textLight;
      default:
        return AppTheme.textLight;
    }
  }

  Widget _profileSummaryAnimated(BuildContext context, UserProfile profile) {
    final card = _buildProfileSummary(context, profile);
    if (kIsWeb) return card;
    return card.appSlideIn();
  }

  /// Build a profile summary section below the photo
  Widget _buildProfileSummary(BuildContext context, UserProfile profile) {
    // Generate a simple summary text
    final age = profile.age;
    final education = profile.education?.split(' - ').first ?? '';
    final occupation = profile.occupation?.split(' / ').first ?? '';
    final city = profile.city ?? '';
    final state = profile.state ?? '';
    final sect = profile.sect ?? '';
    final nakshatra = profile.simpleNakshatra ?? '';

    // Build summary parts
    List<String> summaryParts = [];
    
    summaryParts.add('$age years old');
    if (education.isNotEmpty) summaryParts.add(education);
    if (occupation.isNotEmpty) summaryParts.add(occupation);
    
    String location = '';
    if (city.isNotEmpty && state.isNotEmpty) {
      location = '$city, $state';
    } else if (city.isNotEmpty) {
      location = city;
    } else if (state.isNotEmpty) {
      location = state;
    }

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Summary Text
          Text(
            summaryParts.join(' • '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AC.text(context),
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
          ),
          if (location.isNotEmpty) ...[
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AC.textMuted(context),
                ),
                SizedBox(width: 4),
                Text(
                  location,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textMuted(context),
                      ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Quick Info Chips
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (sect.isNotEmpty)
                _buildQuickChip(Icons.temple_hindu, sect),
              if (nakshatra.isNotEmpty)
                _buildQuickChip(Icons.star_outline, nakshatra),
              if (profile.gothram != null)
                _buildQuickChip(Icons.account_tree_outlined, profile.gothram!),
              if (profile.familyType != null)
                _buildQuickChip(Icons.home_outlined, profile.familyType!),
            ],
          ),
          // Siblings quick info
          if ((profile.brothers ?? 0) > 0 || (profile.sisters ?? 0) > 0) ...[
            const SizedBox(height: 12),
            _buildSiblingQuickInfo(profile),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.templeGold),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.templeGold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiblingQuickInfo(UserProfile profile) {
    final brothers = profile.brothers ?? 0;
    final sisters = profile.sisters ?? 0;
    final brothersMarried = profile.brothersMarried ?? 0;
    final sistersMarried = profile.sistersMarried ?? 0;

    List<String> parts = [];
    if (brothers > 0) {
      parts.add('$brothers Brother${brothers > 1 ? 's' : ''}${brothersMarried > 0 ? ' ($brothersMarried married)' : ''}');
    }
    if (sisters > 0) {
      parts.add('$sisters Sister${sisters > 1 ? 's' : ''}${sistersMarried > 0 ? ' ($sistersMarried married)' : ''}');
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people_outline, size: 14, color: AC.textMuted(context)),
        SizedBox(width: 6),
        Text(
          parts.join(' • '),
          style: TextStyle(
            fontSize: 12,
            color: AC.textSub(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSiblingsSection(BuildContext context, UserProfile profile) {
    final brothers = profile.brothers ?? 0;
    final sisters = profile.sisters ?? 0;

    if (brothers == 0 && sisters == 0) {
      return _buildSection(
        context,
        title: 'Siblings',
        icon: Icons.group_outlined,
        isOptional: true,
        children: [
          Text(
            'No siblings / Not Disclosed',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AC.textMuted(context),
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.elevatedCard(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AC.surface2(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.group_outlined,
                  color: AC.text(context),
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Siblings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AC.text(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AC.textMuted(context).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Optional',
                  style: TextStyle(
                    fontSize: 11,
                    color: AC.textMuted(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Brothers
          if (brothers > 0)
            _buildSiblingRow(
              context,
              icon: Icons.man,
              label: 'Brother${brothers > 1 ? 's' : ''}',
              count: brothers,
              marriedCount: profile.brothersMarried,
            ),
          if (brothers > 0 && sisters > 0)
            const SizedBox(height: 12),
          // Sisters
          if (sisters > 0)
            _buildSiblingRow(
              context,
              icon: Icons.woman,
              label: 'Sister${sisters > 1 ? 's' : ''}',
              count: sisters,
              marriedCount: profile.sistersMarried,
            ),
        ],
      ),
    );
  }

  Widget _buildSiblingRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    int? marriedCount,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AC.surface(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppTheme.primaryOrange),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count $label',
                style: TextStyle(
                  color: AC.text(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (marriedCount != null && marriedCount > 0)
                Text(
                  '$marriedCount married',
                  style: TextStyle(
                    color: AC.textMuted(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInterestsSection(BuildContext context, UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.elevatedCard(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AC.icon(context).withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.interests,
                  color: AC.icon(context),
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Interests & Languages',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AC.text(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // Languages
          if (profile.languages != null && profile.languages!.isNotEmpty) ...[
            Text(
              'Languages',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.languages!
                  .map((lang) => _buildInterestChip(lang, Icons.language))
                  .toList(),
            ),
            SizedBox(height: 16),
          ],
          // Hobbies
          if (profile.hobbies != null && profile.hobbies!.isNotEmpty) ...[
            Text(
              'Hobbies',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.hobbies!
                  .map((hobby) => _buildInterestChip(hobby, Icons.favorite_outline))
                  .toList(),
            ),
          ],
          // Modern Interests
          if (profile.interests != null && profile.interests!.isNotEmpty) ...[
            SizedBox(height: 16),
            Text(
              'Interests',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.interests!
                  .map((interest) => _buildInterestChip(interest, Icons.star_outline))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInterestChip(String text, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AC.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.templeGold),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AC.text(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool isMandatory = false,
    bool isOptional = false,
    Color? titleColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.elevatedCard(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AC.surface2(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: AC.text(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: titleColor ?? AC.text(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (isMandatory)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.kumkumRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 10, color: AppTheme.kumkumRed),
                      const SizedBox(width: 4),
                      Text(
                        'Required',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.kumkumRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isOptional)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AC.textMuted(context).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 11,
                      color: AC.textMuted(context),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isMandatory = false,
    bool isOptional = false,
  }) {
    final isNotDisclosed = value == 'Not Disclosed' || value == 'N/A';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AC.textMuted(context),
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isMandatory) ...[
                  const SizedBox(width: 2),
                  Text(
                    '*',
                    style: TextStyle(
                      color: AppTheme.kumkumRed,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isNotDisclosed
                    ? AC.textMuted(context)
                    : AC.text(context),
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontStyle: isNotDisclosed ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gap wrapper — places a styled separator between the pinned AppBar
  /// and the hero photo so the two sections are visually distinct.
  Widget _buildHeroPhotoWithGap(
      BuildContext context, UserProfile profile, AuthService authService) {
    final topPad = MediaQuery.of(context).padding.top +
        AppHeader.kToolbarHeightWithLogo;
    return Column(
      children: [
        // ── Orange area that sits behind the AppBar toolbar ────────
        Container(height: topPad, color: AppTheme.primaryOrange),

        // ── Divider between orange header & hero ──────────────────
        Container(height: 2, color: Theme.of(context).brightness == Brightness.dark
            ? AC.border(context)
            : Colors.white),

        // ── Band between header & photo ─────────────────────────────
        Container(height: 23, color: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.surfaceDark2
            : const Color(0xFFFFF3E0)),

        // ── Hero photo fills the rest ──────────────────────────────
        Expanded(child: _buildHeroPhoto(context, profile, authService)),
      ],
    );
  }

  String _resolvedTargetPhotoUrl(UserProfile profile) {
    return resolveProfilePhotoUrl(
      profile: profile,
      userDoc: _targetUserPrivacyDoc,
    );
  }

  bool _targetHasResolvablePhoto(UserProfile profile) {
    if (_resolvedTargetPhotoUrl(profile).isNotEmpty) return true;
    final ownerId = (_user?.id ?? '').trim();
    return shouldAttemptProfilePhotoProxy(ownerUserId: ownerId);
  }

  /// Full-bleed hero photo with My Profile style border and shadow
  Widget _buildHeroPhoto(BuildContext context, UserProfile profile, AuthService authService) {
    final resolvedPhotoUrl = _resolvedTargetPhotoUrl(profile);
    final hasPhoto = _targetHasResolvablePhoto(profile);
    final isPrivate = _isTargetPhotoPrivate(profile);
    final isAcceptedConnection = (_sentInterestStatus ?? '').toLowerCase() == 'accepted' ||
        (_sentInterestStatus ?? '').toLowerCase() == 'granted';
    final privacyAllowsPhoto = _user == null || authService.currentUser == null
        ? true
        : _privacyService.canShowPhotoInDiscover(
            viewer: authService.currentUser!,
            candidate: _user!,
            candidateDoc: _targetUserPrivacyDoc,
          ) ||
            isAcceptedConnection ||
            // If an explicit photo-access request was approved, treat the photo
            // as visible for this viewer even if "discover" privacy rules hide it.
            (isPrivate && _canViewPrivatePhoto);
    final viewerPremium =
        authService.currentUser?.membership.isPremium ?? false;
    // For private photos, photo-access approval should allow viewing even if
    // the viewer doesn't have the premium entitlement.
    final photoEntitled =
        _serverPhotoPremium || viewerPremium || (isPrivate && _canViewPrivatePhoto);
    final canView = hasPhoto &&
        photoEntitled &&
        (!isPrivate || _canViewPrivatePhoto) &&
        privacyAllowsPhoto;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleHeroPhotoTap(
        context,
        authService,
        profile,
        hasPhoto: hasPhoto,
        photoEntitled: photoEntitled,
        privacyAllowsPhoto: privacyAllowsPhoto,
        canView: canView,
        isPrivate: isPrivate,
      ),
  
      child: Container(
        color: AC.surface(context),
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background - clean light gray ─────────────────
              Container(
                color: AC.surface(context),
              ),

              // ── Centered photo with nice border (My Profile style) ────────
              Center(
                child: _wrapHeroIfNeeded(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 25,
                          offset: const Offset(0, 12),
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppTheme.primaryGold.withAlpha(180),
                            width: 5,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: canView
                              // Premium + (public or approved private) → real photo
                              ? _buildStyledPhoto(resolvedPhotoUrl, profile)
                              : !photoEntitled && hasPhoto
                                  // Free user: show blurred overlay
                                  ? _buildBlurredPremiumPhoto(context, profile)
                                  : !privacyAllowsPhoto
                                      ? _buildPrivacyPlaceholderSmall(
                                          context, profile, authService)
                                  : isPrivate && !_canViewPrivatePhoto
                                      // Private photo (premium but not approved)
                                      ? _buildPrivacyPlaceholderSmall(
                                          context, profile, authService)
                                      : _buildAvatarPlaceholder(profile),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Top gradient so AppBar back/action icons stay readable ─
              Positioned(
                top: 0, left: 0, right: 0,
                height: 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(120),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── "Tap to view" hint — only for premium users who can open full photo ─────
              if (canView)
                Positioned(
                  bottom: 20, 
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        const Text('Tap to view',
                            style: TextStyle(color: Colors.white70,
                                fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),

              // ── Target user's membership badge (bottom — avoid covering face in hero photo)
              Positioned(
                bottom: 20,
                left: 16,
                child: MembershipBadgeChip(
                  isPremium: _user?.membership.isPremium ?? false,
                ),
              ),

              // ── Status badge (top-right) — premium lock for free users, privacy for premium ─
              Positioned(
                top: 12, right: 16,
                child: !photoEntitled && hasPhoto
                    // Free viewer — show "Premium Only" badge
                    ? GestureDetector(
                        onTap: () => _showPremiumRequired(context, 'View Profile Photos'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryOrange.withAlpha(220),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('Premium Only',
                                  style: TextStyle(color: Colors.white,
                                      fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      )
                    // Premium viewer — show privacy status
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPrivate
                              ? Colors.orange.withAlpha(200)
                              : Colors.green.withAlpha(200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPrivate ? Icons.lock_outline : Icons.lock_open_outlined,
                              color: Colors.white, size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isPrivate ? 'Private' : 'Public',
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wrapHeroIfNeeded({required Widget child}) {
    final tag = widget.heroTag;
    if (tag == null || tag.isEmpty) return child;
    return Hero(tag: tag, child: child);
  }

  /// Hero-sized blurred photo overlay for free (non-premium) viewers.
  /// Shows the real image heavily blurred + a centred premium lock/upgrade prompt.
  Widget _buildBlurredPremiumPhoto(BuildContext context, UserProfile profile) {
    final url = _resolvedTargetPhotoUrl(profile);
    final policy = ProtectedProfilePhoto.resolvePolicy();
    const heroSize = 260.0;
    final rawImage = ProtectedProfilePhoto(
      imageUrl: url,
      imageCacheKey:
          url.isNotEmpty ? url : 'proxy:${_user?.id ?? profile.id}',
      ownerUserId: _user?.id,
      viewerId: ProfilePhotoSecurityContext.viewerProfileId(context),
      ownerId: _user?.profileId ?? profile.id,
      sessionToken: ProfilePhotoSecurityContext.sessionToken(),
      proxyVariant: ProfilePhotoProxyVariant.preview,
      fit: BoxFit.cover,
      width: heroSize,
      height: heroSize,
      memCacheWidth: 120,
      memCacheHeight: 120,
      restrictSensitiveViewing: policy.restrictSensitiveViewing,
      heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
      errorWidget: Container(color: AppTheme.primaryOrange.withAlpha(20)),
    );

    return SizedBox(
      width: heroSize,
      height: heroSize,
      child: Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        // Blurred photo
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: rawImage,
          ),
        ),
        // Dark overlay
        Container(color: Colors.black.withAlpha(90)),
        // Premium lock content
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(25),
                  border: Border.all(color: AppTheme.primaryGold.withAlpha(200), width: 2),
                ),
                child: Icon(Icons.lock_outline, size: 36, color: AppTheme.primaryGold),
              ),
              const SizedBox(height: 14),
              const Text(
                'Photo Locked',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Upgrade to Platinum to view\nclear profile photos',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                    height: 1.4),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => _showPremiumRequired(context, 'View Profile Photos'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryOrange, AppTheme.primaryOrange.withAlpha(200)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primaryOrange.withAlpha(100),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Upgrade to View',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildStyledPhoto(String imagePath, UserProfile profile) {
    final policy = ProtectedProfilePhoto.resolvePolicy();
    const heroSize = 260.0;
    final ownerDocId = (_user?.id ?? '').trim();
    final mayUseDirectFallback =
        _canViewPrivatePhoto || !_isTargetPhotoPrivate(profile);
    return ValueListenableBuilder<int>(
      valueListenable: AccessRequestBroadcast.tick,
      builder: (context, tick, _) {
        return ProtectedProfilePhoto(
      imageUrl: imagePath,
      imageCacheKey: imagePath.isNotEmpty
          ? '$imagePath|grant:$_canViewPrivatePhoto|tick:$tick'
          : 'proxy:$ownerDocId|grant:$_canViewPrivatePhoto|tick:$tick',
      ownerUserId: ownerDocId.isNotEmpty ? ownerDocId : null,
      viewerId: ProfilePhotoSecurityContext.viewerProfileId(context),
      ownerId: _user?.profileId ?? profile.id,
      sessionToken: ProfilePhotoSecurityContext.sessionToken(),
      proxyVariant: ProfilePhotoProxyVariant.full,
      fit: BoxFit.cover,
      width: heroSize,
      height: heroSize,
      restrictSensitiveViewing: policy.restrictSensitiveViewing,
      heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
      allowLegacyDirectOnProxyFailure:
          mayUseDirectFallback &&
          (imagePath.isNotEmpty || ownerDocId.isNotEmpty),
      placeholder: Container(
        color: AppTheme.primaryOrange.withAlpha(15),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryOrange,
            strokeWidth: 2,
          ),
        ),
      ),
      errorWidget: _buildAvatarPlaceholder(profile),
    );
      },
    );
  }

  Widget _buildPrivacyPlaceholderSmall(
    BuildContext context,
    UserProfile profile,
    AuthService authService,
  ) {
    return Material(
      color: AppTheme.primaryOrange.withAlpha(12),
      child: InkWell(
        onTap: () => _handleHeroPhotoTap(
          context,
          authService,
          profile,
          hasPhoto: true,
          photoEntitled: _serverPhotoPremium ||
              (authService.currentUser?.membership.isPremium ?? false),
          privacyAllowsPhoto: true,
          canView: false,
          isPrivate: _isTargetPhotoPrivate(profile),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 48, color: AppTheme.primaryOrange.withAlpha(180)),
            const SizedBox(height: 12),
            Text(
              'Photo Protected',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Tap to Request',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder(UserProfile profile) {
    return Container(
      color: AppTheme.primaryOrange.withAlpha(18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryOrange.withAlpha(30),
                border: Border.all(color: AppTheme.primaryOrange.withAlpha(80), width: 2),
              ),
              child: Center(
                child: Text(
                  profile.firstName.isNotEmpty ? profile.firstName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700,
                      color: AppTheme.primaryOrange),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No Photo',
              style: TextStyle(fontSize: 14, color: AC.textMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullPhoto(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullScreenPhotoViewer(
              imagePath: imagePath,
              ownerUserId: _user?.id ?? '',
              viewerId: ProfilePhotoSecurityContext.viewerProfileId(context),
              ownerId: _user?.profileId ?? '',
            ),
          );
        },
      ),
    );
  }

  /// Shows a 5-second auto-dismissing popup overlay after blocking a profile
  void _showBlockedPopup(BuildContext context, String profileName, VoidCallback onUndo) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => _BlockedPopupOverlay(
        profileName: profileName,
        onUndo: () {
          onUndo();
          entry.remove();
        },
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);

    // Auto-remove after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _showBlockDialog(BuildContext context, String profileName) {
    final blockService = context.read<BlockService>();
    final isCurrentlyBlocked = blockService.isEitherBlocked(
      peerUserDocId: _user!.id,
      peerProfileId: _user!.profileId,
    );

    if (isCurrentlyBlocked) {
      // Unblock dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Unblock Profile'),
          content: Text(
            'Are you sure you want to unblock $profileName?\n\nThey will be able to see your profile again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                blockService.unblockUser(_user!.profileId);
                Navigator.pop(ctx);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile unblocked successfully'),
                    backgroundColor: AppTheme.sacredGreen,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sacredGreen),
              child: const Text('Unblock'),
            ),
          ],
        ),
      );
    } else {
      // Block dialog
      String? selectedReason;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.block, color: AppTheme.kumkumRed),
                SizedBox(width: 12),
                Text('Block Profile', style: TextStyle(color: AC.text(context))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to block $profileName?\n\nWhen you block someone:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AC.text(context),
                      ),
                ),
                const SizedBox(height: 12),
                _buildBlockPoint('They cannot see your profile'),
                _buildBlockPoint('They cannot contact you'),
                _buildBlockPoint('You won\'t see them in matches'),
                const SizedBox(height: 16),
                Text(
                  'Reason (optional):',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AC.text(context),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Unlike',
                    'Inappropriate behavior',
                    'Fake profile',
                    'Other',
                  ].map((reason) => ChoiceChip(
                    label: Text(reason),
                    selected: selectedReason == reason,
                    onSelected: (selected) {
                      setState(() {
                        selectedReason = selected ? reason : null;
                      });
                    },
                    selectedColor: AppTheme.primaryOrange.withAlpha(30),
                    labelStyle: TextStyle(
                      color: selectedReason == reason
                          ? AppTheme.primaryOrange
                          : AC.text(context),
                    ),
                  )).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final blockedProfileId = _user!.profileId;
                  try {
                    await blockService.blockUser(
                      profileId: blockedProfileId,
                      userDocId: _user!.id,
                      name: profileName,
                      photo: _user!.profile?.profilePicture,
                      reason: selectedReason,
                    );
                  } catch (e) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (context.mounted) {
                      AppError.showError(
                        context,
                        AppError.firebaseWriteMessage(e),
                      );
                    }
                    return;
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  // Also pop the profile screen since they blocked this user
                  Navigator.pop(context);
                  // Show 5-second auto-dismissing overlay popup
                  _showBlockedPopup(context, profileName, () {
                    blockService.unblockUser(blockedProfileId);
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.kumkumRed),
                child: const Text('Block'),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Build contact section - server-validated premium + privacy.
  Widget _buildContactSection(BuildContext context, User targetUser, User currentUser) {
    return ServerPremiumGate(
      feature: PremiumEntitlementService.featureViewContact,
      localMembership: currentUser.membership,
      builder: (context, serverPremium) =>
          _buildContactSectionBody(context, targetUser, currentUser, serverPremium),
    );
  }

  Widget _buildContactSectionBody(
    BuildContext context,
    User targetUser,
    User currentUser,
    bool serverPremium,
  ) {
    final profile = targetUser.profile!;
    final mobileNumber = targetUser.mobileNumber;
    final altMobileNumber = targetUser.alternativeMobileNumber;
    final canShowContact = _privacyService.canShowContactDetails(
      viewer: currentUser,
      candidate: targetUser,
      candidateDoc: _targetUserPrivacyDoc,
    );

    final profileDetails = '''
⭐ Nakshatra: ${profile.nakshatra ?? 'N/A'}
🏠 Location: ${profile.city ?? ''}, ${profile.state ?? ''}
📚 Education: ${profile.education ?? 'N/A'}
💼 Occupation: ${profile.occupation ?? 'N/A'}
''';

    if (!canShowContact) {
      return _buildSection(
        context,
        title: 'Contact Information',
        titleColor: AC.text(context),
        icon: Icons.phone_outlined,
        children: [
          _buildPremiumLockedCard(
            context,
            title: 'Contact Hidden',
            description:
                'This member has hidden contact details using privacy controls.',
            icon: Icons.lock_outline,
          ),
        ],
      );
    }

    if (!serverPremium) {
      return _buildSection(
        context,
        title: 'Contact Information',
        titleColor: AC.text(context),
        icon: Icons.phone_outlined,
        children: [
          _buildPremiumLockedCard(
            context,
            title: 'Contact Information',
            description:
                'Upgrade to Platinum to view contact numbers, make calls, and send WhatsApp messages.',
            icon: Icons.phone_locked_outlined,
          ),
        ],
      );
    }

    return _buildSection(
      context,
      title: 'Contact Information',
      titleColor: AC.text(context),
      icon: Icons.phone_outlined,
      children: [
        // Primary Mobile Number
        if (mobileNumber.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AC.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone, size: 20, color: AC.icon(context)),
                    SizedBox(width: 8),
                    Text(
                      'Mobile Number',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AC.text(context),
                          ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SelectableText(
                  mobileNumber,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AC.text(context),
                      ),
                ),
                SizedBox(height: 12),
                // Call + WhatsApp action buttons for primary number
                Row(
                  children: [
                    // Direct Call button
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => ContactUtils.makePhoneCall(mobileNumber),
                          icon: Icon(Icons.call, size: 20, color: Colors.white),
                          label: Text(
                            'Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.sacredGreen,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // WhatsApp button - Send Interest
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _sendInterestViaWhatsApp(),
                          icon: Icon(Icons.message, size: 20, color: Colors.white),
                          label: Text(
                            'Send Interest',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF25D366),
                            shadowColor: const Color(0xFF25D366).withAlpha(50),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (altMobileNumber != null && altMobileNumber.isNotEmpty) const SizedBox(height: 16),
        ],
        
        // Alternative Mobile Number
        if (altMobileNumber != null && altMobileNumber.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AC.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_android, size: 20, color: AC.icon(context)),
                    SizedBox(width: 8),
                    Text(
                      'Alternative Contact',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AC.text(context),
                          ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SelectableText(
                  altMobileNumber,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AC.text(context),
                      ),
                ),
                SizedBox(height: 12),
                // Call + WhatsApp action buttons for alternative number
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => ContactUtils.makePhoneCall(altMobileNumber),
                          icon: Icon(Icons.call, size: 20, color: Colors.white),
                          label: Text(
                            'Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.sacredGreen,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _sendInterestViaWhatsApp(altMobileNumber),
                          icon: Icon(Icons.message, size: 20, color: Colors.white),
                          label: Text(
                            'Send Interest',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            shadowColor: const Color(0xFF25D366).withAlpha(50),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 16),
        
        // Share Profile via WhatsApp (premium users only)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => ContactUtils.shareProfileViaWhatsApp(
              phoneNumber: mobileNumber,
              profileId: targetUser.profileId,
              profileName: profile.fullName,
              profileDetails: profileDetails,
              requesterName: currentUser.profile?.fullName,
              requesterProfileId: currentUser.profileId,
            ),
            icon: const Icon(Icons.share, size: 20),
            label: const Text(
              'Share Profile via WhatsApp',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AC.text(context),
              side: BorderSide(color: AC.border(context), width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlockPoint(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check, size: 16, color: AC.textMuted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: AC.text(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    final reasons = [
      'Fake profile / Fraud',
      'Inappropriate photos',
      'Harassment',
      'Already married',
      'Wrong information',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.flag, color: AppTheme.kumkumRed),
              SizedBox(width: 12),
              Text('Report Profile', style: TextStyle(color: AC.text(context))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this profile?',
                style: TextStyle(fontSize: 14, color: AC.text(context)),
              ),
              const SizedBox(height: 16),
              ...reasons.map((reason) => Row(
                children: [
                  Radio<String>(
                    value: reason,
                    // ignore: deprecated_member_use
                    groupValue: selectedReason,
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      setState(() => selectedReason = value);
                    },
                    activeColor: AppTheme.primaryOrange,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => selectedReason = reason);
                      },
                      child: Text(
                        reason,
                        style: TextStyle(fontSize: 14, color: AC.text(context)),
                      ),
                    ),
                  ),
                ],
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        await FirestoreService().submitReport(
                          reporterId: context.read<AuthService>().currentUser?.id ?? '',
                          reportedUserId: _user?.id ?? '',
                          reason: selectedReason!,
                        );
                      } catch (_) {}
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report submitted. We will review this profile.'),
                            backgroundColor: AppTheme.sacredGreen,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.kumkumRed),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  /// Birth details — blurred for all users, request access available to everyone (no premium gate).
  /// Scoped with [Selector] so [AuthService] updates do not rebuild the entire profile screen.
  Widget _buildPrivateBirthInfo(BuildContext context, UserProfile profile) {
    return Selector<AuthService, String>(
      selector: (_, auth) {
        final u = auth.currentUser;
        return '${u?.id ?? ''}|${u?.membership.isPremium ?? false}|${u?.profile?.id ?? ''}';
      },
      builder: (context, _, __) {
        final currentUser = context.read<AuthService>().currentUser;
        return BirthDetailsWidget(
          profile: profile,
          currentUser: currentUser,
          ownerUserId: _user!.id,
          ownerProfileId: _user!.profileId,
        );
      },
    );
  }

}

/// Full-screen photo viewer with pinch-to-zoom, double-tap zoom, and swipe-to-close
class _FullScreenPhotoViewer extends StatefulWidget {
  final String imagePath;
  final String viewerId;
  final String ownerId;
  final String ownerUserId;

  const _FullScreenPhotoViewer({
    required this.imagePath,
    required this.viewerId,
    required this.ownerId,
    required this.ownerUserId,
  });

  @override
  State<_FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _isZoomed = false;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_animation != null) {
          _transformController.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
      _animController.forward(from: 0);
      setState(() => _isZoomed = false);
    } else {
      final x = _doubleTapPosition.dx;
      final y = _doubleTapPosition.dy;
      const scale = 2.5;
      final zoomed = Matrix4.identity()
        ..translateByDouble(-x * (scale - 1), -y * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: zoomed,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
      _animController.forward(from: 0);
      setState(() => _isZoomed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = ProtectedProfilePhoto.resolvePolicy();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onDoubleTapDown: (details) {
              _doubleTapPosition = details.localPosition;
            },
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.8,
              maxScale: 5.0,
              panEnabled: true,
              scaleEnabled: true,
              onInteractionUpdate: (details) {
                final scale = _transformController.value.getMaxScaleOnAxis();
                final nowZoomed = scale > 1.05;
                if (nowZoomed != _isZoomed) {
                  setState(() => _isZoomed = nowZoomed);
                }
              },
              child: SizedBox.expand(
                child: Center(
                  child: ProtectedProfilePhoto(
                    imageUrl: widget.imagePath,
                    ownerUserId: widget.ownerUserId,
                    viewerId: widget.viewerId,
                    ownerId: widget.ownerId,
                    sessionToken: ProfilePhotoSecurityContext.sessionToken(),
                    proxyVariant: ProfilePhotoProxyVariant.full,
                    fit: BoxFit.contain,
                    restrictSensitiveViewing:
                        policy.restrictSensitiveViewing,
                    heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
                    placeholder: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white70,
                            strokeWidth: 2,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading photo...',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    errorWidget: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              color: Colors.white38, size: 64),
                          SizedBox(height: 12),
                          Text(
                            'Could not load photo',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top overlay: close + zoom hint
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => NavHelper.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Icon(Icons.close, color: AC.card(context), size: 22),
                      ),
                    ),
                    if (!_isZoomed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: AC.textMuted(context), size: 16),
                            SizedBox(width: 6),
                            Text('Pinch or double-tap to zoom', style: TextStyle(color: AC.textMuted(context), fontSize: 12)),
                          ],
                        ),
                      ),
                    if (_isZoomed)
                      GestureDetector(
                        onTap: () {
                          _animation = Matrix4Tween(
                            begin: _transformController.value,
                            end: Matrix4.identity(),
                          ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
                          _animController.forward(from: 0);
                          setState(() => _isZoomed = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_out, color: AC.textMuted(context), size: 16),
                              SizedBox(width: 6),
                              Text('Reset zoom', style: TextStyle(color: AC.textMuted(context), fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ─── Blocked Profile Auto-Dismiss Popup ──────────────────────────────────────

class _BlockedPopupOverlay extends StatefulWidget {
  final String profileName;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _BlockedPopupOverlay({
    required this.profileName,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  State<_BlockedPopupOverlay> createState() => _BlockedPopupOverlayState();
}

class _BlockedPopupOverlayState extends State<_BlockedPopupOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    // Countdown tick
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 90,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.kumkumRed.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block, color: AppTheme.kumkumRed, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.profileName} blocked',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Dismissing in ${_countdown}s',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Undo', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(Icons.close, color: Colors.white54, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
