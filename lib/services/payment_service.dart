import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity_service.dart';
import '../utils/log.dart';
import '../utils/firestore_cache_read.dart';
import '../utils/ttl_cache.dart';
import '../core/contract.dart';
import 'plan_service.dart';

/// Payment helpers: legacy **manual UPI + UTR** path vs **Razorpay** path.
///
/// - **Premium / platinum checkout** in the app uses Razorpay SDK → `createRazorpayOrder` /
///   `verifyRazorpayPayment` and Firestore `payments/{orderId}` (not this service’s
///   [initiatePayment]).
/// - **[initiatePayment]** writes **`payment_requests`** for a manual UPI + UTR flow that
///   expects admin follow-up. It is not wired from [PremiumUpgradeScreen]; keep it only
///   if you still expose that flow elsewhere.
/// - [getPaymentHistory], [checkPaymentStatus], and [paymentStatusStream] may combine both
///   sources where relevant.
class PaymentService extends ChangeNotifier {
  static PaymentService? _instance;
  static PaymentService get instance => _instance ??= PaymentService._internal();
  
  PaymentService._internal();
  
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _kPaymentHistoryTtl = Duration(minutes: 3);
  static const Duration _kPremiumStatusTtl = Duration(minutes: 5);
  final TtlCache<String, List<Map<String, dynamic>>> _paymentHistoryCache =
      TtlCache(ttl: _kPaymentHistoryTtl);
  final TtlCache<String, bool> _premiumStatusCache =
      TtlCache(ttl: _kPremiumStatusTtl);

  // Payment state
  bool _isProcessing = false;
  String? _lastError;
  Map<String, dynamic>? _lastPaymentResult;
  String? _currentRequestId;
  
  // UPI Payment Details (show to user)
  final String upiId = 'manabrahminmatri@upi';  // Correct UPI ID
  final String accountName = 'Mana Brahmin Matrimony';
  
  bool get isProcessing => _isProcessing;
  String? get lastError => _lastError;
  Map<String, dynamic>? get lastPaymentResult => _lastPaymentResult;
  String? get currentRequestId => _currentRequestId;

  /// Get real user doc ID from SharedPreferences
  Future<String?> _getRealUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_user_id');
  }

  // Backward compatibility stubs for old Razorpay API
  /// Deprecated: Use addListener() instead. Stub for backward compatibility.
  void init({
    required Function(dynamic) onSuccess,
    required Function(dynamic) onError,
    Function(dynamic)? onExternalWallet,
  }) {
    // No-op: UPI flow doesn't need initialization
    Log.d('PaymentService.init() called - no-op for UPI flow');
  }

  /// Deprecated: Stub for backward compatibility.
  void disposeRazorpay() {
    // No-op: UPI flow doesn't use Razorpay
    Log.d('PaymentService.disposeRazorpay() called - no-op for UPI flow');
  }

  /// Initiate UPI payment request
  /// [planId] the selected plan ID (monthly, quarterly, half_yearly, yearly)
  /// [utr] UPI Transaction Reference number (12 digits)
  Future<void> initiatePayment({
    required String planId,
    required String utr,
  }) async {
    if (_isProcessing) {
      throw Exception('Payment already in progress');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    // Get real user doc ID
    final realUserId = await _getRealUserId();
    if (realUserId == null || realUserId.isEmpty) {
      throw Exception('User session not found. Please log in again.');
    }

    // Get plan from PlanService (Firebase)
    final plan = PlanService.instance.getPlanById(planId);
    if (plan == null) {
      throw Exception('Invalid plan selected. Please try again.');
    }

    // Use the discounted fee from Firebase
    final amount = plan.discountedFee;

    // Validate UTR (should be 12 digits)
    if (utr.length != 12 || !RegExp(r'^\d{12}$').hasMatch(utr)) {
      throw Exception('Invalid UTR number. Please enter 12-digit UPI transaction reference.');
    }

    try {
      _isProcessing = true;
      _lastError = null;
      notifyListeners();

      Log.d('Creating UPI payment request: ₹$amount, Plan: ${plan.name}, UTR: $utr');

      // Create payment request document in Firestore
      // This triggers the 'onPaymentRequestCreated' Cloud Function
      final requestData = {
        'user_id': realUserId,
        'auth_uid': user.uid,
        'amount': amount,
        'actualFee': plan.actualFee,
        'discountedFee': plan.discountedFee,
        'planId': planId,
        'planName': plan.name,
        'durationMonths': plan.durationMonths,
        'duration_months': plan.durationMonths,
        'utr': utr,
        'status': 'pending', // Triggers Cloud Function
        'description': '${plan.name} - ${plan.durationDisplay}',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'currency': 'INR',
        'paymentMethod': 'UPI',
        'upiId': upiId,
      };

      final docRef = await _db
          .collection('payment_requests')
          .add(requestData);

      _currentRequestId = docRef.id;

      Log.d('Payment request created: $_currentRequestId');

      _lastPaymentResult = {
        'requestId': _currentRequestId,
        'status': 'pending',
        'message': 'Payment request submitted for verification',
      };

      _isProcessing = false;
      notifyListeners();

      _paymentHistoryCache.remove(realUserId);
      _premiumStatusCache.remove(realUserId);

    } catch (e, stackTrace) {
      Log.e('Failed to initiate payment: $e');
      developer.log(
        'Payment initiation failed',
        error: e,
        stackTrace: stackTrace,
        name: 'PaymentService',
      );
      
      _isProcessing = false;
      _lastError = e.toString();
      notifyListeners();
      
      rethrow;
    }
  }

  /// Check payment status by request ID
  Future<Map<String, dynamic>?> checkPaymentStatus(String requestId) async {
    try {
      final pr = await _db.collection('payment_requests').doc(requestId).get();
      if (pr.exists) {
        return {
          'id': pr.id,
          ...pr.data()!,
          '_source': 'payment_requests',
        };
      }
      final pay = await _db.collection('payments').doc(requestId).get();
      if (!pay.exists) return null;
      return {
        'id': pay.id,
        ...pay.data()!,
        '_source': 'payments',
      };
    } catch (e) {
      Log.e('Failed to check payment status: $e');
      return null;
    }
  }

  /// Poll payment status — avoids long-lived snapshot listeners on payment docs.
  Stream<Map<String, dynamic>?> paymentStatusStream(String requestId) {
    if (requestId.isEmpty) return Stream.value(null);
    final controller = StreamController<Map<String, dynamic>?>();
    Timer? timer;
    var ticks = 0;

    Future<void> poll() async {
      try {
        final m = await checkPaymentStatus(requestId);
        if (controller.isClosed) return;
        controller.add(m);
        ticks++;
        final st = (m?['status'] as String? ?? '').toLowerCase().trim();
        const terminal = {
          'completed',
          'verified',
          'failed',
          'rejected',
          'cancelled',
          'success',
          'captured',
          'paid',
        };
        if (terminal.contains(st) || ticks >= 50) {
          timer?.cancel();
          await controller.close();
        }
      } catch (e) {
        Log.e('paymentStatusStream poll: $e');
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller.onListen = () {
      scheduleMicrotask(() async {
        await poll();
        timer = Timer.periodic(const Duration(seconds: 12), (_) => poll());
      });
    };
    controller.onCancel = () {
      timer?.cancel();
    };
    return controller.stream;
  }

  static bool _premiumFromUserData(Map<String, dynamic>? data) {
    if (data == null) return false;
    final tier = (data['membership_tier'] as String? ?? '').toLowerCase();
    if (tier == 'platinum' || tier == 'premium') {
      final expiryStr = (data['membership_expiry_date'] as String?)?.trim();
      if (expiryStr == null || expiryStr.isEmpty) return false;
      final expiry = DateTime.tryParse(expiryStr);
      if (expiry == null || !expiry.isAfter(DateTime.now())) return false;
      return true;
    }
    return false;
  }

  /// Check if user is premium by reading from Firestore
  /// Uses real user doc ID from SharedPreferences
  Future<bool> isPremium({bool forceRefresh = false}) async {
    final realUserId = await _getRealUserId();
    if (realUserId == null || realUserId.isEmpty) return false;

    if (!forceRefresh) {
      final hit = _premiumStatusCache.get(realUserId);
      if (hit != null) return hit;
    }

    try {
      final doc =
          await getDocumentCachedFirst(_db.collection(Collections.users).doc(realUserId));

      if (!doc.exists) {
        _premiumStatusCache.set(realUserId, false);
        return false;
      }

      final data = doc.data();
      final v = _premiumFromUserData(data);
      _premiumStatusCache.set(realUserId, v);
      return v;
    } catch (e) {
      Log.e('Error checking premium status: $e');
      return false;
    }
  }

  /// Premium flag polled on a TTL — avoids a permanent user-doc snapshot listener.
  Stream<bool> premiumStatusStream() {
    final controller = StreamController<bool>();
    Timer? timer;

    Future<void> emit({bool force = false}) async {
      final v = await isPremium(forceRefresh: force);
      if (!controller.isClosed) controller.add(v);
    }

    controller.onListen = () {
      scheduleMicrotask(() async {
        await emit();
        timer = Timer.periodic(const Duration(minutes: 5), (_) => emit(force: true));
      });
    };
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  static int _paymentHistorySortDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ma = _paymentCreatedMillis(a);
    final mb = _paymentCreatedMillis(b);
    return mb.compareTo(ma);
  }

  static int _paymentCreatedMillis(Map<String, dynamic> m) {
    final v = m['created_at'] ?? m['verified_at'] ?? m['captured_at'] ?? m['paid_at'];
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    return 0;
  }

  Future<List<Map<String, dynamic>>> _fetchPaymentHistoryFromFirestore(
    String realUserId,
  ) async {
    final byKey = <String, Map<String, dynamic>>{};

    Future<void> addRequests(String userKey, String userVal) async {
      final snapshot = await _db
          .collection('payment_requests')
          .where('user_id', isEqualTo: userVal)
          .orderBy('created_at', descending: true)
          .get();
      for (final doc in snapshot.docs) {
        byKey['pr:$userKey:${doc.id}'] = {
          'id': doc.id,
          ...doc.data(),
          '_source': 'payment_requests',
        };
      }
    }

    await addRequests('doc', realUserId);

    if (realUserId.isNotEmpty) {
      final paySnap = await _db
          .collection('payments')
          .where('profile_id', isEqualTo: realUserId)
          .orderBy('created_at', descending: true)
          .get();
      for (final doc in paySnap.docs) {
        byKey['pay:${doc.id}'] = {
          'id': doc.id,
          ...doc.data(),
          '_source': 'payments',
        };
      }
    }

    final out = byKey.values.toList()..sort(_paymentHistorySortDesc);
    return out;
  }

  /// Get payment history for current user
  /// Uses IdentityService for consistent identity
  Future<List<Map<String, dynamic>>> getPaymentHistory({
    bool forceRefresh = false,
  }) async {
    final identityService = IdentityService();
    final userId = await identityService.getUserId();
    if (userId.isEmpty) {
      throw Exception('User not logged in');
    }

    final realUserId = userId;

    if (!forceRefresh) {
      final cached = _paymentHistoryCache.get(realUserId);
      if (cached != null) {
        return List<Map<String, dynamic>>.from(cached);
      }
    }

    try {
      final out = await _fetchPaymentHistoryFromFirestore(realUserId);
      _paymentHistoryCache.set(realUserId, out);
      return out;
    } catch (e) {
      Log.e('Failed to fetch payment history: $e');
      return [];
    }
  }

  /// Periodic one-shot reloads (TTL) instead of query snapshot listeners.
  Stream<List<Map<String, dynamic>>> paymentHistoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    final controller = StreamController<List<Map<String, dynamic>>>();
    Timer? timer;

    Future<void> pump({bool force = false}) async {
      try {
        final list = await getPaymentHistory(forceRefresh: force);
        if (!controller.isClosed) controller.add(list);
      } catch (e, st) {
        Log.e('paymentHistoryStream: $e');
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller.onListen = () {
      scheduleMicrotask(() async {
        await pump();
        timer = Timer.periodic(_kPaymentHistoryTtl, (_) => pump(force: true));
      });
    };
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  /// Reset state
  void reset() {
    _isProcessing = false;
    _lastError = null;
    _lastPaymentResult = null;
    notifyListeners();
  }
}
