import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Pure static splash — zero animation overhead.
/// Shown for < 50ms while SharedPreferences is read synchronously.
/// As soon as AuthWrapper._decideRouteFromPrefs() completes, this
/// is replaced by the real first screen — users rarely even see it.
class OptimizedSplashScreen extends StatelessWidget {
  const OptimizedSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8E7),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite,
                          size: 80,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'mana Vivaaha Vedika',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryOrange,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'For Telugu Brahmin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        color: AppTheme.primaryOrange.withAlpha(180),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias kept for any legacy references
class StaticSplashScreen extends OptimizedSplashScreen {
  const StaticSplashScreen({super.key});
}
