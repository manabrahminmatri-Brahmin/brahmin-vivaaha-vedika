import 'package:flutter/material.dart';

import 'existing_user_login_screen.dart';

/// App entry for sign-in — bank-style login (mobile → MPIN / biometric).
class AuthSelectionScreen extends StatelessWidget {
  const AuthSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExistingUserLoginScreen(isEntryPoint: true);
  }
}
