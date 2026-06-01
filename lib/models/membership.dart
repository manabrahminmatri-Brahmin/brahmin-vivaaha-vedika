import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../services/plan_service.dart' show SubscriptionPlan;

/// Membership tiers for the app
enum MembershipTier {
  free,      // Unlimited viewing, no contact
  platinum,  // Premium tier — pricing from PlanService / Firestore
}

/// Membership model for user subscription
class Membership {
  final MembershipTier tier;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final String? transactionId;
  final String? paymentMethod;
  final double? amountPaid;
  final int? contactsUsed; // For silver/gold tiers

  Membership({
    this.tier = MembershipTier.free,
    this.startDate,
    this.expiryDate,
    this.transactionId,
    this.paymentMethod,
    this.amountPaid,
    this.contactsUsed,
  });

  /// Check if premium membership is active
  bool get isPremium {
    if (tier != MembershipTier.free) {
      if (expiryDate == null) return true;
      return DateTime.now().isBefore(expiryDate!);
    }
    // Paid expiry on file but tier not synced (common after admin/payment updates).
    if (expiryDate != null && DateTime.now().isBefore(expiryDate!)) {
      return true;
    }
    return false;
  }

  /// Check if membership is expired
  bool get isExpired {
    if (tier == MembershipTier.free) return false;
    if (expiryDate == null) return true;
    return DateTime.now().isAfter(expiryDate!);
  }

  /// Days remaining in premium
  int get daysRemaining {
    if (!isPremium || expiryDate == null) return 0;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  /// Get monthly contact limit based on tier
  int get monthlyContactLimit {
    switch (tier) {
      case MembershipTier.free:
        return 0;
      case MembershipTier.platinum:
        return -1; // Unlimited
    }
  }

  /// Check if user has advanced matching access
  bool get hasAdvancedMatching => tier == MembershipTier.platinum;

  /// Check if user can send more contacts this month
  bool canSendMoreContacts() {
    if (tier == MembershipTier.platinum) return true; // Unlimited
    if (tier == MembershipTier.free) return false;
    return (contactsUsed ?? 0) < monthlyContactLimit;
  }

  /// Get remaining contacts for this month
  int get remainingContacts {
    if (tier == MembershipTier.platinum) return -1; // Unlimited
    if (tier == MembershipTier.free) return 0;
    return monthlyContactLimit - (contactsUsed ?? 0);
  }

  /// Membership pricing (fallback - actual prices from Firebase)
  static const Map<MembershipTier, double> monthlyRates = {
    MembershipTier.free: 0.0,         // Free
    MembershipTier.platinum: 99.0,   // Display hint; live prices from PlanService
  };

  static const Map<MembershipTier, double> yearlyRates = {
    MembershipTier.free: 0.0,         // Free
    MembershipTier.platinum: 1188.0,   // ₹1188 per year (12M plan)
  };

  Membership copyWith({
    MembershipTier? tier,
    DateTime? startDate,
    DateTime? expiryDate,
    String? transactionId,
    String? paymentMethod,
    double? amountPaid,
    int? contactsUsed,
  }) {
    return Membership(
      tier: tier ?? this.tier,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      transactionId: transactionId ?? this.transactionId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountPaid: amountPaid ?? this.amountPaid,
      contactsUsed: contactsUsed ?? this.contactsUsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'startDate': startDate?.toIso8601String(),
        'expiryDate': expiryDate?.toIso8601String(),
        'transactionId': transactionId,
        'paymentMethod': paymentMethod,
        'amountPaid': amountPaid,
        'contactsUsed': contactsUsed,
      };

  factory Membership.fromJson(Map<String, dynamic> json) {
    // Support both camelCase (membership_json) and snake_case (flat Firestore fields).
    // Always lowercase tier before matching so 'Free', 'FREE', 'free' all work.
    final tierRaw = (json['tier'] as String?
            ?? json['membership_tier'] as String?
            ?? 'free')
        .toLowerCase()
        .trim();

    String? asDateString(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return raw;
      if (raw is DateTime) return raw.toIso8601String();
      if (raw is Timestamp) return raw.toDate().toIso8601String();
      return raw.toString();
    }

    final expiryRaw = asDateString(
      json['expiryDate'] ?? json['membership_expires_at'] ?? json['membership_expiry_date'],
    );

    final startRaw = asDateString(
      json['startDate'] ?? json['membership_start_date'],
    );

    return Membership(
      tier: MembershipTier.values.firstWhere(
        (t) => t.name == tierRaw,
        orElse: () => MembershipTier.free,
      ),
      startDate: startRaw != null ? DateTime.tryParse(startRaw) : null,
      expiryDate: expiryRaw != null ? DateTime.tryParse(expiryRaw) : null,
      transactionId: json['transactionId'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      amountPaid: (json['amountPaid'] as num?)?.toDouble(),
      contactsUsed: json['contactsUsed'] as int?,
    );
  }

  /// Free membership (default)
  factory Membership.free() => Membership(tier: MembershipTier.free);

  /// Platinum membership for given days
  factory Membership.platinum({
    required int days,
    required String transactionId,
    required double amount,
    String paymentMethod = 'UPI',
  }) {
    final now = DateTime.now();
    return Membership(
      tier: MembershipTier.platinum,
      startDate: now,
      expiryDate: now.add(Duration(days: days)),
      transactionId: transactionId,
      paymentMethod: paymentMethod,
      amountPaid: amount,
      contactsUsed: 0,
    );
  }
}

/// Membership plan options
class MembershipPlan {
  final String id;
  final String name;
  final MembershipTier tier;
  final int days;
  final double price;
  final double? originalPrice;
  final String description;
  final bool isPopular;
  final List<String> features;

  const MembershipPlan({
    this.id = '',
    required this.name,
    required this.tier,
    required this.days,
    required this.price,
    this.originalPrice,
    required this.description,
    this.isPopular = false,
    required this.features,
  });

  double get savings => originalPrice != null ? originalPrice! - price : 0;
  double get dailyRate => price / days;

  /// Default fallback plans if Firebase fetch fails
  /// Fallback only when PlanService has not hydrated (avoid hardcoding in UI).
  /// Prices: 1M=₹99, 3M=₹297, 6M=₹594, 12M=₹1188
  static const List<MembershipPlan> defaultPlans = [
    // Free Plan
    MembershipPlan(
      id: 'free',
      name: 'Free',
      tier: MembershipTier.free,
      days: 365, // 1 year
      price: 0,
      description: 'Browse profiles, upgrade to connect',
      features: [
        'View all profile details',
        'Profile photos are blurred (Premium to unlock)',
        'View "About Me" section',
        'Basic sorting & filtering',
        'Edit profile anytime',
        'Receive interest requests',
      ],
    ),
    // Platinum Plans - New pricing structure
    MembershipPlan(
      id: 'platinum_1m',
      name: 'Platinum 1 Month',
      tier: MembershipTier.platinum,
      days: 30,
      price: 99,
      originalPrice: 499,
      description: 'Complete access to all features',
      isPopular: false,
      features: [
        'Unlimited contact requests',
        'Direct WhatsApp messaging',
        'Advanced compatibility matching',
        'Priority profile visibility',
        'View contact information',
        'Access Community Heads details',
        'Community reference requests',
        'Send interest',
        'Profile highlighter',
        'Read receipts for messages',
        'Advanced filters',
        'Incognito mode',
      ],
    ),
    MembershipPlan(
      id: 'platinum_3m',
      name: 'Platinum 3 Months',
      tier: MembershipTier.platinum,
      days: 90,
      price: 297,
      originalPrice: 1497,
      description: '3 months premium access',
      isPopular: true,
      features: [
        'Unlimited contact requests',
        'Direct WhatsApp messaging',
        'Advanced compatibility matching',
        'Priority profile visibility',
        'View contact information',
        'Access Community Heads details',
        'Community reference requests',
        'Send interest',
        'Profile highlighter',
        'Read receipts for messages',
        'Advanced filters',
        'Incognito mode',
      ],
    ),
    MembershipPlan(
      id: 'platinum_6m',
      name: 'Platinum 6 Months',
      tier: MembershipTier.platinum,
      days: 180,
      price: 594,
      originalPrice: 2994,
      description: '6 months premium access',
      features: [
        'Unlimited contact requests',
        'Direct WhatsApp messaging',
        'Advanced compatibility matching',
        'Priority profile visibility',
        'View contact information',
        'Access Community Heads details',
        'Community reference requests',
        'Send interest',
        'Profile highlighter',
        'Read receipts for messages',
        'Advanced filters',
        'Incognito mode',
      ],
    ),
    MembershipPlan(
      id: 'platinum_12m',
      name: 'Platinum 12 Months',
      tier: MembershipTier.platinum,
      days: 365,
      price: 1188,
      originalPrice: 5988,
      description: '12 months premium access',
      features: [
        'Unlimited contact requests',
        'Direct WhatsApp messaging',
        'Advanced compatibility matching',
        'Priority profile visibility',
        'View contact information',
        'Access Community Heads details',
        'Community reference requests',
        'Send interest',
        'Profile highlighter',
        'Read receipts for messages',
        'Advanced filters',
        'Incognito mode',
      ],
    ),
  ];

  /// Dynamic plans list - populated from Firebase
  static List<MembershipPlan> _plans = [];
  static List<MembershipPlan> get plans => _plans.isNotEmpty ? _plans : defaultPlans;
  static set plans(List<MembershipPlan> value) => _plans = value;

  /// Create MembershipPlan from Firebase document data
  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    final featuresList = json['features'] as List<dynamic>?;
    return MembershipPlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Plan',
      tier: MembershipTier.values.firstWhere(
        (t) => t.name == (json['tier'] as String? ?? 'platinum'),
        orElse: () => MembershipTier.platinum,
      ),
      days: json['days'] as int? ?? 30,
      price: (json['price'] as num?)?.toDouble() ?? 99.0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ??
          (json['originalPrice'] as num?)?.toDouble(),
      description: json['description'] as String? ?? '',
      isPopular: json['is_popular'] as bool? ?? json['isPopular'] as bool? ?? false,
      features: featuresList?.cast<String>() ?? defaultPlans.firstWhere(
        (p) => p.tier == MembershipTier.platinum,
        orElse: () => defaultPlans[1],
      ).features,
    );
  }

  /// Convert to JSON for Firebase storage
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tier': tier.name,
        'days': days,
        'price': price,
        'original_price': originalPrice,
        'description': description,
        'is_popular': isPopular,
        'features': features,
        'is_active': true,
        'sort_order': days,
      };
}

/// Maps Firestore [SubscriptionPlan] rows to legacy [MembershipPlan] for Razorpay UI.
extension SubscriptionPlanMembershipMapping on SubscriptionPlan {
  int get _approxDays {
    switch (durationMonths) {
      case 1:
        return 30;
      case 3:
        return 90;
      case 6:
        return 180;
      case 12:
        return 365;
      default:
        return (durationMonths * 30).clamp(1, 9999);
    }
  }

  MembershipPlan toMembershipPlanForCheckout() {
    return MembershipPlan(
      id: id,
      name: name,
      tier: MembershipTier.platinum,
      days: _approxDays,
      price: discountedFee,
      originalPrice: actualFee > discountedFee ? actualFee : null,
      description: description,
      isPopular: isPopular,
      features: List<String>.from(features),
    );
  }
}

/// Features available by membership tier
class MembershipFeatures {
  /// Free member features
  static const List<String> freeFeatures = [
    'Create & complete profile',
    'Browse unlimited profiles',
    'View all profile details',
    'Profile photos are blurred',
    'View "About Me" section',
    'Contact information is hidden',
    'Basic sorting & filtering',
    'Edit profile anytime',
    'Receive interest requests',
    'See star compatibility score',
  ];

  /// Features NOT available for free members
  static const List<String> freeRestrictions = [
    'Cannot send interest',
    'Cannot send contact requests',
    'Cannot view actual contact details',
    'Profile photos are blurred — upgrade to see clearly',
    'No Community Heads access',
    'No community reference requests',
    'Limited to basic matching',
    'No WhatsApp direct messaging',
    'No incognito mode',
  ];

  /// Platinum member features
  static const List<String> platinumFeatures = [
    'All Free features',
    'Send interest to profiles',
    'Unlimited contact requests',
    'Direct WhatsApp messaging',
    'Advanced AI matching',
    'View full profile photos',
    'See contact details (phone/email)',
    'Access Community Heads details',
    'Community reference requests',
    'Incognito browsing mode',
    'Priority profile listing',
    'Instant notifications',
    'VIP customer support',
  ];

  /// Get features by tier
  static List<String> getFeaturesByTier(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return freeFeatures;
      case MembershipTier.platinum:
        return platinumFeatures;
    }
  }

  /// Get tier display name
  static String getTierDisplayName(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return 'Free';
      case MembershipTier.platinum:
        return 'Platinum';
    }
  }

  /// Get tier color
  static String getTierColor(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return '#9E9E9E'; // Grey
      case MembershipTier.platinum:
        return '#E5E4E2'; // Platinum
    }
  }
}
