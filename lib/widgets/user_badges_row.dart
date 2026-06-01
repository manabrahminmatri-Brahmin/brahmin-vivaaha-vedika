import 'package:flutter/material.dart';
import '../models/user_badge.dart';

/// Horizontal row of user badges for profile display
class UserBadgesRow extends StatelessWidget {
  final List<UserBadge> badges;
  final double badgeSize;
  final bool showLabels;
  final MainAxisAlignment alignment;
  final EdgeInsets padding;

  const UserBadgesRow({
    super.key,
    required this.badges,
    this.badgeSize = 24,
    this.showLabels = false,
    this.alignment = MainAxisAlignment.start,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  /// Create from user data map
  factory UserBadgesRow.fromUserData(
    Map<String, dynamic> user, {
    double badgeSize = 24,
    bool showLabels = false,
  }) {
    return UserBadgesRow(
      badges: (user['badges'] as List<dynamic>?)?.cast<UserBadge>() ?? [],
      badgeSize: badgeSize,
      showLabels: showLabels,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.start,
        children: badges.map((badge) => _buildBadge(badge)).toList(),
      ),
    );
  }

  Widget _buildBadge(UserBadge badge) {
    final badgeWidget = Container(
      padding: showLabels 
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: badge.backgroundColor,
        borderRadius: BorderRadius.circular(showLabels ? 12 : 16),
        border: Border.all(
          color: badge.textColor.withAlpha(30),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badge.icon,
            size: badgeSize * 0.7,
            color: badge.textColor,
          ),
          if (showLabels) ...[
            const SizedBox(width: 4),
            Text(
              badge.label,
              style: TextStyle(
                fontSize: badgeSize * 0.5,
                fontWeight: FontWeight.w600,
                color: badge.textColor,
              ),
            ),
          ],
        ],
      ),
    );

    if (badge.tooltip != null) {
      return Tooltip(
        message: badge.tooltip!,
        child: badgeWidget,
      );
    }

    return badgeWidget;
  }
}

/// Compact badge chip for lists and cards
class BadgeChip extends StatelessWidget {
  final BadgeType type;
  final VoidCallback? onTap;

  const BadgeChip({
    super.key,
    required this.type,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = UserBadge.forType(type);
    
    final chip = Material(
      color: badge.backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                badge.icon,
                size: 14,
                color: badge.textColor,
              ),
              const SizedBox(width: 4),
              Text(
                badge.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: badge.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (badge.tooltip != null) {
      return Tooltip(
        message: badge.tooltip!,
        child: chip,
      );
    }

    return chip;
  }
}

/// Badge selection widget for admin use
class BadgeSelector extends StatelessWidget {
  final Set<BadgeType> selectedBadges;
  final Function(Set<BadgeType>) onSelectionChanged;
  final bool isMultiSelect;

  const BadgeSelector({
    super.key,
    required this.selectedBadges,
    required this.onSelectionChanged,
    this.isMultiSelect = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BadgeType.values.map((type) {
        final badge = UserBadge.forType(type);
        final isSelected = selectedBadges.contains(type);
        
        return FilterChip(
          selected: isSelected,
          onSelected: (selected) {
            final newSelection = Set<BadgeType>.from(selectedBadges);
            if (isMultiSelect) {
              if (selected) {
                newSelection.add(type);
              } else {
                newSelection.remove(type);
              }
            } else {
              newSelection.clear();
              if (selected) {
                newSelection.add(type);
              }
            }
            onSelectionChanged(newSelection);
          },
          avatar: Icon(
            badge.icon,
            size: 16,
            color: isSelected ? badge.textColor : badge.textColor.withAlpha(180),
          ),
          label: Text(badge.label),
          selectedColor: badge.backgroundColor,
          checkmarkColor: badge.textColor,
          labelStyle: TextStyle(
            color: isSelected ? badge.textColor : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}
