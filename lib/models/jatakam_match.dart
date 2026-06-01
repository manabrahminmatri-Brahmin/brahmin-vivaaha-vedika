/// Comprehensive Jatakam (Horoscope) Matching Result

library;

import 'birth_chart.dart';
import 'dasha.dart';
import 'dosha.dart';
import '../services/star_compatibility_service.dart' show AshtakootResult;

/// Comprehensive matching result combining all factors
class JatakamMatchResult {
  // Basic compatibility
  final AshtakootResult ashtakoot;
  
  // Birth charts
  final BirthChart maleChart;
  final BirthChart femaleChart;
  
  // Dasha analysis
  final DashaInfo maleDasha;
  final DashaInfo femaleDasha;
  final DashaCompatibility dashaCompatibility;
  
  // Dosha analysis
  final DoshaAnalysis maleDoshas;
  final DoshaAnalysis femaleDoshas;
  final CombinedDoshaAnalysis combinedDoshas;
  
  // Planetary compatibility
  final PlanetaryCompatibility planetaryCompatibility;
  
  // House compatibility
  final HouseCompatibility houseCompatibility;
  
  // Overall score and recommendation
  final double overallScore; // 0-100
  final MatchRecommendation recommendation;
  final String detailedAnalysis;
  final List<String> strengths;
  final List<String> concerns;
  final List<String> remedies;
  
  // Muhurta (Auspicious timing)
  final List<MuhurtaPeriod> auspiciousPeriods;
  final List<MuhurtaPeriod> inauspiciousPeriods;

  JatakamMatchResult({
    required this.ashtakoot,
    required this.maleChart,
    required this.femaleChart,
    required this.maleDasha,
    required this.femaleDasha,
    required this.dashaCompatibility,
    required this.maleDoshas,
    required this.femaleDoshas,
    required this.combinedDoshas,
    required this.planetaryCompatibility,
    required this.houseCompatibility,
    required this.overallScore,
    required this.recommendation,
    required this.detailedAnalysis,
    required this.strengths,
    required this.concerns,
    required this.remedies,
    required this.auspiciousPeriods,
    required this.inauspiciousPeriods,
  });
}

/// Dasha compatibility between two charts
class DashaCompatibility {
  final bool isCompatible;
  final String analysis;
  final List<String> favorablePeriods;
  final List<String> challengingPeriods;
  final double compatibilityScore; // 0-100

  DashaCompatibility({
    required this.isCompatible,
    required this.analysis,
    required this.favorablePeriods,
    required this.challengingPeriods,
    required this.compatibilityScore,
  });
}

/// Combined dosha analysis for both partners
class CombinedDoshaAnalysis {
  final bool isCompatible;
  final List<DoshaInfo> mutualDoshas;
  final List<DoshaInfo> individualDoshas;
  final String analysis;
  final List<String> combinedRemedies;
  final double compatibilityScore; // 0-100

  CombinedDoshaAnalysis({
    required this.isCompatible,
    required this.mutualDoshas,
    required this.individualDoshas,
    required this.analysis,
    required this.combinedRemedies,
    required this.compatibilityScore,
  });
}

/// Planetary compatibility analysis
class PlanetaryCompatibility {
  final Map<Planet, double> planetScores; // Individual planet compatibility
  final double overallScore; // 0-100
  final String analysis;
  final List<PlanetaryAspect> beneficialAspects;
  final List<PlanetaryAspect> challengingAspects;

  PlanetaryCompatibility({
    required this.planetScores,
    required this.overallScore,
    required this.analysis,
    required this.beneficialAspects,
    required this.challengingAspects,
  });
}

/// House compatibility analysis
class HouseCompatibility {
  final Map<House, double> houseScores; // Individual house compatibility
  final double overallScore; // 0-100
  final String analysis;
  final List<House> strongHouses;
  final List<House> weakHouses;

  HouseCompatibility({
    required this.houseScores,
    required this.overallScore,
    required this.analysis,
    required this.strongHouses,
    required this.weakHouses,
  });
}

/// Match recommendation
enum MatchRecommendation {
  highlyRecommended,
  recommended,
  recommendedWithRemedies,
  caution,
  notRecommended,
}

/// Muhurta (Auspicious timing) period
class MuhurtaPeriod {
  final DateTime startDate;
  final DateTime endDate;
  final String name;
  final String description;
  final bool isAuspicious;
  final double auspiciousnessScore; // 0-100

  MuhurtaPeriod({
    required this.startDate,
    required this.endDate,
    required this.name,
    required this.description,
    required this.isAuspicious,
    required this.auspiciousnessScore,
  });
}
