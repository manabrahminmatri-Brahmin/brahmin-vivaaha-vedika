import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Custom styled dropdown with search capability
/// Automatically shows a text field when "Other" is selected
class CustomDropdown extends StatelessWidget {
  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final IconData? icon;
  final bool enabled;
  final bool searchable;
  final int minSearchChars;
  final TextEditingController? customInputController;
  final ValueChanged<String>? onCustomInputChanged;
  final String? customInputLabel;
  final String? customInputHint;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    this.onChanged,
    this.icon,
    this.enabled = true,
    this.searchable = true,
    this.minSearchChars = 1,
    this.customInputController,
    this.onCustomInputChanged,
    this.customInputLabel,
    this.customInputHint,
  });

  bool get _showCustomInput => value == 'Other' && customInputController != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AC.text(context),
              ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: enabled && items.isNotEmpty
              ? () {
                  // Dismiss keyboard before showing dropdown
                  FocusScope.of(context).unfocus();
                  _showSelectionSheet(context);
                }
              : null,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: enabled ? AC.surface(context) : AC.surface2(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled ? AppTheme.primaryOrange.withAlpha(30) : AC.border(context),
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: enabled ? AC.textSub(context) : AC.textMuted(context),
                    size: 24,
                  ),
                  SizedBox(width: 16),
                ],
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: value != null ? AC.text(context) : AC.textMuted(context),
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: enabled ? AC.textMuted(context) : AC.textMuted(context),
                ),
              ],
            ),
          ),
        ),
        // Show custom input field when "Other" is selected
        if (_showCustomInput) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: customInputController,
            onChanged: onCustomInputChanged,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onEditingComplete: () {
              // Dismiss keyboard when done editing
              FocusScope.of(context).unfocus();
            },
            onTap: () {
              // Ensure keyboard is shown when tapping the field
              FocusScope.of(context).requestFocus();
            },
            decoration: InputDecoration(
              labelText: customInputLabel ?? 'Please specify',
              hintText: customInputHint ?? 'Enter custom value',
              prefixIcon: Icon(Icons.edit_outlined, size: 24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: AC.surface(context),
            ),
            validator: (value) {
              if (_showCustomInput && (value == null || value.trim().isEmpty)) {
                return 'Please enter a value';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  void _showSelectionSheet(BuildContext context) {
    // Dismiss any existing keyboard
    FocusScope.of(context).unfocus();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet(
        title: label,
        items: items,
        selectedValue: value ?? (items.isNotEmpty && items.first == 'Any' ? 'Any' : value),
        onSelected: (selected) {
          // Convert "Any" to null for consistency
          onChanged?.call(selected == 'Any' ? null : selected);
          Navigator.of(context).pop();
        },
        searchable: searchable,
        minSearchChars: minSearchChars,
      ),
    );
  }
}

class _SelectionSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final String? selectedValue;
  final ValueChanged<String> onSelected;
  final bool searchable;
  final int minSearchChars;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.searchable = true,
    this.minSearchChars = 1,
  });

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  final _searchController = TextEditingController();
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else if (query.trim().length < widget.minSearchChars) {
        _filteredItems = const [];
      } else {
        _filteredItems = widget.items
            .where((item) => item.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final kb = media.viewInsets.bottom;
    // Leave room for IME so the search field + list stay above the keyboard.
    final maxHeight = (media.size.height - kb) * 0.72;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(200.0, media.size.height),
        ),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Handle
          Container(
            margin: EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AC.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.primaryOrange,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, size: 24),
                  color: AC.icon(context),
                ),
              ],
            ),
          ),

          // Search Field
          if (widget.searchable && widget.items.length > 10)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: _filterItems,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  // Dismiss keyboard when searching
                  FocusScope.of(context).unfocus();
                },
                onTap: () {
                  // Ensure keyboard is shown for search
                  FocusScope.of(context).requestFocus();
                },
                decoration: InputDecoration(
                  hintText: widget.minSearchChars <= 1
                      ? 'Search...'
                      : 'Type ${widget.minSearchChars}+ letters to search...',
                  prefixIcon: Icon(Icons.search, size: 24),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _filterItems('');
                            FocusScope.of(context).requestFocus();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AC.surface(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),
          if (widget.searchable &&
              _searchController.text.isNotEmpty &&
              _searchController.text.trim().length < widget.minSearchChars)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enter at least ${widget.minSearchChars} characters to show matches',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textMuted(context),
                      ),
                ),
              ),
            ),

          // Items List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                // Handle null value - treat it as "Any" if "Any" is in the list
                final selectedValue = widget.selectedValue ?? 
                    (widget.items.isNotEmpty && widget.items.first == 'Any' ? 'Any' : null);
                final isSelected = item == selectedValue;

                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryOrange.withAlpha(15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    onTap: () {
                      // Dismiss keyboard before selecting
                      FocusScope.of(context).unfocus();
                      widget.onSelected(item);
                    },
                    title: Text(
                      item,
                      style: TextStyle(
                        color: isSelected ? AppTheme.primaryOrange : AC.text(context),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppTheme.primaryMaroon,
                          )
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}

