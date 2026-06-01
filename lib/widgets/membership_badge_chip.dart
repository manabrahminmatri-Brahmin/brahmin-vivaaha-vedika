import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small Premium / Free label for profile cards and lists.
class MembershipBadgeChip extends StatelessWidget {
  final bool isPremium;
  final bool compact;

  const MembershipBadgeChip({
    super.key,
    required this.isPremium,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = isPremium ? 'Premium' : 'Free';
    final bg = isPremium ? AppTheme.primaryGold : const Color(0xFF5C5C5C);
    final fg = isPremium ? const Color(0xFF3A2A00) : Colors.white;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(compact ? 6 : 10),
        border: Border.all(
          color: isPremium
              ? AppTheme.templeGold.withValues(alpha: 0.85)
              : Colors.white24,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}
