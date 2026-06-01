import 'package:flutter/material.dart';
import '../../data/reference_data.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_guard.dart';
import '../custom_dropdown.dart';

/// Education & Career Step Widget for Profile Wizard
class EducationStep extends StatelessWidget {
  final String? education;
  final ValueChanged<String?> onEducationChanged;
  final String? specialization;
  final ValueChanged<String?> onSpecializationChanged;
  final String? educationStatus;
  final ValueChanged<String?> onEducationStatusChanged;
  final TextEditingController universityNameController;
  final TextEditingController additionalQualificationsController;
  final TextEditingController qualificationNotesController;
  final String? educationLocationCountry;
  final ValueChanged<String?> onEducationLocationCountryChanged;
  final String? educationLocationState;
  final ValueChanged<String?> onEducationLocationStateChanged;
  final TextEditingController educationLocationCityController;
  final String? occupation;
  final ValueChanged<String?> onOccupationChanged;
  final String? employmentType;
  final ValueChanged<String?> onEmploymentTypeChanged;
  final TextEditingController companyNameController;
  final TextEditingController incomeController;
  final String? incomeRange;
  final ValueChanged<String?> onIncomeRangeChanged;
  final String? country;
  final ValueChanged<String?> onCountryChanged;
  final String? state;
  final ValueChanged<String?> onStateChanged;
  final TextEditingController cityController;
  final GlobalKey<FormState> formKey;
  final Function(String)? onShowInputGuardWarning;
  final Function(String)? onAdvanceToNextField;

  const EducationStep({
    super.key,
    required this.education,
    required this.onEducationChanged,
    required this.specialization,
    required this.onSpecializationChanged,
    required this.educationStatus,
    required this.onEducationStatusChanged,
    required this.universityNameController,
    required this.additionalQualificationsController,
    required this.qualificationNotesController,
    required this.educationLocationCountry,
    required this.onEducationLocationCountryChanged,
    required this.educationLocationState,
    required this.onEducationLocationStateChanged,
    required this.educationLocationCityController,
    required this.occupation,
    required this.onOccupationChanged,
    required this.employmentType,
    required this.onEmploymentTypeChanged,
    required this.companyNameController,
    required this.incomeController,
    required this.incomeRange,
    required this.onIncomeRangeChanged,
    required this.country,
    required this.onCountryChanged,
    required this.state,
    required this.onStateChanged,
    required this.cityController,
    required this.formKey,
    this.onShowInputGuardWarning,
    this.onAdvanceToNextField,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
      child: Form(
        key: formKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withAlpha(40),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEducationHeader(context),
              const SizedBox(height: 28),

              _buildSectionTitle(context, 'Education Details', Icons.school_outlined),
              const SizedBox(height: 8),
              Text(
                'Tell us about your educational achievements',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 20),

              // Education Level
              CustomDropdown(
                label: 'Highest Qualification *',
                hint: 'Select your highest qualification',
                value: education,
                items: ReferenceData.educationLevels,
                onChanged: (value) {
                  onEducationChanged(value);
                  onSpecializationChanged(null); // Reset specialization when education changes
                },
                icon: Icons.school,
              ),
              if (education != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.sacredGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppTheme.sacredGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Great choice! $education is an excellent qualification.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.sacredGreen,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Specialization
              CustomDropdown(
                label: 'Specialization',
                hint: education != null 
                    ? 'Select your field of specialization (optional)'
                    : 'Select education first',
                value: specialization,
                items: education != null 
                    ? ReferenceData.specializationsFor(education!)
                    : ['Select education first'],
                onChanged: education != null ? onSpecializationChanged : null,
                enabled: education != null,
                icon: Icons.psychology,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional: Helps find matches with similar interests',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[500] 
                          : Colors.grey[600],
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 20),

              // Education Status
              CustomDropdown(
                label: 'Education Status',
                hint: 'Select your current status (optional)',
                value: educationStatus,
                items: ['Pursuing', 'Completed'],
                onChanged: onEducationStatusChanged,
                icon: Icons.trending_up,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional: Indicate if you\'re currently studying or have completed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[500] 
                          : Colors.grey[600],
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 20),

              // University/Institution Name
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: universityNameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('universityName'),
                decoration: const InputDecoration(
                  labelText: 'University/Institution Name',
                  hintText: 'Enter your alma mater (optional)',
                  prefixIcon: Icon(Icons.school, color: Color(0xFF757575)),
                  helperText: 'Optional: Share where you studied',
                ),
              ),
              const SizedBox(height: 20),

              const SizedBox(height: 24),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 24),

              // Education Location Section
              _buildSectionTitle(context, 'Where Did You Study?', Icons.location_on_outlined),
              const SizedBox(height: 8),
              Text(
                'Optional: Help others find matches from similar educational backgrounds',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 20),

              // Education Location Country
              CustomDropdown(
                label: 'Country',
                hint: 'Select country (optional)',
                value: educationLocationCountry,
                items: ReferenceData.countries,
                onChanged: (value) {
                  onEducationLocationCountryChanged(value ?? 'India');
                  onEducationLocationStateChanged(null);
                  educationLocationCityController.clear();
                },
                icon: Icons.public,
              ),
              const SizedBox(height: 20),

              // Education Location State
              if (educationLocationCountry == 'India')
                CustomDropdown(
                  label: 'State',
                  hint: 'Select state (optional)',
                  value: educationLocationState,
                  items: ReferenceData.indianStates,
                  onChanged: (value) {
                    onEducationLocationStateChanged(value);
                    educationLocationCityController.clear();
                  },
                  icon: Icons.map_outlined,
                )
              else
                TextFormField(
                  inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                  controller: TextEditingController(text: educationLocationState ?? ''),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State/Province *',
                    hintText: 'Enter state or province',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  onChanged: (value) {
                    onEducationLocationStateChanged(value.trim().isEmpty ? null : value.trim());
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter state or province';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20),

              // Education Location City
              if (educationLocationCountry == 'India')
                educationLocationState != null && ReferenceData.cities.containsKey(educationLocationState!)
                    ? CustomDropdown(
                        label: 'City',
                        hint: 'Select city (optional)',
                        value: educationLocationCityController.text.trim().isEmpty ? null : educationLocationCityController.text.trim(),
                        items: ReferenceData.cities[educationLocationState!]!,
                        onChanged: (value) {
                          educationLocationCityController.text = value ?? '';
                        },
                        icon: Icons.location_city,
                      )
                    : TextFormField(
                        inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                        controller: educationLocationCityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'City',
                          hintText: educationLocationState == null ? 'Select state first (optional)' : 'Enter city (optional)',
                          prefixIcon: const Icon(Icons.location_city),
                        ),
                        enabled: educationLocationState != null,
                      )
              else
                TextFormField(
                  inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                  controller: educationLocationCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'Enter city (optional)',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
              const SizedBox(height: 20),

              // Additional Qualifications
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: additionalQualificationsController,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Additional Qualifications',
                  hintText: 'Certifications, courses, or other achievements (optional)',
                  prefixIcon: Icon(Icons.workspace_premium),
                  helperText: 'Optional: Showcase your extra qualifications',
                ),
              ),
              const SizedBox(height: 20),

              // Qualification Notes
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: qualificationNotesController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional Notes',
                  hintText: 'Any special achievements or honors (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                  helperText: 'Optional: Share any notable achievements',
                ),
              ),
              const SizedBox(height: 28),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 28),

              _buildCareerHeader(context),
              const SizedBox(height: 24),

              // Occupation
              CustomDropdown(
                label: 'Occupation *',
                hint: 'Select occupation',
                value: occupation,
                items: ReferenceData.occupations,
                onChanged: onOccupationChanged,
                icon: Icons.work,
              ),
              const SizedBox(height: 20),

              // Employment Type
              CustomDropdown(
                label: 'Employment Type',
                hint: 'Select your employment type (optional)',
                value: employmentType,
                items: ReferenceData.employmentTypes,
                onChanged: onEmploymentTypeChanged,
                icon: Icons.business_center_outlined,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional: Helps others understand your work situation',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[500] 
                          : Colors.grey[600],
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 20),

              // Company Name
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: companyNameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('companyName'),
                decoration: const InputDecoration(
                  labelText: 'Company/Organization',
                  hintText: 'Where do you work? (optional)',
                  prefixIcon: Icon(Icons.business, color: Color(0xFF757575)),
                  helperText: 'Optional: Share your workplace',
                ),
              ),
              const SizedBox(height: 20),

              // Annual Income
              _buildIncomeSection(context),
              const SizedBox(height: 28),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 28),

              _buildLocationHeader(context),
              const SizedBox(height: 20),

              // Current Location Country
              CustomDropdown(
                label: 'Country *',
                hint: 'Select country',
                value: country,
                items: ReferenceData.countries,
                onChanged: (value) {
                  onCountryChanged(value ?? 'India');
                  onStateChanged(null);
                  cityController.clear();
                },
                icon: Icons.public,
              ),
              const SizedBox(height: 20),

              // Current Location State
              if (country == 'India')
                CustomDropdown(
                  label: 'State *',
                  hint: 'Select state',
                  value: state,
                  items: ReferenceData.indianStates,
                  onChanged: onStateChanged,
                  icon: Icons.map_outlined,
                )
              else
                TextFormField(
                  inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                  controller: TextEditingController(text: state ?? ''),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State/Province *',
                    hintText: 'Enter state or province',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  onChanged: (value) {
                    onStateChanged(value.trim().isEmpty ? null : value.trim());
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter state or province';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20),

              // Current Location City
              if (country == 'India')
                state != null && ReferenceData.cities.containsKey(state!)
                    ? CustomDropdown(
                        label: 'City/Town *',
                        hint: 'Select your city or town',
                        value: cityController.text.trim().isEmpty ? null : cityController.text.trim(),
                        items: ReferenceData.cities[state!]!,
                        onChanged: (value) {
                          cityController.text = value ?? '';
                        },
                        icon: Icons.location_city,
                      )
                    : TextFormField(
                        inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                        controller: cityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'City/Town *',
                          hintText: state == null ? 'Select state first' : 'Enter city or town',
                          prefixIcon: const Icon(Icons.location_city),
                        ),
                        enabled: state != null,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter city or town';
                          }
                          return null;
                        },
                      )
              else
                TextFormField(
                  inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                  controller: cityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City/Town *',
                    hintText: 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter city or town';
                    }
                    return null;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEducationHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGold.withAlpha(20),
            AppTheme.primaryOrange.withAlpha(15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryGold.withAlpha(50),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.emoji_events,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.black 
                  : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Showcase Your Achievements! 🎓',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[200] 
                            : Colors.grey[800],
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Share your educational background and career journey',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCareerHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[600]!.withAlpha(15)
                : Colors.grey[600]!.withAlpha(15),
            AppTheme.primaryOrange.withAlpha(10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.grey[400]!.withAlpha(30)
              : Colors.grey[600]!.withAlpha(30),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[400] 
                  : Colors.grey[600],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.work,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.black 
                  : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Professional Journey 💼',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[200] 
                            : Colors.grey[800],
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Share your career details to find compatible matches',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.sacredGreen.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.sacredGreen.withAlpha(30),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.sacredGreen,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.location_on,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.black 
                  : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where Are You Located? 📍',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.sacredGreen,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Required: Helps find matches in your preferred location',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Free-text entry field
        TextFormField(
          controller: incomeController,
          textInputAction: TextInputAction.next,
          onChanged: (v) {
            // When user types, clear any quick-select chip selection
            if (incomeRange != null) onIncomeRangeChanged(null);
          },
          onEditingComplete: () => onAdvanceToNextField?.call('annualIncome'),
          decoration: InputDecoration(
            labelText: 'Annual Income / Salary (optional)',
            hintText: 'e.g. ₹12 LPA, USD 80,000, ₹50,000/month',
            prefixIcon: const Icon(Icons.currency_rupee, color: Color(0xFF757575)),
            helperText: 'Type your exact salary or select a range below',
            suffixIcon: incomeController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      incomeController.clear();
                      onIncomeRangeChanged(null);
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        // Quick-select suggestion chips
        Text(
          'Or pick a range:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[500] 
                    : Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final range in [
              'Not Disclosed',
              '₹3 – 5 LPA',
              '₹5 – 8 LPA',
              '₹8 – 12 LPA',
              '₹12 – 18 LPA',
              '₹18 – 25 LPA',
              '₹25 – 35 LPA',
              '₹35 – 50 LPA',
              '₹50 – 75 LPA',
              '₹75 LPA – 1 Cr',
              'Above ₹2 Cr',
              'USD 50,000 – 75,000',
              'USD 75,000 – 1,00,000',
              'USD 1,00,000 – 1,50,000',
              'AED 10,000 – 20,000 / month',
            ])
              ChoiceChip(
                label: Text(range,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: incomeRange == range
                          ? Colors.white
                          : Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[300] 
                              : Colors.grey[700],
                    )),
                selected: incomeRange == range,
                selectedColor: AppTheme.primaryOrange,
                backgroundColor: Theme.of(context).cardColor,
                side: BorderSide(
                  color: incomeRange == range
                      ? AppTheme.primaryOrange
                      : Theme.of(context).dividerColor,
                ),
                onSelected: (selected) {
                  onIncomeRangeChanged(selected ? range : null);
                  // Clear free-text when chip is selected
                  if (selected) incomeController.clear();
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: AppTheme.primaryOrange,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryOrange,
                ),
          ),
        ),
      ],
    );
  }
}
