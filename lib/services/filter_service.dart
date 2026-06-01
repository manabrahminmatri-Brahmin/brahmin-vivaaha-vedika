import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/search/filter_screen.dart'
    show FilterPreferences, MemberTypeFilter;

// ─────────────────────────────────────────────────────────────────────────────
// FilterService — global, persistent filter state
//
// • Registered as a ChangeNotifierProvider in main.dart so every screen that
//   calls context.watch<FilterService>() automatically rebuilds when filters
//   change.
// • Persists to SharedPreferences so filters survive tab switches, screen
//   navigation, and app restarts.
// • The ONLY place filters are stored — no more local _activeFilters fields
//   scattered across individual screens.
// ─────────────────────────────────────────────────────────────────────────────

class FilterService extends ChangeNotifier {
  FilterPreferences? _current;

  /// The currently active filter. Null means "no filter / show all".
  FilterPreferences? get current => _current;

  bool get hasFilters => _current != null && _current!.hasFilters;

  // SharedPreferences keys
  static const _keyMinAge        = 'filter_min_age';
  static const _keyMaxAge        = 'filter_max_age';
  static const _keyEducation     = 'filter_education';
  static const _keyOccupation    = 'filter_occupation';
  static const _keyIncomeRange   = 'filter_income_range';
  static const _keySect          = 'filter_sect';
  static const _keySubSect       = 'filter_sub_sect';
  static const _keyNakshatra     = 'filter_nakshatra';
  static const _keyState         = 'filter_state';
  static const _keyCountry       = 'filter_country';
  static const _keyCity          = 'filter_city';
  static const _keyMaritalStatus = 'filter_marital_status';
  static const _keyFoodHabit     = 'filter_food_habit';
  static const _keyMemberType    = 'filter_member_type';

  static int _memberTypeToStorage(MemberTypeFilter m) {
    switch (m) {
      case MemberTypeFilter.premium:
        return 1;
      case MemberTypeFilter.free:
        return 2;
      case MemberTypeFilter.all:
        return 0;
    }
  }

  static MemberTypeFilter _memberTypeFromStorage(int? v) {
    switch (v) {
      case 1:
        return MemberTypeFilter.premium;
      case 2:
        return MemberTypeFilter.free;
      default:
        return MemberTypeFilter.all;
    }
  }

  /// Drops a single filter field and keeps all others (including rarely-used fields).
  FilterPreferences _filterPreferencesMinus(FilterPreferences f, String field) {
    bool c(String name) => field == name;

    return FilterPreferences(
      minAge: c('age') ? null : f.minAge,
      maxAge: c('age') ? null : f.maxAge,
      education: c('education') ? null : f.education,
      occupation: c('occupation') ? null : f.occupation,
      incomeRange: c('incomeRange') ? null : f.incomeRange,
      sect: c('sect') ? null : f.sect,
      subSect: (c('sect') || c('subSect')) ? null : f.subSect,
      gothram: f.gothram,
      nakshatra: c('nakshatra') ? null : f.nakshatra,
      state: c('state') ? null : f.state,
      country: c('country') ? null : f.country,
      city: c('city') ? null : f.city,
      maritalStatus: c('maritalStatus') ? null : f.maritalStatus,
      foodHabit: c('foodHabit') ? null : f.foodHabit,
      religion: f.religion,
      community: f.community,
      motherTongue: f.motherTongue,
      location: f.location,
      gender: f.gender,
      minHeight: f.minHeight,
      maxHeight: f.maxHeight,
      minIncome: f.minIncome,
      maxIncome: f.maxIncome,
      diet: f.diet,
      smoking: f.smoking,
      drinking: f.drinking,
      hasPhoto: f.hasPhoto,
      isVerified: f.isVerified,
      isOnline: f.isOnline,
      memberType: c('memberType') ? MemberTypeFilter.all : f.memberType,
    );
  }

  // ── Load from SharedPreferences (call once at app start) ─────────────────

  Future<void> loadFromPrefs() async {
    try {
      debugPrint('🔍 FilterService: Loading from preferences...');
      final prefs = await SharedPreferences.getInstance();
      final minAge        = prefs.getInt(_keyMinAge);
      final maxAge        = prefs.getInt(_keyMaxAge);
      final education     = prefs.getString(_keyEducation);
      final occupation    = prefs.getString(_keyOccupation);
      final incomeRange   = prefs.getString(_keyIncomeRange);
      final sect          = prefs.getString(_keySect);
      final subSect       = prefs.getString(_keySubSect);
      final nakshatra     = prefs.getString(_keyNakshatra);
      final state         = prefs.getString(_keyState);
      final country       = prefs.getString(_keyCountry);
      final city          = prefs.getString(_keyCity);
      final maritalStatus = prefs.getString(_keyMaritalStatus);
      final foodHabit     = prefs.getString(_keyFoodHabit);
      final memberType    = _memberTypeFromStorage(prefs.getInt(_keyMemberType));

      debugPrint('🔍 FilterService raw values: minAge=$minAge, maxAge=$maxAge, '
          'education=$education, occupation=$occupation');

      // Check if any filter values are actually set (not null)
      final anySet = minAge != null ||
          maxAge != null ||
          (education != null && education.isNotEmpty) ||
          (occupation != null && occupation.isNotEmpty) ||
          (incomeRange != null && incomeRange.isNotEmpty) ||
          (sect != null && sect.isNotEmpty) ||
          (subSect != null && subSect.isNotEmpty) ||
          (nakshatra != null && nakshatra.isNotEmpty) ||
          (state != null && state.isNotEmpty) ||
          (country != null && country.isNotEmpty) ||
          (city != null && city.isNotEmpty) ||
          (maritalStatus != null && maritalStatus.isNotEmpty) ||
          (foodHabit != null && foodHabit.isNotEmpty) ||
          memberType != MemberTypeFilter.all;

      debugPrint('🔍 FilterService anySet: $anySet');

      if (anySet) {
        _current = FilterPreferences(
          minAge: minAge,
          maxAge: maxAge,
          education: education,
          occupation: occupation,
          incomeRange: incomeRange,
          sect: sect,
          subSect: subSect,
          nakshatra: nakshatra,
          state: state,
          country: country,
          city: city,
          maritalStatus: maritalStatus,
          foodHabit: foodHabit,
          memberType: memberType,
        );
      } else {
        _current = null;
      }
      notifyListeners();
      debugPrint('🔍 FilterService loaded: ${_current?.activeFilterCount ?? 0} filters active');
    } catch (e) {
      debugPrint('❌ FilterService.loadFromPrefs: $e');
      _current = null;
      notifyListeners();
    }
  }

  // ── Set / update filters ─────────────────────────────────────────────────

  Future<void> setFilters(FilterPreferences filters) async {
    debugPrint('🔍 FilterService.setFilters: ${filters.activeFilterCount} filters');
    _current = filters.hasFilters ? filters : null;
    notifyListeners();
    await _persist();
  }

  Future<void> clearFilters() async {
    debugPrint('🔍 FilterService.clearFilters: Clearing all filters');
    _current = null;
    notifyListeners();
    await _clearPrefs();
  }

  Future<void> clearSingleFilter(String field) async {
    if (_current == null) return;
    const known = {
      'age',
      'education',
      'occupation',
      'incomeRange',
      'sect',
      'subSect',
      'nakshatra',
      'state',
      'country',
      'city',
      'maritalStatus',
      'foodHabit',
      'memberType',
    };
    if (!known.contains(field)) {
      debugPrint('⚠️ FilterService.clearSingleFilter: unknown field "$field"');
      return;
    }
    final updated = _filterPreferencesMinus(_current!, field);
    _current = updated.hasFilters ? updated : null;
    notifyListeners();
    await _persist();
  }

  // ── Apply to a list of app-model Users ───────────────────────────────────

  List<T> applyToUsers<T>(
      List<T> users, bool Function(T, FilterPreferences) test) {
    if (_current == null || !_current!.hasFilters) return users;
    return users.where((u) => test(u, _current!)).toList();
  }

  // ── Count helpers ────────────────────────────────────────────────────────

  int get activeFilterCount {
    if (_current == null) return 0;
    return _current!.activeFilterCount;
  }

  // ── Private persistence helpers ──────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final f = _current;
      if (f == null) {
        await _clearPrefs();
        return;
      }

      if (f.minAge != null) {
        await prefs.setInt(_keyMinAge, f.minAge!);
      } else {
        await prefs.remove(_keyMinAge);
      }
      if (f.maxAge != null) {
        await prefs.setInt(_keyMaxAge, f.maxAge!);
      } else {
        await prefs.remove(_keyMaxAge);
      }

      _saveOrRemove(prefs, _keyEducation,     f.education);
      _saveOrRemove(prefs, _keyOccupation,    f.occupation);
      _saveOrRemove(prefs, _keyIncomeRange,   f.incomeRange);
      _saveOrRemove(prefs, _keySect,          f.sect);
      _saveOrRemove(prefs, _keySubSect,       f.subSect);
      _saveOrRemove(prefs, _keyNakshatra,     f.nakshatra);
      _saveOrRemove(prefs, _keyState,         f.state);
      _saveOrRemove(prefs, _keyCountry,      f.country);
      _saveOrRemove(prefs, _keyCity,         f.city);
      _saveOrRemove(prefs, _keyMaritalStatus, f.maritalStatus);
      _saveOrRemove(prefs, _keyFoodHabit,     f.foodHabit);
      if (f.memberType != MemberTypeFilter.all) {
        await prefs.setInt(_keyMemberType, _memberTypeToStorage(f.memberType));
      } else {
        await prefs.remove(_keyMemberType);
      }
    } catch (e) {
      debugPrint('❌ FilterService._persist: $e');
    }
  }

  Future<void> _clearPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        _keyMinAge, _keyMaxAge, _keyEducation, _keyOccupation,
        _keyIncomeRange, _keySect, _keySubSect, _keyNakshatra,
        _keyState, _keyCountry, _keyCity, _keyMaritalStatus, _keyFoodHabit,
        _keyMemberType,
      ]) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('❌ FilterService._clearPrefs: $e');
    }
  }

  static void _saveOrRemove(
      SharedPreferences prefs, String key, String? value) {
    if (value != null &&
        value.isNotEmpty &&
        value.toLowerCase() != 'any') {
      prefs.setString(key, value);
    } else {
      prefs.remove(key);
    }
  }

  // ── Legacy static shims ──────────────────────────────────────────────────

  static Future<FilterPreferences?> loadFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final minAge        = prefs.getInt(_keyMinAge);
      final maxAge        = prefs.getInt(_keyMaxAge);
      final education     = prefs.getString(_keyEducation);
      final occupation    = prefs.getString(_keyOccupation);
      final incomeRange   = prefs.getString(_keyIncomeRange);
      final sect          = prefs.getString(_keySect);
      final subSect       = prefs.getString(_keySubSect);
      final nakshatra     = prefs.getString(_keyNakshatra);
      final state         = prefs.getString(_keyState);
      final country       = prefs.getString(_keyCountry);
      final city          = prefs.getString(_keyCity);
      final maritalStatus = prefs.getString(_keyMaritalStatus);
      final foodHabit     = prefs.getString(_keyFoodHabit);
      final memberType    = _memberTypeFromStorage(prefs.getInt(_keyMemberType));
      final anySet = minAge != null || maxAge != null ||
          education != null || occupation != null ||
          incomeRange != null || sect != null || subSect != null ||
          nakshatra != null || state != null || country != null ||
          city != null || maritalStatus != null ||
          foodHabit != null || memberType != MemberTypeFilter.all;
      if (!anySet) return null;
      return FilterPreferences(
        minAge: minAge, maxAge: maxAge,
        education: education, occupation: occupation,
        incomeRange: incomeRange, sect: sect, subSect: subSect,
        nakshatra: nakshatra, state: state,
        country: country, city: city,
        maritalStatus: maritalStatus, foodHabit: foodHabit,
        memberType: memberType,
      );
    } catch (e) {
      return null;
    }
  }

  // FIX 7: Added debug warning so callers know this is a no-op shim.
  static Future<void> saveFilters(FilterPreferences filters) async {
    debugPrint('⚠️ FilterService.saveFilters() is a no-op shim. '
        'Use FilterService provider .setFilters() instead.');
  }

  static String getFilterSummary() => '';
}
