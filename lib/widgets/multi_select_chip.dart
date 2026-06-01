import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Multi-select chip widget for hobbies, languages, etc.
class MultiSelectChip extends StatelessWidget {
  final List<String> items;
  final List<String> selectedItems;
  final ValueChanged<List<String>> onSelectionChanged;
  final int? maxSelections;

  const MultiSelectChip({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.onSelectionChanged,
    this.maxSelections,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: items.map((item) {
        final isSelected = selectedItems.contains(item);
        return _buildChip(context, item, isSelected);
      }).toList(),
    );
  }

  Widget _buildChip(BuildContext context, String item, bool isSelected) {
    final maxChipWidth = MediaQuery.sizeOf(context).width - 48;
    return GestureDetector(
      onTap: () {
        List<String> newSelection = List.from(selectedItems);
        
        if (isSelected) {
          newSelection.remove(item);
        } else {
          if (maxSelections == null || newSelection.length < maxSelections!) {
            newSelection.add(item);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Maximum $maxSelections items can be selected'),
                backgroundColor: AppTheme.kumkumRed,
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
        }
        
        onSelectionChanged(newSelection);
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxChipWidth),
        child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryOrange
              : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryOrange
                : AppTheme.primaryOrange.withAlpha(30),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AC.surface(context),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                Icons.check,
                size: 16,
                color: AC.card(context),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                item,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textLight,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Expandable multi-select chip widget that shows limited items initially
class ExpandableMultiSelectChip extends StatefulWidget {
  final List<String> items;
  final List<String> selectedItems;
  final ValueChanged<List<String>> onSelectionChanged;
  final int? maxSelections;
  final int initialVisibleCount;

  const ExpandableMultiSelectChip({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.onSelectionChanged,
    this.maxSelections,
    this.initialVisibleCount = 12,
  });

  @override
  State<ExpandableMultiSelectChip> createState() =>
      _ExpandableMultiSelectChipState();
}

class _ExpandableMultiSelectChipState extends State<ExpandableMultiSelectChip> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final displayItems = _isExpanded
        ? widget.items
        : widget.items.take(widget.initialVisibleCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MultiSelectChip(
          items: displayItems,
          selectedItems: widget.selectedItems,
          onSelectionChanged: widget.onSelectionChanged,
          maxSelections: widget.maxSelections,
        ),
        if (widget.items.length > widget.initialVisibleCount) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isExpanded
                        ? 'Show Less'
                        : 'Show ${widget.items.length - widget.initialVisibleCount} More',
                    style: const TextStyle(
                      color: AppTheme.templeGold,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.templeGold,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

