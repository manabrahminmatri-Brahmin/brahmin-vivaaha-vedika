import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

/// SmartOnboardingScreen — consolidated into OnboardingScreen.
///
/// The "AI-powered cultural experience" variant was never fully implemented
/// and contained a compile-time error (BuildContext used in a const list).
/// All first-time user flow goes through OnboardingScreen which handles
/// the has-seen-onboarding SharedPreferences flag and navigates correctly.
///
/// This redirect exists only to keep any deep-link or legacy reference alive.
class SmartOnboardingScreen extends StatelessWidget {
  const SmartOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingScreen();
}
