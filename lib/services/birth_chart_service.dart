import 'dart:math';
import '../models/birth_chart.dart';
import '../data/reference_data.dart';

/// Comprehensive Birth Chart Calculation Service
/// Calculates all planetary positions, houses, and aspects
class BirthChartService {
  static const double ayanamsaLahiri = 23.8530277778; // degrees (as of 2000 CE)
  
  /// Calculate complete birth chart
  static Future<BirthChart> calculateBirthChart({
    required DateTime birthDateTime,
    required double latitude,
    required double longitude,
    String timezone = 'IST',
  }) async {
    // Calculate Julian Day
    final jd = _julianDay(birthDateTime);
    final d = jd - 2451545.0; // Days since J2000.0
    final t = d / 36525.0; // Centuries since J2000.0

    // Calculate ayanamsa
    final ayanamsa = ayanamsaLahiri + (0.01397 * t);

    // Calculate all planetary positions
    final planets = <Planet, PlanetPosition>{};
    
    // Calculate each planet
    for (final planet in Planet.values) {
      final position = _calculatePlanetPosition(planet, birthDateTime, ayanamsa);
      planets[planet] = position;
    }

    // Calculate house cusps (simplified - using Placidus system approximation)
    final houseCusps = _calculateHouseCusps(
      birthDateTime,
      latitude,
      longitude,
      ayanamsa,
    );

    // Calculate Lagna (Ascendant)
    final lagnaData = _calculateLagna(birthDateTime, latitude, longitude, ayanamsa);
    final lagna = lagnaData['rasi'] as Rasi;
    final lagnaLongitude = lagnaData['longitude'] as double;

    // Get moon's nakshatra
    final moonPos = planets[Planet.moon]!;
    final moonNakshatraIndex = moonPos.nakshatraIndex;
    final moonNakshatra = ReferenceData.nakshatras[moonNakshatraIndex];
    final moonPada = moonPos.pada;

    // Calculate planetary aspects
    final aspects = _calculateAspects(planets);

    // Get Lagna Lord
    final lagnaLord = _getRasiLord(lagna);

    return BirthChart(
      birthDateTime: birthDateTime,
      latitude: latitude,
      longitude: longitude,
      timezone: timezone,
      planets: planets,
      houseCusps: houseCusps,
      lagna: lagna,
      lagnaLongitude: lagnaLongitude,
      moonNakshatra: moonNakshatra,
      moonPada: moonPada,
      aspects: aspects,
      ayanamsa: ayanamsa,
      lagnaLord: lagnaLord,
    );
  }

  /// Calculate Julian Day Number
  static double _julianDay(DateTime dt) {
    final year = dt.year;
    final month = dt.month;
    final day = dt.day;
    final hour = dt.hour + dt.minute / 60.0 + dt.second / 3600.0;
    final dayFraction = hour / 24.0;

    int a, b;
    if (month <= 2) {
      final y = year - 1;
      a = (y / 100).floor();
      b = 2 - a + (a / 4).floor();
    } else {
      a = (year / 100).floor();
      b = 2 - a + (a / 4).floor();
    }

    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        day +
        dayFraction +
        b -
        1524.5;
  }

  /// Calculate planet position
  static PlanetPosition _calculatePlanetPosition(
    Planet planet,
    DateTime birthDateTime,
    double ayanamsa,
  ) {
    final jd = _julianDay(birthDateTime);
    final d = jd - 2451545.0;
    final t = d / 36525.0;

    double longitude;
    bool isRetrograde = false;

    switch (planet) {
      case Planet.sun:
        longitude = _calculateSunLongitude(t);
        break;
      case Planet.moon:
        longitude = _calculateMoonLongitude(t);
        break;
      case Planet.mars:
        longitude = _calculateMarsLongitude(t);
        isRetrograde = _isMarsRetrograde(t);
        break;
      case Planet.mercury:
        longitude = _calculateMercuryLongitude(t);
        isRetrograde = _isMercuryRetrograde(t);
        break;
      case Planet.jupiter:
        longitude = _calculateJupiterLongitude(t);
        isRetrograde = _isJupiterRetrograde(t);
        break;
      case Planet.venus:
        longitude = _calculateVenusLongitude(t);
        isRetrograde = _isVenusRetrograde(t);
        break;
      case Planet.saturn:
        longitude = _calculateSaturnLongitude(t);
        isRetrograde = _isSaturnRetrograde(t);
        break;
      case Planet.rahu:
        longitude = _calculateRahuLongitude(t);
        break;
      case Planet.ketu:
        longitude = _calculateKetuLongitude(t);
        break;
    }

    // Convert to sidereal
    longitude = longitude - ayanamsa;
    longitude = longitude % 360.0;
    if (longitude < 0) longitude += 360.0;

    // Determine Rasi
    final rasiIndex = (longitude / 30.0).floor();
    final rasi = Rasi.values[rasiIndex % 12];
    final positionInRasi = longitude % 30.0;

    // Determine house (simplified - using equal house system)
    final houseIndex = rasiIndex % 12;
    final house = House.values[houseIndex];

    // For moon, calculate nakshatra longitude
    double nakshatraLongitude = longitude;
    if (planet == Planet.moon) {
      nakshatraLongitude = longitude;
    }

    return PlanetPosition(
      planet: planet,
      longitude: longitude,
      rasi: rasi,
      positionInRasi: positionInRasi,
      house: house,
      isRetrograde: isRetrograde,
      nakshatraLongitude: nakshatraLongitude,
    );
  }

  /// Calculate Sun's longitude
  static double _calculateSunLongitude(double t) {
    final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
    final mRad = m * pi / 180.0;
    final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(mRad) +
        (0.019993 - 0.000101 * t) * sin(2 * mRad) +
        0.000289 * sin(3 * mRad);
    final longitude = l0 + c;
    return longitude % 360.0;
  }

  /// Calculate Moon's longitude (using ChandraManamProvider logic)
  static double _calculateMoonLongitude(double t) {
    final l0 = 218.3164477 + 481267.88123421 * t;
    final m = 134.9633964 + 477198.8675055 * t;
    final l0Rad = l0 * pi / 180.0;
    final mRad = m * pi / 180.0;
    
    double longitude = l0;
    longitude += 6.288774 * sin(mRad);
    longitude += 1.274027 * sin(2 * l0Rad - mRad);
    longitude += 0.658314 * sin(2 * l0Rad);
    longitude += 0.213618 * sin(2 * mRad);
    longitude -= 0.185116 * sin(l0Rad);
    
    return longitude % 360.0;
  }

  /// Calculate Mars' longitude
  static double _calculateMarsLongitude(double t) {
    final l = 355.433 + 19140.299 * t;
    final m = 19.373 + 0.524 * t;
    final mRad = m * pi / 180.0;
    final longitude = l + 10.691 * sin(mRad);
    return longitude % 360.0;
  }

  /// Calculate Mercury's longitude
  static double _calculateMercuryLongitude(double t) {
    final l = 252.250906 + 149472.6746358 * t;
    final m = 174.7948 + 4092.325 * t;
    final mRad = m * pi / 180.0;
    final longitude = l + 23.4400 * sin(mRad);
    return longitude % 360.0;
  }

  /// Calculate Jupiter's longitude
  static double _calculateJupiterLongitude(double t) {
    final l = 34.351519 + 3034.9057 * t;
    final m = 20.020 + 0.083 * t;
    final mRad = m * pi / 180.0;
    final longitude = l + 5.555 * sin(mRad);
    return longitude % 360.0;
  }

  /// Calculate Venus' longitude
  static double _calculateVenusLongitude(double t) {
    final l = 50.416186 + 58517.8153876 * t;
    final m = 50.08 + 1.602 * t;
    final mRad = m * pi / 180.0;
    final longitude = l + 0.775 * sin(mRad);
    return longitude % 360.0;
  }

  /// Calculate Saturn's longitude
  static double _calculateSaturnLongitude(double t) {
    final l = 317.0207 + 1222.1139 * t;
    final m = 317.0207 + 0.033 * t;
    final mRad = m * pi / 180.0;
    final longitude = l + 5.497 * sin(mRad);
    return longitude % 360.0;
  }

  /// Calculate Rahu's longitude (Mean North Node)
  static double _calculateRahuLongitude(double t) {
    final longitude = 125.044522 - 1934.136261 * t;
    return longitude % 360.0;
  }

  /// Calculate Ketu's longitude (Mean South Node, 180° from Rahu)
  static double _calculateKetuLongitude(double t) {
    final rahu = _calculateRahuLongitude(t);
    return (rahu + 180.0) % 360.0;
  }

  /// Check if planet is retrograde (simplified)
  static bool _isMarsRetrograde(double t) => false; // Simplified
  static bool _isMercuryRetrograde(double t) => false; // Simplified
  static bool _isJupiterRetrograde(double t) => false; // Simplified
  static bool _isVenusRetrograde(double t) => false; // Simplified
  static bool _isSaturnRetrograde(double t) => false; // Simplified

  /// Calculate house cusps (simplified Placidus approximation)
  static Map<House, HouseCusp> _calculateHouseCusps(
    DateTime birthDateTime,
    double latitude,
    double longitude,
    double ayanamsa,
  ) {
    final lagnaData = _calculateLagna(birthDateTime, latitude, longitude, ayanamsa);
    final lagnaLongitude = lagnaData['longitude'] as double;
    
    final cusps = <House, HouseCusp>{};
    
    // Equal house system (simplified)
    for (int i = 0; i < 12; i++) {
      final houseLongitude = (lagnaLongitude + i * 30.0) % 360.0;
      final rasiIndex = (houseLongitude / 30.0).floor();
      final rasi = Rasi.values[rasiIndex % 12];
      
      cusps[House.values[i]] = HouseCusp(
        house: House.values[i],
        longitude: houseLongitude,
        rasi: rasi,
      );
    }
    
    return cusps;
  }

  /// Calculate Lagna (Ascendant)
  static Map<String, dynamic> _calculateLagna(
    DateTime birthDateTime,
    double latitude,
    double longitude,
    double ayanamsa,
  ) {
    // Simplified calculation - in production, use proper sidereal time calculation
    final jd = _julianDay(birthDateTime);
    final localSiderealTime = _calculateLocalSiderealTime(jd, longitude);
    
    // Convert to degrees
    final lagnaLongitude = (localSiderealTime * 15.0) % 360.0;
    
    // Apply ayanamsa
    final siderealLagna = lagnaLongitude - ayanamsa;
    final normalizedLagna = siderealLagna % 360.0;
    final finalLagna = normalizedLagna < 0 ? normalizedLagna + 360.0 : normalizedLagna;
    
    final rasiIndex = (finalLagna / 30.0).floor();
    final rasi = Rasi.values[rasiIndex % 12];
    
    return {
      'longitude': finalLagna,
      'rasi': rasi,
    };
  }

  /// Calculate Local Sidereal Time (simplified)
  static double _calculateLocalSiderealTime(double jd, double longitude) {
    final t = (jd - 2451545.0) / 36525.0;
    final theta0 = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 
        0.000387933 * t * t - t * t * t / 38710000.0;
    final lst = (theta0 + longitude) / 15.0;
    return lst % 24.0;
  }

  /// Calculate planetary aspects
  static List<PlanetaryAspect> _calculateAspects(
    Map<Planet, PlanetPosition> planets,
  ) {
    final aspects = <PlanetaryAspect>[];
    final planetList = planets.keys.toList();
    
    for (int i = 0; i < planetList.length; i++) {
      for (int j = i + 1; j < planetList.length; j++) {
        final planet1 = planetList[i];
        final planet2 = planetList[j];
        final pos1 = planets[planet1]!;
        final pos2 = planets[planet2]!;
        
        double angle = (pos1.longitude - pos2.longitude).abs();
        if (angle > 180) angle = 360 - angle;
        
        // Check for aspects (with 8° orb)
        final orb = 8.0;
        
        // Conjunction (0°)
        if (angle <= orb || angle >= 360 - orb) {
          aspects.add(PlanetaryAspect(
            fromPlanet: planet1,
            toPlanet: planet2,
            type: AspectType.conjunction,
            orb: angle > 180 ? 360 - angle : angle,
          ));
        }
        // Opposition (180°)
        else if ((angle - 180).abs() <= orb) {
          aspects.add(PlanetaryAspect(
            fromPlanet: planet1,
            toPlanet: planet2,
            type: AspectType.opposition,
            orb: (angle - 180).abs(),
          ));
        }
        // Trine (120°)
        else if ((angle - 120).abs() <= orb || (angle - 240).abs() <= orb) {
          aspects.add(PlanetaryAspect(
            fromPlanet: planet1,
            toPlanet: planet2,
            type: AspectType.trine,
            orb: (angle - 120).abs() < (angle - 240).abs() 
                ? (angle - 120).abs() 
                : (angle - 240).abs(),
          ));
        }
        // Square (90°)
        else if ((angle - 90).abs() <= orb || (angle - 270).abs() <= orb) {
          aspects.add(PlanetaryAspect(
            fromPlanet: planet1,
            toPlanet: planet2,
            type: AspectType.square,
            orb: (angle - 90).abs() < (angle - 270).abs() 
                ? (angle - 90).abs() 
                : (angle - 270).abs(),
          ));
        }
        // Sextile (60°)
        else if ((angle - 60).abs() <= orb || (angle - 300).abs() <= orb) {
          aspects.add(PlanetaryAspect(
            fromPlanet: planet1,
            toPlanet: planet2,
            type: AspectType.sextile,
            orb: (angle - 60).abs() < (angle - 300).abs() 
                ? (angle - 60).abs() 
                : (angle - 300).abs(),
          ));
        }
      }
    }
    
    return aspects;
  }

  /// Get Rasi Lord
  static String _getRasiLord(Rasi rasi) {
    const lords = [
      'Mars',    // Mesha
      'Venus',   // Vrishabha
      'Mercury', // Mithuna
      'Moon',    // Karkata
      'Sun',     // Simha
      'Mercury', // Kanya
      'Venus',   // Tula
      'Mars',    // Vrischika
      'Jupiter', // Dhanu
      'Saturn',  // Makara
      'Saturn',  // Kumbha
      'Jupiter', // Meena
    ];
    return lords[rasi.index];
  }
}
