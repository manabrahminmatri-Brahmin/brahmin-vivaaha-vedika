/// Comprehensive Birth Chart Model for Jatakam Matching
/// Contains all planetary positions, houses, and astrological data

library;

/// Planet enumeration
enum Planet {
  sun,
  moon,
  mars,
  mercury,
  jupiter,
  venus,
  saturn,
  rahu, // North Node
  ketu, // South Node
}

/// House enumeration (1-12)
enum House {
  first,
  second,
  third,
  fourth,
  fifth,
  sixth,
  seventh,
  eighth,
  ninth,
  tenth,
  eleventh,
  twelfth,
}

/// Rasi (Zodiac Sign) enumeration
enum Rasi {
  mesha, // Aries
  vrishabha, // Taurus
  mithuna, // Gemini
  karkata, // Cancer
  simha, // Leo
  kanya, // Virgo
  tula, // Libra
  vrischika, // Scorpio
  dhanu, // Sagittarius
  makara, // Capricorn
  kumbha, // Aquarius
  meena, // Pisces
}

/// Planetary aspect types
enum AspectType {
  conjunction, // 0 degrees
  opposition, // 180 degrees
  trine, // 120 degrees
  square, // 90 degrees
  sextile, // 60 degrees
}

/// Planet position in chart
class PlanetPosition {
  final Planet planet;
  final double longitude; // 0-360 degrees
  final Rasi rasi;
  final double positionInRasi; // 0-30 degrees within rasi
  final House house;
  final bool isRetrograde;
  final double nakshatraLongitude; // For moon's nakshatra

  PlanetPosition({
    required this.planet,
    required this.longitude,
    required this.rasi,
    required this.positionInRasi,
    required this.house,
    this.isRetrograde = false,
    required this.nakshatraLongitude,
  });

  /// Get nakshatra index (0-26)
  int get nakshatraIndex {
    final index = (nakshatraLongitude / 13.333333).floor();
    return index % 27;
  }

  /// Get pada (1-4) within nakshatra
  int get pada {
    final positionInNakshatra = nakshatraLongitude % 13.333333;
    return ((positionInNakshatra / 3.333333).floor() + 1).clamp(1, 4);
  }
}

/// Planetary aspect
class PlanetaryAspect {
  final Planet fromPlanet;
  final Planet toPlanet;
  final AspectType type;
  final double orb; // Orb in degrees

  PlanetaryAspect({
    required this.fromPlanet,
    required this.toPlanet,
    required this.type,
    required this.orb,
  });
}

/// House cusp positions
class HouseCusp {
  final House house;
  final double longitude; // Ascendant for 1st house
  final Rasi rasi;

  HouseCusp({
    required this.house,
    required this.longitude,
    required this.rasi,
  });
}

/// Complete Birth Chart
class BirthChart {
  final DateTime birthDateTime;
  final double latitude;
  final double longitude;
  final String timezone;
  
  // Planetary positions
  final Map<Planet, PlanetPosition> planets;
  
  // House cusps
  final Map<House, HouseCusp> houseCusps;
  
  // Lagna (Ascendant)
  final Rasi lagna;
  final double lagnaLongitude;
  
  // Moon's nakshatra
  final String moonNakshatra;
  final int moonPada;
  
  // Planetary aspects
  final List<PlanetaryAspect> aspects;
  
  // Additional data
  final double ayanamsa; // Lahiri ayanamsa used
  final String lagnaLord; // Lord of ascendant

  BirthChart({
    required this.birthDateTime,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.planets,
    required this.houseCusps,
    required this.lagna,
    required this.lagnaLongitude,
    required this.moonNakshatra,
    required this.moonPada,
    required this.aspects,
    required this.ayanamsa,
    required this.lagnaLord,
  });

  /// Get planet in house
  PlanetPosition? getPlanetInHouse(House house) {
    for (final position in planets.values) {
      if (position.house == house) {
        return position;
      }
    }
    return null;
  }

  /// Get all planets in a house
  List<PlanetPosition> getPlanetsInHouse(House house) {
    return planets.values.where((p) => p.house == house).toList();
  }

  /// Get planet's house
  House? getPlanetHouse(Planet planet) {
    return planets[planet]?.house;
  }
}
