import 'package:flutter/material.dart';
import '../screens/profile/profile_incomplete_screen.dart';
import '../models/user.dart';

class SmartNavigationWrapper extends StatelessWidget {
  final Widget child;
  final Map<String, dynamic>? navigationContext;

  const SmartNavigationWrapper({
    super.key,
    required this.child,
    this.navigationContext,
  });

  @override
  Widget build(BuildContext context) {
    // Check if we need to show profile incomplete screen
    if (navigationContext != null && 
        navigationContext!.containsKey('profile_completion') &&
        navigationContext!.containsKey('profile')) {
      
      final completionPercentage = navigationContext!['profile_completion'] as double;
      final profile = navigationContext!['profile'] as UserProfile?;
      
      if (completionPercentage < 50) {
        return ProfileIncompleteScreen(
          completionPercentage: completionPercentage,
          profile: profile,
        );
      }
    }
    
    return child;
  }
}
