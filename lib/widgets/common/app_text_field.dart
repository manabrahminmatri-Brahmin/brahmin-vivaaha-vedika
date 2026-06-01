import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_guard.dart';

/// Custom text field widget with consistent styling
class AppTextField extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? initialValue;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final void Function()? onTap;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool showPasswordToggle;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? textStyle;
  final String? errorText;
  final bool autofocus;
  final AutovalidateMode autovalidateMode;
  /// When true (default) the field will block phone-number patterns and show
  /// a warning snackbar. Set to false only for numeric-only fields like OTP /
  /// MPIN where digit input is expected.
  final bool blockPhoneNumbers;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.initialValue,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.showPasswordToggle = false,
    this.contentPadding,
    this.textStyle,
    this.errorText,
    this.autofocus = false,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
    this.blockPhoneNumbers = true,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscureText;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String? _phoneWarning;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  // ── guard helpers ─────────────────────────────────────────────────────

  void _handleBlocked(String msg) {
    setState(() => _phoneWarning = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _phoneWarning = null);
    });
  }

  bool get _isAlphaField =>
      widget.blockPhoneNumbers &&
      widget.keyboardType != TextInputType.number &&
      widget.keyboardType != TextInputType.phone &&
      widget.keyboardType != TextInputType.visiblePassword &&
      !widget.obscureText;

  /// Merge caller-supplied formatters with the appropriate guard.
  List<TextInputFormatter> get _formatters {
    final base = widget.inputFormatters ?? [];

    if (!widget.blockPhoneNumbers || widget.obscureText) return base;

    if (_isAlphaField) {
      // Alpha-only fields: block digits + number words + contact sharing
      return [AlphaOnlyGuard(onBlocked: _handleBlocked), ...base];
    }

    // Numeric / phone fields: only block contact-sharing patterns
    return [ContactSharingGuard(onBlocked: _handleBlocked), ...base];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AC.text(context),
            ),
          ),
          SizedBox(height: 8),
        ],
        // ── input-guard warning banner ────────────────────────────────
        if (_phoneWarning != null) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Color(0xFF856404), size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phoneWarning!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF664D03),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _phoneWarning = null),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 15, color: Color(0xFF856404)),
                  ),
                ),
              ],
            ),
          ),
        ],
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          obscureText: _obscureText,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
          textInputAction: widget.textInputAction,
          inputFormatters: _formatters,
          autofocus: widget.autofocus,
          autovalidateMode: widget.autovalidateMode,
          style: widget.textStyle ?? Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AC.text(context),
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AC.textSub(context),
            ),
            prefixIcon: widget.prefixIcon,
            suffixIcon: _buildSuffixIcon(),
            contentPadding: widget.contentPadding ?? const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AC.textMuted(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AC.textMuted(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.primaryOrange, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AC.textMuted(context)),
            ),
            filled: true,
            fillColor: widget.enabled ? AC.surface(context) : AC.surface2(context),
            counterText: '', // Hide character counter
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildSuffixIcon() {
    if (widget.showPasswordToggle) {
      return IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility_off : Icons.visibility,
          color: AC.textSub(context),
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      );
    }
    return widget.suffixIcon;
  }
}

/// Mobile number text field
class MobileNumberField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;

  const MobileNumberField({
    super.key,
    this.label,
    this.hint = 'Enter 10-digit mobile number',
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label ?? 'Mobile Number',
      hint: hint,
      controller: controller,
      keyboardType: TextInputType.phone,
      maxLength: 10,
      blockPhoneNumbers: false, // This IS the phone number field — guard not needed
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) {
          return 'Mobile number is required';
        }
        if (value.length != 10) {
          return 'Mobile number must be 10 digits';
        }
        if (!RegExp(r'^[6-9]').hasMatch(value)) {
          return 'Please enter a valid Indian mobile number';
        }
        return null;
      },
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      prefixIcon: const Icon(Icons.phone, color: AppTheme.textMedium),
    );
  }
}

/// Email text field
class EmailField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;

  const EmailField({
    super.key,
    this.label,
    this.hint = 'Enter your email address',
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label ?? 'Email Address',
      hint: hint,
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) {
          return 'Email is required';
        }
        if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
          return 'Please enter a valid email address';
        }
        return null;
      },
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      prefixIcon: const Icon(Icons.email, color: AppTheme.textMedium),
    );
  }
}

/// Password text field
class PasswordField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;

  const PasswordField({
    super.key,
    this.label,
    this.hint = 'Enter your password',
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label ?? 'Password',
      hint: hint,
      controller: controller,
      obscureText: true,
      showPasswordToggle: true,
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) {
          return 'Password is required';
        }
        if (value.length < 8) {
          return 'Password must be at least 8 characters';
        }
        return null;
      },
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      prefixIcon: const Icon(Icons.lock, color: AppTheme.textMedium),
    );
  }
}

/// MPIN text field
class MpinField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;

  const MpinField({
    super.key,
    this.label,
    this.hint = 'Enter 4-digit MPIN',
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label ?? 'MPIN',
      hint: hint,
      controller: controller,
      obscureText: true,
      maxLength: 4,
      keyboardType: TextInputType.number,
      blockPhoneNumbers: false, // numeric-only field — guard not needed
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) {
          return 'MPIN is required';
        }
        if (value.length != 4) {
          return 'MPIN must be 4 digits';
        }
        return null;
      },
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMedium),
    );
  }
}
