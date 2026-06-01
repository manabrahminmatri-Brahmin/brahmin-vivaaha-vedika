import 'package:flutter/material.dart';

import '../membership/premium_upgrade_screen.dart';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Single source of truth for premium purchase:
    // every premium entry now opens the same plans + gateway flow screen.
    return const PremiumUpgradeScreen();
  }
}
