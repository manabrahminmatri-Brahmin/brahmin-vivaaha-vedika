import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../data/reference_data.dart';
import '../../legacy/compatibility.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/app_header.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FilterPreferences — immutable value object that holds all filter state.
// ─────────────────────────────────────────────────────────────────────────────

/// Member type filter values
enum MemberTypeFilter { all, premium, free }

class FilterPreferences {
  final int? minAge;
  final int? maxAge;
  final String? education;
  final String? occupation;
  final String? incomeRange;
  final String? sect;
  final String? subSect;
  final String? gothram;
  final String? nakshatra;
  final String? state;
  final String? country;
  final String? city;
  final String? maritalStatus;
  final String? foodHabit;
  final String? religion;
  final String? community;
  final String? motherTongue;
  final String? location;
  final String? gender;
  final double? minHeight;
  final double? maxHeight;
  final int? minIncome;
  final int? maxIncome;
  final String? diet;
  final String? smoking;
  final String? drinking;
  final bool? hasPhoto;
  final bool? isVerified;
  final bool? isOnline;
  final MemberTypeFilter memberType;

  const FilterPreferences({
    this.minAge,
    this.maxAge,
    this.education,
    this.occupation,
    this.incomeRange,
    this.sect,
    this.subSect,
    this.gothram,
    this.nakshatra,
    this.state,
    this.country,
    this.city,
    this.maritalStatus,
    this.foodHabit,
    this.religion,
    this.community,
    this.motherTongue,
    this.location,
    this.gender,
    this.minHeight,
    this.maxHeight,
    this.minIncome,
    this.maxIncome,
    this.diet,
    this.smoking,
    this.drinking,
    this.hasPhoto,
    this.isVerified,
    this.isOnline,
    this.memberType = MemberTypeFilter.all,
  });

  FilterPreferences copyWith({
    int? minAge,
    int? maxAge,
    String? education,
    String? occupation,
    String? incomeRange,
    String? sect,
    String? subSect,
    String? gothram,
    String? nakshatra,
    String? state,
    String? country,
    String? city,
    String? maritalStatus,
    String? foodHabit,
    String? religion,
    String? community,
    String? motherTongue,
    String? location,
    String? gender,
    double? minHeight,
    double? maxHeight,
    int? minIncome,
    int? maxIncome,
    String? diet,
    String? smoking,
    String? drinking,
    bool? hasPhoto,
    bool? isVerified,
    bool? isOnline,
    MemberTypeFilter? memberType,
  }) {
    return FilterPreferences(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      education: education ?? this.education,
      occupation: occupation ?? this.occupation,
      incomeRange: incomeRange ?? this.incomeRange,
      sect: sect ?? this.sect,
      subSect: subSect ?? this.subSect,
      gothram: gothram ?? this.gothram,
      nakshatra: nakshatra ?? this.nakshatra,
      state: state ?? this.state,
      country: country ?? this.country,
      city: city ?? this.city,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      foodHabit: foodHabit ?? this.foodHabit,
      religion: religion ?? this.religion,
      community: community ?? this.community,
      motherTongue: motherTongue ?? this.motherTongue,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      minHeight: minHeight ?? this.minHeight,
      maxHeight: maxHeight ?? this.maxHeight,
      minIncome: minIncome ?? this.minIncome,
      maxIncome: maxIncome ?? this.maxIncome,
      diet: diet ?? this.diet,
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      hasPhoto: hasPhoto ?? this.hasPhoto,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      memberType: memberType ?? this.memberType,
    );
  }

  /// Returns true when the value should be treated as an active filter.
  static bool _isFilterValue(String? value) {
    return value != null && value.isNotEmpty && value.toLowerCase() != 'any';
  }

  bool get hasFilters =>
      minAge != null ||
      maxAge != null ||
      _isFilterValue(education) ||
      _isFilterValue(occupation) ||
      _isFilterValue(incomeRange) ||
      _isFilterValue(sect) ||
      _isFilterValue(subSect) ||
      _isFilterValue(nakshatra) ||
      _isFilterValue(state) ||
      _isFilterValue(country) ||
      _isFilterValue(city) ||
      _isFilterValue(maritalStatus) ||
      _isFilterValue(foodHabit) ||
      memberType != MemberTypeFilter.all;

  int get activeFilterCount {
    int c = 0;
    if (minAge != null || maxAge != null) c++;
    if (_isFilterValue(education)) c++;
    if (_isFilterValue(occupation)) c++;
    if (_isFilterValue(incomeRange)) c++;
    if (_isFilterValue(sect)) c++;
    if (_isFilterValue(subSect)) c++;
    if (_isFilterValue(nakshatra)) c++;
    if (_isFilterValue(state)) c++;
    if (_isFilterValue(country)) c++;
    if (_isFilterValue(city)) c++;
    if (_isFilterValue(maritalStatus)) c++;
    if (_isFilterValue(foodHabit)) c++;
    if (memberType != MemberTypeFilter.all) c++;
    return c;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FilterScreen
// ─────────────────────────────────────────────────────────────────────────────

class FilterScreen extends StatefulWidget {
  final FilterPreferences? initialFilters;
  final ValueChanged<FilterPreferences> onApply;
  final bool useScaffold;

  const FilterScreen({
    super.key,
    this.initialFilters,
    required this.onApply,
    this.useScaffold = true,
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  // Use nullable ints for age so that an untouched slider does NOT
  // count as an active filter. null = "Any age".
  int? _minAge;
  int? _maxAge;

  String? _education;
  String? _occupation;
  String? _incomeRange;
  String? _sect;
  String? _subSect;
  String? _nakshatra;
  String? _country;
  String? _state;
  String? _maritalStatus;
  String? _foodHabit;

  MemberTypeFilter _memberType = MemberTypeFilter.all;

  // Controllers for "Other" custom input fields
  final TextEditingController _educationOtherController =
      TextEditingController();
  final TextEditingController _occupationOtherController =
      TextEditingController();
  final TextEditingController _incomeRangeOtherController =
      TextEditingController();
  final TextEditingController _sectOtherController = TextEditingController();
  final TextEditingController _subSectOtherController = TextEditingController();
  final TextEditingController _nakshatraOtherController =
      TextEditingController();
  final TextEditingController _countryOtherController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _nonIndiaStateController =
      TextEditingController();
  final TextEditingController _stateOtherController = TextEditingController();
  final TextEditingController _maritalStatusOtherController =
      TextEditingController();
  final TextEditingController _foodHabitOtherController =
      TextEditingController();

  // Sentinel default values — slider only counts as an active filter when
  // the user has moved it away from these values.
  static const int _kDefaultMinAge = 18;
  static const int _kDefaultMaxAge = 50;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;

    // Initialise age as null when no saved filter exists.
    // The slider displays _minAge ?? _kDefaultMinAge so the UI still shows
    // sensible values, but null means "no age filter applied".
    _minAge = f?.minAge;
    _maxAge = f?.maxAge;
    _memberType = f?.memberType ?? MemberTypeFilter.all;

    _education = f?.education;
    _occupation = f?.occupation;
    _incomeRange = f?.incomeRange;
    _sect = f?.sect;
    _subSect = f?.subSect;
    _nakshatra = f?.nakshatra;
    _maritalStatus = f?.maritalStatus;
    _foodHabit = f?.foodHabit;

    _country = f?.country;
    if (f?.country != null &&
        f!.country!.isNotEmpty &&
        !ReferenceData.searchFilterCountries.contains(f.country!)) {
      _countryOtherController.text = f.country!;
      _country = 'Other';
    }

    _cityController.text = f?.city?.trim() ?? '';

    final resolvedCountry = _peekResolvedCountry();
    final useIndianStateUi =
        resolvedCountry == null || resolvedCountry == 'India';

    if (!useIndianStateUi) {
      _nonIndiaStateController.text = f?.state?.trim() ?? '';
      _state = null;
    } else {
      _state = f?.state;
      if (f?.state != null && !ReferenceData.indianStates.contains(f!.state)) {
        _state = 'Other';
        _stateOtherController.text = f.state!;
      }
    }

    // Restore "Other" custom text if a saved value isn't in the reference list
    if (f?.education != null &&
        !ReferenceData.educationLevels.contains(f!.education)) {
      _education = 'Other';
      _educationOtherController.text = f.education!;
    }
    if (f?.occupation != null &&
        !ReferenceData.occupations.contains(f!.occupation)) {
      _occupation = 'Other';
      _occupationOtherController.text = f.occupation!;
    }
    if (f?.incomeRange != null &&
        !ReferenceData.incomeRanges.contains(f!.incomeRange)) {
      _incomeRange = 'Other';
      _incomeRangeOtherController.text = f.incomeRange!;
    }
    if (f?.sect != null && !ReferenceData.sects.contains(f!.sect)) {
      _sect = 'Other';
      _sectOtherController.text = f.sect!;
    }
    if (f?.subSect != null &&
        _sect != null &&
        !ReferenceData.subSectsForSect(_sect!).contains(f!.subSect)) {
      _subSect = 'Other';
      _subSectOtherController.text = f.subSect!;
    }
    if (f?.nakshatra != null &&
        !ReferenceData.nakshatrasSimple.contains(f!.nakshatra)) {
      _nakshatra = 'Other';
      _nakshatraOtherController.text = f.nakshatra!;
    }
    if (f?.maritalStatus != null &&
        !ReferenceData.maritalStatuses.contains(f!.maritalStatus)) {
      _maritalStatus = 'Other';
      _maritalStatusOtherController.text = f.maritalStatus!;
    }
    if (f?.foodHabit != null &&
        !ReferenceData.foodHabits.contains(f!.foodHabit)) {
      _foodHabit = 'Other';
      _foodHabitOtherController.text = f.foodHabit!;
    }
  }

  @override
  void dispose() {
    _educationOtherController.dispose();
    _occupationOtherController.dispose();
    _incomeRangeOtherController.dispose();
    _sectOtherController.dispose();
    _subSectOtherController.dispose();
    _nakshatraOtherController.dispose();
    _countryOtherController.dispose();
    _cityController.dispose();
    _nonIndiaStateController.dispose();
    _stateOtherController.dispose();
    _maritalStatusOtherController.dispose();
    _foodHabitOtherController.dispose();
    super.dispose();
  }

  /// Country as stored in [FilterPreferences] (after resolving "Other").
  String? _peekResolvedCountry() {
    if (_country == null) return null;
    if (_country == 'Other') {
      final t = _countryOtherController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _country;
  }

  bool _useIndianStatePicker() {
    final c = _peekResolvedCountry();
    return c == null || c == 'India';
  }

  // ── Clear all filters ────────────────────────────────────────────────────

  void _clearFilters() {
    setState(() {
      // Reset age to null ("Any") not to the default int values.
      _minAge = null;
      _maxAge = null;
      _memberType = MemberTypeFilter.all;
      _education = null;
      _occupation = null;
      _incomeRange = null;
      _sect = null;
      _subSect = null;
      _nakshatra = null;
      _country = null;
      _state = null;
      _maritalStatus = null;
      _foodHabit = null;

      _educationOtherController.clear();
      _occupationOtherController.clear();
      _incomeRangeOtherController.clear();
      _sectOtherController.clear();
      _subSectOtherController.clear();
      _nakshatraOtherController.clear();
      _countryOtherController.clear();
      _cityController.clear();
      _nonIndiaStateController.clear();
      _stateOtherController.clear();
      _maritalStatusOtherController.clear();
      _foodHabitOtherController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Filters reset to default values'),
          duration: Duration(seconds: 2),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
    }
  }

  // ── Apply filters ────────────────────────────────────────────────────────

  void _applyFilters() {
    // Resolve "Other" custom input values; null / "Any" → no filter
    String? resolve(String? selected, TextEditingController ctrl) {
      if (selected == 'Other') {
        final text = ctrl.text.trim();
        return text.isEmpty ? null : text;
      }
      if (selected == null || selected == 'Any') return null;
      return selected;
    }

    final education = resolve(_education, _educationOtherController);
    final occupation = resolve(_occupation, _occupationOtherController);
    final incomeRange = resolve(_incomeRange, _incomeRangeOtherController);
    final sect = resolve(_sect, _sectOtherController);
    final subSect = resolve(_subSect, _subSectOtherController);
    final nakshatra = resolve(_nakshatra, _nakshatraOtherController);
    final country = resolve(_country, _countryOtherController);
    final state = _useIndianStatePicker()
        ? resolve(_state, _stateOtherController)
        : () {
            final t = _nonIndiaStateController.text.trim();
            return t.isEmpty ? null : t;
          }();
    final cityText = _cityController.text.trim();
    final city = cityText.isEmpty ? null : cityText;
    final maritalStatus =
        resolve(_maritalStatus, _maritalStatusOtherController);
    final foodHabit = resolve(_foodHabit, _foodHabitOtherController);

    // Only pass age values when the slider was actually moved from defaults.
    final bool ageIsDefault = (_minAge == null || _minAge == _kDefaultMinAge) &&
        (_maxAge == null || _maxAge == _kDefaultMaxAge);

    final filters = FilterPreferences(
      minAge: ageIsDefault ? null : _minAge,
      maxAge: ageIsDefault ? null : _maxAge,
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
      memberType: _memberType,
    );

    // FIX: Pop FIRST before notifying listeners.
    // Calling setFilters() triggers notifyListeners() synchronously, which
    // rebuilds FilterSettingsScreen (context.watch) while this widget is still
    // mounted — causing a black screen.
    // We capture the service reference BEFORE popping so context is still valid.
    final filterService = context.read<FilterService>();
    final onApply = widget.onApply;

    // Guard against widget being unmounted before this is called
    if (!mounted) return;

    Navigator.pop(context);
    filterService.setFilters(filters);
    onApply(filters);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static List<String> _getItemsWithAnyAndOther(List<String> items) =>
      ['Any', ...items, 'Other'];

  Widget _buildMemberTypeChip({
    required String label,
    required IconData icon,
    required MemberTypeFilter value,
    Color? accentColor,
  }) {
    final isSelected = _memberType == value;
    final color = accentColor ?? AC.textSub(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _memberType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AC.border(context).withAlpha(80),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20, color: isSelected ? color : AC.textMuted(context)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : AC.textMuted(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AC.textSub(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Slider display values — fall back to defaults when null (untouched)
    final displayMin = (_minAge ?? _kDefaultMinAge).toDouble();
    final displayMax = (_maxAge ?? _kDefaultMaxAge).toDouble();

    return Scaffold(
      appBar: AppHeader(title: 'Filter Profiles'),
      backgroundColor: AC.bg(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // ── Member Type ───────────────────────────────────────
                  _buildSectionTitle('Member Type'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: AppTheme.elevatedCard(context: context),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Description row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              Icon(Icons.workspace_premium,
                                  size: 18, color: AppTheme.primaryGold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Filter matches by membership status',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AC.textMuted(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Toggle row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                          child: Row(
                            children: [
                              _buildMemberTypeChip(
                                label: 'All Members',
                                icon: Icons.people_alt_outlined,
                                value: MemberTypeFilter.all,
                              ),
                              const SizedBox(width: 8),
                              _buildMemberTypeChip(
                                label: 'Premium',
                                icon: Icons.workspace_premium,
                                value: MemberTypeFilter.premium,
                                accentColor: AppTheme.primaryGold,
                              ),
                              const SizedBox(width: 8),
                              _buildMemberTypeChip(
                                label: 'Free',
                                icon: Icons.person_outline,
                                value: MemberTypeFilter.free,
                                accentColor: AppTheme.sacredGreen,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 60.ms).slideX(begin: -0.1),

                  const SizedBox(height: 24),

                  // ── Age Range ─────────────────────────────────────────
                  _buildSectionTitle('Age Range'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.elevatedCard(context: context),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${displayMin.round()} years',
                              style: TextStyle(
                                  color: AC.text(context),
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${displayMax.round()} years',
                              style: TextStyle(
                                  color: AC.text(context),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: AC.border(context),
                            inactiveTrackColor: AC.border(context),
                            thumbColor: AC.textSub(context),
                          ),
                          child: RangeSlider(
                            values: RangeValues(displayMin, displayMax),
                            min: _kDefaultMinAge.toDouble(),
                            max: _kDefaultMaxAge.toDouble(),
                            divisions: 32,
                            onChanged: (values) {
                              setState(() {
                                _minAge = values.start.round();
                                _maxAge = values.end.round();
                              });
                            },
                          ),
                        ),
                        // Show a hint that age filter is inactive when untouched
                        if (_minAge == null && _maxAge == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Showing all ages (move slider to filter)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AC.textMuted(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),

                  const SizedBox(height: 24),

                  // ── Education & Career ────────────────────────────────
                  _buildSectionTitle('Education & Career'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.elevatedCard(context: context),
                    child: Column(
                      children: [
                        CustomDropdown(
                          label: 'Education',
                          hint: 'Any',
                          value: _education,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.educationLevels),
                          onChanged: (v) => setState(() {
                            _education = v == 'Any' ? null : v;
                            if (_education != 'Other') {
                              _educationOtherController.clear();
                            }
                          }),
                          icon: Icons.school,
                          customInputController: _educationOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Education',
                          customInputHint: 'Type your education level',
                        ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Occupation',
                          hint: 'Any',
                          value: _occupation,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.occupations),
                          onChanged: (v) => setState(() {
                            _occupation = v == 'Any' ? null : v;
                            if (_occupation != 'Other') {
                              _occupationOtherController.clear();
                            }
                          }),
                          icon: Icons.work,
                          customInputController: _occupationOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Occupation',
                          customInputHint: 'Type your occupation',
                        ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Income Range',
                          hint: 'Any Income',
                          value: _incomeRange,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.incomeRanges),
                          onChanged: (v) => setState(() {
                            _incomeRange = v == 'Any' ? null : v;
                            if (_incomeRange != 'Other') {
                              _incomeRangeOtherController.clear();
                            }
                          }),
                          icon: Icons.currency_rupee,
                          customInputController: _incomeRangeOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Income Range',
                          customInputHint: 'Type your income range',
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

                  const SizedBox(height: 24),

                  // ── Religious Details ─────────────────────────────────
                  _buildSectionTitle('Religious Details'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.elevatedCard(context: context),
                    child: Column(
                      children: [
                        CustomDropdown(
                          label: 'Sect',
                          hint: 'Any',
                          value: _sect,
                          items: _getItemsWithAnyAndOther(ReferenceData.sects),
                          onChanged: (v) => setState(() {
                            _sect = v == 'Any' ? null : v;
                            _subSect = null; // reset dependent field
                            _subSectOtherController.clear();
                            if (_sect != 'Other') _sectOtherController.clear();
                          }),
                          icon: Icons.temple_hindu,
                          customInputController: _sectOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Sect',
                          customInputHint: 'Type your sect',
                        ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Sub-Sect',
                          hint: _sect == null || _sect == 'Any'
                              ? 'Select Sect first'
                              : 'Any',
                          value: _subSect,
                          items: _sect != null &&
                                  _sect != 'Any' &&
                                  _sect != 'Other'
                              ? _getItemsWithAnyAndOther(
                                  ReferenceData.subSectsForSect(_sect!))
                              : [],
                          onChanged: (v) => setState(() {
                            _subSect = v == 'Any' ? null : v;
                            if (_subSect != 'Other') {
                              _subSectOtherController.clear();
                            }
                          }),
                          icon: Icons.groups,
                          enabled: _sect != null && _sect != 'Any',
                          customInputController: _subSectOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Sub-Sect',
                          customInputHint: 'Type your sub-sect',
                        ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Nakshatra',
                          hint: 'Any',
                          value: _nakshatra,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.nakshatrasSimple),
                          onChanged: (v) => setState(() {
                            _nakshatra = v == 'Any' ? null : v;
                            if (_nakshatra != 'Other') {
                              _nakshatraOtherController.clear();
                            }
                          }),
                          icon: Icons.star,
                          customInputController: _nakshatraOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Nakshatra',
                          customInputHint: 'Type your nakshatra',
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

                  const SizedBox(height: 24),

                  // ── Location & Lifestyle ──────────────────────────────
                  _buildSectionTitle('Location & Lifestyle'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.elevatedCard(context: context),
                    child: Column(
                      children: [
                        CustomDropdown(
                          label: 'Country',
                          hint: 'Any',
                          value: _country,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.searchFilterCountries),
                          onChanged: (v) => setState(() {
                            _country = v == 'Any' ? null : v;
                            if (_country != 'Other') {
                              _countryOtherController.clear();
                            }
                            if (_useIndianStatePicker()) {
                              _nonIndiaStateController.clear();
                            } else {
                              _state = null;
                              _stateOtherController.clear();
                            }
                          }),
                          icon: Icons.public,
                          customInputController: _countryOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Country',
                          customInputHint: 'Type country name',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cityController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'City / Town (optional)',
                            hintText: 'Filter by city name',
                            prefixIcon: Icon(Icons.location_city,
                                color: AC.textMuted(context)),
                            filled: true,
                            fillColor: AC.bg(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        if (_useIndianStatePicker())
                          CustomDropdown(
                            label: 'State',
                            hint: 'Any',
                            value: _state,
                            items: _getItemsWithAnyAndOther(
                                ReferenceData.indianStates),
                            onChanged: (v) => setState(() {
                              _state = v == 'Any' ? null : v;
                              if (_state != 'Other') {
                                _stateOtherController.clear();
                              }
                            }),
                            icon: Icons.location_on,
                            customInputController: _stateOtherController,
                            onCustomInputChanged: (_) => setState(() {}),
                            customInputLabel: 'Enter State',
                            customInputHint: 'Type your state',
                          )
                        else
                          TextField(
                            controller: _nonIndiaStateController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'State / Province / Region',
                              hintText: 'Optional — e.g. California, Ontario',
                              prefixIcon: Icon(Icons.map_outlined,
                                  color: AC.textMuted(context)),
                              filled: true,
                              fillColor: AC.bg(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Marital Status',
                          hint: 'Any',
                          value: _maritalStatus,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.maritalStatuses),
                          onChanged: (v) => setState(() {
                            _maritalStatus = v == 'Any' ? null : v;
                            if (_maritalStatus != 'Other') {
                              _maritalStatusOtherController.clear();
                            }
                          }),
                          icon: Icons.favorite,
                          customInputController: _maritalStatusOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Marital Status',
                          customInputHint: 'Type your marital status',
                        ),
                        const SizedBox(height: 16),
                        CustomDropdown(
                          label: 'Food Habit',
                          hint: 'Any',
                          value: _foodHabit,
                          items: _getItemsWithAnyAndOther(
                              ReferenceData.foodHabits),
                          onChanged: (v) => setState(() {
                            _foodHabit = v == 'Any' ? null : v;
                            if (_foodHabit != 'Other') {
                              _foodHabitOtherController.clear();
                            }
                          }),
                          icon: Icons.restaurant,
                          customInputController: _foodHabitOtherController,
                          onCustomInputChanged: (_) => setState(() {}),
                          customInputLabel: 'Enter Food Habit',
                          customInputHint: 'Type your food habit',
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          // ── Bottom Actions ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AC.card(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _clearFilters,
                    icon: Icon(Icons.refresh,
                        size: 24, color: AC.textSub(context)),
                    label: Text(
                      'Reset to Default',
                      style: TextStyle(
                          color: AC.text(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AC.border(context).withValues(alpha: 0.8),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _applyFilters,
                    icon: Icon(Icons.check, size: 24, color: AC.card(context)),
                    label: Text(
                      'Apply Filters',
                      style: TextStyle(
                          color: AC.card(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// InlineFilterWidget — Embeds FilterScreen inside a bottom sheet or any
// container. Wraps in Expanded so it fills available space.
// Note: Only use this inside a widget that provides vertical constraints
// (e.g. Column inside a showModalBottomSheet).
// ─────────────────────────────────────────────────────────────────────────────

class InlineFilterWidget extends StatelessWidget {
  /// When true the widget starts with all sections already expanded.
  final bool startExpanded;

  const InlineFilterWidget({super.key, this.startExpanded = false});

  @override
  Widget build(BuildContext context) {
    // Use context.read — we only need the value at open time, not live updates.
    final filterService = context.read<FilterService>();

    return Expanded(
      child: FilterScreen(
        initialFilters: filterService.current,
        onApply: (prefs) {
          // FilterScreen already calls FilterService.setFilters() internally.
          // The onApply callback is intentionally left empty here because
          // the ChangeNotifierProvider rebuild handles the UI update.
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FilterSettingsScreen — standalone full-screen used from Settings / Matches.
// Wraps FilterScreen in a Scaffold so it can be pushed via NavHelper just
// like other screens.
//
// FIX: Changed context.watch → context.read.
//   - context.watch causes FilterSettingsScreen.build() to re-run the moment
//     setFilters() calls notifyListeners(). Since Navigator.pop() fires just
//     before setFilters(), a tight race condition can attempt a rebuild while
//     the screen is being removed from the tree — causing a black screen.
//   - context.read reads the value once at open time (sufficient for
//     passing initialFilters). Live rebuild is not needed here because
//     FilterScreen manages its own local state after open.
// ─────────────────────────────────────────────────────────────────────────────

class FilterSettingsScreen extends StatelessWidget {
  const FilterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX: context.read instead of context.watch — prevents rebuild-during-pop
    // black screen race condition.
    final filterService = context.read<FilterService>();

    return FilterScreen(
      initialFilters: filterService.current,
      // _applyFilters() inside FilterScreen already calls Navigator.pop().
      // Do NOT call pop() again here — double-pop causes a black screen.
      onApply: (_) {},
    );
  }
}
