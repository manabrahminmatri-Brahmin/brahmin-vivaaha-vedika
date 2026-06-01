import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Mana Vivaaha Vedika – Global Theme  (WhatsApp-style light / dark)
///
/// LIGHT                         DARK
/// ─────────────────────────     ──────────────────────────────
/// Scaffold   #FFFFFF             #0B141A  (layered chat-style bg)
/// Card       #FFFFFF             #1F2C34  (elevated surface)
/// Surface    #F0F2F5             #2A3942  (inputs / chips)
/// AppBar     #FC5603 (orange)    #FC5603  (same — always)
/// BottomNav  #FFFFFF             #1F2C34
/// Text       #0A0A0A             #E9EDEF
/// SubText    #54656F             #8696A0
/// ──────────────────────────────────────────────────────────────────────────

class AppTheme {
  // ── Soft touch (global ink) ───────────────────────────────────────
  static WidgetStateProperty<Color?> _softInkWhiteOnBrand() =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.24);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        return null;
      });

  static WidgetStateProperty<Color?> _softInkPrimaryOnLightSurface() =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primaryOrange.withValues(alpha: 0.20);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return primaryOrange.withValues(alpha: 0.10);
        }
        return null;
      });

  static WidgetStateProperty<Color?> _softInkPrimaryOnDarkSurface() =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primaryOrangeLight.withValues(alpha: 0.22);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return primaryOrangeLight.withValues(alpha: 0.12);
        }
        return null;
      });

  // ── BRAND ─────────────────────────────────────────────────────────
  static const Color primaryOrange      = Color(0xFFFC5603);
  static const Color primaryOrangeLight = Color(0xFFFF7A35);
  static const Color primaryOrangeDark  = Color(0xFFD84315);
  static const Color primaryOrangeGlow  = Color(0x33FC5603);

  // ── SEMANTIC ──────────────────────────────────────────────────────
  static const Color kumkumRed       = Color(0xFFE74C3C);
  static const Color sacredGreen     = Color(0xFF27AE60);
  /// Dark green for auth mobile digit boxes (primary & alternate).
  static const Color sacredGreenDark = Color(0xFF1A6B3F);
  static const Color primaryGold     = Color(0xFFD4AF37);
  static const Color peacockBlue     = Color(0xFF3498DB);
  static const Color templeGold      = Color(0xFFD4AF37);
  static const Color turmericYellow  = Color(0xFFF39C12);
  static const Color primaryMaroon   = Color(0xFF8B4513);
  static const Color sandalwoodCream = Color(0xFFD4A574);

  // ── LIGHT SURFACES (WhatsApp light) ──────────────────────────────
  static const Color scaffoldLight  = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color surfaceLight   = Color(0xFFF0F2F5);
  static const Color surfaceLight2  = Color(0xFFE9EDEF);

  // ── DARK SURFACES (layered chat-style — light palette unchanged above) ──
  static const Color scaffoldDark       = Color(0xFF0B141A);
  static const Color cardBackgroundDark = Color(0xFF1F2C34);
  static const Color surfaceDark        = Color(0xFF2A3942);
  static const Color surfaceDark2       = Color(0xFF182229);
  static const Color surfaceDark3       = Color(0xFF050A0D);
  static const Color appBarDark         = Color(0xFF1F2C34);
  static const Color borderDark         = Color(0xFF3A4A54);
  static const Color dividerDark        = Color(0xFF24303A);

  // ── LIGHT TEXT ────────────────────────────────────────────────────
  static const Color textDark    = Color(0xFF0A0A0A);
  static const Color textMedium  = Color(0xFF54656F);
  static const Color textLight   = Color(0xFF8696A0);
  static const Color dividerColor = Color(0xFFE9EDEF);

  // ── DARK TEXT ─────────────────────────────────────────────────────
  static const Color textDarkOnDark   = Color(0xFFE9EDEF);
  static const Color textMediumOnDark = Color(0xFF8696A0);
  static const Color textLightOnDark  = Color(0xFF54656F);

  // ── LEGACY ALIASES ────────────────────────────────────────────────
  static const Color primaryGray   = Color(0xFF202C33);
  static const Color mediumGray    = Color(0xFF54656F);
  static const Color lightGray     = Color(0xFF8696A0);
  static const Color veryLightGray = Color(0xFFE9EDEF);
  static const Color grayDark      = Color(0xFF111B21);
  static const Color grayMedium    = Color(0xFF2A3942);
  static const Color grayLight     = Color(0xFF8796A1);
  static const Color grayVeryLight = Color(0xFFE9EDEF);

  // ── GRADIENTS ─────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(colors: [primaryOrange, Color(0xFFE04803)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient modernGradient  = LinearGradient(colors: [primaryOrange, primaryOrangeDark], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient goldGradient    = LinearGradient(colors: [primaryOrange, primaryOrangeDark], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient subtleGradient  = LinearGradient(colors: [scaffoldLight, surfaceLight, surfaceLight2], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  static const LinearGradient weddingGradient = LinearGradient(colors: [scaffoldLight, surfaceLight, scaffoldLight], begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.5, 1.0]);
  static const LinearGradient orangeGrayGradient = LinearGradient(colors: [primaryOrange, grayDark], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient grayGradient    = LinearGradient(colors: [grayLight, grayMedium], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient darkWeddingGradient = LinearGradient(colors: [scaffoldDark, cardBackgroundDark, scaffoldDark], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  static const LinearGradient darkSubtleGradient  = LinearGradient(colors: [scaffoldDark, surfaceDark, scaffoldDark], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  static const LinearGradient darkModernGradient  = LinearGradient(colors: [primaryOrange, primaryOrangeDark, surfaceDark], begin: Alignment.topLeft, end: Alignment.bottomRight, stops: [0.0, 0.5, 1.0]);

  // ── TEXT THEMES ───────────────────────────────────────────────────
  static final TextTheme _lightTextTheme = _buildLightTextTheme();
  static final TextTheme _darkTextTheme  = _buildDarkTextTheme();

  // ── TYPE SCALE (Material 3 harmonious ramp, Poppins) ─────────────
  //
  //  Role              Size   Weight  Usage
  //  ─────────────── ──────  ──────  ─────────────────────────────────
  //  displayLarge      28     700    Splash / hero numbers only
  //  displayMedium     24     600    Large stat cards, big numerics
  //  displaySmall      20     600    Section hero labels
  //  headlineLarge     20     700    Screen page titles (orange)
  //  headlineMedium    18     600    Card titles, dialog headings
  //  headlineSmall     17     600    Sub-section headings
  //  titleLarge        16     600    List item primary text, card name
  //  titleMedium       15     600    Form labels, tab labels
  //  titleSmall        13     500    Chip labels, tag text
  //  bodyLarge         15     400    Paragraph / detail body
  //  bodyMedium        14     400    Standard body everywhere
  //  bodySmall         12     400    Secondary descriptors
  //  labelLarge        13     600    Button text, CTA labels
  //  labelMedium       12     500    Badge text, secondary labels
  //  labelSmall        11     500    Timestamps, fine print, tags
  //
  static TextTheme _buildLightTextTheme() {
    final base = ThemeData.light().textTheme;
    return GoogleFonts.poppinsTextTheme(base).copyWith(
      displayLarge:  GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: textDark, letterSpacing: -0.5, height: 1.2),
      displayMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: textDark, height: 1.3),
      displaySmall:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: textDark, height: 1.3),
      headlineLarge:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: primaryOrange, height: 1.3),
      headlineMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: primaryOrange, height: 1.3),
      headlineSmall:  GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: textDark, height: 1.4),
      titleLarge:  GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textDark, letterSpacing: 0.1, height: 1.4),
      titleMedium: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: textDark, height: 1.4),
      titleSmall:  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: textMedium, height: 1.4),
      bodyLarge:   GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w400, color: textMedium, height: 1.6),
      bodyMedium:  GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: textMedium, height: 1.55),
      bodySmall:   GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: textLight, height: 1.5),
      labelLarge:  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textDark, letterSpacing: 0.2),
      labelMedium: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textMedium),
      labelSmall:  GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: textLight, letterSpacing: 0.3),
    );
  }

  static TextTheme _buildDarkTextTheme() {
    final base = ThemeData.dark().textTheme;
    return GoogleFonts.poppinsTextTheme(base).copyWith(
      displayLarge:  GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: textDarkOnDark, letterSpacing: -0.5, height: 1.2),
      displayMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: textDarkOnDark, height: 1.3),
      displaySmall:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: textDarkOnDark, height: 1.3),
      headlineLarge:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: primaryOrangeLight, height: 1.3),
      headlineMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: primaryOrangeLight, height: 1.3),
      headlineSmall:  GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: textDarkOnDark, height: 1.4),
      titleLarge:  GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textDarkOnDark, letterSpacing: 0.1, height: 1.4),
      titleMedium: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: textDarkOnDark, height: 1.4),
      titleSmall:  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: textMediumOnDark, height: 1.4),
      bodyLarge:   GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w400, color: textMediumOnDark, height: 1.6),
      bodyMedium:  GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: textMediumOnDark, height: 1.55),
      bodySmall:   GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: textLightOnDark, height: 1.5),
      labelLarge:  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textDarkOnDark, letterSpacing: 0.2),
      labelMedium: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textMediumOnDark),
      labelSmall:  GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: textLightOnDark, letterSpacing: 0.3),
    );
  }

  static ThemeData lightTheme = _buildLightTheme();
  static ThemeData darkTheme  = _buildDarkTheme();

  // ════════════════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ════════════════════════════════════════════════════════════════════
  static ThemeData _buildLightTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primaryOrange, onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDBCC), onPrimaryContainer: primaryOrangeDark,
      secondary: primaryGold, onSecondary: Colors.white,
      secondaryContainer: surfaceLight2, onSecondaryContainer: textMedium,
      tertiary: peacockBlue, onTertiary: Colors.white,
      tertiaryContainer: surfaceLight, onTertiaryContainer: textMedium,
      error: kumkumRed, onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6), onErrorContainer: Color(0xFF93000A),
      surface: cardBackground, onSurface: textDark,
      onSurfaceVariant: textMedium,
      outline: Color(0xFFE9EDEF), outlineVariant: surfaceLight2,
      shadow: Colors.black, scrim: Color(0x80000000),
      inverseSurface: textDark, onInverseSurface: scaffoldLight,
      inversePrimary: primaryOrangeLight, surfaceTint: Colors.transparent,
    ),
    scaffoldBackgroundColor: scaffoldLight,
    textTheme: _lightTextTheme,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primaryOrange,
      selectionColor: primaryOrange.withAlpha(80),
      selectionHandleColor: primaryOrange,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryOrange, foregroundColor: Colors.white,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: primaryOrange,
      unselectedItemColor: Colors.white70,
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: primaryOrange),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11, color: Colors.white70),
      type: BottomNavigationBarType.fixed, elevation: 0,
      showSelectedLabels: true, showUnselectedLabels: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white, elevation: 8,
      shadowColor: Colors.black12, surfaceTintColor: Colors.transparent,
      indicatorColor: primaryOrange.withAlpha(22),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: primaryOrange)
          : GoogleFonts.poppins(fontSize: 11, color: textLight)),
      iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const IconThemeData(color: primaryOrange, size: 24)
          : const IconThemeData(color: textLight, size: 24)),
    ),
    cardTheme: CardThemeData(
      color: cardBackground, surfaceTintColor: Colors.transparent,
      elevation: 1, shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surfaceLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE9EDEF))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE9EDEF))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryOrange, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kumkumRed)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kumkumRed, width: 2)),
      labelStyle: GoogleFonts.poppins(color: textMedium, fontWeight: FontWeight.w500, fontSize: 14),
      // Keep the floating label grey even when the field is focused — the
      // orange focused border already shows active state clearly.
      floatingLabelStyle: GoogleFonts.poppins(color: Color(0xFF757575), fontWeight: FontWeight.w500, fontSize: 12),
      hintStyle:  GoogleFonts.poppins(color: textLight, fontWeight: FontWeight.w400, fontSize: 14),
      prefixIconColor: textMedium, suffixIconColor: textMedium,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: primaryOrange, foregroundColor: Colors.white,
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkWhiteOnBrand())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: primaryOrange, side: const BorderSide(color: primaryOrange, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkPrimaryOnLightSurface())),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: primaryOrange,
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkPrimaryOnLightSurface())),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceLight2, selectedColor: primaryOrange.withAlpha(20),
      disabledColor: surfaceLight2,
      labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textMedium),
      secondaryLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: primaryOrange),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE9EDEF))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: textDark),
      contentTextStyle: GoogleFonts.poppins(fontSize: 14, color: textMedium),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1F2C34),
      contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating, elevation: 6,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE9EDEF), thickness: 1, space: 16),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryOrange, circularTrackColor: Color(0xFFE9EDEF)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: primaryOrange, foregroundColor: Colors.white, elevation: 4, shape: CircleBorder()),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primaryOrange : const Color(0xFFCCCCCC)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primaryOrange : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: Color(0xFFBBBBBB), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      titleTextStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: textDark),
      subtitleTextStyle: GoogleFonts.poppins(fontSize: 12, color: textLight),
      iconColor: textMedium,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primaryOrange, unselectedLabelColor: textLight,
      indicatorColor: primaryOrange, indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
      dividerColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.poppins(fontSize: 14, color: textDark), elevation: 4,
    ),
    menuTheme: MenuThemeData(style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(4),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    )),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.poppins(fontSize: 14, color: textDark),
      menuStyle: const MenuStyle(backgroundColor: WidgetStatePropertyAll(Colors.white), surfaceTintColor: WidgetStatePropertyAll(Colors.transparent)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(overlayColor: _softInkPrimaryOnLightSurface()),
    ),
    iconTheme: const IconThemeData(color: textMedium, size: 24),
  );

  // ════════════════════════════════════════════════════════════════════
  //  DARK THEME  (Material 3 layered surfaces + brand orange)
  // ════════════════════════════════════════════════════════════════════
  static ThemeData _buildDarkTheme() {
    // Seed gives correct M3 surface container ramp; we override to our palette.
    final cs = ColorScheme.fromSeed(
      seedColor: primaryOrange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryOrange,
      onPrimary: Colors.white,
      primaryContainer: primaryOrangeDark,
      onPrimaryContainer: Colors.white,
      secondary: primaryOrangeLight,
      onSecondary: Colors.white,
      secondaryContainer: surfaceDark,
      onSecondaryContainer: textDarkOnDark,
      tertiary: peacockBlue,
      onTertiary: Colors.white,
      tertiaryContainer: surfaceDark2,
      onTertiaryContainer: textMediumOnDark,
      error: kumkumRed,
      onError: Colors.white,
      errorContainer: const Color(0xFF4A1010),
      onErrorContainer: const Color(0xFFFFB4B4),
      surface: scaffoldDark,
      onSurface: textDarkOnDark,
      onSurfaceVariant: textMediumOnDark,
      outline: borderDark,
      outlineVariant: dividerDark,
      shadow: Colors.black,
      scrim: const Color(0xCC000000),
      inverseSurface: textDarkOnDark,
      onInverseSurface: scaffoldDark,
      inversePrimary: primaryOrangeDark,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: surfaceDark3,
      surfaceContainerLow: const Color(0xFF111B21),
      surfaceContainer: cardBackgroundDark,
      surfaceContainerHigh: surfaceDark,
      surfaceContainerHighest: surfaceDark2,
    );

    return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: cs,
    scaffoldBackgroundColor: scaffoldDark,
    textTheme: _darkTextTheme,
    splashColor: primaryOrange.withAlpha(20),
    highlightColor: primaryOrange.withAlpha(10),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primaryOrange,
      selectionColor: primaryOrange.withAlpha(80),
      selectionHandleColor: primaryOrange,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryOrange, foregroundColor: Colors.white,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: primaryOrangeLight,
      unselectedItemColor: Colors.white60,
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: primaryOrangeLight),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11, color: Colors.white60),
      type: BottomNavigationBarType.fixed, elevation: 0,
      showSelectedLabels: true, showUnselectedLabels: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardBackgroundDark,
      elevation: 0, surfaceTintColor: Colors.transparent,
      indicatorColor: primaryOrange.withAlpha(40), height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: primaryOrangeLight)
          : GoogleFonts.poppins(fontSize: 11, color: textMediumOnDark)),
      iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const IconThemeData(color: primaryOrangeLight, size: 24)
          : const IconThemeData(color: textMediumOnDark, size: 24)),
    ),
    cardTheme: CardThemeData(
      color: cardBackgroundDark,
      surfaceTintColor: Colors.transparent,
      elevation: 1.5,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: borderDark, width: 0.5)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surfaceDark,           // #2A3942
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderDark)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderDark)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryOrange, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kumkumRed)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kumkumRed, width: 2)),
      labelStyle: GoogleFonts.poppins(color: textMediumOnDark, fontWeight: FontWeight.w500, fontSize: 14),
      floatingLabelStyle: GoogleFonts.poppins(color: Color(0xFF8696A0), fontWeight: FontWeight.w500, fontSize: 12),
      hintStyle:  GoogleFonts.poppins(color: textLightOnDark, fontWeight: FontWeight.w400, fontSize: 14),
      prefixIconColor: textMediumOnDark, suffixIconColor: textMediumOnDark,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: primaryOrange, foregroundColor: Colors.white,
      elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkWhiteOnBrand())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: primaryOrangeLight, side: const BorderSide(color: primaryOrange, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkPrimaryOnDarkSurface())),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: primaryOrangeLight,
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      tapTargetSize: MaterialTapTargetSize.padded,
    ).copyWith(overlayColor: _softInkPrimaryOnDarkSurface())),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceDark, selectedColor: primaryOrange.withAlpha(40),
      disabledColor: surfaceDark2,
      labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textMediumOnDark),
      secondaryLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: primaryOrangeLight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: borderDark)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardBackgroundDark, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: borderDark, width: 0.5)),
      titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: textDarkOnDark),
      contentTextStyle: GoogleFonts.poppins(fontSize: 14, color: textMediumOnDark), elevation: 24,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardBackgroundDark, surfaceTintColor: Colors.transparent,
      modalBackgroundColor: cardBackgroundDark, dragHandleColor: Color(0xFF8696A0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceDark,
      contentTextStyle: GoogleFonts.poppins(color: textDarkOnDark, fontWeight: FontWeight.w500, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating, elevation: 8,
    ),
    dividerTheme: const DividerThemeData(color: dividerDark, thickness: 0.5, space: 16),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryOrange, circularTrackColor: surfaceDark, linearTrackColor: surfaceDark),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: primaryOrange, foregroundColor: Colors.white, elevation: 6, shape: CircleBorder()),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF8696A0)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryOrange : surfaceDark),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.transparent : borderDark),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryOrange : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: Color(0xFF8696A0), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      titleTextStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: textDarkOnDark),
      subtitleTextStyle: GoogleFonts.poppins(fontSize: 12, color: textMediumOnDark),
      iconColor: textMediumOnDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primaryOrangeLight, unselectedLabelColor: textMediumOnDark,
      indicatorColor: primaryOrangeLight, indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
      dividerColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardBackgroundDark, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: borderDark, width: 0.5)),
      textStyle: GoogleFonts.poppins(fontSize: 14, color: textDarkOnDark), elevation: 12,
    ),
    menuTheme: MenuThemeData(style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(cardBackgroundDark),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(12),
      side: const WidgetStatePropertyAll(BorderSide(color: borderDark, width: 0.5)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    )),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.poppins(fontSize: 14, color: textDarkOnDark),
      menuStyle: const MenuStyle(backgroundColor: WidgetStatePropertyAll(cardBackgroundDark), surfaceTintColor: WidgetStatePropertyAll(Colors.transparent)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(overlayColor: _softInkPrimaryOnDarkSurface()),
    ),
    // Every un-coloured icon uses this — clearly visible on dark bg
    iconTheme: const IconThemeData(color: textMediumOnDark, size: 24),
    drawerTheme: const DrawerThemeData(
      backgroundColor: cardBackgroundDark,
      surfaceTintColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderDark, width: 0.5),
      ),
      textStyle: GoogleFonts.poppins(color: textDarkOnDark, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
  );
  }

  // ── DECORATION HELPERS ────────────────────────────────────────────
  static BoxDecoration modernCard({Color? color, double borderRadius = 12}) => BoxDecoration(
    color: color ?? cardBackground,
    borderRadius: BorderRadius.circular(borderRadius),
    boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 8, offset: const Offset(0, 2))],
  );
  static BoxDecoration darkCard({Color? color, double borderRadius = 12}) => BoxDecoration(
    color: color ?? cardBackgroundDark,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: borderDark, width: 0.5),
  );
  static BoxDecoration orangeAccent({double borderRadius = 12}) => BoxDecoration(
    gradient: modernGradient,
    borderRadius: BorderRadius.circular(borderRadius),
    boxShadow: [BoxShadow(color: primaryOrange.withAlpha(60), blurRadius: 12, offset: const Offset(0, 4))],
  );
  static BoxDecoration elevatedCard({double borderRadius = 12, BuildContext? context}) {
    final isDark = context != null && Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return BoxDecoration(
        color: cardBackgroundDark,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderDark, width: 0.5),
      );
    }
    return BoxDecoration(
      color: cardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, 3))],
    );
  }
  static BoxDecoration traditionalBorder({Color? color, double borderRadius = 20}) => BoxDecoration(
    color: color ?? cardBackground,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: veryLightGray, width: 1),
    boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 8, offset: const Offset(0, 2))],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class ModernPatternPainter extends CustomPainter {
  final Color color;
  ModernPatternPainter({this.color = AppTheme.primaryOrange});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withAlpha(15)..style = PaintingStyle.stroke..strokeWidth = 1;
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
/// AC — Adaptive Color helper (WhatsApp palette, single source of truth).
///
/// Use [AC.text], [AC.textSub], [AC.icon], [AC.border], etc. for any text or
/// chrome on [AC.card]/[AC.surface] backgrounds so light and dark mode stay
/// readable. Avoid `Colors.black*`, `AppTheme.textDark`, or `const TextStyle`
/// without an explicit theme-aware `color:` on screens that support both themes.
// ─────────────────────────────────────────────────────────────────────────────
class AC {
  static bool _d(BuildContext ctx) => Theme.of(ctx).brightness == Brightness.dark;

  static Color bg(BuildContext ctx)       => _d(ctx) ? AppTheme.scaffoldDark       : AppTheme.scaffoldLight;
  static Color card(BuildContext ctx)     => _d(ctx) ? AppTheme.cardBackgroundDark  : AppTheme.cardBackground;
  static Color surface(BuildContext ctx)  => _d(ctx) ? AppTheme.surfaceDark         : AppTheme.surfaceLight;
  static Color surface2(BuildContext ctx) => _d(ctx) ? AppTheme.surfaceDark2        : AppTheme.surfaceLight2;
  static Color surface3(BuildContext ctx) => _d(ctx) ? AppTheme.surfaceDark3        : const Color(0xFFDDDDDD);
  static Color appBar(BuildContext ctx)   => AppTheme.primaryOrange;   // always orange
  static Color border(BuildContext ctx)   => _d(ctx) ? AppTheme.borderDark          : const Color(0xFFE9EDEF);
  static Color divider(BuildContext ctx)  => _d(ctx) ? AppTheme.dividerDark         : const Color(0xFFE9EDEF);
  static Color text(BuildContext ctx)     => _d(ctx) ? AppTheme.textDarkOnDark      : AppTheme.textDark;
  static Color textSub(BuildContext ctx)  => _d(ctx) ? AppTheme.textMediumOnDark    : AppTheme.textMedium;
  static Color textMuted(BuildContext ctx)=> _d(ctx) ? AppTheme.textLightOnDark     : AppTheme.textLight;
  static Color icon(BuildContext ctx)     => _d(ctx) ? AppTheme.textMediumOnDark    : AppTheme.textMedium;
  static Color accent(BuildContext ctx)   => _d(ctx) ? AppTheme.primaryOrangeLight  : AppTheme.primaryOrange;
  static Color shadow(BuildContext ctx)   => _d(ctx) ? Colors.black54               : Colors.black12;
  static Color inputFill(BuildContext ctx)=> _d(ctx) ? AppTheme.surfaceDark         : AppTheme.surfaceLight;
  static Color dropdown(BuildContext ctx) => _d(ctx) ? AppTheme.cardBackgroundDark  : Colors.white;

  static Color shimmerBase(BuildContext ctx)      => _d(ctx) ? AppTheme.surfaceDark  : const Color(0xFFEEEEEE);
  static Color shimmerHighlight(BuildContext ctx) => _d(ctx) ? AppTheme.surfaceDark2 : const Color(0xFFF5F5F5);

  // Shorthand adaptive card decoration
  static BoxDecoration cardDecoration(BuildContext ctx, {double radius = 12}) => _d(ctx)
      ? BoxDecoration(color: AppTheme.cardBackgroundDark, borderRadius: BorderRadius.circular(radius), border: Border.all(color: AppTheme.borderDark, width: 0.5))
      : BoxDecoration(color: AppTheme.cardBackground, borderRadius: BorderRadius.circular(radius), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 8, offset: const Offset(0, 2))]);

  /// Profile wizard / form sections — same shape as [AppTheme.traditionalBorder] but theme-aware.
  static BoxDecoration traditionalBorder(BuildContext ctx, {double borderRadius = 20}) => BoxDecoration(
        color: card(ctx),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border(ctx), width: 1),
        boxShadow: [BoxShadow(color: shadow(ctx), blurRadius: 8, offset: const Offset(0, 2))],
      );
}
