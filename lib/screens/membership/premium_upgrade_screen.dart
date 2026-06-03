import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_firebase_functions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../models/membership.dart';
import '../../services/auth_service.dart';
import '../../services/plan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/whatsapp_channel_card.dart';
import '../../utils/app_animations.dart';
import '../../core/app_router.dart';

/// Premium membership upgrade screen with tier-based plans.
///
/// Payment flow (Razorpay gateway):
///   1. User selects a plan and accepts policy confirmations
///   2. App calls Cloud Function `createRazorpayOrder`
///   3. Razorpay checkout opens with UPI/Card/Netbanking options
///   4. App verifies signature via `verifyRazorpayPayment`
///   5. Cloud Function updates payment status and activates membership
///
/// **Platform note:** `razorpay_flutter` only implements Android/iOS. On Windows,
/// macOS, Linux, or web, the plugin channel has no native implementation.
bool _razorpayNativeCheckoutAvailable() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

class PremiumUpgradeScreen extends StatefulWidget {
  final VoidCallback? onUpgradeComplete;

  const PremiumUpgradeScreen({
    super.key,
    this.onUpgradeComplete,
  });

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  /// Pre-select Platinum so duration + pay CTA are visible without an extra tap.
  MembershipTier? _selectedTier = MembershipTier.platinum;
  int _selectedPlanIndex = 0;
  bool _isGatewayProcessing = false;
  Razorpay? _razorpay;
  Completer<PaymentSuccessResponse>? _paymentCompleter;

  @override
  void initState() {
    super.initState();
    PlanService.instance.startListening();
    _initializeRazorpay();
  }

  void _initializeRazorpay() {
    if (!_razorpayNativeCheckoutAvailable()) {
      _razorpay = null;
      return;
    }
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (response) {
      final typed = response as PaymentSuccessResponse;
      _paymentCompleter?.complete(typed);
      _paymentCompleter = null;
    });
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (response) {
      final typed = response as PaymentFailureResponse;
      _paymentCompleter?.completeError(
        Exception(typed.message ?? 'Payment failed. Please try again.'),
      );
      _paymentCompleter = null;
    });
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
      _paymentCompleter?.completeError(
        Exception(
            'External wallet selected. Please complete the payment and retry.'),
      );
      _paymentCompleter = null;
    });
  }

  /// Plans for [tier] — platinum rows come from [PlanService.activePlans] (Firestore).
  List<MembershipPlan> _plansForTier(MembershipTier tier) {
    if (tier == MembershipTier.free) {
      return MembershipPlan.defaultPlans
          .where((p) => p.tier == MembershipTier.free)
          .toList();
    }
    final live = PlanService.instance.activePlans;
    if (live.isNotEmpty) {
      return live.map((s) => s.toMembershipPlanForCheckout()).toList();
    }
    return MembershipPlan.defaultPlans
        .where((p) => p.tier == MembershipTier.platinum)
        .toList();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  String _rupees(double amount) => amount.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(title: 'Choose Your Plan', showLogo: true),
      body: AnimatedBuilder(
        animation: PlanService.instance,
        builder: (context, _) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(children: [
              _buildHeader(context).appSlideIn(),
              const SizedBox(height: 32),
              _buildTierSelection(context)
                  .appFadeIn(delay: const Duration(milliseconds: 100)),
              const SizedBox(height: 32),
              if (_selectedTier != null)
                _buildPlansSection(context)
                    .appFadeIn(delay: const Duration(milliseconds: 200)),
              const SizedBox(height: 32),
              _buildFeaturesComparison(context)
                  .appFadeIn(delay: const Duration(milliseconds: 300)),
              const SizedBox(height: 16),
              const WhatsAppChannelCard(compact: true)
                  .appFadeIn(delay: const Duration(milliseconds: 350)),
              const SizedBox(height: 32),
              if (_selectedTier != null)
                _buildPaymentButton(context)
                    .appFadeIn(delay: const Duration(milliseconds: 400)),
              const SizedBox(height: 40),
            ]),
          );
        },
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primaryOrange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AC.card(context).withValues(alpha: 0.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Icon(Icons.diamond, size: 48, color: AC.card(context)),
        ),
        const SizedBox(height: 16),
        Text('Unlock Premium Features',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AC.card(context)),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Premium unlocks:\n💌 Send interest  •  🔓 Clear photos  •  📞 Contact details\n👀 Who viewed you  •  👥 Community refs  •  📅 Birth details  •  🔒 Incognito',
          style: TextStyle(fontSize: 15, color: AC.card(context), height: 1.5),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  // ── Tier selection ─────────────────────────────────────────────────────────
  Widget _buildTierSelection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Select Membership Tier',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AC.text(context))),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _buildTierCard(MembershipTier.free)),
          const SizedBox(width: 12),
          Expanded(child: _buildTierCard(MembershipTier.platinum)),
        ]),
      ]),
    );
  }

  Widget _buildTierCard(MembershipTier tier) {
    final isSelected = _selectedTier == tier;
    final tierName = MembershipFeatures.getTierDisplayName(tier);
    final tierColor = MembershipFeatures.getTierColor(tier);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedTier = tier;
        _selectedPlanIndex = 0;
      }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryOrange.withValues(alpha: 0.1)
              : Colors.white,
          border: Border.all(
            color: isSelected ? AppTheme.primaryOrange : AC.border(context),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(int.parse(tierColor.replaceFirst('#', '0xFF'))),
              shape: BoxShape.circle,
            ),
            child: Icon(_getTierIcon(tier), color: AC.card(context), size: 20),
          ),
          const SizedBox(height: 8),
          Text(tierName,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color:
                      isSelected ? AppTheme.primaryOrange : AC.text(context))),
          const SizedBox(height: 4),
          Text(_getTierPrice(tier),
              style: TextStyle(fontSize: 12, color: AC.textSub(context))),
        ]),
      ),
    );
  }

  // ── Plans section ──────────────────────────────────────────────────────────
  Widget _buildPlansSection(BuildContext context) {
    if (_selectedTier == null) return const SizedBox.shrink();
    if (PlanService.instance.isLoading &&
        PlanService.instance.activePlans.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final plans = _plansForTier(_selectedTier!);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Choose Duration',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AC.text(context))),
        const SizedBox(height: 16),
        ...plans.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPlanCard(entry.value, entry.key),
            )),
      ]),
    );
  }

  Widget _buildPlanCard(MembershipPlan plan, int index) {
    final isSelected = _selectedPlanIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlanIndex = index),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryOrange.withValues(alpha: 0.1)
              : Colors.white,
          border: Border.all(
            color: isSelected ? AppTheme.primaryOrange : AC.border(context),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isSelected ? AppTheme.primaryOrange : AppTheme.textLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(plan.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppTheme.primaryOrange
                            : AC.text(context))),
                if (plan.isPopular) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('POPULAR',
                        style: TextStyle(
                            fontSize: 11,
                            color: AC.card(context),
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(plan.description,
                  style: TextStyle(fontSize: 14, color: AC.textSub(context))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${_rupees(plan.price)}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? AppTheme.primaryOrange
                        : AC.text(context))),
            if (plan.originalPrice != null) ...[
              const SizedBox(height: 4),
              Text(
                '₹${_rupees(plan.originalPrice!)}',
                style: TextStyle(
                  fontSize: 14,
                  color: AC.textMuted(context),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  // ── Features comparison ────────────────────────────────────────────────────
  Widget _buildFeaturesComparison(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Features Comparison',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AC.text(context))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.diamond, color: AC.card(context), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Premium-only: Photos are blurred for Free users. Upgrade to see clearly & connect!',
                style: TextStyle(
                    color: AC.card(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Expanded(
                    flex: 2,
                    child: Text('Feature',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AC.text(context)))),
                Expanded(
                    child: Text('Free',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AC.text(context)))),
                Expanded(
                    child: Text('Platinum',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AC.text(context)))),
              ]),
            ),
            const Divider(height: 1),
            _buildFeatureRow('View Profile Details', true, true),
            _buildFeatureRow('Basic Search & Filters', true, true),
            _buildFeatureRow('Receive Interest Requests', true, true),
            _buildFeatureRow('Liked Profiles', true, true),
            _buildFeatureRow('Profile Analytics', true, true),
            _buildFeatureRow('Compatibility Matching', true, true),
            const Divider(height: 1),
            _buildFeatureRow('Send Interest', false, true, isPremium: true),
            _buildFeatureRow('3D Discover Carousel', false, true,
                isPremium: true),
            _buildFeatureRow('Profile Photos', 'Blurred', true,
                isPremium: true),
            _buildFeatureRow('Contact Details', false, true, isPremium: true),
            _buildFeatureRow('Who Saw Your Profile', 'Count Only', true,
                isPremium: true),
            _buildFeatureRow('Community References', false, true,
                isPremium: true),
            _buildFeatureRow('Birth Details', false, true, isPremium: true),
            _buildFeatureRow('Incognito Mode', false, true, isPremium: true),
          ]),
        ),
      ]),
    );
  }

  Widget _buildFeatureRow(String feature, dynamic free, dynamic platinum,
      {bool isPremium = false}) {
    return Container(
      color: isPremium ? AppTheme.primaryOrange.withAlpha(10) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Row(
                children: [
                  if (isPremium)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.diamond,
                        size: 14,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  Expanded(
                    child: Text(feature,
                        style: TextStyle(
                          fontSize: 14,
                          color: AC.text(context),
                          fontWeight:
                              isPremium ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ),
                ],
              )),
          Expanded(child: _buildFeatureCell(free)),
          Expanded(child: _buildFeatureCell(platinum)),
        ]),
      ),
    );
  }

  Widget _buildFeatureCell(dynamic value) {
    if (value is bool) {
      return Icon(
        value ? Icons.check_circle : Icons.cancel,
        color: value ? Colors.green : Colors.red,
        size: 20,
      );
    } else if (value is String) {
      // Special 'Blurred' cell — amber warning style
      if (value == 'Blurred') {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_on, size: 18, color: Colors.amber.shade700),
            const SizedBox(height: 2),
            Text(
              'Blurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade800),
            ),
          ],
        );
      }
      return Text(value,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AC.textSub(context)));
    }
    return const SizedBox.shrink();
  }

  // ── Pay button ─────────────────────────────────────────────────────────────
  Widget _buildPaymentButton(BuildContext context) {
    if (_selectedTier == null) return const SizedBox.shrink();
    final plans = _plansForTier(_selectedTier!);
    if (plans.isEmpty) return const SizedBox.shrink();
    final idx = min(_selectedPlanIndex, plans.length - 1);
    final selectedPlan = plans[idx];
    final payTotal = selectedPlan.price;
    final isPaidPlan = selectedPlan.price > 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (isPaidPlan && !_razorpayNativeCheckoutAvailable()) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                        'In-app payment works on Android and iPhone. '
                        'Please use the mobile app to complete Razorpay checkout.',
                      ),
                      duration: Duration(seconds: 6),
                    ));
                    return;
                  }
                  _showPaymentDialog(context, selectedPlan);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                    isPaidPlan
                        ? 'Pay ₹${_rupees(payTotal)}'
                        : 'Continue with Free Plan',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment Dialog ─────────────────────────────────────────────────────────
  // Shows UPI details, collects UTR, saves record to Firestore for admin verification.
  // Admin will verify UTR against bank records and manually approve/reject the payment.
  void _showPaymentDialog(BuildContext context, MembershipPlan plan) {
    final total = plan.price;
    final isPaidPlan = plan.price > 0;
    final savings = plan.originalPrice != null
        ? plan.originalPrice! - total
        : 0.0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var agreedTerms = false;
        var agreedProceed = false;
        return StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Upgrade to ${plan.name}'),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Amount summary ──────────────────────────────
                  _infoRow('Plan Amount', '₹${_rupees(plan.price)}'),
                  _infoRow('Total Payable', '₹${_rupees(total)}'),
                  _infoRow('Duration', '${plan.days} days'),
                  if (isPaidPlan && savings > 0.5)
                    _infoRow('You save', '₹${_rupees(savings)}'),

                  const SizedBox(height: 16),

                  // ── Payment policy highlights (before UPI) ────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryOrange.withAlpha(70),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.policy_outlined,
                                color: AppTheme.primaryOrange, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment policy — read before you pay',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppTheme.primaryOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _paymentPolicyBullet(
                          ctx,
                          'You pay for premium app features (e.g. contacts, visibility, messaging). We do not guarantee marriage, a match, or responses from other members.',
                        ),
                        _paymentPolicyBullet(
                          ctx,
                          'Membership fees are non-refundable and non-transferable once activated, except the limited cases described in the Payment & Refund Policy.',
                        ),
                        _paymentPolicyBullet(
                          ctx,
                          'Use RBI-approved digital payment methods only (e.g. UPI as below). Keep your UTR / reference for your records.',
                        ),
                        _paymentPolicyBullet(
                          ctx,
                          'Premium access is activated automatically after your payment successfully completes and is confirmed by our system—usually within a short time.',
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => NavHelper.push(
                              context, Routes.paymentRefundPolicy),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label:
                              const Text('Open full Payment & Refund Policy'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Payment gateway box ─────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppTheme.sacredGreen.withAlpha(80)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.shield_outlined,
                                color: AppTheme.sacredGreen, size: 20),
                            const SizedBox(width: 8),
                            Text('Pay via Razorpay (Secure)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.sacredGreen)),
                          ]),
                          const SizedBox(height: 10),
                          _upiRow('Plan', plan.name, copyable: false, ctx: ctx),
                          const SizedBox(height: 4),
                          _upiRow('Amount', '₹${_rupees(total)}',
                              copyable: false, ctx: ctx),
                          const SizedBox(height: 4),
                          _upiRow('Currency', 'INR', copyable: false, ctx: ctx),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '👉 Tap "Pay Securely" to open Razorpay checkout. '
                              'Use UPI, Card, Netbanking, or Wallet and complete payment. '
                              'Premium activates automatically after successful verification.',
                              style: TextStyle(fontSize: 12, height: 1.5),
                            ),
                          ),
                        ]),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.kumkumRed.withAlpha(16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.kumkumRed.withAlpha(45),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppTheme.kumkumRed, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Do not pay unless you accept the policy above. '
                            'Amounts are not refunded after activation except as stated in the policy.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AC.textSub(ctx),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Agreement checkboxes ───────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: agreedTerms,
                        onChanged: (v) => setDlgState(
                          () => agreedTerms = v ?? false,
                        ),
                        activeColor: AppTheme.primaryOrange,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDlgState(
                            () => agreedTerms = !agreedTerms,
                          ),
                          child: Text(
                            'I have read and accept the Terms & Conditions and the Payment & Refund Policy.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: agreedTerms
                                  ? AppTheme.primaryOrange
                                  : AC.text(ctx),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: agreedProceed,
                        onChanged: (v) => setDlgState(
                          () => agreedProceed = v ?? false,
                        ),
                        activeColor: AppTheme.primaryOrange,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDlgState(
                            () => agreedProceed = !agreedProceed,
                          ),
                          child: Text(
                            'I am making this payment voluntarily and agree to continue: '
                            'I understand premium will activate automatically after successful payment completion.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: agreedProceed
                                  ? AppTheme.primaryOrange
                                  : AC.text(ctx),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!(agreedTerms && agreedProceed))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Tick both confirmations above to activate secure payment.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AC.textMuted(ctx),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (agreedTerms && agreedProceed && !_isGatewayProcessing)
                  ? () {
                      Navigator.pop(ctx);
                      _startGatewayPayment(plan);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppTheme.primaryOrange.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              ),
              child: Text(
                _isGatewayProcessing
                    ? 'Processing...'
                    : isPaidPlan
                        ? 'Pay ₹${_rupees(total)} Securely'
                        : 'Continue',
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  // ── Razorpay gateway flow ──────────────────────────────────────────────────
  Future<void> _startGatewayPayment(MembershipPlan plan) async {
    if (_isGatewayProcessing) return;

    if (plan.price > 0 &&
        (!_razorpayNativeCheckoutAvailable() || _razorpay == null)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Razorpay checkout is only available on Android and iPhone. '
          'Use the mobile app to pay.',
        ),
        backgroundColor: AppTheme.kumkumRed,
        duration: Duration(seconds: 6),
      ));
      return;
    }

    setState(() => _isGatewayProcessing = true);

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Preparing secure checkout...'),
        ]),
      ),
    );

    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      if (user == null) throw Exception('Not logged in');

      final createOrderCallable =
          appFirebaseFunctions.httpsCallable('createRazorpayOrder');

      final baseAmount = plan.price;
      final totalAmount = baseAmount;
      final amountInPaise = (totalAmount * 100).round();
      final sub = PlanService.instance.getPlanById(plan.id);
      // Razorpay requires receipt length <= 40.
      final shortReceipt = 'rcpt_${DateTime.now().millisecondsSinceEpoch}';
      final orderResult = await createOrderCallable.call({
        'amount': amountInPaise,
        'currency': 'INR',
        'receipt': shortReceipt,
        'notes': {
          'planId': plan.id,
          'planName': plan.name,
          'planDays': plan.days,
          'durationMonths': sub?.durationMonths ?? (plan.days / 30).round(),
          'actualFee': sub?.actualFee ?? baseAmount,
          'discountedFee': sub?.discountedFee ?? baseAmount,
          'tier': plan.tier.name,
          'baseAmount': baseAmount,
          'totalAmount': totalAmount,
          'userDocId': user.id,
          'mobile': user.mobileNumber,
        },
      });
      final orderData = Map<String, dynamic>.from(orderResult.data);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      _paymentCompleter = Completer<PaymentSuccessResponse>();

      _razorpay?.open({
        'key': orderData['keyId'],
        'amount': orderData['amount'],
        'currency': orderData['currency'],
        'name': 'Mana Vivaaha Vedika',
        'description': plan.name,
        'order_id': orderData['orderId'],
        'timeout': 600,
        'retry': {'enabled': true, 'max_count': 2},
        'prefill': {
          'contact': user.mobileNumber,
          'name': user.profile?.firstName ?? '',
        },
        'theme': {'color': '#F57C00'},
      });

      final paymentResponse = await _paymentCompleter!.future;

      final verifyCallable =
          appFirebaseFunctions.httpsCallable('verifyRazorpayPayment');
      await verifyCallable.call({
        'orderId': paymentResponse.orderId,
        'paymentId': paymentResponse.paymentId,
        'signature': paymentResponse.signature,
      });

      if (!mounted) return;
      _showPaymentSuccessDialog(
        plan,
        paymentResponse.paymentId ?? paymentResponse.orderId ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context); // Close loading dialog if still open
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment failed: $e'),
        backgroundColor: AppTheme.kumkumRed,
      ));
    } finally {
      if (mounted) {
        setState(() => _isGatewayProcessing = false);
      }
    }
  }

  // ── After payment details submitted ────────────────────────────────────────
  void _showPaymentSuccessDialog(MembershipPlan plan, String utr) {
    final total = plan.price;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppTheme.sacredGreen.withAlpha(35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: AppTheme.sacredGreen, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Payment details received',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Your payment of ₹${_rupees(total)} (reference: $utr) has been recorded.\n\n'
            'Our team will verify your payment against bank records and activate '
            'your premium membership shortly—usually within a few hours.\n\n'
            'You will receive a confirmation once activated. Pull to refresh on Home or '
            'reopen the app to see your status update.\n\n'
            'Need help? Contact us on WhatsApp.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: AC.textSub(ctx), height: 1.55),
          ),
          const SizedBox(height: 20),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final msg =
                    'Hi mana Vivaaha Vedika — I paid ₹${_rupees(total)} for ${plan.name}. '
                    'UTR/ref: $utr. Mobile: ${context.read<AuthService>().currentUser?.mobileNumber ?? ''}. '
                    'Please help if my premium status has not updated.';
                Clipboard.setData(ClipboardData(text: msg));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Support message copied — paste in WhatsApp'),
                  duration: Duration(seconds: 3),
                ));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy WhatsApp support message'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.sacredGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await context.read<AuthService>().refreshUserData();
                } catch (_) {}
                if (widget.onUpgradeComplete != null) {
                  widget.onUpgradeComplete!();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryOrange,
                side: const BorderSide(color: AppTheme.primaryOrange),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _paymentPolicyBullet(BuildContext ctx, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontSize: 13, color: AC.textSub(ctx))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AC.text(ctx),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Text(value, style: TextStyle(fontSize: 13, color: AC.textSub(context))),
      ]),
    );
  }

  Widget _upiRow(String label, String value,
      {required bool copyable, required BuildContext ctx}) {
    return Row(children: [
      Text('$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500))),
      if (copyable)
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('UPI ID copied!'),
              duration: Duration(seconds: 2),
            ));
          },
          child: const Icon(Icons.copy, size: 16, color: AppTheme.sacredGreen),
        ),
    ]);
  }

  IconData _getTierIcon(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.free:
        return Icons.person;
      case MembershipTier.platinum:
        return Icons.diamond;
    }
  }

  String _getTierPrice(MembershipTier tier) {
    if (tier == MembershipTier.free) return 'Free';
    final live = PlanService.instance.activePlans;
    if (live.isEmpty) {
      final rate = Membership.monthlyRates[tier] ?? 0;
      return rate > 0 ? 'From ₹${rate.toInt()}/mo' : 'Premium';
    }
    final minP = live.map((e) => e.discountedFee).reduce(min);
    return 'From ₹${minP.toInt()}';
  }
}
