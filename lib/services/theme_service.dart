import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Service to manage app theme (dark/light mode, color schemes, and font size)
class ThemeService extends ChangeNotifier {
  static const String _darkModeKey = 'dark_mode';
  static const String _colorSchemePrefKey = 'color_scheme';
  static const String _fontSizeKey = 'font_size';

  final SharedPreferences _prefs;
  bool _isDarkMode = false;
  String _currentColorScheme = 'traditional';
  String _fontSizeKey2 = 'medium';
  bool _disposed = false; // 🔥 FIX: Guard against notify after dispose

  /// 🔥 FIX: Safe notify that checks disposed state
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get isDarkMode => _isDarkMode;
  String get colorSchemeKey => _currentColorScheme;
  String get fontSizeKey => _fontSizeKey2;

  /// Font scale based on selected size
  double get fontScale {
    switch (_fontSizeKey2) {
      case 'small':
        return 0.85;
      case 'medium':
        return 1.0;
      case 'large':
        return 1.15;
      case 'extra_large':
        return 1.3;
      default:
        return 1.0;
    }
  }

  String get fontSizeName {
    switch (_fontSizeKey2) {
      case 'small':
        return 'Small';
      case 'medium':
        return 'Medium';
      case 'large':
        return 'Large';
      case 'extra_large':
        return 'Extra Large';
      default:
        return 'Medium';
    }
  }

  String get colorSchemeName {
    switch (_currentColorScheme) {
      case 'traditional':
        return 'Traditional Maroon';
      case 'royal':
        return 'Royal Purple';
      case 'elegant':
        return 'Elegant Teal';
      case 'warm':
        return 'Warm Copper';
      case 'modern':
        return 'Modern Blue';
      case 'forest':
        return 'Forest Green';
      default:
        return 'Traditional Maroon';
    }
  }

  /// Available color schemes — each scheme has its own distinct colors.
  // FIX B3: All 6 schemes previously mapped primary+secondary to AppTheme.primaryOrange,
  // making setColorScheme() a no-op. Each scheme now has its own palette.
  static final Map<String, Map<String, Color>> colorSchemes = {
    'traditional': {
      'primary':   AppTheme.primaryOrange,          // Warm saffron orange
      'secondary': const Color(0xFFBF360C),          // Deep maroon
      'accent':    const Color(0xFFFF8F00),           // Amber gold
    },
    'royal': {
      'primary':   const Color(0xFF6A1B9A),          // Royal purple
      'secondary': const Color(0xFF4A148C),          // Deep purple
      'accent':    const Color(0xFFE6B800),           // Gold accent
    },
    'elegant': {
      'primary':   const Color(0xFF00695C),          // Teal
      'secondary': const Color(0xFF004D40),          // Deep teal
      'accent':    const Color(0xFF00897B),           // Light teal
    },
    'warm': {
      'primary':   const Color(0xFFAD6326),          // Warm copper
      'secondary': const Color(0xFF8D4E1B),          // Dark copper
      'accent':    const Color(0xFFCD7F32),           // Bronze
    },
    'modern': {
      'primary':   const Color(0xFF1565C0),          // Modern blue
      'secondary': const Color(0xFF0D47A1),          // Deep blue
      'accent':    const Color(0xFF42A5F5),           // Light blue
    },
    'forest': {
      'primary':   const Color(0xFF2E7D32),          // Forest green
      'secondary': const Color(0xFF1B5E20),          // Deep green
      'accent':    const Color(0xFF66BB6A),           // Light green
    },
  };

  ThemeService(this._prefs) {
    // Load preferences synchronously from pre-initialized SharedPreferences
    _loadPreferencesSync();
    _syncSystemUiOverlay();
  }

  void _loadPreferencesSync() {
    try {
      _isDarkMode = _prefs.getBool(_darkModeKey) ?? false;
      _currentColorScheme = _prefs.getString(_colorSchemePrefKey) ?? 'traditional';
      _fontSizeKey2 = _prefs.getString(_fontSizeKey) ?? 'medium';
    } catch (e) {
      // Use defaults on error
      _isDarkMode = false;
      _currentColorScheme = 'traditional';
      _fontSizeKey2 = 'medium';
    }
  }

  /// Status bar + navigation bar icons match light/dark (MaterialApp does not set these).
  void _syncSystemUiOverlay() {
    if (_isDarkMode) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.scaffoldDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ));
    } else {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.scaffoldLight,
        systemNavigationBarIconBrightness: Brightness.dark,
      ));
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _prefs.setBool(_darkModeKey, _isDarkMode);
    _syncSystemUiOverlay();
    _safeNotify();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    await _prefs.setBool(_darkModeKey, _isDarkMode);
    _syncSystemUiOverlay();
    _safeNotify();
  }

  Future<void> setColorScheme(String key) async {
    if (colorSchemes.containsKey(key)) {
      _currentColorScheme = key;
      await _prefs.setString(_colorSchemePrefKey, _currentColorScheme);
      _safeNotify();
    }
  }

  Future<void> setFontSize(String key) async {
    final validKeys = ['small', 'medium', 'large', 'extra_large'];
    if (validKeys.contains(key)) {
      _fontSizeKey2 = key;
      await _prefs.setString(_fontSizeKey, _fontSizeKey2);
      _safeNotify();
    }
  }

  ThemeData get currentTheme => _isDarkMode ? darkTheme : lightTheme;

  Color get primaryColor => 
      colorSchemes[_currentColorScheme]?['primary'] ?? AppTheme.primaryOrange;
  
  Color get secondaryColor => 
      colorSchemes[_currentColorScheme]?['secondary'] ?? AppTheme.primaryOrange;
  
  Color get accentColor => 
      colorSchemes[_currentColorScheme]?['accent'] ?? AppTheme.primaryOrange;

  /// Light Theme with selected color scheme
  ThemeData get lightTheme {
    final primary = primaryColor;
    final secondary = secondaryColor;
    
    return AppTheme.lightTheme.copyWith(
      primaryColor: primary,
      colorScheme: AppTheme.lightTheme.colorScheme.copyWith(
        primary: primary,
        secondary: secondary,
        onPrimary: Colors.white,
      ),
      appBarTheme: AppTheme.lightTheme.appBarTheme.copyWith(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppTheme.lightTheme.elevatedButtonTheme.style?.copyWith(
          backgroundColor: WidgetStateProperty.all(primary),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: AppTheme.lightTheme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: primary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary.withAlpha(100);
          return null;
        }),
      ),
    );
  }

  /// Dark Theme with selected color scheme
  ThemeData get darkTheme {
    final primary = primaryColor;
    final secondary = secondaryColor;
    
    return AppTheme.darkTheme.copyWith(
      primaryColor: primary,
      colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
        primary: primary,
        secondary: secondary,
        onPrimary: Colors.white,
      ),
      appBarTheme: AppTheme.darkTheme.appBarTheme.copyWith(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppTheme.darkTheme.elevatedButtonTheme.style?.copyWith(
          backgroundColor: WidgetStateProperty.all(primary),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: AppTheme.darkTheme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: primary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary.withAlpha(100);
          return null;
        }),
      ),
    );
  }
}
