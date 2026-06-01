import 'package:flutter/material.dart';
import '../../data/reference_data.dart';
import '../../models/gender.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_guard.dart';
import '../custom_dropdown.dart';
import '../profile_photo_picker.dart';

/// Basic Information Step Widget for Profile Wizard
class BasicInfoStep extends StatelessWidget {
  final String? profileCreatedBy;
  final ValueChanged<String?> onProfileCreatedByChanged;
  final TextEditingController profileCreatedByRelationController;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final Gender gender;
  final ValueChanged<Gender> onGenderChanged;
  final String? height;
  final ValueChanged<String?> onHeightChanged;
  final String? weight;
  final ValueChanged<String?> onWeightChanged;
  final String? complexion;
  final ValueChanged<String?> onComplexionChanged;
  final String? bodyType;
  final ValueChanged<String?> onBodyTypeChanged;
  final String? physicalStatus;
  final ValueChanged<String?> onPhysicalStatusChanged;
  final String? profilePicturePath;
  final ValueChanged<String?> onProfilePictureChanged;
  final bool isPhotoPrivate;
  final ValueChanged<bool> onPhotoPrivacyChanged;
  final GlobalKey<FormState> formKey;

  const BasicInfoStep({
    super.key,
    required this.profileCreatedBy,
    required this.onProfileCreatedByChanged,
    required this.profileCreatedByRelationController,
    required this.firstNameController,
    required this.lastNameController,
    required this.gender,
    required this.onGenderChanged,
    required this.height,
    required this.onHeightChanged,
    required this.weight,
    required this.onWeightChanged,
    required this.complexion,
    required this.onComplexionChanged,
    required this.bodyType,
    required this.onBodyTypeChanged,
    required this.physicalStatus,
    required this.onPhysicalStatusChanged,
    required this.profilePicturePath,
    required this.onProfilePictureChanged,
    required this.isPhotoPrivate,
    required this.onPhotoPrivacyChanged,
    required this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(context, 'Profile Created By', Icons.person_add_outlined),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Profile Created By *',
                hint: 'Select who is creating this profile',
                value: profileCreatedBy,
                items: ReferenceData.profileCreatedByOptions,
                onChanged: onProfileCreatedByChanged,
                icon: Icons.person_outline,
              ),
              if (profileCreatedBy == 'Other') ...[
                const SizedBox(height: 20),
                TextFormField(
                  controller: profileCreatedByRelationController,
                  inputFormatters: [PhoneNumberGuard()],
                  decoration: const InputDecoration(
                    labelText: 'Relation *',
                    hintText: 'Specify relation',
                    prefixIcon: Icon(Icons.info_outline),
                  ),
                  validator: (value) {
                    if (profileCreatedBy == 'Other' &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Please specify relation';
                    }
                    final phoneError = validateNoPhoneNumber(value);
                    if (phoneError != null) return phoneError;
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Personal Information', Icons.person_outline),
              const SizedBox(height: 20),
              TextFormField(
                controller: firstNameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [PhoneNumberGuard()],
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  hintText: 'Enter first name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter first name';
                  }
                  return validateNoPhoneNumber(value);
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: lastNameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [PhoneNumberGuard()],
                decoration: const InputDecoration(
                  labelText: 'Last Name *',
                  hintText: 'Enter last name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter last name';
                  }
                  return validateNoPhoneNumber(value);
                },
              ),
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Gender', Icons.wc_outlined),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildGenderOption(
                      context,
                      Gender.male,
                      'Male',
                      Icons.male,
                      gender == Gender.male,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGenderOption(
                      context,
                      Gender.female,
                      'Female',
                      Icons.female,
                      gender == Gender.female,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Physical Details', Icons.accessibility_new_outlined),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Height *',
                hint: 'Select height',
                value: height,
                items: ReferenceData.heights,
                onChanged: onHeightChanged,
                icon: Icons.height,
              ),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Weight',
                hint: 'Select weight',
                value: weight,
                items: ReferenceData.weightRanges,
                onChanged: onWeightChanged,
                icon: Icons.monitor_weight_outlined,
              ),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Complexion *',
                hint: 'Select complexion',
                value: complexion,
                items: ReferenceData.complexions,
                onChanged: onComplexionChanged,
                icon: Icons.palette_outlined,
              ),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Body Type *',
                hint: 'Select body type',
                value: bodyType,
                items: ReferenceData.bodyTypes,
                onChanged: onBodyTypeChanged,
                icon: Icons.fitness_center_outlined,
              ),
              const SizedBox(height: 20),
              CustomDropdown(
                label: 'Physical Status *',
                hint: 'Select physical status',
                value: physicalStatus,
                items: ReferenceData.physicalStatuses,
                onChanged: onPhysicalStatusChanged,
                icon: Icons.health_and_safety_outlined,
              ),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Profile Photo', Icons.camera_alt_outlined),
              const SizedBox(height: 20),
              ProfilePhotoPicker(
                currentImagePath: profilePicturePath,
                onImageSelected: onProfilePictureChanged,
                isPrivate: isPhotoPrivate,
                onPrivacyChanged: onPhotoPrivacyChanged,
              ),
            ],
          ),
        ),
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

  Widget _buildGenderOption(
    BuildContext context,
    Gender genderValue,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () => onGenderChanged(genderValue),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryOrange.withAlpha(15)
              : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryOrange
                : AppTheme.primaryOrange.withAlpha(30),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: AC.textSub(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : AC.textSub(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
