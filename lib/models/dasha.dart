import 'birth_chart.dart';

/// Dasha (Planetary Periods) Models for Vimshottari and other systems

/// Dasha type
enum DashaType {
  vimshottari, // 120 years cycle (most common)
  ashtottari, // 108 years cycle
  yogini, // 36 years cycle
  chaturthimshat, // 34 years cycle
}

/// Dasha period information
class DashaPeriod {
  final Planet planet;
  final DateTime startDate;
  final DateTime endDate;
  final double durationYears;
  final String name; // e.g., "Sun Mahadasha"
  final DashaType type;

  DashaPeriod({
    required this.planet,
    required this.startDate,
    required this.endDate,
    required this.durationYears,
    required this.name,
    required this.type,
  });

  /// Check if a date falls within this period
  bool contains(DateTime date) {
    return date.isAfter(startDate) && date.isBefore(endDate) ||
        date.isAtSameMomentAs(startDate) ||
        date.isAtSameMomentAs(endDate);
  }

  /// Get remaining years
  double getRemainingYears(DateTime currentDate) {
    if (currentDate.isAfter(endDate)) return 0;
    if (currentDate.isBefore(startDate)) return durationYears;
    final remaining = endDate.difference(currentDate).inDays / 365.25;
    return remaining.clamp(0, durationYears);
  }
}

/// Antardasha (Sub-period) within a Mahadasha
class AntardashaPeriod {
  final Planet mahadashaPlanet;
  final Planet antardashaPlanet;
  final DateTime startDate;
  final DateTime endDate;
  final double durationYears;
  final String name; // e.g., "Sun Mahadasha - Moon Antardasha"

  AntardashaPeriod({
    required this.mahadashaPlanet,
    required this.antardashaPlanet,
    required this.startDate,
    required this.endDate,
    required this.durationYears,
    required this.name,
  });
}

/// Pratyantardasha (Sub-sub-period) within Antardasha
class PratyantardashaPeriod {
  final Planet mahadashaPlanet;
  final Planet antardashaPlanet;
  final Planet pratyantardashaPlanet;
  final DateTime startDate;
  final DateTime endDate;
  final double durationYears;
  final String name;

  PratyantardashaPeriod({
    required this.mahadashaPlanet,
    required this.antardashaPlanet,
    required this.pratyantardashaPlanet,
    required this.startDate,
    required this.endDate,
    required this.durationYears,
    required this.name,
  });
}

/// Complete Dasha information
class DashaInfo {
  final DashaType type;
  final DashaPeriod currentMahadasha;
  final AntardashaPeriod? currentAntardasha;
  final PratyantardashaPeriod? currentPratyantardasha;
  final List<DashaPeriod> upcomingMahadashas;
  final List<AntardashaPeriod> upcomingAntardashas;

  DashaInfo({
    required this.type,
    required this.currentMahadasha,
    this.currentAntardasha,
    this.currentPratyantardasha,
    required this.upcomingMahadashas,
    required this.upcomingAntardashas,
  });

  /// Get all dasha periods in order
  List<DashaPeriod> getAllMahadashas() {
    return [currentMahadasha, ...upcomingMahadashas];
  }
}
