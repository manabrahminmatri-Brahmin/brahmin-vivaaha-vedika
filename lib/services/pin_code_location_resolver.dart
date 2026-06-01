import '../data/reference_data.dart';
import 'pincode_service.dart';

/// India Post / third-party API spellings → [ReferenceData.indianStates].
const Map<String, String> _pinApiStateAliases = {
  'orissa': 'Odisha',
  'odisa': 'Odisha',
  'pondicherry': 'Puducherry',
  'puducherry': 'Puducherry',
  'uttaranchal': 'Uttarakhand',
  'uttarakhand': 'Uttarakhand',
  'chattisgarh': 'Chhattisgarh',
  'chhatisgarh': 'Chhattisgarh',
  'nct of delhi': 'Delhi',
  'national capital territory of delhi': 'Delhi',
  'new delhi': 'Delhi',
  'jammu and kashmir': 'Jammu & Kashmir',
  'jammu & kashmir': 'Jammu & Kashmir',
  'andaman and nicobar islands': 'Andaman & Nicobar Islands',
  'andaman & nicobar islands': 'Andaman & Nicobar Islands',
  'dadra and nagar haveli': 'Dadra & Nagar Haveli and Daman & Diu',
  'daman and diu': 'Dadra & Nagar Haveli and Daman & Diu',
  'telangana state': 'Telangana',
  'andhra pradesh state': 'Andhra Pradesh',
};

String _normalizePinApiStateLabel(String raw) {
  var t = raw.trim().toLowerCase();
  if (t.isEmpty) return '';
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceAll(' and ', ' & ');
  return t;
}

/// Maps India Post API state names to [ReferenceData.indianStates] labels.
String? matchIndianStateFromPinApi(String apiState) {
  final t = apiState.trim();
  if (t.isEmpty) return null;

  final alias = _pinApiStateAliases[_normalizePinApiStateLabel(t)];
  if (alias != null) return alias;

  for (final s in ReferenceData.indianStates) {
    if (s == t || s.toLowerCase() == t.toLowerCase()) return s;
  }
  // Already a canonical app label (e.g. from server matchedState).
  if (ReferenceData.indianStates.contains(t)) return t;
  final normalized = t.replaceAll(' and ', ' & ').replaceAll(' And ', ' & ');
  for (final s in ReferenceData.indianStates) {
    if (s.toLowerCase() == normalized.toLowerCase()) return s;
  }
  return null;
}

/// Resolved state/city/area after India Post PIN lookup.
class PinCodeResolvedLocation {
  const PinCodeResolvedLocation({
    required this.country,
    required this.state,
    required this.apiState,
    required this.city,
    required this.area,
    required this.district,
    this.pinCityOptions = const [],
  });

  final String country;
  final String? state;
  final String apiState;
  final String city;
  final String area;
  final String district;

  /// Major cities / regions for this PIN only (not full [ReferenceData.cities]).
  final List<String> pinCityOptions;

  /// Profile City/Town — same locality as the selected post office when known.
  String get cityForProfile {
    if (area.isNotEmpty) return area;
    if (city.isNotEmpty) return city;
    if (district.isNotEmpty) return district;
    return '';
  }

  PinCodeResolvedLocation withPinCityOptions(List<String> options) {
    return PinCodeResolvedLocation(
      country: country,
      state: state,
      apiState: apiState,
      city: city,
      area: area,
      district: district,
      pinCityOptions: options,
    );
  }
}

/// Maps [PinCodePostOffice] fields to profile city/state (district ≠ city).
class PinCodeLocationResolver {
  PinCodeLocationResolver._();

  static PinCodeResolvedLocation resolve(PinCodePostOffice office) {
    final apiStateRaw = office.state.trim().isNotEmpty
        ? office.state.trim()
        : office.circle.trim();
    final matchedState = _resolveCanonicalState(apiStateRaw);
    final area = office.name.trim();
    final district = office.district.trim();
    final city = _resolveCity(
      matchedState: matchedState,
      area: area,
      district: district,
      region: office.region,
      division: office.division,
      block: office.block,
      suggestedCity: office.suggestedCity,
    );

    return PinCodeResolvedLocation(
      country: office.country.isNotEmpty ? office.country : 'India',
      state: matchedState,
      apiState: apiStateRaw,
      city: city,
      area: area,
      district: district,
      pinCityOptions: const [],
    );
  }

  static String? _resolveCanonicalState(String apiStateRaw) {
    final raw = apiStateRaw.trim();
    if (raw.isEmpty) return null;
    if (ReferenceData.indianStates.contains(raw)) return raw;
    return matchIndianStateFromPinApi(raw);
  }

  static String _resolveCity({
    required String? matchedState,
    required String area,
    required String district,
    required String region,
    required String division,
    required String block,
    String? suggestedCity,
  }) {
    // Post office locality is copied into City/Town (not a different metro name).
    if (area.isNotEmpty) {
      if (matchedState != null && ReferenceData.cities.containsKey(matchedState)) {
        final cities = ReferenceData.cities[matchedState]!;
        final exact = _exactCityMatch(cities, area);
        if (exact != null) return exact;
        final fuzzy = _fuzzyCityMatch(cities, area);
        if (fuzzy != null) return fuzzy;
      }
      return area;
    }

    final candidates = <String>[
      if (suggestedCity != null && suggestedCity.isNotEmpty) suggestedCity,
      if (region.isNotEmpty) region,
      if (division.isNotEmpty) division,
      if (block.isNotEmpty) block,
      if (district.isNotEmpty) district,
    ];

    if (matchedState != null && ReferenceData.cities.containsKey(matchedState)) {
      final cities = ReferenceData.cities[matchedState]!;
      for (final candidate in candidates) {
        final exact = _exactCityMatch(cities, candidate);
        if (exact != null) return exact;
      }
      for (final candidate in candidates) {
        final fuzzy = _fuzzyCityMatch(cities, candidate);
        if (fuzzy != null) return fuzzy;
      }
    }

    for (final candidate in [region, division, block, district]) {
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  static String? _exactCityMatch(List<String> cities, String candidate) {
    final c = candidate.trim();
    if (c.isEmpty) return null;
    for (final city in cities) {
      if (city.toLowerCase() == c.toLowerCase()) return city;
    }
    return null;
  }

  static String? _fuzzyCityMatch(List<String> cities, String candidate) {
    final c = candidate.trim().toLowerCase();
    if (c.isEmpty) return null;
    for (final city in cities) {
      final lc = city.toLowerCase();
      if (lc.contains(c) || c.contains(lc)) return city;
    }
    return null;
  }
}
