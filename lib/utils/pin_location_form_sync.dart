import 'package:flutter/material.dart';

import '../data/reference_data.dart';
import '../services/pin_code_location_resolver.dart';
import '../services/pincode_service.dart';

/// Holds country/state/city for one PIN-autofill block (dropdown source of truth).
class PinLocationSlot {
  String? country;
  String? state;
  String city = '';
  int applySerial = 0;

  /// When non-empty, city dropdown uses only these (from PIN), not full state list.
  List<String> pinScopedCityOptions = [];

  bool get hasPinScopedCities => pinScopedCityOptions.isNotEmpty;

  void clearPinCityScope() {
    pinScopedCityOptions = [];
  }

  void seed({
    String? country,
    String? state,
    String? city,
    String defaultCountry = 'India',
  }) {
    this.country = (country?.trim().isNotEmpty ?? false) ? country!.trim() : defaultCountry;
    this.state = (state?.trim().isNotEmpty ?? false) ? state!.trim() : null;
    this.city = city?.trim() ?? '';
  }

  void applyResolved(
    PinCodeResolvedLocation resolved, {
    String defaultCountry = 'India',
  }) {
    country = resolved.country.isNotEmpty ? resolved.country : defaultCountry;
    state = resolved.state ??
        (resolved.apiState.isNotEmpty
            ? matchIndianStateFromPinApi(resolved.apiState)
            : null);
    final locality = resolved.area.trim().isNotEmpty
        ? resolved.area.trim()
        : resolved.cityForProfile;
    city = canonicalCityForState(state, locality);
    pinScopedCityOptions = resolved.pinCityOptions.isNotEmpty
        ? List<String>.from(resolved.pinCityOptions)
        : (locality.isNotEmpty ? [city] : <String>[]);
    applySerial++;
  }

  String? get cityDropdownValue {
    final t = city.trim();
    return t.isEmpty ? null : t;
  }
}

/// Picks the reference-data spelling when [rawCity] matches a known city (case-insensitive).
String canonicalCityForState(String? state, String rawCity) {
  final pick = rawCity.trim();
  if (pick.isEmpty || state == null) return pick;
  if (!ReferenceData.cities.containsKey(state)) return pick;
  for (final known in ReferenceData.cities[state]!) {
    if (known.toLowerCase() == pick.toLowerCase()) return known;
  }
  return pick;
}

/// Major cities/regions returned for a PIN (India Post region/city/division fields).
List<String> pinMajorCityDropdownOptions(
  PinCodeLookupResult result, {
  String? state,
}) {
  final seen = <String>{};
  final out = <String>[];

  void addCandidate(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return;
    final label = state != null ? canonicalCityForState(state, t) : t;
    if (label.isEmpty) return;
    final key = label.toLowerCase();
    if (seen.add(key)) out.add(label);
  }

  for (final office in result.postOffices) {
    final resolved = PinCodeLocationResolver.resolve(office);
    addCandidate(office.region);
    addCandidate(office.suggestedCity);
    addCandidate(office.division);
    addCandidate(resolved.city);
    addCandidate(office.district);
  }
  return out;
}

List<String> _mergeSelectedCity(
  List<String> items,
  String? selectedCity,
  String? state,
) {
  final pick = selectedCity?.trim() ?? '';
  if (pick.isEmpty) return items;
  final canonical = state != null ? canonicalCityForState(state, pick) : pick;
  if (canonical.isEmpty) return items;
  if (items.any((e) => e.toLowerCase() == canonical.toLowerCase())) {
    return items;
  }
  return [canonical, ...items];
}

/// City list for dropdown. After PIN, pass [pinScopedOptions] — not the full state list.
List<String> indianCityDropdownItems(
  String? state, {
  String? selectedCity,
  List<String>? pinScopedOptions,
}) {
  if (pinScopedOptions != null && pinScopedOptions.isNotEmpty) {
    final items = <String>[];
    final seen = <String>{};
    for (final raw in pinScopedOptions) {
      final label = state != null ? canonicalCityForState(state, raw) : raw.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      if (seen.add(key)) items.add(label);
    }
    return _mergeSelectedCity(items, selectedCity, state);
  }

  if (state == null || !ReferenceData.cities.containsKey(state)) {
    return const [];
  }
  final items = List<String>.from(ReferenceData.cities[state]!);
  return _mergeSelectedCity(items, selectedCity, state);
}

List<String> internationalCityDropdownItems(
  String? country, {
  String? selectedCity,
}) {
  if (country == null || !ReferenceData.citiesByCountry.containsKey(country)) {
    return const [];
  }
  final items = List<String>.from(ReferenceData.citiesByCountry[country]!);
  final pick = selectedCity?.trim() ?? '';
  if (pick.isNotEmpty && !items.any((e) => e.toLowerCase() == pick.toLowerCase())) {
    items.insert(0, pick);
  }
  return items;
}

/// Writes [city] into a profile city controller so TextFormField stays in sync.
void syncLocationCityController(TextEditingController controller, String city) {
  final trimmed = city.trim();
  controller.value = TextEditingValue(
    text: trimmed,
    selection: TextSelection.collapsed(offset: trimmed.length),
  );
}

/// Applies resolved PIN data to slot + optional legacy controller.
void applyPinResolvedToSlot({
  required PinCodeResolvedLocation resolved,
  required PinLocationSlot slot,
  TextEditingController? cityController,
  String defaultCountry = 'India',
}) {
  slot.applyResolved(resolved, defaultCountry: defaultCountry);
  if (cityController != null) {
    syncLocationCityController(cityController, slot.city);
  }
}

/// Pushes slot values into profile wizard backing fields (call inside setState).
void commitPinSlotToFields({
  required PinLocationSlot slot,
  required void Function(String?) setCountry,
  required void Function(String?) setStateValue,
}) {
  setCountry(slot.country);
  setStateValue(slot.state);
}
