import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/pin_code_location_resolver.dart';
import '../services/pincode_analytics_service.dart';
import '../services/pincode_service.dart';
import '../utils/pin_location_form_sync.dart';
import '../theme/app_theme.dart';
import 'auth/auth_pin_fields.dart';
import 'custom_dropdown.dart';

export '../services/pin_code_location_resolver.dart' show matchIndianStateFromPinApi;

/// 6-digit PIN lookup + optional area dropdown; calls [onApply] with resolved office.
class PinCodeLocationAutofillSection extends StatefulWidget {
  const PinCodeLocationAutofillSection({
    super.key,
    required this.onApply,
    this.onError,
    this.onManualLocationEdit,
    this.sectionTitle,
    this.focusAfterSingleMatch,
    this.focusAfterMultipleAreas,
    this.initialPin,
    this.onPinDigitsChanged,
  });

  /// Called when PIN resolves or user picks a post office — includes mapped state/city.
  final void Function(PinCodeResolvedLocation resolved) onApply;
  final void Function(String message)? onError;
  final VoidCallback? onManualLocationEdit;

  /// e.g. "Current residence", "Place of birth".
  final String? sectionTitle;
  final FocusNode? focusAfterSingleMatch;
  final FocusNode? focusAfterMultipleAreas;
  final String? initialPin;

  /// Normalized 6-digit PIN (or shorter while typing) for parent forms.
  final ValueChanged<String>? onPinDigitsChanged;

  @override
  State<PinCodeLocationAutofillSection> createState() =>
      _PinCodeLocationAutofillSectionState();
}

class _PinCodeLocationAutofillSectionState
    extends State<PinCodeLocationAutofillSection> {
  final _pinController = TextEditingController();
  final _areaSectionFocus = FocusNode();
  Timer? _debounce;
  String? _lastRequestedPin;
  bool _loading = false;
  bool _lookupSucceeded = false;
  List<PinCodePostOffice> _postOffices = [];
  String? _selectedArea;

  @override
  void initState() {
    super.initState();
    final seed = PinCodeService.normalizePin(widget.initialPin ?? '');
    if (seed.length == 6) {
      _pinController.text = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookup(seed);
      });
    }
  }

  @override
  void didUpdateWidget(PinCodeLocationAutofillSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = PinCodeService.normalizePin(widget.initialPin ?? '');
    final prev = PinCodeService.normalizePin(oldWidget.initialPin ?? '');
    if (next.length == 6 && next != prev) {
      if (_pinController.text != next) {
        _pinController.text = next;
      }
      _lookup(next);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pinController.dispose();
    _areaSectionFocus.dispose();
    super.dispose();
  }

  String _normalizedPinFromInput(String value) {
    final fromController = PinCodeService.normalizePin(_pinController.text);
    final fromCallback = PinCodeService.normalizePin(value);
    return fromController.length >= fromCallback.length
        ? fromController
        : fromCallback;
  }

  void _clearLookupState() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _lookupSucceeded = false;
      _postOffices = [];
      _selectedArea = null;
    });
  }

  void _emitPinDigits(String digits) {
    widget.onPinDigitsChanged?.call(digits);
  }

  void _onPinChanged(String value) {
    final digits = _normalizedPinFromInput(value);
    _emitPinDigits(digits);
    if (digits.length != 6) {
      _debounce?.cancel();
      _lastRequestedPin = null;
      if (_loading ||
          _lookupSucceeded ||
          _postOffices.isNotEmpty ||
          _selectedArea != null) {
        _clearLookupState();
      }
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _lookup(digits));
  }

  void _onPinCompleted(String value) {
    _debounce?.cancel();
    final digits = _normalizedPinFromInput(value);
    if (digits.length == 6) _lookup(digits);
  }

  Future<void> _lookup(String pin) async {
    final cleaned = PinCodeService.normalizePin(pin);
    if (cleaned.length != 6) return;

    _lastRequestedPin = cleaned;
    if (!mounted) return;

    final needsNetwork = !await PinCodeService.hasCachedResult(cleaned);
    if (needsNetwork) {
      setState(() {
        _loading = true;
        _lookupSucceeded = false;
      });
    }

    PinCodeFetchResponse response;
    try {
      response = await PinCodeService.lookup(cleaned);
    } catch (e, st) {
      debugPrint('PIN lookup error: $e\n$st');
      if (!mounted) return;
      _clearLookupState();
      widget.onError?.call('Unable to verify PIN. Please try again.');
      return;
    }

    if (!mounted) return;
    if (_lastRequestedPin != cleaned) return;

    if (needsNetwork) {
      setState(() => _loading = false);
    }

    switch (response.status) {
      case PinCodeFetchStatus.invalid:
        PinCodeAnalyticsService.logInvalidPin();
        _clearLookupState();
        widget.onError?.call(response.userMessage);
        break;
      case PinCodeFetchStatus.malformed:
        PinCodeAnalyticsService.logMalformedResponse();
        _clearLookupState();
        widget.onError?.call(response.userMessage);
        break;
      case PinCodeFetchStatus.networkTimeout:
        PinCodeAnalyticsService.logNetworkTimeout();
        _clearLookupState();
        widget.onError?.call(response.userMessage);
        break;
      case PinCodeFetchStatus.unknown:
        PinCodeAnalyticsService.logUnknownFailure();
        _clearLookupState();
        widget.onError?.call(response.userMessage);
        break;
      case PinCodeFetchStatus.success:
        final result = response.result!;
        final source = response.source;
        if (source == PinCodeLookupSource.memory) {
          PinCodeAnalyticsService.logCacheHit(source: 'memory');
        } else if (source == PinCodeLookupSource.disk) {
          PinCodeAnalyticsService.logCacheHit(source: 'disk');
        } else {
          PinCodeAnalyticsService.logNetworkSuccess();
        }
        if (!mounted) return;
        final areas = result.uniqueAreaNames;
        if (kDebugMode) {
          debugPrint(
            'PIN autofill: pin=$cleaned offices=${result.postOffices.length} '
            'areas=$areas primary=${result.primary.name}',
          );
        }
        setState(() {
          _postOffices = result.postOffices;
          _lookupSucceeded = true;
        });
        if (areas.length > 1) {
          // Prefill state/city from primary; user refines via post-office dropdown.
          _notifyResolved(PinCodeLocationResolver.resolve(result.primary));
          setState(() => _selectedArea = null);
          _focusAfter(multipleAreas: true);
        } else {
          final office = areas.isEmpty
              ? result.primary
              : result.officeForAreaName(areas.first);
          setState(() {
            _selectedArea = office.name.isNotEmpty ? office.name : null;
          });
          _notifyResolved(PinCodeLocationResolver.resolve(office));
          _focusAfter(multipleAreas: false);
        }
        break;
    }
  }

  void _focusAfter({required bool multipleAreas}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (multipleAreas) {
        (widget.focusAfterMultipleAreas ?? _areaSectionFocus).requestFocus();
      } else {
        widget.focusAfterSingleMatch?.requestFocus();
      }
    });
  }

  void _notifyResolved(PinCodeResolvedLocation resolved) {
    if (!mounted) return;
    final lookup = PinCodeLookupResult(postOffices: _postOffices);
    final options = pinMajorCityDropdownOptions(
      lookup,
      state: resolved.state,
    );
    widget.onApply(resolved.withPinCityOptions(options));
  }

  void _applyOffice(PinCodePostOffice office) {
    if (!mounted) return;
    final resolved = PinCodeLocationResolver.resolve(office);
    if (kDebugMode) {
      debugPrint(
        'PIN autofill apply office: ${office.name} → '
        'state=${resolved.state} city=${resolved.cityForProfile}',
      );
    }
    setState(() {
      _selectedArea = office.name.isNotEmpty ? office.name : null;
      _lookupSucceeded = true;
    });
    _notifyResolved(resolved);
    _focusAfter(multipleAreas: false);
  }

  @override
  Widget build(BuildContext context) {
    final areaNames = PinCodeLookupResult(postOffices: _postOffices)
        .uniqueAreaNames;
    final title = widget.sectionTitle?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.sacredGreen,
                ),
          ),
          const SizedBox(height: 8),
        ],
        AuthPinCodeLocationField(
          controller: _pinController,
          isLoading: _loading,
          lookupSucceeded: _lookupSucceeded,
          onChanged: (v) {
            widget.onManualLocationEdit?.call();
            _onPinChanged(v);
          },
          onCompleted: _onPinCompleted,
        ),
        if (_lookupSucceeded && areaNames.length > 1) ...[
          const SizedBox(height: 16),
          Focus(
            focusNode: _areaSectionFocus,
            child: CustomDropdown(
              label: 'Area / Post Office',
              hint: areaNames.length > 1
                  ? 'Select your area'
                  : 'Locality for this PIN',
              value: _selectedArea,
              items: areaNames,
              onChanged: (value) {
                if (value == null) return;
                final office = PinCodeLookupResult(postOffices: _postOffices)
                    .officeForAreaName(value);
                _applyOffice(office);
              },
              icon: Icons.place_outlined,
            ),
          ),
        ],
      ],
    );
  }
}
