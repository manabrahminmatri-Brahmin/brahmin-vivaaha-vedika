import 'package:flutter/material.dart';

import '../../models/membership.dart';
import '../../services/premium_entitlement_service.dart';

/// Resolves server-side premium entitlement once, then builds UI.
///
/// Use [PremiumEntitlementService.displayPremiumHint] for badges only.
class ServerPremiumGate extends StatefulWidget {
  const ServerPremiumGate({
    super.key,
    required this.feature,
    required this.builder,
    this.loading,
    this.localMembership,
  });

  final String feature;
  final Membership? localMembership;
  final Widget Function(BuildContext context, bool serverEntitled) builder;
  final Widget? loading;

  @override
  State<ServerPremiumGate> createState() => _ServerPremiumGateState();
}

class _ServerPremiumGateState extends State<ServerPremiumGate> {
  late Future<bool> _future;

  @override
  void initState() {
    super.initState();
    _future = PremiumEntitlementService.isEntitled(
      feature: widget.feature,
      localMembershipHint: widget.localMembership,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loading ??
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
        }
        return widget.builder(context, snapshot.data == true);
      },
    );
  }
}
