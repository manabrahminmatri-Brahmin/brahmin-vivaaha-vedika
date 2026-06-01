import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../services/theme_service.dart';

/// Font Size Settings screen
class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Font Size',
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AC.surface(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AC.surface(context),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.text_fields, color: Color(0xFF757575)),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adjust Text Size',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose the text size that works best for you',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),

            const SizedBox(height: 32),

            // Font Size Options
            Text(
              'Select Font Size',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AC.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SizedBox(height: 16),

            _buildFontOption(
              context,
              themeService,
              key: 'small',
              label: 'Small',
              scale: 0.85,
              sampleSize: 13,
            ).animate().fadeIn(delay: 100.ms),
            
            const SizedBox(height: 12),
            
            _buildFontOption(
              context,
              themeService,
              key: 'medium',
              label: 'Medium (Default)',
              scale: 1.0,
              sampleSize: 15,
            ).animate().fadeIn(delay: 150.ms),
            
            const SizedBox(height: 12),
            
            _buildFontOption(
              context,
              themeService,
              key: 'large',
              label: 'Large',
              scale: 1.15,
              sampleSize: 17,
            ).animate().fadeIn(delay: 200.ms),
            
            const SizedBox(height: 12),
            
            _buildFontOption(
              context,
              themeService,
              key: 'extra_large',
              label: 'Extra Large',
              scale: 1.3,
              sampleSize: 19,
            ).animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 32),

            // Preview Section
            Text(
              'Preview',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AC.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AC.card(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AC.divider(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Name',
                    style: TextStyle(
                      fontSize: 18 * themeService.fontScale,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This is how profile titles will appear in the app.',
                    style: TextStyle(
                      fontSize: 14 * themeService.fontScale,
                      color: AC.textSub(context),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Sample Profile Information',
                    style: TextStyle(
                      fontSize: 16 * themeService.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Age: 25 years | Height: 5\'8"',
                    style: TextStyle(
                      fontSize: 13 * themeService.fontScale,
                      color: AC.textMuted(context),
                    ),
                  ),
                  Text(
                    'Education: B.Tech, Computer Science',
                    style: TextStyle(
                      fontSize: 13 * themeService.fontScale,
                      color: AC.textMuted(context),
                    ),
                  ),
                  Text(
                    'Nakshatra: Ashwini | Gothram: Bharadwaja',
                    style: TextStyle(
                      fontSize: 13 * themeService.fontScale,
                      color: AC.textMuted(context),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 24),

            // Note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.templeGold, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Font size changes apply to most text in the app. Some elements may remain fixed for design consistency.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFontOption(
    BuildContext context,
    ThemeService themeService, {
    required String key,
    required String label,
    required double scale,
    required double sampleSize,
  }) {
    final isSelected = themeService.fontSizeKey == key;

    return GestureDetector(
      onTap: () => themeService.setFontSize(key),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.primaryOrange.withAlpha(15) 
              : AC.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? AppTheme.primaryOrange 
                : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryOrange : AppTheme.textLight,
                  width: 2,
                ),
                color: isSelected ? AppTheme.primaryOrange : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 14, color: AC.card(context))
                  : null,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppTheme.primaryOrange : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aa Bb Cc',
                    style: TextStyle(
                      fontSize: sampleSize,
                      color: AC.textSub(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${(scale * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AC.textMuted(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

