import 'package:flutter/material.dart';
import '../../data/reference_data.dart';
import '../../theme/app_theme.dart';
import '../custom_dropdown.dart';

/// Religious Details Step Widget for Profile Wizard
class ReligiousStep extends StatelessWidget {
  final String? sect;
  final ValueChanged<String?> onSectChanged;
  final String? subSect;
  final ValueChanged<String?> onSubSectChanged;
  final String? gothram;
  final ValueChanged<String?> onGothramChanged;
  final String? nakshatra;
  final ValueChanged<String?> onNakshatraChanged;
  final String? pada;
  final ValueChanged<String?> onPadaChanged;
  final String? rasi;
  final ValueChanged<String?> onRasiChanged;
  final bool starConfirmed;
  final ValueChanged<bool> onStarConfirmedChanged;
  final bool showStarConflict;
  final GlobalKey<FormState> formKey;

  const ReligiousStep({
    super.key,
    required this.sect,
    required this.onSectChanged,
    required this.subSect,
    required this.onSubSectChanged,
    required this.gothram,
    required this.onGothramChanged,
    required this.nakshatra,
    required this.onNakshatraChanged,
    required this.pada,
    required this.onPadaChanged,
    required this.rasi,
    required this.onRasiChanged,
    required this.starConfirmed,
    required this.onStarConfirmedChanged,
    required this.showStarConflict,
    required this.formKey,
  });

  void _calculateStar() {
    // This would be handled by the parent widget
    // The calculation logic depends on nakshatra and pada
  }

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
              _buildSectionTitle(context, 'Caste Details', Icons.temple_hindu_outlined),
              const SizedBox(height: 20),

              // Sect
              CustomDropdown(
                label: 'Sect *',
                hint: 'Select your sect',
                value: sect,
                items: ReferenceData.sects,
                onChanged: (value) {
                  onSectChanged(value);
                  onSubSectChanged(null); // Reset sub-sect when sect changes
                },
                icon: Icons.group_outlined,
              ),
              const SizedBox(height: 20),

              // Sub-Sect
              CustomDropdown(
                label: 'Sub-Sect *',
                hint: sect == null ? 'Select sect first' : 'Select sub-sect',
                value: subSect,
                items: sect != null ? ReferenceData.subSectsForSect(sect!) : [],
                onChanged: onSubSectChanged,
                icon: Icons.groups_outlined,
                enabled: sect != null,
              ),
              const SizedBox(height: 20),

              // Gothram
              CustomDropdown(
                label: 'Gothram *',
                hint: 'Select your gothram',
                value: gothram,
                items: ReferenceData.gothrams,
                onChanged: onGothramChanged,
                icon: Icons.family_restroom,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle(context, 'Nakshatra & Rasi', Icons.star_outline),
              const SizedBox(height: 20),

              // Nakshatra
              CustomDropdown(
                label: 'Birth Star (Nakshatra) *',
                hint: 'Select your nakshatra',
                value: nakshatra,
                items: ReferenceData.nakshatras,
                onChanged: (value) {
                  onNakshatraChanged(value);
                  _calculateStar();
                },
                icon: Icons.star,
              ),
              const SizedBox(height: 20),

              // Pada
              CustomDropdown(
                label: 'Pada *',
                hint: 'Select pada',
                value: pada,
                items: ReferenceData.padas,
                onChanged: (value) {
                  onPadaChanged(value);
                  _calculateStar();
                },
                icon: Icons.looks_4_outlined,
              ),
              const SizedBox(height: 20),

              // Rasi (Auto-calculated)
              CustomDropdown(
                label: 'Rasi (Moon Sign) *',
                hint: 'Auto-calculated from Nakshatra',
                value: rasi,
                items: ReferenceData.rasis,
                onChanged: (value) {
                  onRasiChanged(value);
                  // Parent widget handles showStarConflict logic.
                },
                icon: Icons.brightness_3,
              ),

              if (showStarConflict) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.kumkumRed.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.kumkumRed.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.kumkumRed,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rasi differs from calculated value. Please verify.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.kumkumRed,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Star Confirmation
              CheckboxListTile(
                value: starConfirmed,
                onChanged: (value) => onStarConfirmedChanged(value ?? false),
                title: const Text('I confirm my birth star is correct'),
                subtitle: const Text(
                  'Check if you have verified from your horoscope',
                ),
                activeColor: AppTheme.primaryOrange,
                contentPadding: EdgeInsets.zero,
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryOrange,
              ),
        ),
      ],
    );
  }
}
