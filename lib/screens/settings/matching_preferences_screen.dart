import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/star_compatibility_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/common/labeled_adaptive_switch.dart';

/// Screen to configure Ashtakoot matching preferences
class MatchingPreferencesScreen extends StatefulWidget {
  final Function(MatchingPreferences) onSave;
  final MatchingPreferences? initialPreferences;

  const MatchingPreferencesScreen({
    super.key,
    required this.onSave,
    this.initialPreferences,
  });

  @override
  State<MatchingPreferencesScreen> createState() => _MatchingPreferencesScreenState();
}

class _MatchingPreferencesScreenState extends State<MatchingPreferencesScreen> {
  late MatchingPreferences _preferences;

  // Koota data for display
  final List<_KootaInfo> _kootas = [
    _KootaInfo('Varna', 'Spiritual compatibility (ego)', 1, false, false, Icons.person),
    _KootaInfo('Vashya', 'Mutual attraction & control', 2, false, false, Icons.favorite),
    _KootaInfo('Tara', 'Birth star compatibility', 3, true, false, Icons.star),
    _KootaInfo('Yoni', 'Physical & sexual compatibility', 4, false, false, Icons.favorite_border),
    _KootaInfo('Graha Maitri', 'Mental & intellectual match', 5, false, false, Icons.psychology),
    _KootaInfo('Gana', 'Temperament & nature', 6, false, false, Icons.psychology_alt),
    _KootaInfo('Bhakoot', 'Love & emotional bonding', 7, false, false, Icons.heart_broken),
    _KootaInfo('Nadi', 'Health & genetic compatibility', 8, false, true, Icons.health_and_safety),
  ];

  @override
  void initState() {
    super.initState();
    _preferences = widget.initialPreferences ?? MatchingPreferences();
  }

  bool _isSkipped(int index) {
    switch (index) {
      case 0: return _preferences.skipVarna;
      case 1: return _preferences.skipVashya;
      case 2: return _preferences.skipTara;
      case 3: return _preferences.skipYoni;
      case 4: return _preferences.skipGrahaMaitri;
      case 5: return _preferences.skipGana;
      case 6: return _preferences.skipBhakoot;
      case 7: return _preferences.skipNadi;
      default: return false;
    }
  }

  void _setSkipped(int index, bool value) {
    setState(() {
      switch (index) {
        case 0:
          _preferences = _preferences.copyWith(skipVarna: value);
          break;
        case 1:
          _preferences = _preferences.copyWith(skipVashya: value);
          break;
        case 2:
          _preferences = _preferences.copyWith(skipTara: value);
          break;
        case 3:
          _preferences = _preferences.copyWith(skipYoni: value);
          break;
        case 4:
          _preferences = _preferences.copyWith(skipGrahaMaitri: value);
          break;
        case 5:
          _preferences = _preferences.copyWith(skipGana: value);
          break;
        case 6:
          _preferences = _preferences.copyWith(skipBhakoot: value);
          break;
        case 7:
          _preferences = _preferences.copyWith(skipNadi: value);
          break;
      }
    });
  }

  int _calculateActiveMaxScore() {
    int score = 36;
    if (_preferences.skipVarna) score -= 1;
    if (_preferences.skipVashya) score -= 2;
    if (_preferences.skipTara) score -= 3;
    if (_preferences.skipYoni) score -= 4;
    if (_preferences.skipGrahaMaitri) score -= 5;
    if (_preferences.skipGana) score -= 6;
    if (_preferences.skipBhakoot) score -= 7;
    if (_preferences.skipNadi) score -= 8;
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Star Matching Preferences',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AC.surface2(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AC.border(context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AC.textSub(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Customize which Kootas to include in compatibility matching. Skipped Kootas will not affect the score.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AC.textSub(context),
                          ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideX(begin: -0.1),
            const SizedBox(height: 16),

            // Koota Selection
            ..._kootas.asMap().entries.map((entry) {
              final koota = _kootas[entry.key];
              final isSkipped = _isSkipped(entry.key);
              final isIncluded = !isSkipped;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AC.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSkipped
                        ? AppTheme.primaryOrange
                        : AC.border(context),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      koota.icon,
                      color: isSkipped
                          ? AppTheme.primaryOrange
                          : AC.textSub(context),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            koota.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: isSkipped
                                      ? AppTheme.primaryOrange
                                      : AC.text(context),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            koota.description,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AC.textSub(context),
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Status: ${isIncluded ? 'ON' : 'OFF'}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: isIncluded
                                      ? AppTheme.sacredGreen
                                      : AC.textMuted(context),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _buildLabeledSwitch(
                        context,
                        value: isIncluded,
                        onChanged: (value) => _toggleKoota(entry.key, value),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: (entry.key * 50).ms).slideX(begin: -0.1);
            }),
            SizedBox(height: 16),
            // Compatibility Score Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withValues(alpha: isDark ? 0.14 : 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryOrange.withValues(alpha: isDark ? 0.45 : 0.4),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.star,
                        color: AppTheme.primaryOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Compatibility Score',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppTheme.primaryOrange,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Current Score: ${_calculateActiveMaxScore()}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.primaryOrange,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Higher scores indicate better compatibility. Adjust your preferences to improve matching results.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
          ],
        ),
      ),
      bottomNavigationBar: Material(
        color: AC.card(context),
        elevation: 8,
        shadowColor: AC.shadow(context),
        child: SafeArea(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              onPressed: () {
                widget.onSave(_preferences);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Matching preferences saved!'),
                    backgroundColor: AppTheme.sacredGreen,
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text(
                'Save Preferences',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildLabeledSwitch(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return LabeledAdaptiveSwitch(
      value: value,
      onChanged: onChanged,
    );
  }

  void _toggleKoota(int index, bool include) async {
    final koota = _kootas[index];

    if (!include && (koota.isPrimary || koota.isCritical)) {
      final confirmed = await _showWarningDialog(koota);
      if (!mounted) return; // ← guard: widget may have been disposed during dialog
      if (!confirmed) return;
    }

    _setSkipped(index, !include);
  }

  Future<bool> _showWarningDialog(_KootaInfo koota) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.kumkumRed),
            const SizedBox(width: 12),
            Text(
              'Warning',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.kumkumRed,
                  ),
            ),
          ],
        ),
        content: Text(
          koota.isPrimary
              ? '${koota.name} is a PRIMARY compatibility factor in Ashtakoot. Skipping it may result in less accurate matches.\n\nAre you sure you want to skip this?'
              : '${koota.name} is a CRITICAL factor related to genetic compatibility and health of progeny. Skipping it is NOT recommended.\n\nAre you sure you want to skip this?',
          style: TextStyle(color: AC.textSub(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kumkumRed,
            ),
            child: const Text('Skip Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Helper class for koota information
class _KootaInfo {
  final String name;
  final String description;
  final int maxPoints;
  final bool isPrimary;
  final bool isCritical;
  final IconData icon;

  _KootaInfo(this.name, this.description, this.maxPoints, this.isPrimary, this.isCritical, this.icon);
}
