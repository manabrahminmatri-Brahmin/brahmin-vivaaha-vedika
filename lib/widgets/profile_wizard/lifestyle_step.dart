import 'package:flutter/material.dart';
import '../../data/reference_data.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_guard.dart';
import '../custom_dropdown.dart';
import '../multi_select_chip.dart';
import '../profile_photo_picker.dart';

/// Lifestyle & Interests Step Widget for Profile Wizard
class LifestyleStep extends StatelessWidget {
  final String? profilePicturePath;
  final ValueChanged<String?> onProfilePictureChanged;
  final bool isPhotoPrivate;
  final ValueChanged<bool> onPhotoPrivacyChanged;
  final TextEditingController partnerPreferencesController;
  final int? partnerAgeMin;
  final ValueChanged<int?> onPartnerAgeMinChanged;
  final int? partnerAgeMax;
  final ValueChanged<int?> onPartnerAgeMaxChanged;
  final String? partnerHeightMin;
  final ValueChanged<String?> onPartnerHeightMinChanged;
  final String? partnerHeightMax;
  final ValueChanged<String?> onPartnerHeightMaxChanged;
  final List<String> selectedPartnerEducation;
  final ValueChanged<List<String>> onSelectedPartnerEducationChanged;
  final List<String> selectedPartnerOccupation;
  final ValueChanged<List<String>> onSelectedPartnerOccupationChanged;
  final String? partnerIncomeMin;
  final ValueChanged<String?> onPartnerIncomeMinChanged;
  final List<String> selectedPartnerMaritalStatus;
  final ValueChanged<List<String>> onSelectedPartnerMaritalStatusChanged;
  final List<String> selectedPartnerLocations;
  final ValueChanged<List<String>> onSelectedPartnerLocationsChanged;
  final bool? partnerManglikPreference;
  final ValueChanged<bool?> onPartnerManglikPreferenceChanged;
  final String? foodHabit;
  final ValueChanged<String?> onFoodHabitChanged;
  final String? smokingHabit;
  final ValueChanged<String?> onSmokingHabitChanged;
  final String? drinkingHabit;
  final ValueChanged<String?> onDrinkingHabitChanged;
  final List<String> selectedLanguages;
  final ValueChanged<List<String>> onSelectedLanguagesChanged;
  final List<String> selectedHobbies;
  final ValueChanged<List<String>> onSelectedHobbiesChanged;
  final TextEditingController aboutMeController;
  final GlobalKey<FormState> formKey;
  final Function(String)? onShowInputGuardWarning;
  final VoidCallback? onAutoGeneratePartnerPreferences;
  final VoidCallback? onAutoGenerateAboutMe;

  const LifestyleStep({
    super.key,
    required this.profilePicturePath,
    required this.onProfilePictureChanged,
    required this.isPhotoPrivate,
    required this.onPhotoPrivacyChanged,
    required this.partnerPreferencesController,
    required this.partnerAgeMin,
    required this.onPartnerAgeMinChanged,
    required this.partnerAgeMax,
    required this.onPartnerAgeMaxChanged,
    required this.partnerHeightMin,
    required this.onPartnerHeightMinChanged,
    required this.partnerHeightMax,
    required this.onPartnerHeightMaxChanged,
    required this.selectedPartnerEducation,
    required this.onSelectedPartnerEducationChanged,
    required this.selectedPartnerOccupation,
    required this.onSelectedPartnerOccupationChanged,
    required this.partnerIncomeMin,
    required this.onPartnerIncomeMinChanged,
    required this.selectedPartnerMaritalStatus,
    required this.onSelectedPartnerMaritalStatusChanged,
    required this.selectedPartnerLocations,
    required this.onSelectedPartnerLocationsChanged,
    required this.partnerManglikPreference,
    required this.onPartnerManglikPreferenceChanged,
    required this.foodHabit,
    required this.onFoodHabitChanged,
    required this.smokingHabit,
    required this.onSmokingHabitChanged,
    required this.drinkingHabit,
    required this.onDrinkingHabitChanged,
    required this.selectedLanguages,
    required this.onSelectedLanguagesChanged,
    required this.selectedHobbies,
    required this.onSelectedHobbiesChanged,
    required this.aboutMeController,
    required this.formKey,
    this.onShowInputGuardWarning,
    this.onAutoGeneratePartnerPreferences,
    this.onAutoGenerateAboutMe,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            // Profile Photo Section
            Container(
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
                children: [
                  _buildSectionTitle('Profile Photo', Icons.camera_alt_outlined),
                  const SizedBox(height: 8),
                  Text(
                    'Add a clear photo to get better matches',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  ProfilePhotoPicker(
                    currentImagePath: profilePicturePath,
                    onImageSelected: onProfilePictureChanged,
                    size: 140,
                    isPrivate: isPhotoPrivate,
                    onPrivacyChanged: onPhotoPrivacyChanged,
                  ),
                  const SizedBox(height: 16),
                  // Privacy info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withAlpha(40),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[300] 
                              : Colors.grey[700],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isPhotoPrivate
                                ? 'Your photo is private. Others need to request to view it.'
                                : 'Your photo is visible to all members.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.grey[400] 
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Partner Preferences Section
            _buildPartnerPreferencesSection(context),
            const SizedBox(height: 20),
            
            // Food & Lifestyle Section
            _buildFoodLifestyleSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerPreferencesSection(BuildContext context) {
    return Container(
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
          _buildSectionTitle('Partner Preferences', Icons.favorite_outline),
          const SizedBox(height: 12),

          // Auto Generate Partner Preferences Button
          OutlinedButton.icon(
            onPressed: onAutoGeneratePartnerPreferences,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Auto Generate Partner Preferences'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.peacockBlue,
              side: const BorderSide(color: AppTheme.peacockBlue),
            ),
          ),
          const SizedBox(height: 16),

          // Partner Preferences (Text Description)
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: partnerPreferencesController,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Partner Preferences *',
              hintText: 'Describe your ideal partner and what qualities you value...',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please describe your partner preferences';
              }
              if (value.trim().length < 30) {
                return 'Please write at least 30 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          
          // Detailed Partner Preferences Section
          _buildSectionTitle('Detailed Partner Preferences (Optional)', Icons.favorite_border),
          const SizedBox(height: 8),
          Text(
            'Set specific preferences to help us find better matches for you',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[400] 
                      : Colors.grey[600],
                ),
          ),
          const SizedBox(height: 16),
          
          // Age Range
          Row(
            children: [
              Expanded(
                child: CustomDropdown(
                  label: 'Min Age',
                  hint: 'Any',
                  value: partnerAgeMin?.toString(),
                  items: ['Any', ...ReferenceData.partnerAgeOptions.map((a) => a.toString())],
                  onChanged: (value) {
                    onPartnerAgeMinChanged(value == 'Any' || value == null 
                        ? null 
                        : int.tryParse(value));
                  },
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomDropdown(
                  label: 'Max Age',
                  hint: 'Any',
                  value: partnerAgeMax?.toString(),
                  items: ['Any', ...ReferenceData.partnerAgeOptions.map((a) => a.toString())],
                  onChanged: (value) {
                    onPartnerAgeMaxChanged(value == 'Any' || value == null 
                        ? null 
                        : int.tryParse(value));
                  },
                  icon: Icons.calendar_today,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Height Range
          Row(
            children: [
              Expanded(
                child: CustomDropdown(
                  label: 'Min Height',
                  hint: 'Any',
                  value: partnerHeightMin,
                  items: ['Any', ...ReferenceData.heights],
                  onChanged: (value) {
                    onPartnerHeightMinChanged(value == 'Any' || value == null ? null : value);
                  },
                  icon: Icons.height,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomDropdown(
                  label: 'Max Height',
                  hint: 'Any',
                  value: partnerHeightMax,
                  items: ['Any', ...ReferenceData.heights],
                  onChanged: (value) {
                    onPartnerHeightMaxChanged(value == 'Any' || value == null ? null : value);
                  },
                  icon: Icons.height,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Education Preference
          _buildSectionTitle('Preferred Education', Icons.school_outlined),
          const SizedBox(height: 8),
          MultiSelectChip(
            items: ReferenceData.educationLevels,
            selectedItems: selectedPartnerEducation,
            onSelectionChanged: onSelectedPartnerEducationChanged,
          ),
          const SizedBox(height: 16),
          
          // Occupation Preference
          _buildSectionTitle('Preferred Occupation', Icons.work_outline),
          const SizedBox(height: 8),
          MultiSelectChip(
            items: ReferenceData.occupations,
            selectedItems: selectedPartnerOccupation,
            onSelectionChanged: onSelectedPartnerOccupationChanged,
          ),
          const SizedBox(height: 16),
          
          // Income Preference
          CustomDropdown(
            label: 'Minimum Income',
            hint: 'Any',
            value: partnerIncomeMin,
            items: ['Any', ...ReferenceData.incomeRanges],
            onChanged: (value) {
              onPartnerIncomeMinChanged(value == 'Any' || value == null ? null : value);
            },
            icon: Icons.attach_money,
          ),
          const SizedBox(height: 16),
          
          // Marital Status Preference
          _buildSectionTitle('Preferred Marital Status', Icons.favorite),
          const SizedBox(height: 8),
          MultiSelectChip(
            items: ReferenceData.maritalStatuses,
            selectedItems: selectedPartnerMaritalStatus,
            onSelectionChanged: onSelectedPartnerMaritalStatusChanged,
          ),
          const SizedBox(height: 16),
          
          // Location Preference
          _buildSectionTitle('Preferred Locations', Icons.location_on_outlined),
          const SizedBox(height: 8),
          MultiSelectChip(
            items: ReferenceData.partnerLocationPreferences,
            selectedItems: selectedPartnerLocations,
            onSelectionChanged: onSelectedPartnerLocationsChanged,
          ),
          const SizedBox(height: 16),
          
          // Manglik Preference
          CustomDropdown(
            label: 'Manglik Preference',
            hint: 'No Preference',
            value: partnerManglikPreference == null 
                ? 'No Preference' 
                : (partnerManglikPreference == true ? 'Accepts Manglik' : 'Does Not Accept Manglik'),
            items: ['No Preference', 'Accepts Manglik', 'Does Not Accept Manglik'],
            onChanged: (value) {
              if (value == 'No Preference' || value == null) {
                onPartnerManglikPreferenceChanged(null);
              } else {
                onPartnerManglikPreferenceChanged(value == 'Accepts Manglik');
              }
            },
            icon: Icons.star_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildFoodLifestyleSection(BuildContext context) {
    return Container(
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
          _buildSectionTitle('Food & Lifestyle', Icons.restaurant_outlined),
          const SizedBox(height: 20),

          // Food Habit
          CustomDropdown(
            label: 'Food Habit *',
            hint: 'Select food habit',
            value: foodHabit,
            items: ReferenceData.foodHabits,
            onChanged: onFoodHabitChanged,
            icon: Icons.restaurant,
          ),
          const SizedBox(height: 20),

          // Smoking
          CustomDropdown(
            label: 'Smoking *',
            hint: 'Select option',
            value: smokingHabit,
            items: ReferenceData.smokingHabits,
            onChanged: onSmokingHabitChanged,
            icon: Icons.smoking_rooms,
          ),
          const SizedBox(height: 20),

          // Drinking
          CustomDropdown(
            label: 'Drinking *',
            hint: 'Select option',
            value: drinkingHabit,
            items: ReferenceData.drinkingHabits,
            onChanged: onDrinkingHabitChanged,
            icon: Icons.local_bar,
          ),
          const SizedBox(height: 28),

          _buildSectionTitle('Languages Spoken', Icons.translate),
          const SizedBox(height: 16),

          MultiSelectChip(
            items: ReferenceData.languages,
            selectedItems: selectedLanguages,
            onSelectionChanged: onSelectedLanguagesChanged,
          ),
          const SizedBox(height: 28),

          _buildSectionTitle('Hobbies & Interests', Icons.interests),
          const SizedBox(height: 16),

          MultiSelectChip(
            items: ReferenceData.hobbies,
            selectedItems: selectedHobbies,
            onSelectionChanged: onSelectedHobbiesChanged,
          ),
          const SizedBox(height: 28),

          _buildSectionTitle('About Yourself', Icons.edit_note),
          const SizedBox(height: 12),

          // Auto Generate Button
          OutlinedButton.icon(
            onPressed: onAutoGenerateAboutMe,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Auto Generate from Profile'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryOrange,
              side: const BorderSide(color: AppTheme.primaryOrange),
            ),
          ),
          const SizedBox(height: 16),

          // About Me
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: aboutMeController,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'About Me *',
              hintText: 'Write something about yourself, your values, and what you are looking for...',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please write something about yourself';
              }
              if (value.trim().length < 50) {
                return 'Please write at least 50 characters';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryOrange,
            ),
          ),
        ),
      ],
    );
  }
}
