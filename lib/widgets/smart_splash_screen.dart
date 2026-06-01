import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_initialization_service.dart';
import '../theme/app_theme.dart';

/// Smart splash screen with parallel loading and progress tracking
class SmartSplashScreen extends StatefulWidget {
  const SmartSplashScreen({super.key});

  @override
  State<SmartSplashScreen> createState() => _SmartSplashScreenState();
}

class _SmartSplashScreenState extends State<SmartSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  Timer? _progressTimer; // Add Timer declaration
  
  final AppInitializationService _initService = AppInitializationService();
  String _statusMessage = 'Initializing...';
  bool _showError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    
    // Setup progress animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));
    
    // Start initialization
    _startInitialization();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _progressTimer?.cancel(); // Properly dispose timer
    super.dispose();
  }

  Future<void> _startInitialization() async {
    try {
      // Start parallel initialization
      await _initService.initializeApp();
      
      // Update UI periodically during initialization
      _updateProgress();
      
      // Check initialization result
      if (_initService.isInitializationHealthy) {
        _onInitializationComplete();
      } else {
        _onInitializationWarning();
      }
    } catch (e) {
      _onInitializationError(e);
    }
  }

  void _updateProgress() {
    if (!mounted) return;
    
    int updateCount = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final progress = _initService.initializationProgress;
      _progressController.animateTo(progress);
      
      // Update status message based on progress
      if (progress < 0.2) {
        _statusMessage = 'Starting up...';
      } else if (progress < 0.4) {
        _statusMessage = 'Loading services...';
      } else if (progress < 0.6) {
        _statusMessage = 'Preparing your experience...';
      } else if (progress < 0.8) {
        _statusMessage = 'Almost ready...';
      } else {
        _statusMessage = 'Ready!';
        timer.cancel();
      }
      
      // Prevent infinite updates
      updateCount++;
      if (updateCount > 50) { // 5 seconds max
        timer.cancel();
      }
    });
  }

  void _onInitializationComplete() {
    if (!mounted) return;
    
    setState(() {
      _statusMessage = 'Welcome to mana Vivaaha Vedika!';
    });
    
    // Navigate to main app after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _navigateToMainApp();
      }
    });
  }

  void _onInitializationWarning() {
    if (!mounted) return;
    
    setState(() {
      _statusMessage = 'Ready with limited features';
      _showError = true;
      _errorMessage = 'Some features may not be available';
    });
    
    // Still navigate after a short delay
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _navigateToMainApp();
      }
    });
  }

  void _onInitializationError(Object error) {
    if (!mounted) return;
    
    setState(() {
      _statusMessage = 'Initialization failed';
      _showError = true;
      _errorMessage = 'Please restart the app';
    });
    
    debugPrint('❌ Smart splash initialization error: $error');
  }

  void _navigateToMainApp() {
    // This will be handled by the parent widget
    // We just emit a completion signal
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              // Logo with animation
              _buildLogo(),
              
              const SizedBox(height: 48),
              
              // App name
              _buildAppName(),
              
              const SizedBox(height: 16),
              
              // Tagline
              _buildTagline(),
              
              const SizedBox(height: 64),
              
              // Progress indicator
              _buildProgressIndicator(),
              
              const SizedBox(height: 24),
              
              // Status message
              _buildStatusMessage(),
              
              const SizedBox(height: 16),
              
              // Error message (if any)
              if (_showError) _buildErrorMessage(),
              
              const SizedBox(height: 32),
              
              // Debug info (only in debug mode)
              if (kDebugMode) _buildDebugInfo(),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Hero(
      tag: 'app_logo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/images/app_logo.png',
          width: 160,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return SizedBox(
      width: double.infinity,
      child: Text(
        'mana Vivaaha Vedika',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 35,
          fontWeight: FontWeight.bold,
          color: Color(0xFFE85D04),
          letterSpacing: 0.5,
        ),
      ),
    ).animate()
      .fadeIn(delay: 400.ms, duration: 300.ms)
      .shake(duration: 300.ms, hz: 4);
  }

  Widget _buildTagline() {
    return SizedBox(
      width: double.infinity,
      child: Text(
        'For Telugu Brahmin',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 30,
          color: Color(0xFFE85D04),
          fontWeight: FontWeight.w500,
        ),
      ),
    ).animate()
      .fadeIn(delay: 200.ms, duration: 300.ms)
      .slideY(begin: 0.3, end: 0, delay: 200.ms);
  }

  Widget _buildProgressIndicator() {
    return SizedBox(
      width: 200,
      child: Column(
        children: [
          // Progress bar
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return LinearProgressIndicator(
                value: _progressAnimation.value,
                backgroundColor: AppTheme.primaryOrange.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFFE85D04),
                ),
                minHeight: 4,
              );
            },
          ),
          
          SizedBox(height: 8),
          
          // Progress percentage
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return Text(
                '${(_progressAnimation.value * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: AC.card(context),
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
    ).animate()
      .fadeIn(delay: 300.ms, duration: 300.ms);
  }

  Widget _buildStatusMessage() {
    return Text(
      _statusMessage,
      style: TextStyle(
        fontSize: 14,
        color: _showError ? Colors.red[600] : AC.textMuted(context),
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    ).animate()
      .fadeIn(delay: 400.ms, duration: 300.ms);
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.red[600], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
              ),
            ),
          ),
        ],
      ),
    ).animate()
      .shake(duration: 500.ms, hz: 4)
      .fadeIn(delay: 1000.ms);
  }

  Widget _buildDebugInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryOrange.withAlpha(87),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Debug Info',
            style: TextStyle(
              fontSize: 12,
              color: AC.card(context),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Progress: ${(_initService.initializationProgress * 100).toInt()}%\n'
            'Services: ${_initService.initStatus.length}\n'
            'Errors: ${_initService.initErrors.length}\n'
            'Healthy: ${_initService.isInitializationHealthy}',
            style: TextStyle(
              fontSize: 11,
              color: AC.card(context),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
