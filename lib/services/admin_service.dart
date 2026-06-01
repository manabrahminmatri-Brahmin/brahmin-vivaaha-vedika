import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/app_firebase_functions.dart';
import 'dart:async';
import '../models/membership.dart';
import '../models/verification.dart';
import '../utils/safe_data_extractor.dart';
import '../core/identity_service.dart';
import '../core/contract.dart';

/// Admin service — all four data sets are driven by live Firestore snapshots.
///
/// LIVE STREAMS (auto-update the UI the moment Firestore changes):
///   • _pendingUsers          — users where membership_status == 'pending'
///   • _verifiedUsers         — users where membership_status == 'verified'
///   • _allUsers              — every user document (ordered by doc ID)
///   • _pendingVerifications  — profile_verifications where status == 'pending'
///
/// ACTIVE MEMBERS (derived in Dart from _allUsers):
///   Users whose membership_tier == 'platinum' AND whose membership has not
///   expired. Recomputed every time the allUsers stream fires.
///
/// `notifyListeners()` is called inside each stream handler so every
/// `Consumer<AdminService>` in the dashboard rebuilds automatically.
class AdminService extends ChangeNotifier {
  static AdminService? _instance;
  static AdminService get instance => _instance ??= AdminService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose
  List<Map<String, dynamic>> _pendingUsers        = [];
  List<Map<String, dynamic>> _verifiedUsers       = [];
  List<Map<String, dynamic>> _allUsers            = [];
  List<Map<String, dynamic>> _activeMembers       = [];
  List<ProfileVerification>  _pendingVerifications = [];

  StreamSubscription<QuerySnapshot>? _pendingUsersSub;
  StreamSubscription<QuerySnapshot>? _verifiedUsersSub;
  StreamSubscription<QuerySnapshot>? _allUsersSub;
  StreamSubscription<QuerySnapshot>? _verificationsSub;
  StreamSubscription<QuerySnapshot>? _paymentRequestsSub;
  Timer? _notifyDebounce;

  List<Map<String, dynamic>> _paymentRequests = [];

  // 🔥 Pagination config for performance (5K+ users)
  static const int defaultPageSize = 50; // Users per batch
  int _pageSize = defaultPageSize;
  bool _hasMoreUsers = false;
  DocumentSnapshot? _lastUserDoc;
  
  /// 🔥 Configure page size for better performance
  void setPageSize(int size) {
    final nextSize = size.clamp(20, 200); // Min 20, max 200
    if (_pageSize == nextSize) return;
    _pageSize = nextSize;
    _lastUserDoc = null;
    _startAllUsersStream();
    debugPrint('AdminService: Page size set to $_pageSize');
    _safeNotify();
  }

  AdminService._() {
    debugPrint('AdminService created');
  }

  /// Defer notify to avoid "!_dirty" during Provider mount / build.
  void _safeNotify() {
    if (_disposed) return;
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 48), () {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyDebounce?.cancel();
    _pendingUsersSub?.cancel();
    _verifiedUsersSub?.cancel();
    _allUsersSub?.cancel();
    _verificationsSub?.cancel();
    _paymentRequestsSub?.cancel();
    super.dispose();
  }

  bool get isLoading               => _isLoading;
  List get pendingUsers            => _pendingUsers;
  List get verifiedUsers           => _verifiedUsers;
  List get allUsers                => _allUsers;
  List get activeMembers           => _activeMembers;
  List<ProfileVerification> get pendingVerifications => _pendingVerifications;
  List<Map<String, dynamic>> get paymentRequests => _paymentRequests;
  bool get hasMoreUsers            => _hasMoreUsers;

  // ── Timestamp helper ──────────────────────────────────────────────────────
  DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String? _tsStr(dynamic v) => _parseTimestamp(v)?.toIso8601String();

  Map<String, dynamic> _mapDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = Map<String, dynamic>.from(doc.data() ?? {});
    d['id']          = doc.id;
    d['created_at']  = _tsStr(d['created_at'])  ?? '';
    d['verified_at'] = _tsStr(d['verified_at']) ?? '';
    final pid = SafeDataExtractor.getProfileId(d);
    if (pid.isNotEmpty) d['profile_id'] = pid;
    final exp = SafeDataExtractor.parseFirestoreDate(d['membership_expires_at']);
    if (exp != null) {
      d['membership_expires_at'] = exp.toIso8601String();
    }
    return d;
  }

  // ── Active members — derived from allUsers ────────────────────────────────
  void _recomputeActiveMembers() {
    final now = DateTime.now();
    _activeMembers = _allUsers.where((u) {
      final tier = (u['membership_tier'] as String? ?? '').toLowerCase();
      if (tier != 'platinum') return false;
      final raw = u['membership_expires_at'];
      if (raw == null) return false;
      // FIX: Use _parseTimestamp which correctly handles Timestamp, String, int
      // DateTime.tryParse(raw.toString()) fails silently on Timestamp objects.
      final exp = _parseTimestamp(raw);
      return exp != null && now.isBefore(exp);
    }).toList();
  }

  // ── INITIALIZE — start all live streams ──────────────────────────────────
  // FIX: isLoading is cleared as soon as the allUsers stream delivers its
  // first snapshot (or after 3 s timeout) instead of a blind 600 ms delay.
  // This prevents the "No pending/verified users" empty-state flash that
  // appeared while data was already arriving from Firestore.
  Future<void> initialize() async {
    if (_pendingUsersSub != null) {
      _safeNotify();
      return;
    }
    _isLoading = true;
    _safeNotify();
    try {
      _startPendingUsersStream();
      _startVerifiedUsersStream();
      _startAllUsersStream();
      _startVerificationsStream();
      _startPaymentRequestsStream();
      debugPrint('AdminService: live streams started');
      // Wait for allUsers first snapshot (max 3 s) before clearing spinner
      await Future.any([
        Stream.periodic(const Duration(milliseconds: 100))
            .firstWhere((_) => _allUsersSub != null && _allUsers.isNotEmpty),
        Future.delayed(const Duration(seconds: 3)),
      ]);
    } catch (e) {
      debugPrint('AdminService.initialize error: $e');
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── STREAM: pending users ─────────────────────────────────────────────────
  void _startPendingUsersStream() {
    _pendingUsersSub?.cancel();
    _pendingUsersSub = _firestore
        .collection(Collections.users)
        .where('membership_status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      _pendingUsers = snap.docs
          .map((d) => _mapDoc(d as DocumentSnapshot<Map<String, dynamic>>))
          .toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      debugPrint('LIVE pending: ${_pendingUsers.length}');
      _safeNotify();
    }, onError: (e) => debugPrint('pendingUsers stream error: $e'));
  }

  // ── STREAM: verified users ────────────────────────────────────────────────
  void _startVerifiedUsersStream() {
    _verifiedUsersSub?.cancel();
    _verifiedUsersSub = _firestore
        .collection(Collections.users)
        .where('membership_status', isEqualTo: 'verified')
        .snapshots()
        .listen((snap) {
      _verifiedUsers = snap.docs
          .map((d) => _mapDoc(d as DocumentSnapshot<Map<String, dynamic>>))
          .toList()
        ..sort((a, b) => (b['verified_at'] as String)
            .compareTo(a['verified_at'] as String));
      debugPrint('LIVE verified: ${_verifiedUsers.length}');
      _safeNotify();
    }, onError: (e) => debugPrint('verifiedUsers stream error: $e'));
  }

  // ── STREAM: all users ─────────────────────────────────────────────────────
  void _startAllUsersStream() {
    _allUsersSub?.cancel();
    _allUsersSub = _firestore
        .collection(Collections.users)
        .orderBy(FieldPath.documentId)
        .limit(_pageSize) // 🔥 Limit for performance with large datasets
        .snapshots()
        .listen((snap) {
      _lastUserDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMoreUsers = snap.docs.length >= _pageSize;
      _allUsers = snap.docs
          .map((d) => _mapDoc(d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      _allUsers.sort((a, b) {
        final ad = a['created_at'] as String;
        final bd = b['created_at'] as String;
        if (ad.isEmpty && bd.isEmpty) return 0;
        if (ad.isEmpty) return 1;
        if (bd.isEmpty) return -1;
        return bd.compareTo(ad);
      });

      _recomputeActiveMembers();
      debugPrint('LIVE all: ${_allUsers.length} / active: ${_activeMembers.length}');
      _safeNotify();
    }, onError: (e) => debugPrint('allUsers stream error: $e'));
  }

  // ── STREAM: pending verifications ─────────────────────────────────────────
  void _startVerificationsStream() {
    _verificationsSub?.cancel();
    _verificationsSub = _firestore
        .collection('profile_verifications')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      _pendingVerifications = snap.docs.map((doc) {
        final d = doc.data();
        final rawUid = d['user_id'] ?? d['user_id'];
        final uid = rawUid?.toString().trim() ?? '';
        final rawUrl = d['document_url'] ?? d['documentUrl'];
        final urlStr = rawUrl?.toString().trim() ?? '';
        final docUrl = urlStr.isNotEmpty ? urlStr : null;
        final typeRaw = d['type']?.toString() ?? 'id';
        return ProfileVerification(
          id:              doc.id,
          userId:          uid,
          type: VerificationType.values.firstWhere(
            (e) => e.name == typeRaw,
            orElse: () => VerificationType.id,
          ),
          status: VerificationStatus.values.firstWhere(
            (e) => e.name == d['status'],
            orElse: () => VerificationStatus.pending,
          ),
          submittedAt:     _parseTimestamp(d['submitted_at']),
          verifiedAt:      _parseTimestamp(d['verified_at']),
          verifiedBy:      d['verified_by']      as String?,
          rejectionReason: d['rejection_reason'] as String?,
          documentUrl:     docUrl,
        );
      }).toList()
        ..sort((a, b) {
          final at = a.submittedAt ?? DateTime(2000);
          final bt = b.submittedAt ?? DateTime(2000);
          return bt.compareTo(at);
        });
      debugPrint('LIVE verifications: ${_pendingVerifications.length}');
      _safeNotify();
    }, onError: (e) => debugPrint('verifications stream error: $e'));
  }

  // ── STREAM: payment requests ──────────────────────────────────────────────
  void _startPaymentRequestsStream() {
    _paymentRequestsSub?.cancel();
    _paymentRequestsSub = _firestore
        .collection('payment_requests')
        .snapshots()
        .listen((snap) {
      _paymentRequests = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(
            doc.data());
        d['id'] = doc.id;
        // Normalize mixed old/new schemas so admin UI can consume one format.
        d['user_name'] = (d['user_name'] ?? d['requester_name'] ?? d['name'] ?? 'Unknown').toString();
        d['mobile_number'] = (d['mobile_number'] ?? d['mobile'] ?? '').toString();
        d['plan_name'] = (d['plan_name'] ?? d['planName'] ?? d['planId'] ?? '—').toString();
        // Prefer userDocId (Razorpay / profile doc id) before raw user_id so admin
        // approval targets the same row as in-app checkout.
        final notesMap = d['notes'];
        String? notesUserDoc;
        if (notesMap is Map) {
          final m = Map<String, dynamic>.from(notesMap);
          notesUserDoc = (m['userDocId'] ?? m['user_doc_id'])?.toString();
        }
        final rootUserDoc =
            (d['userDocId'] ?? d['user_doc_id'])?.toString() ?? '';
        final nu = (notesUserDoc ?? '').trim();
        final ru = rootUserDoc.trim();
        final rawUserId = (d['user_id'] ?? '').toString().trim();
        final rawUid = (d['uid'] ?? '').toString().trim();
        d['user_id'] = [ru, nu, rawUserId, rawUid]
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        d['utr'] = (d['utr'] ?? d['paymentId'] ?? d['orderId'] ?? '').toString();
        d['status'] = (d['status'] ?? 'pending').toString().toLowerCase();
        d['submitted_at'] = _tsStr(d['submitted_at'] ?? d['createdAt']) ?? '';
        d['approved_at']  = _tsStr(d['approved_at'] ?? d['processedAt']) ?? '';

        final amount = d['amount'];
        final amountPaise = d['amountPaise'];
        if ((amount == null || amount == '') && amountPaise is num) {
          d['amount'] = amountPaise / 100.0;
        }
        if (d['plan_days'] == null && d['planDays'] is num) {
          d['plan_days'] = (d['planDays'] as num).toInt();
        }
        if (d['plan_days'] == null &&
            notesMap is Map &&
            notesMap['planDays'] is num) {
          d['plan_days'] = (notesMap['planDays'] as num).toInt();
        }
        return d;
      }).toList()
        ..sort((a, b) {
          final aTs = _parseTimestamp(a['submitted_at']) ??
              _parseTimestamp(a['approved_at']) ??
              _parseTimestamp(a['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTs = _parseTimestamp(b['submitted_at']) ??
              _parseTimestamp(b['approved_at']) ??
              _parseTimestamp(b['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTs.compareTo(aTs);
        });
      debugPrint('LIVE payment_requests: ${_paymentRequests.length}');
      _safeNotify();
    }, onError: (e) => debugPrint('paymentRequests stream error: $e'));
  }

  // ── Statistics ────────────────────────────────────────────────────────────
  Map<String, dynamic> get statistics => {
    'totalUsers':           _allUsers.length,
    'pendingUsers':         _pendingUsers.length,
    'verifiedUsers':        _verifiedUsers.length,
    'pendingVerifications': _pendingVerifications.length,
    'activeMembers':        _activeMembers.length,
    'lastUpdated':          DateTime.now().toIso8601String(),
  };

  Future<Map<String, dynamic>> getStatistics() async {
    if (_pendingUsersSub == null) await initialize();
    return statistics;
  }

  // kept for Load More button API compat — no-op with streams
  Future<void> loadMoreUsers() async {
    if (_isLoading || _lastUserDoc == null || !_hasMoreUsers) return;
    _isLoading = true;
    _safeNotify();
    try {
      final snap = await _firestore
          .collection(Collections.users)
          .orderBy(FieldPath.documentId)
          .startAfterDocument(_lastUserDoc!)
          .limit(_pageSize)
          .get();
      if (snap.docs.isEmpty) {
        _hasMoreUsers = false;
        return;
      }
      _lastUserDoc = snap.docs.last;
      final existingIds = _allUsers.map((u) => (u['id'] as String?) ?? '').toSet();
      final appended = snap.docs
          .map((d) => _mapDoc(d as DocumentSnapshot<Map<String, dynamic>>))
          .where((u) => !existingIds.contains(u['id'] as String? ?? ''))
          .toList();
      _allUsers = [..._allUsers, ...appended];
      _hasMoreUsers = snap.docs.length >= _pageSize;
      _allUsers.sort((a, b) {
        final ad = a['created_at'] as String;
        final bd = b['created_at'] as String;
        if (ad.isEmpty && bd.isEmpty) return 0;
        if (ad.isEmpty) return 1;
        if (bd.isEmpty) return -1;
        return bd.compareTo(ad);
      });
      _recomputeActiveMembers();
    } catch (e) {
      debugPrint('loadMoreUsers error: $e');
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // ── Write operations — streams auto-refresh the UI ─────────────────────────
  Future<bool> _callAdminMutation(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    try {
      await appFirebaseFunctions.httpsCallable(functionName).call(payload);
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ $functionName callable failed: [${e.code}] ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ $functionName callable error: $e');
      return false;
    }
  }

  Future<bool> approveUserMembership(String userId) async {
    if (userId.isEmpty) return false;
    return _callAdminMutation('adminApproveUserMembership', {
      'user_id': userId,
    });
  }

  Future<bool> suspendUser(String userId, String reason) async {
    if (userId.isEmpty) return false;
    return _callAdminMutation('adminSuspendUser', {
      'user_id': userId,
      'reason': reason,
    });
  }

  Future<bool> rejectUser(String userId, String reason) async {
    if (userId.isEmpty) return false;
    return _callAdminMutation('adminRejectUser', {
      'user_id': userId,
      'reason': reason,
    });
  }

  Future<bool> reactivateUser(String userId) async {
    if (userId.isEmpty) return false;
    return _callAdminMutation('adminReactivateUser', {
      'user_id': userId,
    });
  }

  Future<bool> verifyDocument(
      String verificationId, bool isApproved, String? rejectionReason) async {
    if (verificationId.isEmpty) return false;
    return _callAdminMutation('adminVerifyDocument', {
      'verification_id': verificationId,
      'is_approved': isApproved,
      if (rejectionReason != null && rejectionReason.trim().isNotEmpty)
        'rejection_reason': rejectionReason.trim(),
    });
  }

  Future<bool> deleteUser(String userId) async {
    if (userId.isEmpty) return false;
    return _callAdminMutation('adminDeleteUser', {
      'user_id': userId,
    });
  }

  Future<bool> updateUserMembership(
      String userId, Membership membership) async {
    if (userId.isEmpty) {
      debugPrint('❌ AdminService: updateUserMembership - userId is empty');
      return false;
    }
    final resolvedUserId = await _resolveUserDocId(userId);
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      debugPrint('❌ AdminService: updateUserMembership - unable to resolve doc id for "$userId"');
      return false;
    }

    final ok = await _callAdminMutation('adminUpdateUserMembership', {
      'user_id': resolvedUserId,
      'tier': membership.tier.name,
      'start_date': membership.startDate?.toIso8601String(),
      'expiry_date': membership.expiryDate?.toIso8601String(),
    });
    if (ok) {
      await refreshData().timeout(const Duration(seconds: 10));
      return true;
    }

    // Fallback for environments where callable isn't deployed/authorized.
    final fallbackOk = await _updateMembershipDirect(resolvedUserId, membership);
    if (fallbackOk) {
      await refreshData().timeout(const Duration(seconds: 10));
      return true;
    }
    return false;
  }

  Future<String?> _resolveUserDocId(String rawId) async {
    final candidate = rawId.trim();
    if (candidate.isEmpty) return null;
    try {
      final byDoc = await _firestore.collection(Collections.users).doc(candidate).get();
      if (byDoc.exists) return candidate;

      final byProfile = await _firestore
          .collection(Collections.users)
          .where('profile_id', isEqualTo: candidate)
          .limit(1)
          .get();
      if (byProfile.docs.isNotEmpty) return byProfile.docs.first.id;

      final byAuthUid = await _firestore
          .collection(Collections.users)
          .where('auth_uid', isEqualTo: candidate)
          .limit(1)
          .get();
      if (byAuthUid.docs.isNotEmpty) return byAuthUid.docs.first.id;
    } catch (e) {
      debugPrint('⚠️ AdminService: _resolveUserDocId failed for "$rawId": $e');
    }
    return null;
  }

  Future<bool> _updateMembershipDirect(String userDocId, Membership membership) async {
    try {
      final nowTs = FieldValue.serverTimestamp();
      final expiryTs = membership.expiryDate != null
          ? Timestamp.fromDate(membership.expiryDate!)
          : null;
      final startTs = membership.startDate != null
          ? Timestamp.fromDate(membership.startDate!)
          : FieldValue.serverTimestamp();

      final tierName = membership.tier.name.toLowerCase();
      // Match User.toDatabaseJson: status mirrors tier so queries/UI stay consistent.
      final status = tierName;

      await _firestore.collection(Collections.users).doc(userDocId).set({
        'membership_tier': tierName,
        'membership_status': status,
        'membership_start_at': startTs,
        'membership_expires_at': expiryTs,
        if (membership.expiryDate != null)
          'membership_expiry_date': membership.expiryDate!.toIso8601String()
        else
          'membership_expiry_date': FieldValue.delete(),
        'membership_json': {
          'tier': tierName,
          'startDate': membership.startDate?.toIso8601String(),
          'expiryDate': membership.expiryDate?.toIso8601String(),
          'transactionId': membership.transactionId,
          'paymentMethod': membership.paymentMethod ?? 'admin_direct',
          'amountPaid': membership.amountPaid,
          'contactsUsed': membership.contactsUsed ?? 0,
        },
        'updated_at': nowTs,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('❌ AdminService: _updateMembershipDirect failed for "$userDocId": $e');
      return false;
    }
  }

  Future<int> clearProfileViewHistory(String userIdOrProfileId) async {
    final resolvedUserDocId = await _resolveUserDocId(userIdOrProfileId);
    if (resolvedUserDocId == null || resolvedUserDocId.isEmpty) {
      debugPrint('❌ AdminService: clearProfileViewHistory - unable to resolve user for "$userIdOrProfileId"');
      return -1;
    }

    try {
      final userDoc = await _firestore.collection(Collections.users).doc(resolvedUserDocId).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final profileId = (userData['profile_id'] as String? ?? '').trim();
      final authUid = (userData['auth_uid'] as String? ?? '').trim();

      final ids = <String>{resolvedUserDocId, profileId, authUid}
        ..removeWhere((v) => v.trim().isEmpty);
      if (ids.isEmpty) return 0;

      final targetIds = ids.take(10).toList();
      final refs = <String, DocumentReference<Map<String, dynamic>>>{};

      Future<void> collectByField(String field) async {
        Query<Map<String, dynamic>> q;
        if (targetIds.length == 1) {
          q = _firestore.collection('profile_views').where(field, isEqualTo: targetIds.first);
        } else {
          q = _firestore.collection('profile_views').where(field, whereIn: targetIds);
        }
        final snap = await q.get();
        for (final d in snap.docs) {
          refs[d.id] = d.reference;
        }
      }

      await collectByField('viewed_profile_id');
      await collectByField('viewed_user_id');

      if (refs.isEmpty) return 0;

      final allRefs = refs.values.toList();
      var deleted = 0;
      for (var i = 0; i < allRefs.length; i += 450) {
        final batch = _firestore.batch();
        final end = (i + 450 < allRefs.length) ? i + 450 : allRefs.length;
        for (var j = i; j < end; j++) {
          batch.delete(allRefs[j]);
        }
        await batch.commit();
        deleted += (end - i);
      }

      await _firestore.collection(Collections.users).doc(resolvedUserDocId).set({
        'profile_views_received': 0,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return deleted;
    } catch (e) {
      debugPrint('❌ AdminService: clearProfileViewHistory failed: $e');
      return -1;
    }
  }

  Future<bool> verifyAdminStatus() async {
    try {
      // 🔥 CRITICAL: Use unified identity service - NO direct auth usage
      final identityService = IdentityService();
      final userId = await identityService.getUserId();
      if (userId.isEmpty) return false;
      // 🔥 CRITICAL: Use only stored user ID - NO direct auth usage
      final docId = userId;

      if (docId.isEmpty) {
        debugPrint('❌ AdminService: No user ID available');
        return false;
      }

      final userDoc = await _firestore.collection(Collections.users).doc(docId).get();
      if (!userDoc.exists) {
        debugPrint('❌ AdminService: User doc not found for $docId');
        return false;
      }

      final isAdmin = userDoc.data()?['is_admin'] == true;
      debugPrint('✅ AdminService: is_admin=$isAdmin for docId=$docId');
      return isAdmin;
    } catch (e) {
      debugPrint('❌ AdminService.verifyAdminStatus: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUserDetails(String userId) async {
    try {
      final doc = await _firestore.collection(Collections.users).doc(userId).get();
      if (!doc.exists || doc.data() == null) return null;
      return _mapDoc(doc);
    } catch (e) {
      debugPrint('getUserDetails error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return _allUsers;
    final q = query.toLowerCase();
    return _allUsers.where((u) =>
      ((u['first_name']    as String? ?? '').toLowerCase().contains(q)) ||
      ((u['last_name']     as String? ?? '').toLowerCase().contains(q)) ||
      ((u['mobile_number'] as String? ?? '').contains(q))               ||
      (SafeDataExtractor.getProfileId(u).toLowerCase().contains(q))
    ).toList();
  }

  Future<void> refreshData() async {
    // FIX: With live streams, Firestore pushes updates automatically.
    // Cancelling and restarting streams causes a loading flash + empty-state
    // flicker. Just re-notify listeners to force a UI rebuild with current data.
    // Full restart only if streams have died (sub == null).
    if (_pendingUsersSub == null || _allUsersSub == null) {
      _pendingUsersSub?.cancel();  _pendingUsersSub  = null;
      _verifiedUsersSub?.cancel(); _verifiedUsersSub = null;
      _allUsersSub?.cancel();      _allUsersSub      = null;
      _verificationsSub?.cancel(); _verificationsSub = null;
      _paymentRequestsSub?.cancel(); _paymentRequestsSub = null;
      await initialize();
    } else {
      _safeNotify();
    }
  }

  // ── PAYMENT REQUEST ACTIONS ───────────────────────────────────────────────

  /// Approve a payment request: update request doc + grant platinum to user.
  Future<bool> approvePaymentRequest(Map<String, dynamic> request) async {
    final requestId = (request['id'] as String?) ?? '';
    final userId    = (request['user_id'] as String?) ?? '';
    final days      = (request['plan_days'] as int?) ?? 30;
    final tierStr   = (request['tier'] as String?) ?? 'platinum';
    if (requestId.isEmpty || userId.isEmpty) return false;
    return _callAdminMutation('adminApprovePaymentRequest', {
      'request_id': requestId,
      'user_id': userId,
      'plan_days': days,
      'tier': tierStr,
    });
  }

  /// Reject a payment request with an optional reason.
  Future<bool> rejectPaymentRequest(
      String requestId, String reason) async {
    if (requestId.isEmpty) return false;
    return _callAdminMutation('adminRejectPaymentRequest', {
      'request_id': requestId,
      'reason': reason.isNotEmpty ? reason : 'Rejected by admin',
    });
  }
}
