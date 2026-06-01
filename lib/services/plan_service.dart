import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Subscription Plan Model with actual and discounted pricing
class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final int durationMonths;
  final double actualFee;
  final double discountedFee;
  final List<String> features;
  final bool isPopular;
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, dynamic>? metadata;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMonths,
    required this.actualFee,
    required this.discountedFee,
    required this.features,
    this.isPopular = false,
    this.isActive = true,
    this.validFrom,
    this.validUntil,
    this.metadata,
  });

  /// Calculate discount percentage
  int get discountPercentage {
    if (actualFee <= 0) return 0;
    final discount = ((actualFee - discountedFee) / actualFee * 100).round();
    return discount > 0 ? discount : 0;
  }

  /// Get display amount (discounted fee)
  double get displayAmount => discountedFee;

  /// Get formatted duration string
  String get durationDisplay {
    switch (durationMonths) {
      case 1:
        return '1 Month';
      case 3:
        return '3 Months';
      case 6:
        return '6 Months';
      case 12:
        return '1 Year';
      default:
        return '$durationMonths Months';
    }
  }

  /// Get savings amount
  double get savingsAmount => actualFee - discountedFee;

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'duration_months': durationMonths,
      'actual_fee': actualFee,
      'discounted_fee': discountedFee,
      'features': features,
      'is_popular': isPopular,
      'is_active': isActive,
      'valid_from': validFrom?.toIso8601String(),
      'valid_until': validUntil?.toIso8601String(),
      'metadata': metadata,
    };
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  /// Create from Firestore document
  factory SubscriptionPlan.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SubscriptionPlan(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      durationMonths: (data['duration_months'] as num?)?.toInt() ?? 1,
      actualFee: (data['actual_fee'] as num?)?.toDouble() ?? 0,
      discountedFee: (data['discounted_fee'] as num?)?.toDouble() ?? 0,
      features: List<String>.from(data['features'] ?? const []),
      isPopular: data['is_popular'] == true,
      isActive: data['is_active'] != false,
      validFrom: _parseDate(data['valid_from']),
      validUntil: _parseDate(data['valid_until']),
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  /// Create from Map (for backward compatibility)
  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlan(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      durationMonths:
          (map['durationMonths'] ?? map['duration_months'] as num?)?.toInt() ??
              1,
      actualFee: (map['actual_fee'] as num?)?.toDouble() ?? 0,
      discountedFee: (map['discounted_fee'] as num?)?.toDouble() ?? 0,
      features: List<String>.from(map['features'] ?? const []),
      isPopular: map['is_popular'] == true,
      isActive: map['is_active'] != false,
      validFrom: _parseDate(map['validFrom'] ?? map['valid_from']),
      validUntil: _parseDate(map['validUntil'] ?? map['valid_until']),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
    );
  }
}

/// Plan Service — realtime [subscription_plans] + admin CRUD.
class PlanService extends ChangeNotifier {
  static PlanService? _instance;
  static PlanService get instance => _instance ??= PlanService._internal();

  PlanService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<SubscriptionPlan> _plans = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _plansSubscription;
  bool _autoSeedAttempted = false;

  List<SubscriptionPlan> get plans => List.unmodifiable(_plans);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Active plans sorted by duration (for checkout / paywall).
  List<SubscriptionPlan> get activePlans {
    final now = DateTime.now();
    return _plans
        .where((p) => p.isActive)
        .where((p) => p.validFrom == null || p.validFrom!.isBefore(now))
        .where((p) => p.validUntil == null || p.validUntil!.isAfter(now))
        .toList()
      ..sort((a, b) => a.durationMonths.compareTo(b.durationMonths));
  }

  SubscriptionPlan? getPlanById(String id) {
    try {
      return _plans.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  SubscriptionPlan? getPlanByDuration(int months) {
    try {
      return _plans.firstWhere(
        (p) => p.durationMonths == months && p.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// One-shot fetch (e.g. legacy callers). Prefer [startListening] for live data.
  Future<void> loadPlans({bool force = false}) async {
    try {
      if (!force && _plans.isNotEmpty && _plansSubscription != null) {
        notifyListeners();
        return;
      }
      _isLoading = true;
      _error = null;
      notifyListeners();

      final snapshot = await _db
          .collection('subscription_plans')
          .orderBy('duration_months')
          .get();

      var list = snapshot.docs.map(SubscriptionPlan.fromFirestore).toList();
      if (list.isEmpty) {
        await _tryAutoSeedIfEmpty();
        final snap2 = await _db
            .collection('subscription_plans')
            .orderBy('duration_months')
            .get();
        list = snap2.docs.map(SubscriptionPlan.fromFirestore).toList();
      }
      _applyPlansList(list);
    } catch (e) {
      _error = 'Failed to load plans: $e';
      _applyPlansList(getDefaultPlans());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyPlansList(List<SubscriptionPlan> list) {
    if (list.isEmpty) {
      _plans = List<SubscriptionPlan>.from(getDefaultPlans());
      _error ??= 'Using offline default plans';
    } else {
      _plans = List<SubscriptionPlan>.from(list);
    }
  }

  Future<void> _tryAutoSeedIfEmpty() async {
    if (_autoSeedAttempted) return;
    _autoSeedAttempted = true;
    try {
      await seedDefaultPlans();
    } catch (e) {
      debugPrint('PlanService auto-seed skipped/failed: $e');
    }
  }

  /// Realtime listener — replaces periodic polling + TTL cache for plans.
  void startListening() {
    stopListening();
    _isLoading = true;
    _error = null;
    notifyListeners();

    _plansSubscription = _db
        .collection('subscription_plans')
        .orderBy('duration_months')
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) async {
        final list = snapshot.docs.map(SubscriptionPlan.fromFirestore).toList();

        if (list.isEmpty) {
          await _tryAutoSeedIfEmpty();
          _plans = List<SubscriptionPlan>.from(getDefaultPlans());
          _isLoading = false;
          _error ??= 'No plans in Firestore yet — showing defaults until synced';
          notifyListeners();
          return;
        }

        _autoSeedAttempted = false;
        _plans = list;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('PlanService stream error: $e');
        _error = e.toString();
        _applyPlansList(getDefaultPlans());
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void stopListening() {
    _plansSubscription?.cancel();
    _plansSubscription = null;
  }

  /// Force-refresh from server (clears error flag; stream keeps emitting).
  Future<void> refresh() async {
    _error = null;
    notifyListeners();
    await loadPlans(force: true);
  }

  /// Same as [seedDefaultPlans] — explicit admin label.
  Future<void> deployPlans() => seedDefaultPlans();

  /// Seed default plans to Firebase (admin / first deploy).
  Future<void> seedDefaultPlans() async {
    final defaultPlans = getDefaultPlans();
    final batch = _db.batch();

    for (final plan in defaultPlans) {
      final docRef = _db.collection('subscription_plans').doc(plan.id);
      batch.set(docRef, plan.toMap(), SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> createPlan(SubscriptionPlan plan) async {
    if (plan.id.trim().isEmpty) {
      throw ArgumentError('plan.id is required');
    }
    await _db
        .collection('subscription_plans')
        .doc(plan.id)
        .set(plan.toMap(), SetOptions(merge: false));
  }

  Future<void> updatePlan({
    required String planId,
    String? name,
    double? actualFee,
    double? discountedFee,
    int? durationMonths,
    bool? isActive,
    bool? isPopular,
    String? description,
    List<String>? features,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (actualFee != null) updates['actual_fee'] = actualFee;
    if (discountedFee != null) updates['discounted_fee'] = discountedFee;
    if (durationMonths != null) updates['duration_months'] = durationMonths;
    if (isActive != null) updates['is_active'] = isActive;
    if (isPopular != null) updates['is_popular'] = isPopular;
    if (description != null) updates['description'] = description;
    if (features != null) updates['features'] = features;
    if (updates.isEmpty) return;
    await _db.collection('subscription_plans').doc(planId).update(updates);
  }

  Future<void> deletePlan(String planId) async {
    await _db.collection('subscription_plans').doc(planId).delete();
  }

  /// Fallback plans if Firestore is unavailable or empty (after failed seed).
  static List<SubscriptionPlan> getDefaultPlans() {
    return const [
      SubscriptionPlan(
        id: 'monthly',
        name: 'Monthly Premium',
        description: '1 month access to all premium features',
        durationMonths: 1,
        actualFee: 99.0,
        discountedFee: 99.0,
        features: [
          'View all profiles',
          'Send interest',
          'Chat with matches',
          'View contact details',
          'Priority support',
        ],
      ),
      SubscriptionPlan(
        id: 'quarterly',
        name: '3-Month Premium',
        description: '3 months access - Best value!',
        durationMonths: 3,
        actualFee: 297.0,
        discountedFee: 297.0,
        features: [
          'View all profiles',
          'Send interest',
          'Chat with matches',
          'View contact details',
          'Priority support',
          'Profile highlight',
        ],
        isPopular: true,
      ),
      SubscriptionPlan(
        id: 'half_yearly',
        name: '6-Month Premium',
        description: '6 months access - Great savings!',
        durationMonths: 6,
        actualFee: 594.0,
        discountedFee: 594.0,
        features: [
          'View all profiles',
          'Send interest',
          'Chat with matches',
          'View contact details',
          'Priority support',
          'Profile highlight',
          'Premium badge',
        ],
      ),
      SubscriptionPlan(
        id: 'yearly',
        name: 'Yearly Premium',
        description: '1 year access - Maximum value!',
        durationMonths: 12,
        actualFee: 1188.0,
        discountedFee: 1188.0,
        features: [
          'View all profiles',
          'Send interest',
          'Chat with matches',
          'View contact details',
          'Priority support',
          'Profile highlight',
          'Premium badge',
          'Featured profile',
          'Dedicated support',
        ],
      ),
    ];
  }
}

extension SubscriptionPlanLegacy on SubscriptionPlan {
  Map<String, dynamic> toLegacyPlan() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'amount': discountedFee,
      'duration': durationDisplay,
      'popular': isPopular,
      'discount': discountPercentage > 0 ? '$discountPercentage%' : null,
      'actualFee': actualFee,
      'discountedFee': discountedFee,
    };
  }
}
