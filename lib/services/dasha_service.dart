import '../models/birth_chart.dart';
import '../models/dasha.dart';

/// Dasha Calculation Service
/// Implements Vimshottari and other Dasha systems
class DashaService {
  /// Vimshottari Dasha periods in years
  static const Map<Planet, double> vimshottariPeriods = {
    Planet.sun: 6,
    Planet.moon: 10,
    Planet.mars: 7,
    Planet.rahu: 18,
    Planet.jupiter: 16,
    Planet.saturn: 19,
    Planet.mercury: 17,
    Planet.ketu: 7,
    Planet.venus: 20,
  };

  /// Order of planets in Vimshottari Dasha
  static const List<Planet> vimshottariOrder = [
    Planet.sun,
    Planet.moon,
    Planet.mars,
    Planet.rahu,
    Planet.jupiter,
    Planet.saturn,
    Planet.mercury,
    Planet.ketu,
    Planet.venus,
  ];

  /// Calculate Vimshottari Dasha from birth chart
  static DashaInfo calculateVimshottariDasha({
    required BirthChart birthChart,
    DateTime? currentDate,
  }) {
    currentDate ??= DateTime.now();
    
    // Get moon's nakshatra
    final moonPos = birthChart.planets[Planet.moon]!;
    final nakshatraIndex = moonPos.nakshatraIndex;
    
    // Determine starting planet based on nakshatra
    // Each nakshatra is ruled by a planet in Vimshottari
    final startingPlanet = _getNakshatraLord(nakshatraIndex);
    
    // Calculate elapsed time since birth
    final elapsedYears = currentDate.difference(birthChart.birthDateTime).inDays / 365.25;
    
    // Calculate which Mahadasha we're in
    final mahadashaInfo = _calculateCurrentMahadasha(
      startingPlanet,
      elapsedYears,
      birthChart.birthDateTime,
    );
    
    // Calculate Antardasha
    final antardasha = _calculateCurrentAntardasha(
      mahadashaInfo['planet'] as Planet,
      mahadashaInfo['startDate'] as DateTime,
      mahadashaInfo['elapsedInMahadasha'] as double,
    );
    
    // Calculate upcoming Mahadashas
    final upcomingMahadashas = _calculateUpcomingMahadashas(
      startingPlanet,
      elapsedYears,
      birthChart.birthDateTime,
    );
    
    // Calculate upcoming Antardashas
    final upcomingAntardashas = _calculateUpcomingAntardashas(
      mahadashaInfo['planet'] as Planet,
      mahadashaInfo['startDate'] as DateTime,
      mahadashaInfo['elapsedInMahadasha'] as double,
    );
    
    return DashaInfo(
      type: DashaType.vimshottari,
      currentMahadasha: mahadashaInfo['dasha'] as DashaPeriod,
      currentAntardasha: antardasha,
      upcomingMahadashas: upcomingMahadashas,
      upcomingAntardashas: upcomingAntardashas,
    );
  }

  /// Get Nakshatra Lord for Vimshottari
  static Planet _getNakshatraLord(int nakshatraIndex) {
    // Each group of 3 nakshatras is ruled by a planet
    // Sun: 0-2, Moon: 3-5, Mars: 6-8, Rahu: 9-11, Jupiter: 12-14,
    // Saturn: 15-17, Mercury: 18-20, Ketu: 21-23, Venus: 24-26
    final group = nakshatraIndex ~/ 3;
    final planetIndex = group % 9;
    return vimshottariOrder[planetIndex];
  }

  /// Calculate current Mahadasha
  static Map<String, dynamic> _calculateCurrentMahadasha(
    Planet startingPlanet,
    double elapsedYears,
    DateTime birthDate,
  ) {
    double cumulativeYears = 0;
    Planet currentPlanet = startingPlanet;
    int planetIndex = vimshottariOrder.indexOf(startingPlanet);
    DateTime currentStartDate = birthDate;
    
    // Find which Mahadasha we're in
    while (cumulativeYears + vimshottariPeriods[currentPlanet]! < elapsedYears) {
      cumulativeYears += vimshottariPeriods[currentPlanet]!;
      planetIndex = (planetIndex + 1) % 9;
      currentPlanet = vimshottariOrder[planetIndex];
      currentStartDate = currentStartDate.add(
        Duration(days: (vimshottariPeriods[vimshottariOrder[(planetIndex - 1) % 9]]! * 365.25).round()),
      );
    }
    
    final mahadashaDuration = vimshottariPeriods[currentPlanet]!;
    final elapsedInMahadasha = elapsedYears - cumulativeYears;
    final mahadashaStart = currentStartDate;
    final mahadashaEnd = mahadashaStart.add(
      Duration(days: (mahadashaDuration * 365.25).round()),
    );
    
    final dasha = DashaPeriod(
      planet: currentPlanet,
      startDate: mahadashaStart,
      endDate: mahadashaEnd,
      durationYears: mahadashaDuration,
      name: '${_getPlanetName(currentPlanet)} Mahadasha',
      type: DashaType.vimshottari,
    );
    
    return {
      'dasha': dasha,
      'planet': currentPlanet,
      'startDate': mahadashaStart,
      'elapsedInMahadasha': elapsedInMahadasha,
    };
  }

  /// Calculate current Antardasha
  static AntardashaPeriod? _calculateCurrentAntardasha(
    Planet mahadashaPlanet,
    DateTime mahadashaStart,
    double elapsedInMahadasha,
  ) {
    final mahadashaDuration = vimshottariPeriods[mahadashaPlanet]!;
    final mahadashaIndex = vimshottariOrder.indexOf(mahadashaPlanet);
    
    double cumulativeYears = 0;
    Planet currentAntardashaPlanet = mahadashaPlanet;
    int antardashaIndex = mahadashaIndex;
    DateTime antardashaStart = mahadashaStart;
    
    // Find which Antardasha we're in
    while (cumulativeYears < elapsedInMahadasha) {
      final antardashaDuration = (vimshottariPeriods[currentAntardashaPlanet]! * 
          mahadashaDuration) / 120.0;
      
      if (cumulativeYears + antardashaDuration > elapsedInMahadasha) {
        break;
      }
      
      cumulativeYears += antardashaDuration;
      antardashaIndex = (antardashaIndex + 1) % 9;
      currentAntardashaPlanet = vimshottariOrder[antardashaIndex];
      antardashaStart = antardashaStart.add(
        Duration(days: (antardashaDuration * 365.25).round()),
      );
    }
    
    final antardashaDuration = (vimshottariPeriods[currentAntardashaPlanet]! * 
        mahadashaDuration) / 120.0;
    final antardashaEnd = antardashaStart.add(
      Duration(days: (antardashaDuration * 365.25).round()),
    );
    
    return AntardashaPeriod(
      mahadashaPlanet: mahadashaPlanet,
      antardashaPlanet: currentAntardashaPlanet,
      startDate: antardashaStart,
      endDate: antardashaEnd,
      durationYears: antardashaDuration,
      name: '${_getPlanetName(mahadashaPlanet)} Mahadasha - ${_getPlanetName(currentAntardashaPlanet)} Antardasha',
    );
  }

  /// Calculate upcoming Mahadashas
  static List<DashaPeriod> _calculateUpcomingMahadashas(
    Planet startingPlanet,
    double elapsedYears,
    DateTime birthDate,
  ) {
    final upcoming = <DashaPeriod>[];
    final currentInfo = _calculateCurrentMahadasha(startingPlanet, elapsedYears, birthDate);
    final currentPlanet = currentInfo['planet'] as Planet;
    int planetIndex = vimshottariOrder.indexOf(currentPlanet);
    
    // Get next 3 Mahadashas
    for (int i = 0; i < 3; i++) {
      planetIndex = (planetIndex + 1) % 9;
      final planet = vimshottariOrder[planetIndex];
      final duration = vimshottariPeriods[planet]!;
      final startDate = i == 0 
          ? (currentInfo['dasha'] as DashaPeriod).endDate
          : upcoming.last.endDate;
      final endDate = startDate.add(
        Duration(days: (duration * 365.25).round()),
      );
      
      upcoming.add(DashaPeriod(
        planet: planet,
        startDate: startDate,
        endDate: endDate,
        durationYears: duration,
        name: '${_getPlanetName(planet)} Mahadasha',
        type: DashaType.vimshottari,
      ));
    }
    
    return upcoming;
  }

  /// Calculate upcoming Antardashas
  static List<AntardashaPeriod> _calculateUpcomingAntardashas(
    Planet mahadashaPlanet,
    DateTime mahadashaStart,
    double elapsedInMahadasha,
  ) {
    final upcoming = <AntardashaPeriod>[];
    final mahadashaDuration = vimshottariPeriods[mahadashaPlanet]!;
    
    final currentAntardasha = _calculateCurrentAntardasha(
      mahadashaPlanet,
      mahadashaStart,
      elapsedInMahadasha,
    );
    
    if (currentAntardasha == null) return upcoming;
    
    int antardashaIndex = vimshottariOrder.indexOf(currentAntardasha.antardashaPlanet);
    DateTime nextStart = currentAntardasha.endDate;
    
    // Get next 3 Antardashas
    for (int i = 0; i < 3; i++) {
      antardashaIndex = (antardashaIndex + 1) % 9;
      final planet = vimshottariOrder[antardashaIndex];
      final duration = (vimshottariPeriods[planet]! * mahadashaDuration) / 120.0;
      final endDate = nextStart.add(
        Duration(days: (duration * 365.25).round()),
      );
      
      upcoming.add(AntardashaPeriod(
        mahadashaPlanet: mahadashaPlanet,
        antardashaPlanet: planet,
        startDate: nextStart,
        endDate: endDate,
        durationYears: duration,
        name: '${_getPlanetName(mahadashaPlanet)} Mahadasha - ${_getPlanetName(planet)} Antardasha',
      ));
      
      nextStart = endDate;
    }
    
    return upcoming;
  }

  /// Get planet name
  static String _getPlanetName(Planet planet) {
    switch (planet) {
      case Planet.sun:
        return 'Sun';
      case Planet.moon:
        return 'Moon';
      case Planet.mars:
        return 'Mars';
      case Planet.mercury:
        return 'Mercury';
      case Planet.jupiter:
        return 'Jupiter';
      case Planet.venus:
        return 'Venus';
      case Planet.saturn:
        return 'Saturn';
      case Planet.rahu:
        return 'Rahu';
      case Planet.ketu:
        return 'Ketu';
    }
  }
}
