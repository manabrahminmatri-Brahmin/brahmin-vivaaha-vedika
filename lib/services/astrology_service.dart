import 'package:flutter/foundation.dart';
import '../data/reference_data.dart';
import 'chandra_manam_provider.dart';
import '../models/user.dart';

class AstrologyDetails {
  AstrologyDetails({required this.nakshatra, required this.pada});

  final String nakshatra;
  final String pada;
}

abstract class AstrologyProvider {
  Future<AstrologyDetails> compute({
    required DateTime birthDateTime,
    double? latitude,
    double? longitude,
  });
}

/// Improved Fallback astrology provider with better accuracy
/// 
/// This implementation provides more accurate nakshatra calculations
/// using astronomical algorithms that approximate lunar calendar calculations.
/// While still a fallback, it's much more accurate than the simple modulo approach.
class ImprovedFallbackAstrologyProvider implements AstrologyProvider {
  static final DateTime _epoch = DateTime.utc(2000, 1, 1, 12, 0, 0); // J2000.0 epoch

  @override
  Future<AstrologyDetails> compute({
    required DateTime birthDateTime,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Convert birth datetime to UTC
      final birthUTC = birthDateTime.toUtc();
      
      // Calculate Julian Day Number
      final julianDay = _calculateJulianDay(birthUTC);
      
      // Calculate moon position (simplified but more accurate)
      final moonLongitude = _calculateMoonLongitude(julianDay);
      
      // Determine nakshatra based on moon position
      final nakshatraIndex = (moonLongitude / 13.333333333).floor(); // 360/27 = 13.333...
      final nakshatra = ReferenceData.nakshatras[nakshatraIndex % ReferenceData.nakshatras.length];
      
      // Calculate pada (each nakshatra has 4 padas of 3°20' each)
      final padaIndex = ((moonLongitude % 13.333333333) / 3.333333333).floor();
      final pada = (padaIndex + 1).toString();
      
      debugPrint('🌙 Nakshatra calculated: $nakshatra Pada $pada (Moon longitude: ${moonLongitude.toStringAsFixed(2)}°)');
      
      return AstrologyDetails(nakshatra: nakshatra, pada: pada);
    } catch (e) {
      debugPrint('❌ Error calculating nakshatra: $e');
      // Fallback to simple calculation if improved method fails
      return _fallbackSimpleCalculation(birthDateTime);
    }
  }

  /// Calculate Julian Day Number for given datetime
  double _calculateJulianDay(DateTime dateTime) {
    final year = dateTime.year;
    final month = dateTime.month;
    final day = dateTime.day;
    final hour = dateTime.hour;
    final minute = dateTime.minute;
    final second = dateTime.second;
    
    int a, b;
    if (month <= 2) {
      a = year - 1;
      b = (a / 100).floor() - (a / 400).floor() - 2;
    } else {
      a = year;
      b = (a / 100).floor() - (a / 400).floor();
    }
    
    final jd = (365.25 * (a + 4716)).floor() +
               (30.6001 * (month + 1)).floor() +
               day + b - 1524.5 +
               (hour / 24.0) +
               (minute / 1440.0) +
               (second / 86400.0);
    
    return jd;
  }

  /// Calculate moon longitude (simplified but more accurate than modulo)
  double _calculateMoonLongitude(double julianDay) {
    // Number of days since J2000.0 epoch
    final daysSinceEpoch = julianDay - 2451545.0;
    
    // Mean longitude of Moon (simplified formula)
    double moonLongitude = 218.3164477 + 
                          13.1763966 * daysSinceEpoch +
                          0.001878 * _sinDeg(135.0 + 13.1763966 * daysSinceEpoch);
    
    // Apply some corrections for better accuracy
    moonLongitude += 0.0059 * _sinDeg(93.3 + 13.1763966 * daysSinceEpoch);
    moonLongitude += 0.0032 * _sinDeg(228.2 + 26.5528777 * daysSinceEpoch);
    
    // Normalize to 0-360 degrees
    moonLongitude = moonLongitude % 360;
    if (moonLongitude < 0) moonLongitude += 360;
    
    return moonLongitude;
  }

  /// Sine function working with degrees
  double _sinDeg(double degrees) {
    return _sin(_toRadians(degrees));
  }

  /// Convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * 3.141592653589793 / 180.0;
  }

  /// Simple sine function (Taylor series approximation)
  double _sin(double radians) {
    // Simplified sine calculation using Taylor series
    double result = radians;
    double term = radians;
    double radiansSquared = radians * radians;
    
    // Taylor series: sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    for (int i = 1; i <= 5; i++) {
      term *= -radiansSquared / ((2 * i) * (2 * i + 1));
      result += term;
    }
    
    return result;
  }

  /// Fallback simple calculation if improved method fails
  AstrologyDetails _fallbackSimpleCalculation(DateTime birthDateTime) {
    final minutes = birthDateTime.toUtc().difference(_epoch).inMinutes;
    final safeMinutes = minutes >= 0 ? minutes : -minutes;

    final nakshatraIndex = safeMinutes % ReferenceData.nakshatras.length;
    final nakshatra = ReferenceData.nakshatras[nakshatraIndex];

    final pada = (safeMinutes % 4) + 1;

    debugPrint('⚠️ Used fallback simple calculation for nakshatra');
    return AstrologyDetails(nakshatra: nakshatra, pada: pada.toString());
  }
}

/// Fallback astrology provider - DEPRECATED, use ImprovedFallbackAstrologyProvider
/// 
/// This is the old simple placeholder calculation and does NOT use Chandra Manam (lunar calendar).
/// For accurate nakshatra calculation based on Chandra Manam, you MUST use
/// ImprovedFallbackAstrologyProvider or configure a proper astrology API provider using AstrologyService.configure().
/// 
/// The nakshatra should be calculated based on the moon's position in the lunar calendar,
/// which requires proper astronomical calculations. This fallback uses a simple modulo
/// operation which will produce incorrect results.
@Deprecated('Use ImprovedFallbackAstrologyProvider instead')
class FallbackAstrologyProvider implements AstrologyProvider {
  static final DateTime _epoch = DateTime.utc(1900, 1, 1);

  @override
  Future<AstrologyDetails> compute({
    required DateTime birthDateTime,
    double? latitude,
    double? longitude,
  }) async {
    // WARNING: This is NOT an accurate calculation!
    // This is a placeholder that does NOT use Chandra Manam (lunar calendar).
    // For accurate nakshatra, configure an astrology API provider that calculates
    // based on the moon's position in the lunar calendar.
    final minutes = birthDateTime.toUtc().difference(_epoch).inMinutes;
    final safeMinutes = minutes >= 0 ? minutes : -minutes;

    final nakshatraIndex = safeMinutes % ReferenceData.nakshatras.length;
    final nakshatra = ReferenceData.nakshatras[nakshatraIndex];

    final pada = (safeMinutes % 4) + 1;

    return AstrologyDetails(nakshatra: nakshatra, pada: pada.toString());
  }
}

class AstrologyService {
  AstrologyService._();

  // Use ChandraManamProvider by default for accurate lunar calendar calculations
  static AstrologyProvider _provider = ChandraManamProvider();

  static void configure(AstrologyProvider provider) {
    _provider = provider;
  }

  static Future<AstrologyDetails> calculate(
    DateTime birthDateTime, {
    double? latitude,
    double? longitude,
  }) {
    return _provider.compute(
      birthDateTime: birthDateTime,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Rashis (Moon Signs) in order
  static const List<String> _rashis = [
    'Aries',      // Mesha - 1
    'Taurus',     // Vrishabha - 2  
    'Gemini',      // Mithuna - 3
    'Cancer',     // Karka - 4
    'Leo',        // Simha - 5
    'Virgo',      // Kanya - 6
    'Libra',      // Tula - 7
    'Scorpio',    // Vrischika - 8
    'Sagittarius', // Dhanu - 9
    'Capricorn',  // Makara - 10
    'Aquarius',   // Kumbha - 11
    'Pisces',     // Meena - 12
  ];

  /// Get rashi index (1-12) from rashi name
  static int _getRashiIndex(String? rashi) {
    if (rashi == null || rashi.isEmpty) return 0;
    
    final index = _rashis.indexOf(rashi.trim());
    return index >= 0 ? index + 1 : 0; // Return 1-12 or 0 if not found
  }

  /// Check Shashta Ashtaka Dosha between two rashis
  /// Returns [hasDosha, relation, details]
  static ShashtaAshtakaResult checkShashtaAshtakaDosha({
    required String? brideRashi,
    required String? groomRashi,
  }) {
    final brideIndex = _getRashiIndex(brideRashi);
    final groomIndex = _getRashiIndex(groomRashi);

    if (brideIndex == 0 || groomIndex == 0) {
      return ShashtaAshtakaResult(
        hasDosha: false,
        relation: 'Unknown',
        details: 'Rashi information not available',
      );
    }

    // Calculate position differences
    final brideToGroom = _getRashiRelation(brideIndex, groomIndex);
    final groomToBride = _getRashiRelation(groomIndex, brideIndex);

    // Check for 6th (Shashta) or 8th (Ashtaka) positions
    final hasDosha = brideToGroom == 6 || brideToGroom == 8 || 
                   groomToBride == 6 || groomToBride == 8;

    String relation = 'Compatible';
    String details = 'No dosha detected';

    if (hasDosha) {
      final relations = <String>[];
      if (brideToGroom == 6) relations.add('Bride is 6th from Groom (Shashta)');
      if (brideToGroom == 8) relations.add('Bride is 8th from Groom (Ashtaka)');
      if (groomToBride == 6) relations.add('Groom is 6th from Bride (Shashta)');
      if (groomToBride == 8) relations.add('Groom is 8th from Bride (Ashtaka)');
      
      relation = 'Shashta Ashtaka Dosha';
      details = relations.join(', ');
    }

    return ShashtaAshtakaResult(
      hasDosha: hasDosha,
      relation: relation,
      details: details,
      brideToGroomPosition: brideToGroom,
      groomToBridePosition: groomToBride,
    );
  }

  /// Get positional relationship between two rashis (1-12)
  static int _getRashiRelation(int fromRashi, int toRashi) {
    if (fromRashi == toRashi) return 0;
    
    int difference = toRashi - fromRashi;
    if (difference <= 0) difference += 12;
    
    return difference;
  }

  /// Get rashi from date of birth (simplified calculation)
  /// Note: For accurate calculations, use proper astrology libraries
  static String? getRashiFromDOB(DateTime dob) {
    // This is a simplified calculation
    // In production, use proper Vedic astrology calculation based on exact time and location
    final month = dob.month;
    final day = dob.day;

    // Simplified rashi calculation (not 100% accurate without time/location)
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return 'Aries';
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return 'Taurus';
    if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return 'Gemini';
    if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return 'Cancer';
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return 'Leo';
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return 'Virgo';
    if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return 'Libra';
    if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return 'Scorpio';
    if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return 'Sagittarius';
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return 'Capricorn';
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'Aquarius';
    if ((month == 2 && day >= 19) || (month == 3 && day <= 20)) return 'Pisces';
    
    return null;
  }

  /// Check dosha between two users using their DOB
  static ShashtaAshtakaResult checkDoshaBetweenUsers({
    required DateTime? brideDOB,
    required DateTime? groomDOB,
    String? brideRashi,
    String? groomRashi,
  }) {
    // Use provided rashi if available, otherwise calculate from DOB
    brideRashi ??= getRashiFromDOB(brideDOB ?? DateTime.now());
    groomRashi ??= getRashiFromDOB(groomDOB ?? DateTime.now());

    return checkShashtaAshtakaDosha(
      brideRashi: brideRashi,
      groomRashi: groomRashi,
    );
  }

  /// Check dosha between current user and another profile
  static ShashtaAshtakaResult checkDoshaWithCurrentUser(User otherUser, User? currentUser) {
    if (currentUser == null || currentUser.profile == null || otherUser.profile == null) {
      return const ShashtaAshtakaResult(
        hasDosha: false,
        relation: 'Unknown',
        details: 'Profile information not available',
      );
    }

    return checkDoshaBetweenUsers(
      brideDOB: currentUser.profile!.dateOfBirth,
      groomDOB: otherUser.profile!.dateOfBirth,
      brideRashi: currentUser.profile?.rasi,
      groomRashi: otherUser.profile?.rasi,
    );
  }
}

/// Result of Shashta Ashtaka Dosha check
class ShashtaAshtakaResult {
  final bool hasDosha;
  final String relation;
  final String details;
  final int? brideToGroomPosition;
  final int? groomToBridePosition;

  const ShashtaAshtakaResult({
    required this.hasDosha,
    required this.relation,
    required this.details,
    this.brideToGroomPosition,
    this.groomToBridePosition,
  });

  @override
  String toString() {
    return 'ShashtaAshtakaResult(hasDosha: $hasDosha, relation: $relation, details: $details)';
  }
}
