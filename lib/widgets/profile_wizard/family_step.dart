import 'package:flutter/material.dart';
import '../../data/reference_data.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_guard.dart';
import '../custom_dropdown.dart';

/// Family Details Step Widget for Profile Wizard
class FamilyStep extends StatelessWidget {
  final String? maritalStatus;
  final ValueChanged<String?> onMaritalStatusChanged;
  final String? familyType;
  final ValueChanged<String?> onFamilyTypeChanged;
  final String? familyStatus;
  final ValueChanged<String?> onFamilyStatusChanged;
  final String? familyValues;
  final ValueChanged<String?> onFamilyValuesChanged;
  final TextEditingController fatherNameController;
  final String? fatherOccupation;
  final ValueChanged<String?> onFatherOccupationChanged;
  final TextEditingController fatherNoteController;
  final TextEditingController motherNameController;
  final String? motherOccupation;
  final ValueChanged<String?> onMotherOccupationChanged;
  final TextEditingController motherNoteController;
  final TextEditingController motherSurnameController;
  final String? familyOriginCountry;
  final ValueChanged<String?> onFamilyOriginCountryChanged;
  final String? familyOriginState;
  final ValueChanged<String?> onFamilyOriginStateChanged;
  final TextEditingController familyOriginCityController;
  final TextEditingController knownReferenceController;
  final TextEditingController knownReference2Controller;
  final int brothers;
  final ValueChanged<int> onBrothersChanged;
  final int brothersMarried;
  final ValueChanged<int> onBrothersMarriedChanged;
  final int sisters;
  final ValueChanged<int> onSistersChanged;
  final int sistersMarried;
  final ValueChanged<int> onSistersMarriedChanged;
  final TextEditingController aboutFamilyController;
  final String? nativePlaceCountry;
  final ValueChanged<String?> onNativePlaceCountryChanged;
  final String? nativePlaceState;
  final ValueChanged<String?> onNativePlaceStateChanged;
  final TextEditingController nativePlaceCityController;
  final GlobalKey<FormState> formKey;
  final Function(String)? onShowInputGuardWarning;
  final Function(String)? onAdvanceToNextField;

  const FamilyStep({
    super.key,
    required this.maritalStatus,
    required this.onMaritalStatusChanged,
    required this.familyType,
    required this.onFamilyTypeChanged,
    required this.familyStatus,
    required this.onFamilyStatusChanged,
    required this.familyValues,
    required this.onFamilyValuesChanged,
    required this.fatherNameController,
    required this.fatherOccupation,
    required this.onFatherOccupationChanged,
    required this.fatherNoteController,
    required this.motherNameController,
    required this.motherOccupation,
    required this.onMotherOccupationChanged,
    required this.motherNoteController,
    required this.motherSurnameController,
    required this.familyOriginCountry,
    required this.onFamilyOriginCountryChanged,
    required this.familyOriginState,
    required this.onFamilyOriginStateChanged,
    required this.familyOriginCityController,
    required this.knownReferenceController,
    required this.knownReference2Controller,
    required this.brothers,
    required this.onBrothersChanged,
    required this.brothersMarried,
    required this.onBrothersMarriedChanged,
    required this.sisters,
    required this.onSistersChanged,
    required this.sistersMarried,
    required this.onSistersMarriedChanged,
    required this.aboutFamilyController,
    required this.nativePlaceCountry,
    required this.onNativePlaceCountryChanged,
    required this.nativePlaceState,
    required this.onNativePlaceStateChanged,
    required this.nativePlaceCityController,
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
              _buildSectionTitle('Marital Status', Icons.favorite_outline),
              const SizedBox(height: 20),

              // Marital Status
              CustomDropdown(
                label: 'Marital Status *',
                hint: 'Select marital status',
                value: maritalStatus,
                items: ReferenceData.maritalStatuses,
                onChanged: onMaritalStatusChanged,
                icon: Icons.favorite,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle('Family Information', Icons.family_restroom),
              const SizedBox(height: 20),

              // Family Type
              CustomDropdown(
                label: 'Family Type *',
                hint: 'Select family type',
                value: familyType,
                items: ReferenceData.familyTypes,
                onChanged: onFamilyTypeChanged,
                icon: Icons.home,
              ),
              const SizedBox(height: 20),

              // Family Status
              CustomDropdown(
                label: 'Family Status *',
                hint: 'Select family status',
                value: familyStatus,
                items: ReferenceData.familyStatuses,
                onChanged: onFamilyStatusChanged,
                icon: Icons.account_balance,
              ),
              const SizedBox(height: 20),

              // Family Values
              CustomDropdown(
                label: 'Family Values *',
                hint: 'Select family values',
                value: familyValues,
                items: ReferenceData.familyValues,
                onChanged: onFamilyValuesChanged,
                icon: Icons.psychology_outlined,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle("Parents' Details", Icons.people_outline),
              const SizedBox(height: 20),

              // Father's Name (Required)
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: fatherNameController,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('fatherName'),
                decoration: InputDecoration(
                  labelText: "Father's Name *",
                  hintText: 'Enter father\'s full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.primaryOrange, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter father\'s name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Father's Status
              CustomDropdown(
                label: "Father's Status *",
                hint: 'Select status',
                value: fatherOccupation,
                items: ReferenceData.fatherOccupations,
                onChanged: (value) {
                  onFatherOccupationChanged(value);
                  onAdvanceToNextField?.call('fatherOccupation');
                },
                icon: Icons.man,
              ),
              const SizedBox(height: 14),

              // Father's Occupation Note (optional free text)
              _buildNoteField(
                controller: fatherNoteController,
                label: "Father's Additional Note (Optional)",
                hint: 'e.g. Retired IAS officer, runs family business, actively involved in social service…',
              ),
              const SizedBox(height: 20),

              // Mother's Name (Required)
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: motherNameController,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('motherName'),
                decoration: InputDecoration(
                  labelText: "Mother's Name *",
                  hintText: 'Enter mother\'s full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.primaryOrange, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter mother\'s name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Mother's Status
              CustomDropdown(
                label: "Mother's Status *",
                hint: 'Select status',
                value: motherOccupation,
                items: ReferenceData.motherOccupations,
                onChanged: (value) {
                  onMotherOccupationChanged(value);
                  onAdvanceToNextField?.call('motherOccupation');
                },
                icon: Icons.woman,
              ),
              const SizedBox(height: 14),

              // Mother's Occupation Note (optional free text)
              _buildNoteField(
                controller: motherNoteController,
                label: "Mother's Additional Note (Optional)",
                hint: 'e.g. Housewife, actively involved in community service, manages family affairs…',
              ),
              const SizedBox(height: 28),

              // Reference Section for Backend Verification (Optional)
              _buildSectionTitle('Quick Reference (Optional)', Icons.verified_user_outlined),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryGold.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.templeGold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Optional: These details help establish quick family connections between matches. You can skip if you prefer privacy.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[300] 
                              : Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mother's Maiden Surname (Optional)
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: motherSurnameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('motherSurname'),
                decoration: const InputDecoration(
                  labelText: "Mother's Surname (Maiden Name)",
                  hintText: "Enter mother's family surname before marriage",
                  prefixIcon: Icon(Icons.person_outline),
                  helperText: 'Optional - Example: Sharma, Reddy, Rao, etc.',
                ),
              ),
              const SizedBox(height: 20),

              // Family Origin Location (Optional)
              _buildFamilyOriginSection(context),
              const SizedBox(height: 20),

              // Known Reference 1 (Optional)
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: knownReferenceController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('knownReference'),
                decoration: const InputDecoration(
                  labelText: 'Reference 1 (Community Elder/Person)',
                  hintText: 'Name of someone who can vouch for family',
                  prefixIcon: Icon(Icons.person_pin),
                  helperText: 'Optional - A respected person who knows your family',
                ),
              ),
              const SizedBox(height: 20),

              // Known Reference 2 (Optional)
              TextFormField(
                inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
                controller: knownReference2Controller,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => onAdvanceToNextField?.call('knownReference2'),
                decoration: const InputDecoration(
                  labelText: 'Reference 2 (Community Elder/Person)',
                  hintText: 'Name of another person who can vouch',
                  prefixIcon: Icon(Icons.people_outline),
                  helperText: 'Optional - Another trusted person in community',
                ),
              ),
              const SizedBox(height: 28),

              _buildSectionTitle('Siblings', Icons.group_outlined),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildCounterField(
                      context: context,
                      label: 'Brothers',
                      value: brothers,
                      onChanged: onBrothersChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCounterField(
                      context: context,
                      label: 'Married',
                      value: brothersMarried,
                      max: brothers,
                      onChanged: onBrothersMarriedChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildCounterField(
                      context: context,
                      label: 'Sisters',
                      value: sisters,
                      onChanged: onSistersChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCounterField(
                      context: context,
                      label: 'Married',
                      value: sistersMarried,
                      max: sisters,
                      onChanged: onSistersMarriedChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // About Family Section
              _buildAboutFamilySection(context),
              const SizedBox(height: 24),

              // Native Place Location
              _buildNativePlaceSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.note_outlined),
        helperText: 'Optional - Additional details',
      ),
    );
  }

  Widget _buildFamilyOriginSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Family Origin (Ancestral Place)', Icons.location_history),
        const SizedBox(height: 20),
        
        // Family Origin Country
        CustomDropdown(
          label: 'Country',
          hint: 'Select country',
          value: familyOriginCountry,
          items: ReferenceData.countries,
          onChanged: (value) {
            onFamilyOriginCountryChanged(value ?? 'India');
            onFamilyOriginStateChanged(null);
            familyOriginCityController.clear();
          },
          icon: Icons.public,
        ),
        const SizedBox(height: 20),

        // Family Origin State
        if (familyOriginCountry == 'India')
          CustomDropdown(
            label: 'State',
            hint: 'Select state',
            value: familyOriginState,
            items: ReferenceData.indianStates,
            onChanged: onFamilyOriginStateChanged,
            icon: Icons.map_outlined,
          )
        else
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: TextEditingController(text: familyOriginState ?? ''),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'State/Province',
              hintText: 'Enter state or province',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            onChanged: (value) {
              onFamilyOriginStateChanged(value.trim().isEmpty ? null : value.trim());
            },
          ),
        const SizedBox(height: 20),

        // Family Origin City/Town
        if (familyOriginCountry == 'India' && 
            familyOriginState != null && 
            ReferenceData.cities.containsKey(familyOriginState!))
          CustomDropdown(
            label: 'City/Town',
            hint: 'Select city or town',
            value: familyOriginCityController.text.trim().isEmpty
                ? null
                : familyOriginCityController.text.trim(),
            items: ReferenceData.cities[familyOriginState!]!,
            onChanged: (value) {
              familyOriginCityController.text = value ?? '';
            },
            icon: Icons.location_city,
          )
        else if (familyOriginCountry != null && 
                 familyOriginCountry != 'India' && 
                 ReferenceData.citiesByCountry.containsKey(familyOriginCountry!))
          CustomDropdown(
            label: 'City/Town',
            hint: 'Select city or town',
            value: familyOriginCityController.text.trim().isEmpty
                ? null
                : familyOriginCityController.text.trim(),
            items: ReferenceData.citiesByCountry[familyOriginCountry!]!,
            onChanged: (value) {
              familyOriginCityController.text = value ?? '';
            },
            icon: Icons.location_city,
          )
        else if (familyOriginCountry != null)
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: familyOriginCityController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'City/Town',
              hintText: familyOriginCountry == 'India'
                  ? (familyOriginState == null ? 'Select state first' : 'Enter city or town')
                  : 'Enter city or town',
              prefixIcon: const Icon(Icons.location_city),
              helperText: 'Optional - Original place where family comes from',
            ),
            enabled: familyOriginCountry == 'India' ? familyOriginState != null : true,
          ),
      ],
    );
  }

  Widget _buildAboutFamilySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('About Your Family', Icons.family_restroom),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryGold.withAlpha(40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.templeGold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Share any additional information about your family that you would like others to know.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[300] 
                        : Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Anything to say about your family
        TextFormField(
          inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
          controller: aboutFamilyController,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Anything to say about your family',
            hintText: 'Share information about your family background, values, traditions, or anything else you would like others to know (optional)',
            prefixIcon: Icon(Icons.edit_note),
            alignLabelWithHint: true,
            helperText: 'Optional - This helps others understand your family better',
          ),
        ),
      ],
    );
  }

  Widget _buildNativePlaceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Native Place', Icons.home_work_outlined),
        const SizedBox(height: 20),
        
        // Native Place Country
        CustomDropdown(
          label: 'Country *',
          hint: 'Select country',
          value: nativePlaceCountry,
          items: ReferenceData.countries,
          onChanged: (value) {
            onNativePlaceCountryChanged(value ?? 'India');
            onNativePlaceStateChanged(null);
            nativePlaceCityController.clear();
          },
          icon: Icons.public,
        ),
        const SizedBox(height: 20),

        // Native Place State
        if (nativePlaceCountry == 'India')
          CustomDropdown(
            label: 'State *',
            hint: 'Select state',
            value: nativePlaceState,
            items: ReferenceData.indianStates,
            onChanged: onNativePlaceStateChanged,
            icon: Icons.map_outlined,
          )
        else
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: TextEditingController(text: nativePlaceState ?? ''),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'State/Province *',
              hintText: 'Enter state or province',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            onChanged: (value) {
              onNativePlaceStateChanged(value.trim().isEmpty ? null : value.trim());
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter state/province';
              }
              return null;
            },
          ),
        const SizedBox(height: 20),

        // Native Place City/Town
        if (nativePlaceCountry == 'India' && 
            nativePlaceState != null && 
            ReferenceData.cities.containsKey(nativePlaceState!))
          CustomDropdown(
            label: 'City/Town *',
            hint: 'Select city or town',
            value: nativePlaceCityController.text.trim().isEmpty
                ? null
                : nativePlaceCityController.text.trim(),
            items: ReferenceData.cities[nativePlaceState!]!,
            onChanged: (value) {
              nativePlaceCityController.text = value ?? '';
            },
            icon: Icons.location_city,
          )
        else if (nativePlaceCountry != null && 
                 nativePlaceCountry != 'India' && 
                 ReferenceData.citiesByCountry.containsKey(nativePlaceCountry!))
          CustomDropdown(
            label: 'City/Town *',
            hint: 'Select city or town',
            value: nativePlaceCityController.text.trim().isEmpty
                ? null
                : nativePlaceCityController.text.trim(),
            items: ReferenceData.citiesByCountry[nativePlaceCountry!]!,
            onChanged: (value) {
              nativePlaceCityController.text = value ?? '';
            },
            icon: Icons.location_city,
          )
        else if (nativePlaceCountry != null)
          TextFormField(
            inputFormatters: [PhoneNumberGuard(onPhoneDetected: onShowInputGuardWarning ?? (_) {})],
            controller: nativePlaceCityController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'City/Town *',
              hintText: nativePlaceCountry == 'India'
                  ? (nativePlaceState == null ? 'Select state first' : 'Enter city or town')
                  : 'Enter city or town',
              prefixIcon: const Icon(Icons.location_city),
            ),
            enabled: nativePlaceCountry == 'India' ? nativePlaceState != null : true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter city/town';
              }
              return null;
            },
          ),
      ],
    );
  }

  Widget _buildCounterField({
    required BuildContext context,
    required String label,
    required int value,
    int max = 10,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.primaryOrange,
                iconSize: 28,
              ),
              Container(
                width: 36,
                alignment: Alignment.center,
                child: Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.primaryOrange,
                iconSize: 28,
              ),
            ],
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryOrange,
          ),
        ),
      ],
    );
  }
}
