import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/reference_data.dart';
import '../../theme/app_theme.dart';
import '../custom_dropdown.dart';

/// Birth Details Step Widget for Profile Wizard
class BirthDetailsStep extends StatelessWidget {
  final DateTime dateOfBirth;
  final ValueChanged<DateTime> onDateOfBirthChanged;
  final TimeOfDay? birthTime;
  final ValueChanged<TimeOfDay?> onBirthTimeChanged;
  final String? timeOfBirth;
  final TextEditingController placeOfBirthController;
  final String? placeOfBirthCountry;
  final ValueChanged<String?> onPlaceOfBirthCountryChanged;
  final String? placeOfBirthState;
  final ValueChanged<String?> onPlaceOfBirthStateChanged;
  final bool isCalculatingNakshatra;
  final VoidCallback onCalculateNakshatra;
  final GlobalKey<FormState> formKey;
  // Add star calculation result fields
  final String? calculatedNakshatra;
  final String? calculatedPada;
  final String? calculatedRasi;
  final bool starConfirmed;
  final VoidCallback? onConfirmStar;
  final VoidCallback? onChangeStar;

  const BirthDetailsStep({
    super.key,
    required this.dateOfBirth,
    required this.onDateOfBirthChanged,
    required this.birthTime,
    required this.onBirthTimeChanged,
    required this.timeOfBirth,
    required this.placeOfBirthController,
    required this.placeOfBirthCountry,
    required this.onPlaceOfBirthCountryChanged,
    required this.placeOfBirthState,
    required this.onPlaceOfBirthStateChanged,
    required this.isCalculatingNakshatra,
    required this.onCalculateNakshatra,
    required this.formKey,
    this.calculatedNakshatra,
    this.calculatedPada,
    this.calculatedRasi,
    this.starConfirmed = false,
    this.onConfirmStar,
    this.onChangeStar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(context, 'Date of Birth', Icons.calendar_month_outlined),
              const SizedBox(height: 20),
              InkWell(
                onTap: () => _selectDateOfBirth(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AC.surface(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        color: AC.textSub(context),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat('dd MMMM yyyy').format(dateOfBirth),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '(Age: ${_calculateAge(dateOfBirth)})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Time of Birth', Icons.access_time_outlined),
              const SizedBox(height: 20),
              InkWell(
                onTap: () => _selectBirthTime(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AC.surface(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: birthTime != null
                            ? AppTheme.primaryOrange
                            : AC.textMuted(context),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          birthTime != null
                              ? DateFormat('hh:mm a').format(
                                  DateTime(2000, 1, 1, birthTime!.hour, birthTime!.minute),
                                )
                              : 'Select time of birth *',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: birthTime != null
                                    ? AC.text(context)
                                    : AC.textMuted(context),
                              ),
                        ),
                      ),
                      if (isCalculatingNakshatra) ...[
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryOrange,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (birthTime != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: isCalculatingNakshatra ? null : onCalculateNakshatra,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Calculate Nakshatra'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Place of Birth', Icons.location_on_outlined),
              const SizedBox(height: 20),
              
              // Country of Birth
              CustomDropdown(
                label: 'Country *',
                hint: 'Select country',
                value: placeOfBirthCountry,
                items: ReferenceData.countries,
                onChanged: (value) {
                  onPlaceOfBirthCountryChanged(value);
                  // Clear state and city when country changes
                  if (value != placeOfBirthCountry) {
                    onPlaceOfBirthStateChanged(null);
                    placeOfBirthController.clear();
                  }
                },
                icon: Icons.public,
              ),
              const SizedBox(height: 20),
              
              // State/Region (only for India)
              if (placeOfBirthCountry == 'India') ...[
                CustomDropdown(
                  label: 'State *',
                  hint: 'Select state',
                  value: placeOfBirthState,
                  items: ReferenceData.indianStates,
                  onChanged: onPlaceOfBirthStateChanged,
                  icon: Icons.map_outlined,
                ),
                const SizedBox(height: 20),
              ],
              
              // City/Town of Birth
              if (placeOfBirthCountry == 'India' && placeOfBirthState != null && ReferenceData.cities.containsKey(placeOfBirthState!))
                CustomDropdown(
                  label: 'City/Town of Birth *',
                  hint: 'Select birth place',
                  value: placeOfBirthController.text.trim().isEmpty
                      ? null
                      : placeOfBirthController.text.trim(),
                  items: ReferenceData.cities[placeOfBirthState!]!,
                  onChanged: (value) {
                    placeOfBirthController.text = value ?? '';
                  },
                  icon: Icons.location_city,
                  minSearchChars: 3,
                )
              else if (placeOfBirthCountry != null && placeOfBirthCountry != 'India' && ReferenceData.citiesByCountry.containsKey(placeOfBirthCountry!))
                CustomDropdown(
                  label: 'City/Town of Birth *',
                  hint: 'Select birth place',
                  value: placeOfBirthController.text.trim().isEmpty
                      ? null
                      : placeOfBirthController.text.trim(),
                  items: ReferenceData.citiesByCountry[placeOfBirthCountry!]!,
                  onChanged: (value) {
                    placeOfBirthController.text = value ?? '';
                  },
                  icon: Icons.location_city,
                  minSearchChars: 3,
                )
              else if (placeOfBirthCountry != null)
                TextFormField(
                  controller: placeOfBirthController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'City/Town of Birth *',
                    hintText: placeOfBirthCountry == 'India'
                        ? (placeOfBirthState == null ? 'Select state first' : 'Enter birth place')
                        : 'Enter birth place',
                    prefixIcon: const Icon(Icons.location_city),
                  ),
                  enabled: placeOfBirthCountry == 'India' ? placeOfBirthState != null : true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter birth place';
                    }
                    return null;
                  },
                ),
              // Star Calculation Section
              if (birthTime != null && placeOfBirthController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildStarCalculationSection(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build star calculation section with display and controls
  Widget _buildStarCalculationSection(BuildContext context) {
    if (isCalculatingNakshatra) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primaryGold.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryGold.withAlpha(50)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AC.textSub(context)),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Calculating your birth star...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AC.textSub(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (calculatedNakshatra != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: starConfirmed 
              ? AppTheme.sacredGreen.withAlpha(20)
              : AppTheme.primaryGold.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: starConfirmed 
                ? AppTheme.sacredGreen.withAlpha(80)
                : AppTheme.primaryGold.withAlpha(60),
            width: starConfirmed ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  starConfirmed ? Icons.check_circle : Icons.auto_awesome, 
                  color: starConfirmed ? AppTheme.sacredGreen : AppTheme.templeGold, 
                  size: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    starConfirmed ? 'Birth Star Confirmed ✓' : 'Calculated Birth Star',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: starConfirmed ? AppTheme.sacredGreen : AppTheme.templeGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (starConfirmed && onChangeStar != null)
                  TextButton.icon(
                    onPressed: onChangeStar,
                    icon: Icon(Icons.edit, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.textMedium),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AC.card(context).withAlpha(80),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('నక్షత్రం (Nakshatra)', 
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AC.card(context),
                          )),
                        SizedBox(height: 4),
                        Text(
                          calculatedNakshatra!,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryMaroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('పాదం (Pada)', 
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AC.card(context),
                          )),
                        SizedBox(height: 4),
                        Text(
                          calculatedPada ?? '-',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AC.textSub(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('రాశి (Rasi)', 
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textMedium,
                          )),
                        SizedBox(height: 4),
                        Text(
                          calculatedRasi?.split(' (').first ?? '-',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.kumkumRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!starConfirmed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onChangeStar,
                      icon: Icon(Icons.edit, size: 18),
                      label: const Text('Change Star'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textMedium,
                        side: BorderSide(color: AC.textMuted(context)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onConfirmStar,
                      icon: Icon(Icons.check, size: 18),
                      label: const Text('Confirm Star'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.sacredGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Please verify with your horoscope before confirming',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textMuted(context),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    // Show calculate button if no star calculated yet
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.surface(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.star_outline, color: AC.textSub(context), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Calculate Your Birth Star',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AC.textSub(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCalculateNakshatra,
              icon: Icon(Icons.auto_awesome, size: 20),
              label: const Text('Calculate Birth Star'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Star will be calculated based on date, time, and place of birth',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AC.textSub(context),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AC.textSub(context), size: 24),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AC.text(context),
          ),
        ),
      ],
    );
  }

  int _calculateAge(DateTime dateOfBirth) {
    final now = DateTime.now();
    int years = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      years--;
    }
    return years;
  }

  Future<void> _selectDateOfBirth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: dateOfBirth,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppTheme.primaryOrange,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onDateOfBirthChanged(picked);
    }
  }

  Future<void> _selectBirthTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: birthTime ?? const TimeOfDay(hour: 6, minute: 0),
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppTheme.primaryOrange,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onBirthTimeChanged(picked);
    }
  }
}
