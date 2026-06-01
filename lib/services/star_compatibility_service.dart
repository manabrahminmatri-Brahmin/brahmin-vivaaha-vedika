import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum CompatibilityLevel {
  excellent,
  good,
  average,
  belowAverage,
  notRecommended,
  unknown,
}

extension CompatibilityLevelExtension on CompatibilityLevel {
  String get emoji {
    switch (this) {
      case CompatibilityLevel.excellent:      return '🌟';
      case CompatibilityLevel.good:           return '✨';
      case CompatibilityLevel.average:        return '⭐';
      case CompatibilityLevel.belowAverage:   return '🌙';
      case CompatibilityLevel.notRecommended: return '❌';
      case CompatibilityLevel.unknown:        return '❓';
    }
  }

  String get displayName {
    switch (this) {
      case CompatibilityLevel.excellent:      return 'Excellent';
      case CompatibilityLevel.good:           return 'Good';
      case CompatibilityLevel.average:        return 'Average';
      case CompatibilityLevel.belowAverage:   return 'Below Average';
      case CompatibilityLevel.notRecommended: return 'Not Recommended';
      case CompatibilityLevel.unknown:        return 'Unknown';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KootaResult — one of the 8 kootas in an Ashtakoot calculation
// ─────────────────────────────────────────────────────────────────────────────

class KootaResult {
  final String name;
  final String teluguName;
  final int score;
  final int maxScore;
  final bool isMatched;
  final bool isPrimary;   // High-weight koota (Nadi, Bhakoot, Gana)
  final bool isCritical;  // Dosha-level (Nadi Dosha, Bhakoot Dosha)
  final String description;
  final String details;

  const KootaResult({
    required this.name,
    required this.teluguName,
    required this.score,
    required this.maxScore,
    required this.isMatched,
    required this.isPrimary,
    required this.isCritical,
    required this.description,
    required this.details,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AshtakootResult — full 8-fold compatibility result
// ─────────────────────────────────────────────────────────────────────────────

class AshtakootResult {
  final List<KootaResult> kootas;
  final CompatibilityLevel level;
  final double score;         // out of 36
  final String description;
  final String message;
  final bool hasNadiDosha;
  final bool success;

  AshtakootResult({
    required this.kootas,
    required this.level,
    required this.score,
    required this.description,
    required this.message,
    required this.hasNadiDosha,
    required this.success,
  });

  /// 0–100 percentage (limited to 2 decimal places)
  double get percentage => double.parse(((score / 36.0) * 100).toStringAsFixed(2));
  double get maxScore => 36.0;

  /// Legacy: raw data map for any code that still reads result.data
  Map<String, dynamic> get data => {
    'score': score,
    'maxScore': maxScore,
    'percentage': percentage,
    'level': level.displayName,
    'hasNadiDosha': hasNadiDosha,
    'calculated_at': DateTime.now().toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchingPreferences — which kootas to skip (user setting)
// ─────────────────────────────────────────────────────────────────────────────

class MatchingPreferences {
  bool skipVarna        = false;
  bool skipVashya       = false;
  bool skipTara         = false;
  bool skipYoni         = false;
  bool skipGrahaMaitri  = false;
  bool skipGana         = false;
  bool skipBhakoot      = false;
  bool skipNadi         = false;

  MatchingPreferences();

  Map<String, dynamic> toJson() => {
    'skipVarna': skipVarna, 'skipVashya': skipVashya,
    'skipTara': skipTara,   'skipYoni': skipYoni,
    'skipGrahaMaitri': skipGrahaMaitri, 'skipGana': skipGana,
    'skipBhakoot': skipBhakoot, 'skipNadi': skipNadi,
  };

  factory MatchingPreferences.fromJson(Map<String, dynamic> json) {
    final p = MatchingPreferences();
    p.skipVarna       = json['skipVarna']       ?? false;
    p.skipVashya      = json['skipVashya']      ?? false;
    p.skipTara        = json['skipTara']        ?? false;
    p.skipYoni        = json['skipYoni']        ?? false;
    p.skipGrahaMaitri = json['skipGrahaMaitri'] ?? false;
    p.skipGana        = json['skipGana']        ?? false;
    p.skipBhakoot     = json['skipBhakoot']     ?? false;
    p.skipNadi        = json['skipNadi']        ?? false;
    return p;
  }

  MatchingPreferences copyWith({
    bool? skipVarna, bool? skipVashya, bool? skipTara, bool? skipYoni,
    bool? skipGrahaMaitri, bool? skipGana, bool? skipBhakoot, bool? skipNadi,
  }) {
    final p = MatchingPreferences();
    p.skipVarna       = skipVarna       ?? this.skipVarna;
    p.skipVashya      = skipVashya      ?? this.skipVashya;
    p.skipTara        = skipTara        ?? this.skipTara;
    p.skipYoni        = skipYoni        ?? this.skipYoni;
    p.skipGrahaMaitri = skipGrahaMaitri ?? this.skipGrahaMaitri;
    p.skipGana        = skipGana        ?? this.skipGana;
    p.skipBhakoot     = skipBhakoot     ?? this.skipBhakoot;
    p.skipNadi        = skipNadi        ?? this.skipNadi;
    return p;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StarCompatibilityService
// ─────────────────────────────────────────────────────────────────────────────

class StarCompatibilityService {
  // ── 27 Nakshatras in order (index 0–26) ───────────────────────────────────
  static const List<String> _nakshatras = [
    'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
    'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni',
    'Uttara Phalguni', 'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha',
    'Jyeshtha', 'Mula', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana',
    'Dhanishta', 'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati',
  ];

  // ── Varna (1 point) ── 4 groups: Brahmin=3, Kshatriya=2, Vaishya=1, Shudra=0
  static const List<int> _varna = [
    3,2,1,3,3,0,3,3,0,3,1,1,1,0,0,1,3,0,0,1,1,3,0,0,3,3,3,
  ];

  // ── Vashya (2 points) ── 5 groups: 0=Manav,1=Vanchar,2=Chatushpad,3=Jalachara,4=Keet
  static const List<int> _vashya = [
    2,2,2,0,0,0,0,0,3,0,0,0,0,0,0,0,0,3,4,0,0,0,2,3,0,0,0,
  ];

  // ── Tara (3 points) ── just nakshatra index mod 9, check below ─────────────

  // ── Yoni (4 points) ── 13 animal pairs ─────────────────────────────────────
  // 0=Horse,1=Elephant,2=Sheep,3=Snake,4=Dog,5=Cat,6=Rat,7=Cow,8=Buffalo,
  // 9=Tiger,10=Hare,11=Monkey,12=Mongoose
  static const List<int> _yoni = [
    0,1,2,3,4,5,6,7,8,9,10,11,12,0,4,9,8,3,1,7,0,2,10,6,11,5,12,
  ];

  // ── Grah Maitri (5 points) ── ruling planet lord per nakshatra ────────────
  // 0=Ketu,1=Venus,2=Sun,3=Moon,4=Mars,5=Rahu,6=Jupiter,7=Saturn,8=Mercury
  static const List<int> _grahaLord = [
    0,1,2,3,4,5,6,7,8,0,1,2,3,4,5,6,7,8,0,1,2,3,4,5,6,7,8,
  ];

  // Planet friendship matrix [lord1][lord2] → 0/2/5 (enemy/neutral/friend)
  static const List<List<int>> _grahaFriendship = [
    //Ke Ve Su Mo Ma Ra Ju Sa Me
    [5, 0, 0, 0, 5, 5, 5, 5, 0], // Ketu
    [0, 5, 0, 2, 0, 2, 0, 2, 5], // Venus
    [0, 0, 5, 5, 5, 0, 5, 0, 0], // Sun
    [0, 5, 5, 5, 5, 0, 5, 0, 5], // Moon
    [5, 0, 5, 2, 5, 5, 5, 0, 0], // Mars
    [5, 2, 0, 0, 5, 5, 0, 5, 0], // Rahu
    [5, 0, 5, 5, 5, 0, 5, 0, 0], // Jupiter
    [5, 2, 0, 0, 0, 5, 0, 5, 5], // Saturn
    [0, 5, 0, 0, 0, 0, 0, 5, 5], // Mercury
  ];

  // ── Gana (6 points) ── 0=Deva,1=Manushya,2=Rakshasa ──────────────────────
  static const List<int> _gana = [
    0,2,0,0,1,2,0,0,2,2,1,0,0,2,0,1,0,2,2,1,0,0,2,2,2,0,0,
  ];

  // ── Bhakoot (7 points) ── rasi (sign) per nakshatra ──────────────────────
  // 0=Aries,1=Taurus,2=Gemini,3=Cancer,4=Leo,5=Virgo,
  // 6=Libra,7=Scorpio,8=Sagittarius,9=Capricorn,10=Aquarius,11=Pisces
  static const List<int> _rasi = [
    0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,6,7,7,8,8,9,9,10,10,11,11,11,
  ];

  // ── Nadi (8 points) ── 0=Aadi,1=Madhya,2=Antya ───────────────────────────
  static const List<int> _nadi = [
    0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,
  ];

  /// Public accessor for Nadi values by nakshatra index (0=Aadi, 1=Madhya, 2=Antya)
  static List<int> get nakshatraNadi => _nadi;

  // ── Lookup nakshatra index (case-insensitive, partial match) ──────────────
  static int _nakIdx(String? name) {
    if (name == null || name.isEmpty) return -1;
    final n = name.toLowerCase().trim();
    for (int i = 0; i < _nakshatras.length; i++) {
      if (_nakshatras[i].toLowerCase().startsWith(n) ||
          n.startsWith(_nakshatras[i].toLowerCase())) {
        return i;
      }
    }
    // Partial contains match
    for (int i = 0; i < _nakshatras.length; i++) {
      if (_nakshatras[i].toLowerCase().contains(n) ||
          n.contains(_nakshatras[i].toLowerCase())) {
        return i;
      }
    }
    return -1;
  }

  // ── 1. Varna (max 1 pt) ───────────────────────────────────────────────────
  static KootaResult _calcVarna(int b, int g) {
    // Boy varna >= girl varna for match (or equal)
    final bv = b >= 0 ? _varna[b] : 2;
    final gv = g >= 0 ? _varna[g] : 2;
    final matched = bv >= gv;
    return KootaResult(
      name: 'Varna', teluguName: 'వర్ణ',
      score: matched ? 1 : 0, maxScore: 1,
      isMatched: matched, isPrimary: false, isCritical: false,
      description: 'Social order & spiritual compatibility',
      details: matched
          ? 'Good social compatibility between the couple.'
          : 'The social orders differ — consider matching carefully.',
    );
  }

  // ── 2. Vashya (max 2 pts) ─────────────────────────────────────────────────
  static KootaResult _calcVashya(int b, int g) {
    final bv = b >= 0 ? _vashya[b] : 0;
    final gv = g >= 0 ? _vashya[g] : 0;
    final score = (bv == gv) ? 2 : 1;
    return KootaResult(
      name: 'Vashya', teluguName: 'వశ్య',
      score: score, maxScore: 2,
      isMatched: score >= 1, isPrimary: false, isCritical: false,
      description: 'Mutual attraction & control',
      details: score == 2
          ? 'Strong mutual attraction between the couple.'
          : 'Moderate mutual attraction. Some adjustment may be needed.',
    );
  }

  // ── 3. Tara (max 3 pts) ───────────────────────────────────────────────────
  static KootaResult _calcTara(int b, int g) {
    // Tara = (girl_index - boy_index + 27) % 27, then /3 → if result in {1,3,5,7} = good
    if (b < 0 || g < 0) {
      return KootaResult(
        name: 'Tara', teluguName: 'తార',
        score: 1, maxScore: 3, isMatched: true,
        isPrimary: false, isCritical: false,
        description: 'Birth star compatibility & health',
        details: 'Nakshatra not set — using neutral score.',
      );
    }
    final diff = (g - b + 27) % 27;
    final taraNum = (diff ~/ 3) + 1; // 1–9
    final auspicious = [1, 3, 5, 7].contains(taraNum);
    final score = auspicious ? 3 : 0;
    return KootaResult(
      name: 'Tara', teluguName: 'తార',
      score: score, maxScore: 3,
      isMatched: auspicious, isPrimary: false, isCritical: false,
      description: 'Birth star compatibility & health',
      details: auspicious
          ? 'Auspicious Tara — good health and fortune for the couple.'
          : 'Inauspicious Tara. Remedial measures may be advisable.',
    );
  }

  // ── 4. Yoni (max 4 pts) ───────────────────────────────────────────────────
  static KootaResult _calcYoni(int b, int g) {
    final by = b >= 0 ? _yoni[b] : 6;
    final gy = g >= 0 ? _yoni[g] : 6;
    int score;
    if (by == gy) {
      score = 4; // same animal — best
    } else if ((by - gy).abs() <= 3) {
      score = 2; // friendly animal
    } else {
      score = 0;
    }
    return KootaResult(
      name: 'Yoni', teluguName: 'యోని',
      score: score, maxScore: 4,
      isMatched: score >= 2, isPrimary: false, isCritical: false,
      description: 'Physical intimacy & sexual compatibility',
      details: score == 4
          ? 'Excellent physical compatibility — same animal group.'
          : score == 2
              ? 'Good physical compatibility — friendly animal groups.'
              : 'Different animal groups may indicate physical incompatibility.',
    );
  }

  // ── 5. Grah Maitri (max 5 pts) ───────────────────────────────────────────
  static KootaResult _calcGrahaMaitri(int b, int g) {
    final bl = b >= 0 ? _grahaLord[b] : 6;
    final gl = g >= 0 ? _grahaLord[g] : 6;
    final friendship = _grahaFriendship[bl][gl];
    final score = friendship; // 0, 2, or 5
    return KootaResult(
      name: 'Grah Maitri', teluguName: 'గ్రహ మైత్రి',
      score: score, maxScore: 5,
      isMatched: score >= 2, isPrimary: false, isCritical: false,
      description: 'Mental compatibility & friendship',
      details: score == 5
          ? 'Ruling planets are friends — excellent mental bond.'
          : score == 2
              ? 'Ruling planets are neutral — good friendship possible.'
              : 'Ruling planets are enemies — mental clashes may occur.',
    );
  }

  // ── 6. Gana (max 6 pts) ───────────────────────────────────────────────────
  static KootaResult _calcGana(int b, int g) {
    final bg = b >= 0 ? _gana[b] : 0;
    final gg = g >= 0 ? _gana[g] : 0;
    int score;
    String details;
    if (bg == gg) {
      score = 6;
      details = 'Same Gana — excellent temperament match.';
    } else if ((bg == 0 && gg == 1) || (bg == 1 && gg == 0)) {
      score = 5;
      details = 'Deva–Manushya combination — compatible temperaments.';
    } else if ((bg == 0 && gg == 2) || (bg == 2 && gg == 0)) {
      score = 1;
      details = 'Deva–Rakshasa combination — significant temperament difference.';
    } else {
      // Manushya–Rakshasa
      score = 0;
      details = 'Manushya–Rakshasa combination — different temperaments, needs effort.';
    }
    return KootaResult(
      name: 'Gana', teluguName: 'గణ',
      score: score, maxScore: 6,
      isMatched: score >= 5, isPrimary: true, isCritical: false,
      description: 'Temperament & nature compatibility',
      details: details,
    );
  }

  // ── 7. Bhakoot (max 7 pts) ────────────────────────────────────────────────
  static KootaResult _calcBhakoot(int b, int g) {
    final br = b >= 0 ? _rasi[b] : 0;
    final gr = g >= 0 ? _rasi[g] : 0;
    // Inauspicious combinations: 6-8, 5-9, 12-2
    final diff1 = (gr - br + 12) % 12 + 1;
    final diff2 = (br - gr + 12) % 12 + 1;
    final inauspicious = (diff1 == 6 && diff2 == 8) ||
        (diff1 == 8 && diff2 == 6) ||
        (diff1 == 5 && diff2 == 9) ||
        (diff1 == 9 && diff2 == 5) ||
        (diff1 == 12 && diff2 == 2) ||
        (diff1 == 2 && diff2 == 12);
    final score = inauspicious ? 0 : 7;
    return KootaResult(
      name: 'Bhakoot', teluguName: 'భకూట',
      score: score, maxScore: 7,
      isMatched: !inauspicious, isPrimary: true,
      isCritical: inauspicious, // Bhakoot Dosha when inauspicious
      description: 'Love, prosperity & well-being',
      details: inauspicious
          ? 'Bhakoot Dosha present — inauspicious Rasi combination. Consultation with a Jyotishi recommended.'
          : 'Auspicious Bhakoot — good for love, prosperity and family life.',
    );
  }

  // ── 8. Nadi (max 8 pts) ───────────────────────────────────────────────────
  static KootaResult _calcNadi(int b, int g) {
    final bn = b >= 0 ? _nadi[b] : 0;
    final gn = g >= 0 ? _nadi[g] : 1;
    final nadiDosha = bn == gn; // same nadi = Nadi Dosha
    final score = nadiDosha ? 0 : 8;
    return KootaResult(
      name: 'Nadi', teluguName: 'నాడి',
      score: score, maxScore: 8,
      isMatched: !nadiDosha, isPrimary: true,
      isCritical: nadiDosha, // Nadi Dosha is the most serious
      description: 'Health, genes & progeny',
      details: nadiDosha
          ? 'Nadi Dosha — same Nadi detected. Health and progeny concerns; remedial puja strongly advised.'
          : 'Different Nadi — excellent for health, progeny and longevity of the marriage.',
    );
  }

  // ── Main calculation entry point ──────────────────────────────────────────

  /// Calculate full 8-koota Ashtakoot matching.
  ///
  /// Pass [user1] and [user2] maps with at minimum a 'nakshatra' key.
  /// The 'nakshatra' is matched case-insensitively against the 27 Nakshatra list.
  static AshtakootResult calculateAshtakoot(
    Map<String, dynamic> user1,
    Map<String, dynamic> user2,
  ) {
    try {
      // Resolve nakshatra indices
      // user1 = groom/boy side, user2 = bride/girl side (or either — scoring is symmetric except Varna)
      final n1 = _nakIdx(user1['nakshatra'] as String?);
      final n2 = _nakIdx(user2['nakshatra'] as String?);

      // Calculate all 8 kootas
      final kootas = <KootaResult>[
        _calcVarna(n1, n2),
        _calcVashya(n1, n2),
        _calcTara(n1, n2),
        _calcYoni(n1, n2),
        _calcGrahaMaitri(n1, n2),
        _calcGana(n1, n2),
        _calcBhakoot(n1, n2),
        _calcNadi(n1, n2),
      ];

      final totalScore = kootas.fold<int>(0, (sum, k) => sum + k.score).toDouble();
      final nadiDosha  = kootas.last.isCritical;
      final bhakootDosha = kootas[6].isCritical;

      // Level thresholds (traditional: 18+/36 = good)
      CompatibilityLevel level;
      if (totalScore >= 32) {
        level = CompatibilityLevel.excellent;
      } else if (totalScore >= 25) {
        level = CompatibilityLevel.good;
      } else if (totalScore >= 18) {
        level = CompatibilityLevel.average;
      } else if (totalScore >= 12) {
        level = CompatibilityLevel.belowAverage;
      } else {
        level = CompatibilityLevel.notRecommended;
      }

      String message;
      if (nadiDosha && bhakootDosha) {
        message = 'Nadi Dosha and Bhakoot Dosha both present. Consultation with a Jyotishi is strongly recommended before proceeding.';
      } else if (nadiDosha) {
        message = 'Nadi Dosha present. Remedial puja is strongly recommended. Overall score of ${totalScore.round()}/36.';
      } else if (bhakootDosha) {
        message = 'Bhakoot Dosha present. Remedial measures are advisable. Overall score of ${totalScore.round()}/36.';
      } else if (level == CompatibilityLevel.excellent) {
        message = 'Exceptional compatibility! A very auspicious match with a score of ${totalScore.round()}/36.';
      } else if (level == CompatibilityLevel.good) {
        message = 'Good compatibility with a score of ${totalScore.round()}/36. A promising match.';
      } else if (level == CompatibilityLevel.average) {
        message = 'Average compatibility with a score of ${totalScore.round()}/36. Matches above 18/36 are generally considered acceptable.';
      } else {
        message = 'Score of ${totalScore.round()}/36 is below the recommended 18 points. Consultation with a Jyotishi is advised.';
      }

      return AshtakootResult(
        kootas: kootas,
        level: level,
        score: totalScore,
        description: _getDescription(totalScore),
        message: message,
        hasNadiDosha: nadiDosha,
        success: true,
      );
    } catch (e) {
      debugPrint('❌ Ashtakoot calculation error: $e');
      return AshtakootResult(
        kootas: [],
        level: CompatibilityLevel.unknown,
        score: 0.0,
        description: 'Calculation failed',
        message: 'Could not calculate compatibility. Please ensure both profiles have a Nakshatra set.',
        hasNadiDosha: false,
        success: false,
      );
    }
  }

  static String _getDescription(double score) {
    if (score >= 32) return 'Excellent compatibility!';
    if (score >= 25) return 'Good compatibility';
    if (score >= 18) return 'Average compatibility — acceptable match';
    if (score >= 12) return 'Below average — caution advised';
    return 'Low compatibility — not recommended without remedies';
  }

  // ── Legacy instance methods (kept for backward compatibility) ─────────────

  Future<Map<String, dynamic>> calculateStarCompatibility(
    String userId1, String userId2,
  ) async {
    try {
      if (userId1.isEmpty || userId2.isEmpty) {
        return {'success': false, 'score': 0.0, 'stars': 0, 'error': 'Invalid user IDs'};
      }
      // Without nakshatra data we can only return unknown
      return {
        'success': true,
        'score': 0.0,
        'stars': 0,
        'description': 'Use calculateAshtakoot() with nakshatra data for accurate results.',
        'error': null,
      };
    } catch (e) {
      return {'success': false, 'score': 0.0, 'stars': 0, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getCompatibilityDetails(
    String userId1, String userId2,
  ) async {
    final c = await calculateStarCompatibility(userId1, userId2);
    if (c['success'] != true) return {'success': false, 'details': {}};
    return {
      'success': true,
      'details': {
        'overall_score': c['score'],
        'stars': c['stars'],
        'description': c['description'],
        'calculated_at': DateTime.now().toIso8601String(),
      }
    };
  }

  Future<List<Map<String, dynamic>>> getCompatibilityMultiple(
    String userId, List<String> otherUserIds,
  ) async {
    if (userId.isEmpty || otherUserIds.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    for (final oid in otherUserIds) {
      final c = await calculateStarCompatibility(userId, oid);
      if (c['success'] == true) {
        results.add({'user_id': oid, 'compatibility': c['score'], 'stars': c['stars']});
      }
    }
    return results;
  }

  Future<bool> validateCompatibilityData(Map<String, dynamic> data) async {
    final u1 = data['user_id1'] as String?;
    final u2 = data['user_id2'] as String?;
    return u1 != null && u1.isNotEmpty && u2 != null && u2.isNotEmpty;
  }
}
