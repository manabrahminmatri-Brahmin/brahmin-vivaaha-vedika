/// Telugu Translations for Jatakam and Astrology Terms
class TeluguTranslations {
  // Jatakam Terms
  static const String jatakam = 'జాతకం';
  static const String comprehensiveJatakam = 'సమగ్ర జాతకం';
  static const String horoscope = 'హోరోస్కోప్';
  static const String birthChart = 'జనన చార్ట్';
  
  // Compatibility Terms
  static const String compatibility = 'అనుకూలత';
  static const String matching = 'సరిపోలిక';
  static const String ashtakoot = 'అష్టకూట';
  static const String ashtakootMatching = 'అష్టకూట సరిపోలిక';
  
  // Dosha Terms
  static const String dosha = 'దోషం';
  static const String doshas = 'దోషాలు';
  static const String mangalDosha = 'మంగళ దోషం';
  static const String nadiDosha = 'నాడి దోషం';
  static const String bhakootDosha = 'భకూట దోషం';
  static const String ganaDosha = 'గణ దోషం';
  static const String rajyuDosha = 'రజ్జు దోషం';
  static const String sadeSati = 'సాడె సాటి';
  static const String dhaiya = 'ధైయ';
  static const String kantakaShani = 'కంటక శని';
  
  // Dasha Terms
  static const String dasha = 'దశ';
  static const String mahadasha = 'మహా దశ';
  static const String antardasha = 'అంతర దశ';
  static const String pratyantardasha = 'ప్రత్యంతర దశ';
  static const String vimshottari = 'వింశోత్తరి';
  
  // Planetary Terms
  static const String planets = 'గ్రహాలు';
  static const String sun = 'సూర్యుడు';
  static const String moon = 'చంద్రుడు';
  static const String mars = 'అంగారకుడు';
  static const String mercury = 'బుధుడు';
  static const String jupiter = 'గురువు';
  static const String venus = 'శుక్రుడు';
  static const String saturn = 'శని';
  static const String rahu = 'రాహు';
  static const String ketu = 'కేతు';
  
  // House Terms
  static const String houses = 'భవనాలు';
  static const String lagna = 'లగ్నం';
  static const String ascendant = 'లగ్నం';
  
  // Nakshatra Terms
  static const String nakshatra = 'నక్షత్రం';
  static const String nakshatras = 'నక్షత్రాలు';
  static const String pada = 'పాదం';
  static const String rasi = 'రాశి';
  static const String star = 'నక్షత్రం';
  
  // Analysis Terms
  static const String analysis = 'విశ్లేషణ';
  static const String detailedAnalysis = 'వివరణాత్మక విశ్లేషణ';
  static const String overallScore = 'మొత్తం స్కోరు';
  static const String recommendation = 'సిఫార్సు';
  static const String strengths = 'బలాలు';
  static const String concerns = 'ఆందోళనలు';
  static const String remedies = 'పరిహారాలు';
  
  // Muhurta Terms
  static const String muhurta = 'ముహూర్తం';
  static const String auspicious = 'శుభకరమైన';
  static const String inauspicious = 'అశుభకరమైన';
  static const String auspiciousPeriods = 'శుభకరమైన కాలాలు';
  static const String inauspiciousPeriods = 'అశుభకరమైన కాలాలు';
  
  // Severity Terms
  static const String none = 'లేదు';
  static const String mild = 'తేలికపాటి';
  static const String moderate = 'మధ్యస్థ';
  static const String severe = 'తీవ్రమైన';
  static const String critical = 'క్లిష్టమైన';
  
  // Recommendation Terms
  static const String highlyRecommended = 'అత్యంత సిఫార్సు చేయబడింది';
  static const String recommended = 'సిఫార్సు చేయబడింది';
  static const String recommendedWithRemedies = 'పరిహారాలతో సిఫార్సు చేయబడింది';
  static const String caution = 'జాగ్రత్త';
  static const String notRecommended = 'సిఫార్సు చేయబడలేదు';
  
  // General Terms
  static const String viewInTelugu = 'తెలుగులో చూడండి';
  static const String viewInEnglish = 'English లో చూడండి';
  static const String placeOfBirth = 'జనన స్థలం';
  static const String important = 'ముఖ్యమైన';
  static const String note = 'గమనిక';
  static const String consultAstrologer = 'జ్యోతిష్యుడిని సంప్రదించండి';
  
  /// Get planet name in Telugu
  static String getPlanetName(String planetName) {
    switch (planetName.toLowerCase()) {
      case 'sun':
        return sun;
      case 'moon':
        return moon;
      case 'mars':
        return mars;
      case 'mercury':
        return mercury;
      case 'jupiter':
        return jupiter;
      case 'venus':
        return venus;
      case 'saturn':
        return saturn;
      case 'rahu':
        return rahu;
      case 'ketu':
        return ketu;
      default:
        return planetName;
    }
  }
  
  /// Get dosha name in Telugu
  static String getDoshaName(String doshaName) {
    switch (doshaName.toLowerCase()) {
      case 'mangal dosha':
      case 'mangaldosha':
        return mangalDosha;
      case 'nadi dosha':
      case 'nadidosha':
        return nadiDosha;
      case 'bhakoot dosha':
      case 'bhakootdosha':
        return bhakootDosha;
      case 'gana dosha':
      case 'ganadosha':
        return ganaDosha;
      case 'rajyu dosha':
      case 'rajyudosha':
        return rajyuDosha;
      case 'sade sati':
      case 'sadesati':
        return sadeSati;
      case 'dhaiya':
        return dhaiya;
      case 'kantaka shani':
      case 'kantakashani':
        return kantakaShani;
      default:
        return doshaName;
    }
  }
  
  /// Get severity in Telugu
  static String getSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'none':
        return none;
      case 'mild':
        return mild;
      case 'moderate':
        return moderate;
      case 'severe':
        return severe;
      case 'critical':
        return critical;
      default:
        return severity;
    }
  }
}
