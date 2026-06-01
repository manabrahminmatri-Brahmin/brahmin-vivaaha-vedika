import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../services/pincode_service.dart';
import '../../theme/app_theme.dart';

/// Drives shake/clear animations on MPIN/OTP pin fields.
class AuthPinFieldController {
  AuthPinFieldController() {
    errorAnimation = StreamController<ErrorAnimationType>.broadcast();
  }

  late final StreamController<ErrorAnimationType> errorAnimation;

  void shake() {
    if (!errorAnimation.isClosed) {
      errorAnimation.add(ErrorAnimationType.shake);
    }
  }

  void clearFields() {
    if (!errorAnimation.isClosed) {
      errorAnimation.add(ErrorAnimationType.clear);
    }
  }

  void dispose() {
    if (!errorAnimation.isClosed) {
      errorAnimation.close();
    }
  }
}

bool _isDigitsOnlyPaste(String? text, int maxLen) {
  if (text == null || text.isEmpty) return false;
  final digits = text.replaceAll(RegExp(r'\D'), '');
  return digits.length == maxLen;
}

/// Subtle tray behind MPIN/OTP boxes — improves contrast on auth cards without changing layout.
class AuthPinFieldShell extends StatelessWidget {
  const AuthPinFieldShell({
    super.key,
    required this.child,
    this.accentColor = AppTheme.primaryOrange,
    this.hasError = false,
    this.compact = false,
  });

  final Widget child;
  final Color accentColor;
  final bool hasError;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppTheme.kumkumRed.withValues(alpha: 0.45)
        : accentColor.withValues(alpha: 0.22);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compact ? 8 : 14,
        horizontal: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: hasError
            ? AppTheme.kumkumRed.withValues(alpha: 0.06)
            : AC.surface(context),
        border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: (hasError ? AppTheme.kumkumRed : accentColor)
                .withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

PinTheme _authPinTheme({
  required BuildContext context,
  required Color accent,
  required double fieldHeight,
  required double fieldWidth,
  bool hasError = false,
}) {
  final effectiveAccent = hasError ? AppTheme.kumkumRed : accent;
  final inactiveFill = hasError
      ? AppTheme.kumkumRed.withValues(alpha: 0.08)
      : AC.surface2(context);
  final activeFill = effectiveAccent.withValues(alpha: hasError ? 0.18 : 0.14);
  final selectedFill = effectiveAccent.withValues(alpha: hasError ? 0.26 : 0.22);
  final inactiveBorder =
      hasError ? AppTheme.kumkumRed.withValues(alpha: 0.35) : AC.border(context);

  return PinTheme(
    shape: PinCodeFieldShape.box,
    borderRadius: BorderRadius.circular(14),
    fieldHeight: fieldHeight,
    fieldWidth: fieldWidth,
    borderWidth: hasError ? 2.5 : 2,
    fieldOuterPadding: const EdgeInsets.symmetric(horizontal: 2),
    activeFillColor: activeFill,
    selectedFillColor: selectedFill,
    inactiveFillColor: inactiveFill,
    activeColor: effectiveAccent,
    selectedColor: effectiveAccent,
    inactiveColor: inactiveBorder,
    disabledColor: inactiveBorder.withValues(alpha: 0.5),
    errorBorderColor: AppTheme.kumkumRed,
  );
}

/// 4-digit MPIN entry — square boxes, obscured dots, accent highlight.
class AuthMpinPinField extends StatelessWidget {
  const AuthMpinPinField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.accentColor = AppTheme.primaryOrange,
    this.enabled = true,
    this.autoFocus = false,
    this.onChanged,
    this.fieldController,
    this.hasError = false,
    this.compact = false,
  });

  final TextEditingController controller;
  final void Function(String) onCompleted;
  final Color accentColor;
  final bool enabled;
  final bool autoFocus;
  final void Function(String)? onChanged;
  final AuthPinFieldController? fieldController;
  final bool hasError;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fieldSize = compact ? 48.0 : 56.0;

    return AuthPinFieldShell(
      accentColor: accentColor,
      hasError: hasError,
      compact: compact,
      child: Center(
        child: PinCodeTextField(
          appContext: context,
          length: 4,
          controller: controller,
          autoDisposeControllers: false,
          enabled: enabled,
          autoFocus: autoFocus,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enablePinAutofill: false,
          showCursor: true,
          cursorColor: accentColor,
          cursorWidth: 2,
          animationType: AnimationType.scale,
          animationDuration: const Duration(milliseconds: 150),
          obscureText: true,
          obscuringWidget: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError ? AppTheme.kumkumRed : accentColor,
              boxShadow: [
                BoxShadow(
                  color: (hasError ? AppTheme.kumkumRed : accentColor)
                      .withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          enableActiveFill: true,
          backgroundColor: Colors.transparent,
          errorAnimationController: fieldController?.errorAnimation,
          beforeTextPaste: (text) => _isDigitsOnlyPaste(text, 4),
          pinTheme: _authPinTheme(
            context: context,
            accent: accentColor,
            fieldHeight: fieldSize,
            fieldWidth: fieldSize,
            hasError: hasError,
          ),
          onChanged: onChanged ?? (_) {},
          onCompleted: onCompleted,
        ),
      ),
    );
  }
}

/// Shared 6-digit numeric pin row (OTP / postal PIN) with responsive box sizing.
class _AuthSixDigitPinRow extends StatelessWidget {
  const _AuthSixDigitPinRow({
    required this.controller,
    required this.accentColor,
    required this.onChanged,
    this.onCompleted,
    this.autoFocus = false,
    this.enableSmsAutofill = false,
    this.hasError = false,
    this.errorAnimationController,
  });

  final TextEditingController controller;
  final Color accentColor;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool autoFocus;
  final bool enableSmsAutofill;
  final bool hasError;
  final StreamController<ErrorAnimationType>? errorAnimationController;

  @override
  Widget build(BuildContext context) {
    final pinTextStyle = GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: hasError ? AppTheme.kumkumRed : AC.text(context),
      height: 1.1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const fields = 6;
        const gap = 5.0;
        final maxW = constraints.maxWidth;
        final raw = (maxW - gap * (fields - 1)) / fields;
        final fieldW = raw.clamp(44.0, 50.0);
        final fieldH = (fieldW + 6).clamp(48.0, 54.0);

        return PinCodeTextField(
          appContext: context,
          length: fields,
          controller: controller,
          autoDisposeControllers: false,
          autoFocus: autoFocus,
          autoDismissKeyboard: true,
          keyboardType: TextInputType.number,
          enablePinAutofill: enableSmsAutofill,
          showCursor: true,
          cursorColor: accentColor,
          cursorWidth: 2,
          animationType: AnimationType.fade,
          animationDuration: const Duration(milliseconds: 120),
          textStyle: pinTextStyle,
          pastedTextStyle: pinTextStyle,
          enableActiveFill: true,
          backgroundColor: Colors.transparent,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          errorAnimationController: errorAnimationController,
          beforeTextPaste: (text) => _isDigitsOnlyPaste(text, 6),
          pinTheme: _authPinTheme(
            context: context,
            accent: accentColor,
            fieldHeight: fieldH,
            fieldWidth: fieldW,
            hasError: hasError,
          ),
          onChanged: onChanged,
          onCompleted: onCompleted,
        );
      },
    );
  }
}

/// 6-digit postal PIN for profile location autofill (matches auth OTP styling).
class AuthPinCodeLocationField extends StatelessWidget {
  const AuthPinCodeLocationField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onCompleted,
    this.isLoading = false,
    this.lookupSucceeded = false,
    this.autoFocus = false,
    this.accentColor = AppTheme.sacredGreen,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool isLoading;
  final bool lookupSucceeded;
  final bool autoFocus;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pin_drop_outlined, size: 18, color: accentColor),
            const SizedBox(width: 8),
            Text(
              'PIN Code',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AC.text(context),
              ),
            ),
            const Spacer(),
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: accentColor,
                ),
              )
            else if (lookupSucceeded &&
                PinCodeService.normalizePin(controller.text).length == 6)
              Icon(Icons.check_circle_outline, color: accentColor, size: 22),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Enter 6 digits to auto-fill state and city (India)',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AC.textMuted(context),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        AuthPinFieldShell(
          accentColor: accentColor,
          child: _AuthSixDigitPinRow(
            controller: controller,
            accentColor: accentColor,
            autoFocus: autoFocus,
            enableSmsAutofill: false,
            onChanged: onChanged,
            onCompleted: onCompleted,
          ),
        ),
      ],
    );
  }
}

/// Validates a 10-digit Indian mobile ([6-9] + 9 digits). Empty fails when [required].
String? validateAuthMobileDigits(String? value, {bool required = true}) {
  final v = (value ?? '').trim();
  if (v.isEmpty) {
    return required ? 'Mobile number is required' : null;
  }
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v)) {
    return 'Enter a valid 10-digit number';
  }
  return null;
}

/// 10-digit mobile entry — bank-style bordered field with +91 prefix panel.
class AuthMobilePinField extends StatelessWidget {
  const AuthMobilePinField({
    super.key,
    required this.controller,
    this.accentColor = AppTheme.primaryOrange,
    this.enabled = true,
    this.autoFocus = false,
    this.onChanged,
    this.onCompleted,
    this.fieldController,
    this.hasError = false,
    this.showCountryCode = true,
    this.compact = false,
  });

  final TextEditingController controller;
  final Color accentColor;
  final bool enabled;
  final bool autoFocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final AuthPinFieldController? fieldController;
  final bool hasError;
  final bool showCountryCode;
  final bool compact;

  static OutlineInputBorder _outline(
    Color color, {
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        hasError ? AppTheme.kumkumRed : AppTheme.surfaceLight2;
    final focusedColor = hasError ? AppTheme.kumkumRed : accentColor;
    final textColor = enabled ? AC.text(context) : AC.textMuted(context);

    final digitStyle = GoogleFonts.poppins(
      fontSize: compact ? 15 : 16,
      fontWeight: FontWeight.w600,
      color: textColor,
      letterSpacing: 0.6,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autoFocus,
      keyboardType: TextInputType.phone,
      maxLength: 10,
      textAlign: TextAlign.start,
      textInputAction: TextInputAction.done,
      style: digitStyle,
      cursorColor: focusedColor,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: compact,
        counterText: '',
        filled: true,
        fillColor: enabled ? AC.card(context) : AC.surface(context),
        hintText: 'Enter 10-digit mobile number',
        hintStyle: GoogleFonts.poppins(
          fontSize: compact ? 13 : 14,
          fontWeight: FontWeight.w400,
          color: AC.textMuted(context),
        ),
        prefixIcon: showCountryCode
            ? Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 10),
                    Text(
                      '+91',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AC.textSub(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 22,
                      color: AppTheme.surfaceLight2,
                    ),
                  ],
                ),
              )
            : null,
        prefixIconConstraints: showCountryCode
            ? const BoxConstraints(minWidth: 72, minHeight: 48)
            : null,
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.phone_android_outlined,
            size: 20,
            color: hasError
                ? AppTheme.kumkumRed.withValues(alpha: 0.7)
                : AC.textMuted(context),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 48),
        contentPadding: EdgeInsets.symmetric(
          horizontal: showCountryCode ? 4 : 16,
          vertical: compact ? 12 : 14,
        ),
        border: _outline(borderColor),
        enabledBorder: _outline(borderColor),
        disabledBorder: _outline(AC.border(context).withValues(alpha: 0.5)),
        focusedBorder: _outline(focusedColor, width: 1.5),
        errorBorder: _outline(AppTheme.kumkumRed, width: 1.5),
        focusedErrorBorder: _outline(AppTheme.kumkumRed, width: 1.5),
      ),
      onChanged: (value) {
        onChanged?.call(value);
        if (value.length == 10) {
          onCompleted?.call(value);
        }
      },
      onSubmitted: onCompleted,
    );
  }
}

/// [FormField] wrapper for [AuthMobilePinField] with standard mobile validation.
class AuthMobilePinFormField extends StatelessWidget {
  const AuthMobilePinFormField({
    super.key,
    required this.controller,
    this.validator,
    this.enabled = true,
    this.autoFocus = false,
    this.onChanged,
    this.onCompleted,
    this.fieldController,
    this.showCountryCode = true,
    this.required = true,
    this.compact = false,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool autoFocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final AuthPinFieldController? fieldController;
  final bool showCountryCode;
  final bool required;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      validator: (_) {
        final v = controller.text.trim();
        final value = v.isEmpty && !required ? null : v;
        if (validator != null) return validator!(value);
        return validateAuthMobileDigits(value, required: required);
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthMobilePinField(
              controller: controller,
              enabled: enabled,
              autoFocus: autoFocus,
              compact: compact,
              showCountryCode: showCountryCode,
              fieldController: fieldController,
              hasError: field.hasError,
              onChanged: (value) {
                field.didChange(value);
                onChanged?.call(value);
              },
              onCompleted: onCompleted,
            ),
            if (field.hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  field.errorText!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppTheme.kumkumRed,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 6-digit OTP entry — square boxes, bold digits, SMS autofill, paste support.
class AuthOtpPinField extends StatelessWidget {
  const AuthOtpPinField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.accentColor = AppTheme.primaryOrange,
    this.autoFocus = true,
    this.onChanged,
    this.fieldController,
    this.hasError = false,
  });

  final TextEditingController controller;
  final void Function(String) onCompleted;
  final Color accentColor;
  final bool autoFocus;
  final void Function(String)? onChanged;
  final AuthPinFieldController? fieldController;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return AuthPinFieldShell(
      accentColor: accentColor,
      hasError: hasError,
      child: _AuthSixDigitPinRow(
        controller: controller,
        accentColor: accentColor,
        autoFocus: autoFocus,
        enableSmsAutofill: true,
        hasError: hasError,
        errorAnimationController: fieldController?.errorAnimation,
        onChanged: onChanged ?? (_) {},
        onCompleted: onCompleted,
      ),
    );
  }
}
