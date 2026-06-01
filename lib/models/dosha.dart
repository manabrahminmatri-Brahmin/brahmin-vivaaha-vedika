import 'birth_chart.dart';

/// Advanced Dosha Detection and Remedy Models

/// Dosha types
enum DoshaType {
  mangalDosha, // Mars Dosha (Kuja Dosha)
  nadiDosha, // Nadi Dosha
  bhakootDosha, // Bhakoot Dosha
  ganaDosha, // Gana Dosha
  rajyuDosha, // Rajju Dosha
  vedha, // Vedha (Obstruction)
  kujaDosha, // Mars Dosha (alternative name)
  sadeSati, // Saturn's 7.5 year period
  dhaiya, // 2.5 year period
  kantakaShani, // Saturn in 1st, 4th, 7th, 10th house
}

/// Dosha severity
enum DoshaSeverity {
  none,
  mild,
  moderate,
  severe,
  critical,
}

/// Dosha information
class DoshaInfo {
  final DoshaType type;
  final DoshaSeverity severity;
  final bool isPresent;
  final String description;
  final List<String> effects;
  final List<String> remedies;
  final bool canBeRemedied;
  final String? remedyMethod;
  final Map<String, dynamic>? additionalData;

  DoshaInfo({
    required this.type,
    required this.severity,
    required this.isPresent,
    required this.description,
    required this.effects,
    required this.remedies,
    this.canBeRemedied = true,
    this.remedyMethod,
    this.additionalData,
  });
}

/// Mangal Dosha specific information
class MangalDoshaInfo extends DoshaInfo {
  final PlanetPosition? marsPosition;
  final List<House> affectedHouses;
  final bool isCancelled; // Dosha cancellation
  final String? cancellationReason;

  MangalDoshaInfo({
    required super.type,
    required super.severity,
    required super.isPresent,
    required super.description,
    required super.effects,
    required super.remedies,
    super.canBeRemedied,
    super.remedyMethod,
    super.additionalData,
    this.marsPosition,
    required this.affectedHouses,
    this.isCancelled = false,
    this.cancellationReason,
  });
}

/// Complete Dosha Analysis
class DoshaAnalysis {
  final List<DoshaInfo> allDoshas;
  final List<DoshaInfo> presentDoshas;
  final int totalDoshaCount;
  final DoshaSeverity overallSeverity;
  final bool isMarriageRecommended;
  final String? recommendation;
  final List<String> generalRemedies;

  DoshaAnalysis({
    required this.allDoshas,
    required this.presentDoshas,
    required this.totalDoshaCount,
    required this.overallSeverity,
    required this.isMarriageRecommended,
    this.recommendation,
    required this.generalRemedies,
  });

  /// Get dosha by type
  DoshaInfo? getDosha(DoshaType type) {
    try {
      return allDoshas.firstWhere((d) => d.type == type);
    } catch (e) {
      return null;
    }
  }

  /// Check if specific dosha is present
  bool hasDosha(DoshaType type) {
    return getDosha(type)?.isPresent ?? false;
  }
}
