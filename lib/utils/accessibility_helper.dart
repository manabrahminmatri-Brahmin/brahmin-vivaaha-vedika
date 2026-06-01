import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/navigation_service.dart';

/// Accessibility helper utilities for the Brahmin Vivaaha Vedika app
class AccessibilityHelper {
  
  /// Create semantic label for profile images
  static String getProfileImageLabel(String? name, bool hasPhoto) {
    if (hasPhoto && name != null) {
      return 'Profile photo of $name';
    } else if (hasPhoto) {
      return 'User profile photo';
    } else {
      return 'Default profile placeholder';
    }
  }

  /// Create semantic label for action buttons
  static String getActionButtonLabel(String action, String? target) {
    if (target != null) {
      return '$action $target';
    }
    return action;
  }

  /// Create accessible button
  static Widget accessibleButton({
    required String label,
    required String hint,
    required VoidCallback onPressed,
    Widget? child,
    ButtonStyle? style,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      child: ElevatedButton(
        onPressed: onPressed,
        style: style,
        child: child ?? Text(label),
      ),
    );
  }

  /// Create accessible text field
  static Widget accessibleTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      textField: true,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }

  /// Create accessible profile card
  static Widget accessibleProfileCard({
    required String name,
    required String age,
    required String education,
    required String occupation,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return Semantics(
      label: 'Profile of $name, age $age, $education graduate working as $occupation',
      hint: 'Tap to view full profile',
      button: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: child ?? Container(),
        ),
      ),
    );
  }

  /// Add accessibility properties to dropdown
  static Widget accessibleDropdown<T>({
    required BuildContext context,
    required String label,
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    String Function(T)? itemLabelBuilder,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: AC.dropdown(context),
        style: TextStyle(color: AC.text(context), fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
        items: items.map((T item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(itemLabelBuilder?.call(item) ?? item.toString()),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  /// Create accessible navigation item
  static Widget accessibleNavigationItem({
    required String label,
    required String hint,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : const Color(0xFF9E9E9E),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : const Color(0xFF9E9E9E),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Create accessible progress indicator
  static Widget accessibleProgressIndicator({
    required String label,
    required double value,
    String? semanticValue,
  }) {
    return Semantics(
      label: label,
      value: semanticValue ?? '${(value * 100).toInt()}%',
      child: LinearProgressIndicator(
        value: value,
        semanticsLabel: label,
      ),
    );
  }

  /// Create accessible switch
  static Widget accessibleSwitch({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      toggled: value,
      child: SwitchListTile(
        title: Text(label),
        subtitle: Text(hint),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  /// Create accessible checkbox
  static Widget accessibleCheckbox({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      checked: value,
      child: CheckboxListTile(
        title: Text(label),
        subtitle: Text(hint),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  /// Create accessible radio button
  static Widget accessibleRadio<T>({
    required String label,
    required String hint,
    required T value,
    required T? groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      checked: value == groupValue,
      child: InkWell(
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                value == groupValue
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(hint),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Create accessible slider
  static Widget accessibleSlider({
    required String label,
    required String hint,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 100.0,
    int? divisions,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value.toString(),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }

  /// Create accessible date picker
  static Widget accessibleDatePicker({
    required String label,
    required String hint,
    required DateTime? selectedDate,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      child: ListTile(
        title: Text(label),
        subtitle: Text(selectedDate?.toString() ?? hint),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final date = await showDatePicker(
            context: navigatorKey.currentContext!,
            initialDate: selectedDate ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          );
          onChanged(date);
        },
      ),
    );
  }

  /// Same key as [MaterialApp.navigatorKey] — do not create a second [GlobalKey].
  static GlobalKey<NavigatorState> get navigatorKey =>
      NavigationService().navigatorKey;

  /// Announce screen changes to screen readers
  static void announceScreenChange(String message) {
    // This would need to be implemented with a screen reader plugin
    // For now, we'll use debug print
    debugPrint('🔊 Screen change: $message');
  }

  /// Create accessible loading indicator
  static Widget accessibleLoadingIndicator({
    required String message,
  }) {
    return Semantics(
      label: 'Loading',
      value: message,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  /// Create accessible error message
  static Widget accessibleErrorMessage({
    required String message,
    VoidCallback? onRetry,
  }) {
    return Semantics(
      label: 'Error',
      value: message,
      child: Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
