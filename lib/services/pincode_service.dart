import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_firebase_functions.dart';
import 'pin_code_location_resolver.dart';

/// One post office entry from India Post PIN API.
class PinCodePostOffice {
  const PinCodePostOffice({
    required this.name,
    required this.district,
    required this.state,
    this.country = 'India',
    this.region = '',
    this.division = '',
    this.block = '',
    this.circle = '',
    this.suggestedCity,
  });

  final String name;
  final String district;
  final String state;
  final String country;

  /// India Post `Region` — often the nearest city/town name.
  final String region;

  /// India Post `Division` — postal division (frequently matches city).
  final String division;

  /// India Post `Block` — sub-district / taluk label.
  final String block;

  /// India Post `Circle` — often carries state when `State` is blank.
  final String circle;

  /// Server-resolved city from PIN lookup (when available).
  final String? suggestedCity;

  Map<String, String> toLocationMap() {
    final resolved = PinCodeLocationResolver.resolve(this);
    return {
      'state': resolved.state ?? state,
      'city': resolved.city,
      'area': resolved.area.isNotEmpty ? resolved.area : name,
      'country': resolved.country,
      if (district.isNotEmpty) 'district': district,
    };
  }
}

/// Result of a PIN lookup (may include multiple post offices).
class PinCodeLookupResult {
  const PinCodeLookupResult({required this.postOffices});

  final List<PinCodePostOffice> postOffices;

  PinCodePostOffice get primary => postOffices.first;

  /// Unique post-office localities (India Post `Name`).
  List<String> get uniqueAreaNames {
    final seen = <String>{};
    final names = <String>[];
    for (final office in postOffices) {
      final name = office.name.trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      names.add(name);
    }
    return names;
  }

  bool get hasMultipleAreas => uniqueAreaNames.length > 1;

  List<String> get areaNames => uniqueAreaNames;

  PinCodePostOffice officeForAreaName(String areaName) {
    final target = areaName.trim();
    for (final office in postOffices) {
      if (office.name.trim() == target) return office;
    }
    return primary;
  }
}

enum PinCodeFetchStatus {
  success,
  invalid,
  malformed,
  networkTimeout,
  unknown,
}

/// Where a successful lookup result came from.
enum PinCodeLookupSource {
  memory,
  disk,
  network,
}

class PinCodeFetchResponse {
  const PinCodeFetchResponse._({
    required this.status,
    this.result,
    this.source,
  });

  final PinCodeFetchStatus status;
  final PinCodeLookupResult? result;
  final PinCodeLookupSource? source;

  bool get fromCache =>
      source == PinCodeLookupSource.memory ||
      source == PinCodeLookupSource.disk;

  factory PinCodeFetchResponse.success(
    PinCodeLookupResult result, {
    required PinCodeLookupSource source,
  }) =>
      PinCodeFetchResponse._(
        status: PinCodeFetchStatus.success,
        result: result,
        source: source,
      );

  factory PinCodeFetchResponse.invalid() => const PinCodeFetchResponse._(
        status: PinCodeFetchStatus.invalid,
      );

  factory PinCodeFetchResponse.malformed() => const PinCodeFetchResponse._(
        status: PinCodeFetchStatus.malformed,
      );

  factory PinCodeFetchResponse.networkTimeout() =>
      const PinCodeFetchResponse._(
        status: PinCodeFetchStatus.networkTimeout,
      );

  factory PinCodeFetchResponse.unknown() => const PinCodeFetchResponse._(
        status: PinCodeFetchStatus.unknown,
      );

  /// User-facing SnackBar / validation copy.
  String get userMessage {
    switch (status) {
      case PinCodeFetchStatus.invalid:
        return 'Invalid PIN code.';
      case PinCodeFetchStatus.malformed:
        return 'Unable to verify PIN. Please try again.';
      case PinCodeFetchStatus.networkTimeout:
        return 'PIN lookup timed out. Please try again.';
      case PinCodeFetchStatus.unknown:
        return 'Unable to verify PIN. Please try again.';
      case PinCodeFetchStatus.success:
        return '';
    }
  }
}

/// India Post PIN lookup via Firebase Cloud Function (production path).
class PinCodeService {
  PinCodeService._();

  static const String _cloudFunctionName = 'lookupIndianPincode';

  /// Direct India Post API — debug-only; uses normal TLS (no certificate bypass).
  @visibleForTesting
  static const String debugDirectApiBaseUrl =
      'https://api.postalpincode.in/pincode';

  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxAttempts = 2;
  static const Map<String, String> _requestHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'BrahminVivaahaVedika/1.0 (Flutter; PIN lookup)',
  };
  static const Duration _cacheTtl = Duration(days: 30);
  static const String _cacheVersionPrefix = 'pincode_v2_';

  /// In-session cache for instant repeat lookups (offline-friendly).
  static final Map<String, PinCodeLookupResult> _memoryCache = {};

  /// Coalesce parallel lookups for the same PIN (debounce + onCompleted).
  static final Map<String, Future<PinCodeFetchResponse>> _inflight = {};

  @visibleForTesting
  static void clearMemoryCacheForTests() => _memoryCache.clear();

  @visibleForTesting
  static void seedMemoryCacheForTests(String pin, PinCodeLookupResult result) {
    _rememberInMemory(normalizePin(pin), result);
  }

  /// Versioned cache key, e.g. `pincode_v2_520010`.
  @visibleForTesting
  static String cacheKeyForPin(String pin) => '$_cacheVersionPrefix$pin';

  /// Guards async responses when the user changes PIN before the request finishes.
  @visibleForTesting
  static bool isStaleRequest(String? lastRequestedPin, String currentPin) =>
      lastRequestedPin != currentPin;

  static String normalizePin(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  static void _rememberInMemory(String pin, PinCodeLookupResult result) {
    _memoryCache[pin] = result;
  }

  /// True when this PIN is available locally (memory or disk) — no network needed.
  static Future<bool> hasCachedResult(String pin) async {
    final cleaned = normalizePin(pin);
    if (cleaned.length != 6) return false;
    if (_memoryCache.containsKey(cleaned)) return true;
    final disk = await _readCache(cleaned);
    if (disk != null) {
      _rememberInMemory(cleaned, disk);
      return true;
    }
    return false;
  }

  /// Fetches location for a 6-digit PIN. Returns `null` on any failure.
  static Future<Map<String, String>?> fetchLocation(String pin) async {
    final response = await lookup(pin);
    if (response.status != PinCodeFetchStatus.success ||
        response.result == null) {
      return null;
    }
    return response.result!.primary.toLocationMap();
  }

  /// Full lookup: memory → disk (offline) → Cloud Function (all platforms).
  static Future<PinCodeFetchResponse> lookup(String pin) async {
    final cleaned = normalizePin(pin);
    if (cleaned.length != 6) {
      return PinCodeFetchResponse.invalid();
    }

    final inMemory = _memoryCache[cleaned];
    if (inMemory != null) {
      return PinCodeFetchResponse.success(
        inMemory,
        source: PinCodeLookupSource.memory,
      );
    }

    final onDisk = await _readCache(cleaned);
    if (onDisk != null) {
      _rememberInMemory(cleaned, onDisk);
      return PinCodeFetchResponse.success(
        onDisk,
        source: PinCodeLookupSource.disk,
      );
    }

    final existing = _inflight[cleaned];
    if (existing != null) return existing;

    final future = _lookupFromCloud(cleaned);
    _inflight[cleaned] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(cleaned);
    }
  }

  static Future<PinCodeFetchResponse> _lookupFromCloud(String cleaned) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final payload = await _callLookupCloudFunction(cleaned);
        final status = statusFromCloudPayload(payload);
        if (status != null) return status;

        final parsed = parseCloudPayload(payload);
        if (parsed != null) {
          if (kDebugMode) {
            debugPrint(
              'PinCodeService: parsed PIN $cleaned — '
              '${parsed.postOffices.length} office(s), '
              'areas=${parsed.uniqueAreaNames}',
            );
          }
          _rememberInMemory(cleaned, parsed);
          await _writeCache(cleaned, parsed);
          return PinCodeFetchResponse.success(
            parsed,
            source: PinCodeLookupSource.network,
          );
        }

        if (kDebugMode) {
          debugPrint(
            'PinCodeService: parseCloudPayload returned null for PIN $cleaned '
            '(keys=${payload.keys.toList()})',
          );
        }

        if (attempt < _maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return PinCodeFetchResponse.malformed();
      } on TimeoutException catch (e, st) {
        debugPrint('PinCodeService.lookup timeout: $e\n$st');
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return PinCodeFetchResponse.networkTimeout();
      } on FirebaseFunctionsException catch (e, st) {
        debugPrint(
          'PinCodeService.lookup cloud error [${e.code}]: ${e.message}\n$st',
        );
        final mapped = statusFromFunctionsException(e);
        if (mapped != null) return mapped;
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return PinCodeFetchResponse.unknown();
      } catch (e, st) {
        debugPrint('PinCodeService.lookup failed: $e\n$st');
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return PinCodeFetchResponse.unknown();
      }
    }
    return PinCodeFetchResponse.unknown();
  }

  static Future<Map<String, dynamic>> _callLookupCloudFunction(
    String pin,
  ) async {
    final callable = appFirebaseFunctions.httpsCallable(
      _cloudFunctionName,
      options: HttpsCallableOptions(timeout: _timeout),
    );
    final result = await callable.call({'pin': pin}).timeout(_timeout);
    final payload = coercePayloadMap(result.data);
    if (payload == null) {
      if (kDebugMode) {
        debugPrint(
          'PinCodeService: lookupIndianPincode (asia-south1) returned '
          'non-map data type=${result.data.runtimeType} data=${result.data}',
        );
      }
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'PIN lookup returned unexpected payload',
      );
    }
    if (kDebugMode) {
      debugPrint(
        'PinCodeService: lookupIndianPincode ok pin=$pin '
        'success=${payload['success']} '
        'postOffices=${_listLength(payload['postOffices'] ?? payload['offices'])} '
        'areas=${_listLength(payload['areas'])} '
        'state=${payload['state']} city=${payload['city']} district=${payload['district']}',
      );
    }
    return payload;
  }

  static int? _listLength(dynamic value) => value is List ? value.length : null;

  /// Normalizes Firebase callable `result.data` (Map or Map<Object?, Object?>).
  @visibleForTesting
  static Map<String, dynamic>? coercePayloadMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  @visibleForTesting
  static bool isTruthySuccess(dynamic value) {
    if (value == true) return true;
    if (value is num && value != 0) return true;
    final s = value?.toString().trim().toLowerCase() ?? '';
    return s == 'true' || s == '1' || s == 'success';
  }

  @visibleForTesting
  static PinCodeFetchResponse? statusFromCloudPayload(
    Map<String, dynamic> payload,
  ) {
    if (isTruthySuccess(payload['success'])) return null;
    final error = payload['error']?.toString().toLowerCase() ?? '';
    switch (error) {
      case 'invalid':
        return PinCodeFetchResponse.invalid();
      case 'timeout':
        return PinCodeFetchResponse.networkTimeout();
      case 'unavailable':
      case 'malformed':
        return PinCodeFetchResponse.unknown();
      default:
        return PinCodeFetchResponse.unknown();
    }
  }

  @visibleForTesting
  static PinCodeFetchResponse? statusFromFunctionsException(
    FirebaseFunctionsException e,
  ) {
    switch (e.code) {
      case 'invalid-argument':
        return PinCodeFetchResponse.invalid();
      case 'deadline-exceeded':
        return PinCodeFetchResponse.networkTimeout();
      case 'unavailable':
        return PinCodeFetchResponse.unknown();
      default:
        return null;
    }
  }

  /// Parses normalized Cloud Function payload into [PinCodeLookupResult].
  @visibleForTesting
  static PinCodeLookupResult? parseCloudPayload(Map<String, dynamic> payload) {
    if (!isTruthySuccess(payload['success'])) return null;

    final fromOffices = _postOfficesFromPayloadList(
      payload['postOffices'] ?? payload['offices'],
    );
    if (fromOffices.isNotEmpty) {
      return PinCodeLookupResult(postOffices: fromOffices);
    }

    final areaNames = _stringList(payload['areas']);
    if (areaNames.isNotEmpty) {
      final synthetic = areaNames
          .map((a) => _syntheticOfficeFromPayload(payload, areaName: a))
          .toList();
      return PinCodeLookupResult(postOffices: synthetic);
    }

    final summary = _syntheticOfficeFromPayload(
      payload,
      areaName: payload['area']?.toString().trim() ?? '',
    );
    if (_officeHasLocationData(summary)) {
      return PinCodeLookupResult(postOffices: [summary]);
    }
    return null;
  }

  static bool _officeHasLocationData(PinCodePostOffice office) {
    return office.state.trim().isNotEmpty ||
        office.district.trim().isNotEmpty ||
        office.name.trim().isNotEmpty ||
        (office.suggestedCity?.trim().isNotEmpty ?? false) ||
        office.region.trim().isNotEmpty;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final t = item?.toString().trim() ?? '';
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
    }
    return out;
  }

  static List<PinCodePostOffice> _postOfficesFromPayloadList(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final offices = <PinCodePostOffice>[];
    for (final item in raw) {
      final m = coercePayloadMap(item);
      if (m == null) continue;
      final office = _postOfficeFromMap(m);
      if (office != null) offices.add(office);
    }
    return offices;
  }

  static PinCodePostOffice _syntheticOfficeFromPayload(
    Map<String, dynamic> payload, {
    required String areaName,
  }) {
    final matchedState = payload['matchedState']?.toString().trim() ?? '';
    final apiState = payload['state']?.toString().trim() ?? '';
    final state = matchedState.isNotEmpty ? matchedState : apiState;
    final city = payload['city']?.toString().trim() ?? '';
    final district = payload['district']?.toString().trim() ?? '';
    final area = areaName.trim().isNotEmpty
        ? areaName.trim()
        : (payload['area']?.toString().trim() ?? '');
    final country = payload['country']?.toString().trim().isNotEmpty == true
        ? payload['country'].toString().trim()
        : 'India';
    return PinCodePostOffice(
      name: area.isNotEmpty ? area : district,
      district: district,
      state: state,
      country: country,
      region: city,
      suggestedCity: city.isNotEmpty ? city : null,
    );
  }

  static PinCodePostOffice? _postOfficeFromMap(Map<String, dynamic> m) {
    var name = m['name']?.toString().trim() ?? m['area']?.toString().trim() ?? '';
    final district = m['district']?.toString().trim() ?? '';
    if (name.isEmpty && district.isNotEmpty) name = district;
    final matchedState = m['matchedState']?.toString().trim() ?? '';
    final apiState = m['state']?.toString().trim() ?? '';
    final state = matchedState.isNotEmpty ? matchedState : apiState;
    final country = m['country']?.toString().trim().isNotEmpty == true
        ? m['country'].toString().trim()
        : 'India';
    final city = m['city']?.toString().trim() ?? '';
    final region = m['region']?.toString().trim() ?? '';
    if (name.isEmpty && district.isEmpty && state.isEmpty && city.isEmpty) {
      return null;
    }
    return PinCodePostOffice(
      name: name,
      district: district,
      state: state,
      country: country,
      region: region.isNotEmpty ? region : city,
      division: m['division']?.toString().trim() ?? '',
      block: m['block']?.toString().trim() ?? '',
      circle: m['circle']?.toString().trim() ?? '',
      suggestedCity: city.isNotEmpty
          ? city
          : (region.isNotEmpty ? region : null),
    );
  }

  /// Debug-only: direct India Post API (strict TLS). Not used in release builds.
  @visibleForTesting
  static Future<PinCodeFetchResponse> lookupViaDirectApiDebug(String pin) async {
    if (!kDebugMode) {
      return PinCodeFetchResponse.unknown();
    }
    final cleaned = normalizePin(pin);
    if (cleaned.length != 6) return PinCodeFetchResponse.invalid();
    try {
      final uri = Uri.parse('$debugDirectApiBaseUrl/$cleaned');
      final response = await http
          .get(uri, headers: _requestHeaders)
          .timeout(_timeout);
      final parsed = parseResponseBody(response.body);
      if (parsed == null) {
        final apiStatus = readApiStatus(response.body);
        if (apiStatus != null && apiStatus.toLowerCase() != 'success') {
          return PinCodeFetchResponse.invalid();
        }
        return PinCodeFetchResponse.malformed();
      }
      return PinCodeFetchResponse.success(
        parsed,
        source: PinCodeLookupSource.network,
      );
    } on TimeoutException {
      return PinCodeFetchResponse.networkTimeout();
    } catch (_) {
      return PinCodeFetchResponse.unknown();
    }
  }

  static String _fieldAsString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  static String _pickStateFromOfficeMap(Map<String, dynamic> map) =>
      _fieldAsString(map, ['State', 'state', 'Circle', 'circle']);

  @visibleForTesting
  static Map<String, dynamic>? decodeApiRoot(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        if (decoded.isEmpty) return null;
        final first = decoded.first;
        if (first is Map) return Map<String, dynamic>.from(first);
        return null;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static List<Map<String, dynamic>> coercePostOfficeMaps(dynamic raw) {
    if (raw == null) return const [];
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  @visibleForTesting
  static String? readApiStatus(String body) {
    final rootMap = decodeApiRoot(body);
    if (rootMap == null) return null;
    return (rootMap['Status'] ?? rootMap['status'])?.toString().trim();
  }

  /// Parses raw India Post JSON (debug / unit tests only).
  @visibleForTesting
  static PinCodeLookupResult? parseResponseBody(String body) {
    try {
      final rootMap = decodeApiRoot(body);
      if (rootMap == null) return null;

      final status =
          (rootMap['Status'] ?? rootMap['status'])?.toString().trim();
      if (status == null || status.isEmpty) return null;
      if (status.toLowerCase() != 'success') return null;

      final officesRaw = rootMap['PostOffice'] ??
          rootMap['postOffice'] ??
          rootMap['Postoffices'] ??
          rootMap['postoffices'];
      final officeMaps = coercePostOfficeMaps(officesRaw);
      if (officeMaps.isEmpty) return null;

      final offices = <PinCodePostOffice>[];
      for (final map in officeMaps) {
        final name = _fieldAsString(map, ['Name', 'name']);
        final district = _fieldAsString(map, ['District', 'district']);
        final state = _pickStateFromOfficeMap(map);
        final country =
            _fieldAsString(map, ['Country', 'country']).isEmpty
                ? 'India'
                : _fieldAsString(map, ['Country', 'country']);
        final region = _fieldAsString(map, ['Region', 'region']);
        final division = _fieldAsString(map, ['Division', 'division']);
        final block = _fieldAsString(map, ['Block', 'block']);
        final circle = _fieldAsString(map, ['Circle', 'circle']);
        if (district.isEmpty && name.isEmpty) continue;
        offices.add(
          PinCodePostOffice(
            name: name,
            district: district,
            state: state,
            country: country,
            region: region,
            division: division,
            block: block,
            circle: circle,
          ),
        );
      }

      if (offices.isEmpty) return null;
      return PinCodeLookupResult(postOffices: offices);
    } catch (e) {
      debugPrint('PinCodeService.parseResponseBody: $e');
      return null;
    }
  }

  static Future<PinCodeLookupResult?> _readCache(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKeyForPin(pin));
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final ts = decoded['ts'] as int?;
      if (ts == null) return null;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(ts);
      if (DateTime.now().difference(savedAt) > _cacheTtl) {
        await prefs.remove(cacheKeyForPin(pin));
        return null;
      }

      final officesJson = decoded['offices'];
      if (officesJson is! List) return null;

      final offices = <PinCodePostOffice>[];
      for (final o in officesJson) {
        if (o is! Map) continue;
        final office = _postOfficeFromMap(Map<String, dynamic>.from(o));
        if (office != null) offices.add(office);
      }
      if (offices.isEmpty) return null;
      return PinCodeLookupResult(postOffices: offices);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String pin, PinCodeLookupResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'offices': result.postOffices
            .map(
              (o) => {
                'name': o.name,
                'district': o.district,
                'state': o.state,
                'matchedState': o.state,
                'country': o.country,
                'region': o.region,
                'city': o.suggestedCity ?? o.region,
                'division': o.division,
                'block': o.block,
                'circle': o.circle,
              },
            )
            .toList(),
      };
      await prefs.setString(cacheKeyForPin(pin), jsonEncode(payload));
    } catch (_) {}
  }
}
