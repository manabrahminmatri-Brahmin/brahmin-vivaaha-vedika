import 'package:flutter/material.dart';

import '../../services/plan_service.dart';
import '../../theme/app_theme.dart';

/// Admin: deploy defaults, list/edit/create/delete [subscription_plans] documents.
///
/// Access: only reachable from [AdminDashboardScreen] after [AdminGate].
class AdminSubscriptionPlansScreen extends StatefulWidget {
  const AdminSubscriptionPlansScreen({super.key, this.embedded = true});

  final bool embedded;

  @override
  State<AdminSubscriptionPlansScreen> createState() =>
      _AdminSubscriptionPlansScreenState();
}

class _AdminSubscriptionPlansScreenState
    extends State<AdminSubscriptionPlansScreen> {
  final _ps = PlanService.instance;

  @override
  void initState() {
    super.initState();
    _ps.startListening();
  }

  Future<void> _deploy() async {
    try {
      await _ps.deployPlans();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default plans deployed to Firestore')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deploy failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(SubscriptionPlan p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text('Remove "${p.name}" (${p.id}) from Firestore?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.kumkumRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _ps.deletePlan(p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${p.id}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _openEditor({SubscriptionPlan? existing}) async {
    final idCtrl = TextEditingController(text: existing?.id ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final actualCtrl =
        TextEditingController(text: existing?.actualFee.toString() ?? '');
    final discCtrl =
        TextEditingController(text: existing?.discountedFee.toString() ?? '');
    final monthsCtrl =
        TextEditingController(text: existing?.durationMonths.toString() ?? '1');
    final featuresCtrl = TextEditingController(
      text: existing?.features.join('\n') ?? '',
    );
    var active = existing?.isActive ?? true;
    var popular = existing?.isPopular ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'Create plan' : 'Edit plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing == null)
                  TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Document ID (e.g. monthly)',
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                TextField(
                  controller: monthsCtrl,
                  decoration: const InputDecoration(labelText: 'Duration (months)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: actualCtrl,
                  decoration: const InputDecoration(labelText: 'Actual fee (₹)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: discCtrl,
                  decoration: const InputDecoration(labelText: 'Discounted fee (₹)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: featuresCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Features (one per line)',
                  ),
                  maxLines: 6,
                ),
                SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setDlg(() => active = v),
                ),
                SwitchListTile(
                  title: const Text('Popular'),
                  value: popular,
                  onChanged: (v) => setDlg(() => popular = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    final months = int.tryParse(monthsCtrl.text.trim()) ?? 1;
    final actual = double.tryParse(actualCtrl.text.trim()) ?? 0;
    final disc = double.tryParse(discCtrl.text.trim()) ?? 0;
    final feats = featuresCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    try {
      if (existing == null) {
        final id = idCtrl.text.trim();
        if (id.isEmpty) throw Exception('Plan id required');
        await _ps.createPlan(
          SubscriptionPlan(
            id: id,
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim(),
            durationMonths: months,
            actualFee: actual,
            discountedFee: disc,
            features: feats,
            isPopular: popular,
            isActive: active,
          ),
        );
      } else {
        await _ps.updatePlan(
          planId: existing.id,
          name: nameCtrl.text.trim(),
          description: descCtrl.text.trim(),
          durationMonths: months,
          actualFee: actual,
          discountedFee: disc,
          features: feats,
          isActive: active,
          isPopular: popular,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ps,
      builder: (context, _) {
        final plans = _ps.plans;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _deploy,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Deploy default plans'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('New plan'),
                  ),
                  if (_ps.isLoading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            if (_ps.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _ps.error!,
                  style: TextStyle(color: AppTheme.kumkumRed, fontSize: 12),
                ),
              ),
            Expanded(
              child: plans.isEmpty
                  ? const Center(child: Text('No plans loaded yet'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: plans.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = plans[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (p.isPopular)
                                Chip(
                                  label: const Text('POPULAR'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor:
                                      AppTheme.primaryOrange.withAlpha(40),
                                ),
                              Chip(
                                label: Text(p.isActive ? 'Active' : 'Inactive'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'ID: ${p.id} • ${p.durationMonths} mo\n'
                              'Actual: ₹${p.actualFee.toStringAsFixed(0)} → '
                              'Discounted: ₹${p.discountedFee.toStringAsFixed(0)}',
                              style: const TextStyle(height: 1.35),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _openEditor(existing: p),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: AppTheme.kumkumRed,
                                ),
                                onPressed: () => _confirmDelete(p),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
