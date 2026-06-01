import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import 'profile_wizard_screen.dart';

class ProfileIncompleteScreen extends StatelessWidget {
  final double completionPercentage;
  final UserProfile? profile;

  const ProfileIncompleteScreen({
    super.key,
    this.completionPercentage = 0,
    this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Complete Your Profile',
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 80,
                color: AC.card(context).withValues(alpha: 0.8),
              ),
              SizedBox(height: 24),
              Text(
                'Complete Your Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AC.text(context),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Your profile is ${completionPercentage.toInt()}% complete',
                style: TextStyle(
                  fontSize: 18,
                  color: AC.textSub(context),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'A complete profile helps you find better matches',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AC.card(context),
                ),
              ),
              SizedBox(height: 24),
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: AC.surface2(context),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: completionPercentage / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // Allow user to skip and continue to app
                        Navigator.of(context).pushReplacementNamed('/home');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AC.text(context),
                        side: BorderSide(color: AC.border(context)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Skip for Now'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const ProfileWizardScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.edit),
                      label: Text('Complete Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'You can complete your profile anytime from Settings',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AC.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
