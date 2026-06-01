import 'package:flutter/material.dart';
import '../screens/profile/profile_incomplete_screen.dart';
import '../models/user.dart';

class SmartRouteHandler {
  static Widget getRouteScreen(String route, Map<String, dynamic>? context) {
    switch (route) {
      case '/profile-incomplete':
        if (context != null && 
            context.containsKey('profile_completion') &&
            context.containsKey('profile')) {
          final completionPercentage = context['profile_completion'] as double;
          final profile = context['profile'] as UserProfile?;
          
          return ProfileIncompleteScreen(
            completionPercentage: completionPercentage,
            profile: profile,
          );
        }
        // Fallback with default values
        return const ProfileIncompleteScreen(
          completionPercentage: 0,
          profile: null,
        );
        
      default:
        // For other routes, let the MaterialApp handle them
        return Container(); // Placeholder
    }
  }
  
  static Future<void> navigateToRoute(BuildContext context, String route, Map<String, dynamic>? routeContext) async {
    if (route == '/profile-incomplete') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => getRouteScreen(route, routeContext),
        ),
      );
    } else {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }
}
