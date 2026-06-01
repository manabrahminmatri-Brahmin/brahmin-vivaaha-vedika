import 'package:flutter/material.dart';
import 'package:brahmin_vivaaha_vedika/utils/input_validation_guards.dart';

/// Service for validating user inputs across the app (uses [InputValidationGuards]).
/// Integrates with existing UI and snackbar feedback. Indian mobile: [OtpService]
/// via `package:brahmin_vivaaha_vedika/validation/phone_validator.dart`; profile completeness:
/// `package:brahmin_vivaaha_vedika/validation/profile_validator.dart`.
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  /// Validate text field with specific guard type and show error if needed
  bool validateTextField({
    required String input,
    required ValidationGuardType guardType,
    required BuildContext context,
    String? fieldName,
    bool showError = true,
  }) {
    final result = InputValidationGuards.validate(
      input,
      guardType,
      fieldName: fieldName ?? 'Field',
    );

    if (!result.isValid && showError) {
      _showValidationError(context, result.errorMessage);
    }

    return result.isValid;
  }

  /// Validate form field and update error state
  bool validateFormField({
    required String input,
    required ValidationGuardType guardType,
    required Function(String) onError,
    String? fieldName,
  }) {
    final result = InputValidationGuards.validate(
      input,
      guardType,
      fieldName: fieldName ?? 'Field',
    );

    onError(result.isValid ? '' : result.errorMessage);
    return result.isValid;
  }

  /// Batch validation for multiple fields
  Map<String, ValidationResult> validateMultipleFields(
    Map<String, ValidationInput> fields,
  ) {
    final results = <String, ValidationResult>{};

    for (final entry in fields.entries) {
      final result = InputValidationGuards.validate(
        entry.value.input,
        entry.value.guardType,
        fieldName: entry.value.fieldName,
      );
      results[entry.key] = result;
    }

    return results;
  }

  /// Check if all validations passed
  bool allValidationsPassed(Map<String, ValidationResult> results) {
    return results.values.every((result) => result.isValid);
  }

  /// Sanitize input by removing obvious contact information
  String sanitizeInput(String input) {
    String sanitized = input;

    // Remove phone numbers
    sanitized = sanitized.replaceAll(InputValidationGuards.phonePattern, '[PHONE REMOVED]');

    // Remove email addresses
    sanitized = sanitized.replaceAll(InputValidationGuards.emailPattern, '[EMAIL REMOVED]');

    // Remove WhatsApp references
    sanitized = sanitized.replaceAll(InputValidationGuards.whatsappPattern, '[CONTACT REMOVED]');

    // Remove website URLs
    sanitized = sanitized.replaceAll(InputValidationGuards.websitePattern, '[URL REMOVED]');

    // Remove social media references
    sanitized = sanitized.replaceAll(InputValidationGuards.socialPattern, '[SOCIAL REMOVED]');

    return sanitized;
  }

  /// Show validation error as snackbar
  void _showValidationError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Get validation rules summary for user guidance
  static Map<String, String> getValidationRules() {
    return {
      'alphaOnly': 'Only letters, spaces, and basic punctuation allowed. No numbers or contact information.',
      'noteField': 'No phone numbers, emails, or contact sharing. Maximum 2 consecutive digits allowed.',
      'numericWithUnit': 'Must be in format: number + unit (e.g., 175cm, 70kg, 5.5ft).',
      'parentName': 'Only letters and basic punctuation allowed. No numbers or contact information.',
    };
  }

  /// Get field-specific validation guidance
  static String getFieldGuidance(String fieldName) {
    final guidance = {
      'first_name': 'Enter your first name using letters only',
      'last_name': 'Enter your last name using letters only',
      'city': 'Enter your city name using letters only',
      'gothram': 'Enter your gothram using letters only',
      'sect': 'Enter your sect using letters only',
      'about_me': 'Describe yourself without sharing contact information',
      'familyNotes': 'Describe your family without sharing contact information',
      'height': 'Enter height as number + unit (e.g., 175cm, 5.5ft)',
      'weight': 'Enter weight as number + unit (e.g., 70kg, 154lbs)',
      'fatherName': 'Enter father\'s name using letters only',
      'motherName': 'Enter mother\'s name using letters only',
      'declineReason': 'Provide reason without sharing contact information',
      'feedback': 'Share feedback without sharing contact information',
    };

    return guidance[fieldName] ?? 'Follow standard validation rules';
  }
}

/// Input validation data structure
class ValidationInput {
  final String input;
  final ValidationGuardType guardType;
  final String fieldName;

  ValidationInput({
    required this.input,
    required this.guardType,
    required this.fieldName,
  });
}

/// Widget for validated text input
class ValidatedTextField extends StatefulWidget {
  final String? initialValue;
  final String fieldName;
  final ValidationGuardType guardType;
  final Function(String) onChanged;
  final Function(String)? onSubmitted;
  final String? hintText;
  final int? maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final TextEditingController? controller;

  const ValidatedTextField({
    super.key,
    this.initialValue,
    required this.fieldName,
    required this.guardType,
    required this.onChanged,
    this.onSubmitted,
    this.hintText,
    this.maxLines,
    this.keyboardType,
    this.enabled = true,
    this.controller,
  });

  @override
  State<ValidatedTextField> createState() => _ValidatedTextFieldState();
}

class _ValidatedTextFieldState extends State<ValidatedTextField> {
  late TextEditingController _controller;
  String _errorText = '';
  bool _isValid = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue ?? '');
    
    // Validate initial value
    if (_controller.text.isNotEmpty) {
      _validateInput(_controller.text);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _validateInput(String value) {
    final result = InputValidationGuards.validate(
      value,
      widget.guardType,
      fieldName: widget.fieldName,
    );

    setState(() {
      _isValid = result.isValid;
      _errorText = result.isValid ? '' : result.errorMessage;
    });

    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          maxLines: widget.maxLines ?? 1,
          keyboardType: widget.keyboardType,
          enabled: widget.enabled,
          onChanged: _validateInput,
          onSubmitted: widget.onSubmitted != null 
            ? (value) {
                if (_isValid) {
                  widget.onSubmitted!(value);
                }
              }
            : null,
          decoration: InputDecoration(
            hintText: widget.hintText,
            errorText: _errorText.isEmpty ? null : _errorText,
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: _isValid ? Colors.grey : Colors.red,
                width: _isValid ? 1.0 : 2.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: _isValid ? Colors.grey : Colors.red,
                width: _isValid ? 1.0 : 2.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: _isValid ? Theme.of(context).primaryColor : Colors.red,
                width: 2.0,
              ),
            ),
            suffixIcon: _controller.text.isNotEmpty
              ? Icon(
                  _isValid ? Icons.check_circle : Icons.error,
                  color: _isValid ? Colors.green : Colors.red,
                  size: 20,
                )
              : null,
          ),
        ),
        if (!_isValid)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              ValidationService.getFieldGuidance(widget.fieldName),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}
