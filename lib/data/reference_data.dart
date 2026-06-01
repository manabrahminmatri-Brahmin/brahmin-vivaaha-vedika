// Comprehensive reference data for Andhra Brahmin Vivaaha Vedika
// Includes all traditional and modern fields for profile matching

class ReferenceData {
  // ============ PROFILE CREATION INFO ============

  /// Who is creating this profile
  static const List<String> profileCreatedByOptions = [
    'Self',
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Uncle (Maternal)',
    'Uncle (Paternal)',
    'Aunt (Maternal)',
    'Aunt (Paternal)',
    'Grandfather',
    'Grandmother',
    'Guardian',
    'Friend',
    'Relative',
    'Marriage Bureau',
    'Other',
  ];

  // ============ ANDHRA BRAHMIN SPECIFIC DATA ============
  //
  // DATA MODEL (5 independent fields — store separately, never concatenate):
  //
  //   caste            : "Brahmin"  (fixed for this app)
  //   brahminSubCaste  : Niyogi | Vaidiki | Dravida
  //   brahminBranch    : branch within that sub-caste (see brahminBranches)
  //   brahminRegion    : geographic regional tradition (see brahminRegions)
  //   sect             : philosophical/ritual school (see sects)
  //   vedicAffiliation : Vedic shakha affiliation (see vedicAffiliations)
  //
  // ❌ DO NOT store compound strings like "Vaidiki Velanadu" or
  //    "Niyogi Telaganya" as a single value — use separate fields.
  // ❌ Region, branch and sub-caste are NOT sects — keep them separate.
  //
  // DISPLAY RULE: Show brahminBranch only when subCaste == 'Niyogi' or 'Dravida'.
  // Vaidiki has no branch classification — only region.

  /// Top-level Brahmin sub-castes for Telugu / Andhra / Telangana Brahmins.
  static const List<String> brahminSubCastes = [
    'Niyogi',   // Administrative / secular class
    'Vaidiki',  // Ritual / priestly class (also spelled Vaidika)
    'Dravida',  // South-migrated Tamil-lineage Brahmins
  ];

  /// Branches within each sub-caste.
  /// Vaidiki has no branch — skip this field when subCaste == 'Vaidiki'.
  /// Dravida branches are named lineages rather than regional groupings.
  static const Map<String, List<String>> brahminBranches = {
    'Niyogi': [
      'Aruvela (6000)',       // Most common; also called Aaru Vela Niyogi
      'Pradhama Sakha',       // Vedic / first-branch lineage; keep distinct from Aruvela
      'Karanam',              // Historically village administrative scribes
      'Nandavarika',          // Distinct sub-group; NOT a synonym for any of the above
    ],
    'Vaidiki': [
      // Vaidiki has no branch classification — leave empty / do not display.
      // Classification is entirely by region (see brahminRegions).
    ],
    'Dravida': [
      'Arama Dravida',        // Tamil-origin; migrated to Andhra
      'Tummagunta Dravida',   // Andhra-settled lineage
      'Konaseema Dravida',    // Coastal Krishna / Godavari delta lineage
    ],
  };

  /// Regional traditions (geographic school of practice).
  /// Applied to both Niyogi and Vaidiki sub-castes.
  /// Dravida lineage identity is captured in brahminBranches instead.
  static const Map<String, List<String>> brahminRegions = {
    'Niyogi': [
      'Velanadu',     // Krishna / Guntur districts — the largest Niyogi region
      'Telaganya',    // Telangana (also spelled Telaganya / Telaganadu)
      'Mulakanadu',   // Rayalaseema interior
      'Kasalanadu',   // Rare; parts of northern Andhra
      'Veginadu',     // Coastal Andhra / West Godavari — less common
    ],
    'Vaidiki': [
      'Velanadu',     // Core priestly families of Krishna / Guntur belt
      'Telaganya',    // Telangana priests
      'Mulakanadu',   // Interior Rayalaseema priests
      'Kasalanadu',   // Rare
      'Veginadu',     // Coastal West Godavari
      'Badaganadu',   // Karnataka-influenced northern border region
    ],
    'Dravida': [
      // Dravida uses branch (lineage) as the primary classifier, not region.
      // Leave this empty; do not display a region picker for Dravida.
    ],
  };

  /// Philosophical / ritual sect (cross-cutting — applies across all sub-castes).
  /// Smartha is the overwhelming default for Telugu Brahmins.
  /// Note: Includes both traditional sects and Brahmin sub-castes for comprehensive filtering.
  /// Listed in alphabetical order for consistent UI display.
  static const List<String> sects = [
    // Brahmin sub-castes and philosophical sects (alphabetical)
    'Dravida',           // South-migrated Tamil-lineage Brahmins
    'Madhwa',            // Dvaita tradition; Karnataka / Deshastha lineages
    'Niyogi',            // Administrative / secular class
    'Shaiva',            // Adi Saiva / Shivarchaka lineages
    'Smartha',           // Default for nearly all Telugu Brahmins (Advaita tradition)
    'Sri Vaishnava',     // Iyengar tradition; Vadakalai / Thenkalai sub-divisions
    'Vaidiki',           // Ritual / priestly class (also spelled Vaidika)
    'Vaikhanasa',        // Agamic temple-priest tradition
    'Vaishnava',         // General Vaishnava (non-Sri Vaishnava)
  ];

  /// Sri Vaishnava sub-divisions (display only when sect == 'Sri Vaishnava').
  static const List<String> sriVaishnavaDivisions = [
    'Vadakalai',   // Northern school; follows Vedanta Desika
    'Thenkalai',   // Southern school; follows Pillai Lokacharya
    'Hebbar Sri Vaishnava',
    'Mandayam',
  ];

  /// Madhwa sub-divisions (display only when sect == 'Madhwa').
  static const List<String> madhwaDivisions = [
    'Deshastha Madhwa',
    'Karnataka Madhwa',
    'Shivalli Madhwa',
    'Goud Saraswat Brahmin',
  ];

  /// Get sub-sect divisions based on the selected sect.
  /// Returns empty list for sects without subdivisions (e.g., 'Smartha').
  /// For Brahmin sub-castes (Niyogi, Vaidiki, Dravida), returns branches and regions.
  static List<String> subSectsForSect(String? sect) {
    if (sect == null) return [];
    switch (sect) {
      case 'Sri Vaishnava':
        return sriVaishnavaDivisions;
      case 'Madhwa':
        return madhwaDivisions;
      // For Brahmin sub-castes used as sect filters, return their branches + regions
      case 'Niyogi':
        final branches = brahminBranches['Niyogi'] ?? [];
        final regions = brahminRegions['Niyogi'] ?? [];
        return [...branches, ...regions];
      case 'Vaidiki':
        // Vaidiki has no branches, only regions
        return brahminRegions['Vaidiki'] ?? [];
      case 'Dravida':
        // Dravida uses branches as primary classifier
        return brahminBranches['Dravida'] ?? [];
      case 'Smartha':
      case 'Vaishnava':
      case 'Vaikhanasa':
      case 'Shaiva':
      default:
        return []; // No subdivisions for these sects
    }
  }

  /// Vedic shakha / affiliation — independent optional field.
  /// NOT a sub-caste. Store separately; display as an optional profile field.
  /// Most Telugu Brahmins follow Krishna Yajurveda (Apastamba sutra).
  static const List<String> vedicAffiliations = [
    'Yajurvedi',    // Krishna Yajurveda — by far the most common for Telugu Brahmins
    'Rigvedi',      // Rigveda followers
    'Samavedi',     // Samaveda followers
    'Atharvavedi',  // Atharvaveda followers — rare among Telugu Brahmins
  ];

  // ---------------------------------------------------------------------------
  // LEGACY COMPATIBILITY — kept for read-path migration only.
  // These two maps cover old data written with the flat "Vaidiki Velanadu" style.
  // Use brahminSubCastes + brahminBranches + brahminRegions for all NEW writes.
  // ---------------------------------------------------------------------------

  /// @deprecated Use brahminSubCastes + brahminRegions instead.
  /// Maps old flat subSect strings to their normalized field values.
  static const Map<String, Map<String, String>> legacySubSectNormalization = {
    'Vaidiki Velanadu':   {'subCaste': 'Vaidiki',  'region': 'Velanadu'},
    'Vaidiki Veginadu':   {'subCaste': 'Vaidiki',  'region': 'Veginadu'},
    'Vaidiki Mulakanadu': {'subCaste': 'Vaidiki',  'region': 'Mulakanadu'},
    'Vaidiki Telaganadu': {'subCaste': 'Vaidiki',  'region': 'Telaganya'},
    'Vaidiki Kammanadu':  {'subCaste': 'Vaidiki',  'region': 'Kasalanadu'},
    'Velnati Vaidiki':    {'subCaste': 'Vaidiki',  'region': 'Velanadu'},
    'Veginati Vaidiki':   {'subCaste': 'Vaidiki',  'region': 'Veginadu'},
    'Telaganya Vaidiki':  {'subCaste': 'Vaidiki',  'region': 'Telaganya'},
    'Mulakanadu Vaidiki': {'subCaste': 'Vaidiki',  'region': 'Mulakanadu'},
    'Aruvela Niyogi':         {'subCaste': 'Niyogi', 'branch': 'Aruvela (6000)'},
    'Aaru Vela Niyogi':       {'subCaste': 'Niyogi', 'branch': 'Aruvela (6000)'},
    'Nandavarika Niyogi':     {'subCaste': 'Niyogi', 'branch': 'Nandavarika'},
    'Prathamashaakha Niyogi': {'subCaste': 'Niyogi', 'branch': 'Pradhama Sakha'},
    'Karanakamma Niyogi':     {'subCaste': 'Niyogi', 'branch': 'Karanam'},
    'Niyogi Aruvela':         {'subCaste': 'Niyogi', 'branch': 'Aruvela (6000)'},
    'Niyogi Nandavarika':     {'subCaste': 'Niyogi', 'branch': 'Nandavarika'},
    'Niyogi Velanadu':        {'subCaste': 'Niyogi', 'region': 'Velanadu'},
    'Niyogi Veginadu':        {'subCaste': 'Niyogi', 'region': 'Veginadu'},
    'Niyogi Mulakanadu':      {'subCaste': 'Niyogi', 'region': 'Mulakanadu'},
    'Niyogi Telaganadu':      {'subCaste': 'Niyogi', 'region': 'Telaganya'},
    'Velnati Niyogi':         {'subCaste': 'Niyogi', 'region': 'Velanadu'},
  };

  // ============ HELPER METHODS — BRAHMIN HIERARCHY ============

  /// Returns branches for a given sub-caste, or empty list if none apply.
  static List<String> brahminBranchesFor(String subCaste) {
    return brahminBranches[subCaste] ?? [];
  }

  /// Returns regions for a given sub-caste, or empty list if none apply.
  static List<String> brahminRegionsFor(String subCaste) {
    return brahminRegions[subCaste] ?? [];
  }

  /// Returns true if the given sub-caste uses branch classification.
  static bool subCasteHasBranches(String subCaste) {
    final branches = brahminBranches[subCaste];
    return branches != null && branches.isNotEmpty;
  }

  /// Returns true if the given sub-caste uses region classification.
  static bool subCasteHasRegions(String subCaste) {
    final regions = brahminRegions[subCaste];
    return regions != null && regions.isNotEmpty;
  }

  /// Attempts to normalize a legacy flat subSect string into structured fields.
  /// Returns null if the string is not recognized as a legacy value.
  static Map<String, String>? normalizeLegacySubSect(String rawValue) {
    return legacySubSectNormalization[rawValue];
  }

  /// All Gothrams (Vedic patrilineal lineages) — Telugu Brahmin comprehensive list.
  /// Sorted A-Z; 'Other' always last.
  ///
  /// Additions over the previous list (16 common + 9 rare):
  ///   Common  : Atreyasa, Badayana, Darbhasa, Gargeya, Gritsamada, Jabali,
  ///             Jamadagnya, Kapishtala, Kapi, Krishnatreya, Kundina, Lauhitya,
  ///             Maitreya, Nrisimhadeva, Pracheta, Pulastya
  ///   Rare    : Devala, Dhanvantari, Lomasha, Markandeya, Pippalada,
  ///             Sankha, Shaunaka, Taittiriya, Vatula
  static const List<String> gothrams = [
    'Agastya',
    'Angirasa',
    'Atreya',
    'Atreyasa',        // variant / sub-lineage of Atreya
    'Badayana',        // Badarayana; Vedanta lineage
    'Bharadwaja',
    'Bhargava',
    'Bhrigu',
    'Chandratre',
    'Darbhasa',
    'Devala',          // rare
    'Dhananjaya',
    'Dhanvantari',     // rare; medical lineage
    'Galava',
    'Gargeya',         // branch of Garga
    'Garga',
    'Gautama',
    'Gritsamada',
    'Harita',
    'Jabali',
    'Jamadagni',
    'Jamadagnya',      // Parashurama lineage; distinct from Jamadagni
    'Kanva',
    'Kapi',
    'Kapila',
    'Kapishtala',      // Kapishtala-Katha branch; Yajurveda
    'Kashyapa',
    'Kaundinya',
    'Kaushika',
    'Krishnatreya',    // Krishna + Atreya compound gotra
    'Kundina',
    'Kutsa',
    'Lauhitya',        // also seen as Lohitya; variant of Lohita
    'Lohita',
    'Lomasha',         // rare
    'Mandavya',
    'Markandeya',      // rare
    'Maitreya',
    'Maudgalya',
    'Mudgala',
    'Naidhruva',
    'Nrisimhadeva',    // post-Vedic; found in some Vaishnava Brahmin families
    'Parashara',
    'Pippalada',       // rare; Atharvaveda lineage
    'Pracheta',
    'Pulastya',
    'Rathitara',
    'Sankha',          // rare
    'Shandilya',
    'Shaunaka',        // rare; Atharvaveda school
    'Srivatsa',
    'Sunkriti',
    'Taittiriya',      // rare; used in some Yajurvedi families
    'Upamanyu',
    'Vashista',
    'Vatsa',
    'Vatula',          // rare; Shaiva / South Indian lineages
    'Vishwamitra',
    'Other',
  ];

  /// 27 Nakshatras (Birth Stars)
  static const List<String> nakshatras = [
    'Ashwini (అశ్వని)',
    'Bharani (భరణి)',
    'Krittika (కృత్తిక)',
    'Rohini (రోహిణి)',
    'Mrigashira (మృగశిర)',
    'Ardra (ఆర్ద్ర)',
    'Punarvasu (పునర్వసు)',
    'Pushya (పుష్యమి)',
    'Ashlesha (ఆశ్లేష)',
    'Magha (మఖ)',
    'Purva Phalguni (పుబ్బ)',
    'Uttara Phalguni (ఉత్తర)',
    'Hasta (హస్త)',
    'Chitra (చిత్ర)',
    'Swati (స్వాతి)',
    'Vishakha (విశాఖ)',
    'Anuradha (అనురాధ)',
    'Jyeshtha (జ్యేష్ట)',
    'Mula (మూల)',
    'Purva Ashadha (పూర్వాషాఢ)',
    'Uttara Ashadha (ఉత్తరాషాఢ)',
    'Shravana (శ్రవణం)',
    'Dhanishta (ధనిష్ట)',
    'Shatabhisha (శతభిషం)',
    'Purva Bhadrapada (పూర్వాభాద్ర)',
    'Uttara Bhadrapada (ఉత్తరాభాద్ర)',
    'Revati (రేవతి)',
  ];

  /// Simple Nakshatra names without Telugu
  static const List<String> nakshatrasSimple = [
    'Ashwini',
    'Bharani',
    'Krittika',
    'Rohini',
    'Mrigashira',
    'Ardra',
    'Punarvasu',
    'Pushya',
    'Ashlesha',
    'Magha',
    'Purva Phalguni',
    'Uttara Phalguni',
    'Hasta',
    'Chitra',
    'Swati',
    'Vishakha',
    'Anuradha',
    'Jyeshtha',
    'Mula',
    'Purva Ashadha',
    'Uttara Ashadha',
    'Shravana',
    'Dhanishta',
    'Shatabhisha',
    'Purva Bhadrapada',
    'Uttara Bhadrapada',
    'Revati',
  ];

  /// Nakshatra Padas (1-4)
  static const List<String> padas = ['1st Pada', '2nd Pada', '3rd Pada', '4th Pada'];

  /// 12 Rasis (Moon Signs) - Telugu names
  static const List<String> rasis = [
    'Mesha (మేషం) - Aries',
    'Vrishabha (వృషభం) - Taurus',
    'Mithuna (మిథునం) - Gemini',
    'Karkata (కర్కాటకం) - Cancer',
    'Simha (సింహం) - Leo',
    'Kanya (కన్య) - Virgo',
    'Tula (తుల) - Libra',
    'Vrischika (వృశ్చికం) - Scorpio',
    'Dhanu (ధనుస్సు) - Sagittarius',
    'Makara (మకరం) - Capricorn',
    'Kumbha (కుంభం) - Aquarius',
    'Meena (మీనం) - Pisces',
  ];

  /// Nakshatra to Rasi mapping
  static const Map<String, String> nakshatraToRasi = {
    'Ashwini': 'Mesha (మేషం) - Aries',
    'Bharani': 'Mesha (మేషం) - Aries',
    'Krittika': 'Mesha (మేషం) - Aries', // First pada
    'Rohini': 'Vrishabha (వృషభం) - Taurus',
    'Mrigashira': 'Vrishabha (వృషభం) - Taurus', // First 2 padas
    'Ardra': 'Mithuna (మిథునం) - Gemini',
    'Punarvasu': 'Mithuna (మిథునం) - Gemini', // First 3 padas
    'Pushya': 'Karkata (కర్కాటకం) - Cancer',
    'Ashlesha': 'Karkata (కర్కాటకం) - Cancer',
    'Magha': 'Simha (సింహం) - Leo',
    'Purva Phalguni': 'Simha (సింహం) - Leo',
    'Uttara Phalguni': 'Simha (సింహం) - Leo', // First pada
    'Hasta': 'Kanya (కన్య) - Virgo',
    'Chitra': 'Kanya (కన్య) - Virgo', // First 2 padas
    'Swati': 'Tula (తుల) - Libra',
    'Vishakha': 'Tula (తుల) - Libra', // First 3 padas
    'Anuradha': 'Vrischika (వృశ్చికం) - Scorpio',
    'Jyeshtha': 'Vrischika (వృశ్చికం) - Scorpio',
    'Mula': 'Dhanu (ధనుస్సు) - Sagittarius',
    'Purva Ashadha': 'Dhanu (ధనుస్సు) - Sagittarius',
    'Uttara Ashadha': 'Dhanu (ధనుస్సు) - Sagittarius', // First pada
    'Shravana': 'Makara (మకరం) - Capricorn',
    'Dhanishta': 'Makara (మకరం) - Capricorn', // First 2 padas
    'Shatabhisha': 'Kumbha (కుంభం) - Aquarius',
    'Purva Bhadrapada': 'Kumbha (కుంభం) - Aquarius', // First 3 padas
    'Uttara Bhadrapada': 'Meena (మీనం) - Pisces',
    'Revati': 'Meena (మీనం) - Pisces',
  };

  // ============ EDUCATION & CAREER ============

  /// Education levels - Updated with modern courses
  static const List<String> educationLevels = [
    // ── School ──────────────────────────────────────────────────────────────
    'Below 10th',
    '10th / SSC',
    '12th / Intermediate',
    // ── Diploma / ITI ────────────────────────────────────────────────────────
    'Diploma',
    'ITI',
    // ── Undergraduate — Engineering & Technology ─────────────────────────────
    'B.Tech / B.E.',
    'B.Arch',
    'B.Des (Design)',
    'BCA',
    // ── Undergraduate — Medical & Health ────────────────────────────────────
    'BASLP (Audiology & Speech)',
    'BAMS (Ayurveda)',
    'BDS',
    'BHMS (Homeopathy)',
    'BOT (Occupational Therapy)',
    'B.Optometry',
    'B.Pharm',
    'BPT (Physiotherapy)',
    'B.Sc Nursing',
    'BUMS (Unani)',
    'BVSc (Veterinary Science)',
    'MBBS',
    // ── Undergraduate — Science ──────────────────────────────────────────────
    'B.Sc Agriculture',
    'B.Sc (Hons)',
    'Bachelors - Science',
    // ── Undergraduate — Commerce & Management ────────────────────────────────
    'B.Com (Hons)',
    'Bachelors - Commerce',
    'BBA',
    'BHM (Hotel Management)',
    // ── Undergraduate — Arts & Humanities ────────────────────────────────────
    'B.A. (Hons)',
    'B.Ed (Education)',
    'BFA (Fine Arts)',
    'Bachelors - Arts',
    // ── Undergraduate — Law ──────────────────────────────────────────────────
    'LLB',
    // ── Postgraduate — Engineering & Technology ──────────────────────────────
    'M.Arch',
    'M.Des (Design)',
    'M.Tech / M.E.',
    'MCA',
    // ── Postgraduate — Medical & Health ─────────────────────────────────────
    'DM / MCh (Super Speciality)',
    'DNB (Diplomate of NB)',
    'MDS',
    'MD / MS',
    'MFA (Fine Arts)',
    'MHA (Hospital Administration)',
    'MHM (Hotel Management)',
    'M.Pharm',
    'MPH (Public Health)',
    'MPT (Master of Physiotherapy)',
    'M.Sc Nursing',
    // ── Postgraduate — Science ───────────────────────────────────────────────
    'M.Sc Agriculture',
    'M.Sc (Hons)',
    'Masters - Science',
    // ── Postgraduate — Commerce & Management ─────────────────────────────────
    'Executive MBA',
    'M.Com (Hons)',
    'Masters - Commerce',
    'MBA',
    'PGDM',
    // ── Postgraduate — Arts & Humanities ─────────────────────────────────────
    'M.A. (Hons)',
    'M.Ed',
    'Masters - Arts',
    // ── Postgraduate — Law ───────────────────────────────────────────────────
    'LLM',
    // ── Dual / Integrated ────────────────────────────────────────────────────
    'Integrated B.Tech + M.Tech (5 Year)',
    'Integrated BA + LLB (5 Year)',
    'Integrated BBA + LLB (5 Year)',
    // ── Doctoral ─────────────────────────────────────────────────────────────
    'D.Litt (Doctor of Letters)',
    'D.Sc (Doctor of Science)',
    'Ph.D',
    'Post Doctorate',
    // ── Professional Certifications ──────────────────────────────────────────
    'CA (Chartered Accountant)',
    'CFA (Chartered Financial Analyst)',
    'CMA / ICWA',
    'CPA (Certified Public Accountant)',
    'CS (Company Secretary)',
    'FRM (Financial Risk Manager)',
    'PMP (Project Management)',
    // ── Technology Certifications ─────────────────────────────────────────────
    'AWS / Azure / GCP Cloud Certification',
    'Cybersecurity Certification (CEH/CISSP)',
    'Data Science & AI Certification',
    'Digital Marketing Certification',
    'Full Stack Development Bootcamp',
    // ── Vedic & Traditional Studies ───────────────────────────────────────────
    'Veda Adhyayanam (Rigveda)',
    'Veda Adhyayanam (Yajurveda)',
    'Veda Adhyayanam (Samaveda)',
    'Veda Adhyayanam (Atharvaveda)',
    'Agama Shastra',
    'Jyotisha (Vedic Astrology)',
    'Shiksha (Phonetics)',
    'Vyakarana (Grammar)',
    'Nirukta (Etymology)',
    'Chandas (Prosody)',
    'Kalpa (Rituals)',
    'Dharmashastra',
    'Nyaya (Logic)',
    'Mimamsa',
    'Sankhya',
    'Yoga Shastra',
    'Vedanta',
    'Itihasa & Purana',
    'Ganita (Vedic Mathematics)',
    'Ayurveda (Traditional Medicine)',
    'Silpa Shastra (Temple Architecture)',
    'Sangeeta Shastra (Music)',
    'Nritya Shastra (Dance)',
    'Alankara Shastra (Poetics)',
    'Natya Shastra',
    'Other',
  ];

  /// Specializations based on education level
  static const Map<String, List<String>> specializations = {
    'Below 10th': ['Not Applicable'],
    'ITI': ['Not Applicable'],
    '10th / SSC': ['General'],
    '12th / Intermediate': [
      'Arts', 'BiPC (Biology, Physics, Chemistry)', 'CEC (Commerce, Economics, Civics)',
      'Commerce', 'HEC (History, Economics, Civics)', 'MEC (Mathematics, Economics, Civics)',
      'MPC (Mathematics, Physics, Chemistry)', 'Science', 'Vocational', 'Not Applicable',
    ],
    'Diploma': [
      'Aeronautical Engineering', 'Agricultural Engineering', 'Architecture',
      'Automobile Engineering', 'Business Administration', 'Chemical Engineering',
      'Civil Engineering', 'Computer Applications (DCA)', 'Computer Science Engineering',
      'Education (D.Ed)', 'Electrical Engineering', 'Electronics & Communication Engineering',
      'Fashion Designing', 'Hotel Management', 'Information Technology',
      'Interior Designing', 'Mechanical Engineering', 'Nursing', 'Pharmacy', 'Other',
    ],
    'B.Tech / B.E.': [
      'Aerospace Engineering', 'Agricultural Engineering', 'Artificial Intelligence',
      'Automobile Engineering', 'Biotechnology Engineering', 'Chemical Engineering',
      'Civil Engineering (CE)', 'Cloud Computing', 'Computer Science Engineering (CSE)',
      'Cybersecurity', 'Data Science', 'Electrical & Electronics Engineering (EEE)',
      'Electronics & Communication Engineering (ECE)', 'Environmental Engineering',
      'Industrial Engineering', 'Information Technology (IT)', 'Machine Learning',
      'Marine Engineering', 'Mechanical Engineering (ME)', 'Metallurgical Engineering',
      'Mining Engineering', 'Naval Architecture', 'Petroleum Engineering',
      'Textile Engineering', 'Blockchain Technology', 'Internet of Things (IoT)',
      'Robotics & Automation', 'AR / VR Development', 'Full Stack Development',
      'Mobile Application Development', 'Big Data Analytics', 'DevSecOps',
      'Site Reliability Engineering', 'Other',
    ],
    'Integrated B.Tech + M.Tech (5 Year)': [
      'Computer Science Engineering', 'Electronics & Communication Engineering',
      'Information Technology', 'Mechanical Engineering', 'Other',
    ],
    'Integrated BA + LLB (5 Year)': ['Law', 'Other'],
    'Integrated BBA + LLB (5 Year)': ['Law', 'Other'],
    'M.Tech / M.E.': [
      'Aerospace Engineering', 'Artificial Intelligence', 'Biotechnology',
      'Blockchain Technology', 'Chemical Engineering', 'Civil Engineering',
      'Cloud Computing', 'Computer Science Engineering', 'Cybersecurity',
      'Data Science', 'Electrical Engineering', 'Electronics & Communication Engineering',
      'Embedded Systems', 'Environmental Engineering', 'Industrial Engineering',
      'Information Technology', 'Internet of Things (IoT)',
      'Machine Learning', 'Mechanical Engineering', 'Power Systems',
      'Production Engineering', 'Robotics & Automation', 'Structural Engineering',
      'VLSI Design', 'Other',
    ],
    'MBBS': [
      'Anesthesiology', 'Cardiology', 'Dermatology', 'Emergency Medicine',
      'General Medicine', 'Gynecology', 'Neurology', 'Oncology', 'Ophthalmology',
      'Orthopedics', 'Pathology', 'Pediatrics', 'Psychiatry', 'Radiology', 'Surgery', 'Other',
    ],
    'BDS': ['General Dentistry', 'Oral Surgery', 'Orthodontics', 'Prosthodontics', 'Other'],
    'BAMS (Ayurveda)': ['General Ayurveda', 'Panchakarma', 'Other'],
    'BHMS (Homeopathy)': ['General Homeopathy', 'Other'],
    'BUMS (Unani)': ['General Unani', 'Other'],
    'BPT (Physiotherapy)': ['General Physiotherapy', 'Neurological', 'Orthopedic', 'Pediatric', 'Sports', 'Other'],
    'B.Optometry': ['Contact Lens', 'Low Vision', 'Optometry', 'Other'],
    'B.Pharm': ['Pharmaceutical Sciences', 'Pharmacy', 'Other'],
    'B.Sc Nursing': ['General Nursing', 'ICU / Critical Care', 'Midwifery', 'Pediatric Nursing', 'Other'],
    'BASLP (Audiology & Speech)': ['Audiology', 'Speech Language Pathology', 'Other'],
    'BOT (Occupational Therapy)': ['Neurological Rehabilitation', 'Occupational Therapy', 'Pediatric OT', 'Other'],
    'BVSc (Veterinary Science)': ['Animal Husbandry', 'Veterinary Medicine', 'Veterinary Surgery', 'Other'],
    'MD / MS': [
      'Anesthesiology', 'Cardiology', 'Dermatology', 'Emergency Medicine',
      'General Medicine', 'General Surgery', 'Gynecology', 'Neurology',
      'Oncology', 'Ophthalmology', 'Orthopedics', 'Pathology', 'Pediatrics',
      'Psychiatry', 'Radiology', 'Other',
    ],
    'DM / MCh (Super Speciality)': [
      'Cardiology (DM)', 'Cardiothoracic Surgery (MCh)', 'Endocrinology (DM)',
      'Gastroenterology (DM)', 'Neonatology (DM)', 'Nephrology (DM)',
      'Neurology (DM)', 'Neurosurgery (MCh)', 'Oncology (DM)',
      'Pediatric Surgery (MCh)', 'Plastic Surgery (MCh)', 'Pulmonology (DM)',
      'Urology (MCh)', 'Other',
    ],
    'DNB (Diplomate of NB)': [
      'General Medicine', 'General Surgery', 'Gynecology',
      'Orthopedics', 'Pediatrics', 'Radiology', 'Other',
    ],
    'MDS': ['Endodontics', 'Oral Surgery', 'Orthodontics', 'Periodontics', 'Prosthodontics', 'Other'],
    'MPT (Master of Physiotherapy)': [
      'Cardiopulmonary', 'Musculoskeletal', 'Neurology', 'Pediatrics', 'Sports', 'Other',
    ],
    'M.Sc Nursing': [
      'Community Health Nursing', 'ICU / Critical Care', 'Medical-Surgical Nursing',
      'Midwifery', 'Pediatric Nursing', 'Psychiatric Nursing', 'Other',
    ],
    'M.Pharm': ['Pharmaceutical Chemistry', 'Pharmaceutical Technology', 'Pharmacology', 'Pharmaceutics', 'Other'],
    'MPH (Public Health)': ['Epidemiology', 'Health Management', 'Public Health', 'Other'],
    'MHA (Hospital Administration)': ['Healthcare Administration', 'Hospital Management', 'Other'],
    'Bachelors - Science': [
      'Agriculture', 'Biochemistry', 'Biology', 'Biotechnology', 'Botany',
      'Chemistry', 'Computer Science', 'Electronics', 'Environmental Science',
      'Fashion Technology', 'Food Science', 'Home Science', 'Information Technology',
      'Interior Design', 'Mathematics', 'Microbiology', 'Nutrition & Dietetics',
      'Physics', 'Psychology', 'Statistics', 'Zoology', 'Other',
    ],
    'B.Sc (Hons)': [
      'Biochemistry', 'Biology', 'Biotechnology', 'Chemistry', 'Computer Science',
      'Mathematics', 'Microbiology', 'Physics', 'Statistics', 'Other',
    ],
    'Masters - Science': [
      'Agriculture', 'Biochemistry', 'Biology', 'Biotechnology', 'Botany',
      'Chemistry', 'Computer Science', 'Electronics', 'Environmental Science',
      'Food Science', 'Information Technology', 'Mathematics', 'Microbiology',
      'Nutrition & Dietetics', 'Physics', 'Psychology', 'Statistics', 'Zoology', 'Other',
    ],
    'M.Sc (Hons)': [
      'Biochemistry', 'Biology', 'Biotechnology', 'Chemistry',
      'Computer Science', 'Mathematics', 'Physics', 'Statistics', 'Other',
    ],
    'B.Sc Agriculture': [
      'Agricultural Engineering', 'Agriculture', 'Forestry', 'Horticulture', 'Sericulture', 'Other',
    ],
    'M.Sc Agriculture': [
      'Agricultural Economics', 'Agriculture', 'Agronomy', 'Entomology',
      'Forestry', 'Horticulture', 'Plant Pathology', 'Soil Science', 'Other',
    ],
    'BCA': ['Computer Applications', 'Database Management', 'Software Development', 'Web Development', 'Other'],
    'MCA': [
      'Artificial Intelligence', 'Computer Applications', 'Cybersecurity',
      'Data Science', 'Information Technology', 'Software Engineering', 'Other',
    ],
    'Bachelors - Commerce': [
      'Accounting & Finance', 'Banking & Insurance', 'Business Analytics',
      'Computer Applications', 'Corporate Secretaryship', 'E-Commerce',
      'General', 'Taxation', 'Other',
    ],
    'B.Com (Hons)': [
      'Accounting & Finance', 'Banking & Insurance', 'Business Analytics',
      'Computer Applications', 'Corporate Secretaryship', 'E-Commerce',
      'General', 'Taxation', 'Other',
    ],
    'BBA': [
      'Entrepreneurship', 'Finance', 'General', 'Human Resources',
      'Information Technology', 'International Business', 'Marketing',
      'Supply Chain Management', 'Other',
    ],
    'Masters - Commerce': [
      'Accounting & Finance', 'Banking & Finance', 'Business Administration', 'General', 'Taxation', 'Other',
    ],
    'M.Com (Hons)': [
      'Accounting & Finance', 'Banking & Finance', 'Business Administration', 'General', 'Taxation', 'Other',
    ],
    'MBA': [
      'Agri-Business Management', 'Entrepreneurship', 'Finance', 'General',
      'Healthcare Management', 'Hospitality Management', 'Human Resources',
      'Information Technology', 'International Business', 'Marketing',
      'Operations', 'Supply Chain Management', 'Other',
    ],
    'Executive MBA': [
      'Finance', 'General Management', 'Human Resources', 'Marketing', 'Operations', 'Strategy', 'Other',
    ],
    'PGDM': ['Finance', 'General Management', 'Human Resources', 'Marketing', 'Operations', 'Other'],
    'BHM (Hotel Management)': ['Culinary Arts', 'Hospitality Management', 'Hotel Management', 'Other'],
    'MHM (Hotel Management)': ['Culinary Arts', 'Hospitality Management', 'Hotel Management', 'Other'],
    'Bachelors - Arts': [
      'Dance', 'Economics', 'English Literature', 'Fine Arts', 'Geography',
      'Hindi Literature', 'History', 'Journalism & Mass Communication', 'Music',
      'Philosophy', 'Political Science', 'Psychology', 'Public Administration',
      'Sanskrit', 'Social Work', 'Sociology', 'Telugu Literature', 'Other',
    ],
    'B.A. (Hons)': [
      'Economics', 'English Literature', 'History', 'Political Science',
      'Psychology', 'Telugu Literature', 'Other',
    ],
    'Masters - Arts': [
      'Dance', 'Economics', 'English Literature', 'Fine Arts', 'Geography',
      'Hindi Literature', 'History', 'Journalism & Mass Communication', 'Music',
      'Philosophy', 'Political Science', 'Psychology', 'Public Administration',
      'Sanskrit', 'Social Work', 'Sociology', 'Telugu Literature', 'Other',
    ],
    'M.A. (Hons)': [
      'Economics', 'English Literature', 'History', 'Political Science',
      'Psychology', 'Telugu Literature', 'Other',
    ],
    'B.Ed (Education)': [
      'English Education', 'General Education', 'Mathematics Education',
      'Physical Education', 'Science Education', 'Social Studies Education',
      'Telugu Education', 'Other',
    ],
    'M.Ed': [
      'Curriculum Development', 'Educational Administration', 'Educational Psychology',
      'General Education', 'Special Education', 'Other',
    ],
    'B.Arch': ['Architecture', 'Interior Architecture', 'Landscape Architecture', 'Urban Planning', 'Other'],
    'M.Arch': ['Architecture', 'Interior Architecture', 'Landscape Architecture', 'Urban Planning', 'Other'],
    'B.Des (Design)': [
      'Fashion Design', 'Graphic Design', 'Industrial Design',
      'Interior Design', 'Product Design', 'UI/UX Design', 'Other',
    ],
    'M.Des (Design)': [
      'Fashion Design', 'Graphic Design', 'Industrial Design',
      'Interior Design', 'Product Design', 'UI/UX Design', 'Other',
    ],
    'BFA (Fine Arts)': ['Applied Arts', 'Fine Arts', 'Painting', 'Sculpture', 'Other'],
    'MFA (Fine Arts)': ['Applied Arts', 'Fine Arts', 'Painting', 'Sculpture', 'Other'],
    'LLB': [
      '3 Year LLB', '5 Year Integrated (BA LLB)', '5 Year Integrated (BBA LLB)',
      '5 Year Integrated (B.Com LLB)', '5 Year Integrated (B.Sc LLB)',
      'Civil Law', 'Constitutional Law', 'Corporate Law', 'Criminal Law',
      'Family Law', 'Intellectual Property', 'Tax Law', 'Other',
    ],
    'LLM': [
      'Constitutional Law', 'Corporate Law', 'Criminal Law', 'Environmental Law',
      'Human Rights Law', 'Intellectual Property Law', 'International Law', 'Tax Law', 'Other',
    ],
    'Ph.D': ['Agriculture', 'Arts', 'Commerce', 'Education', 'Engineering', 'Law', 'Management', 'Medicine', 'Science', 'Other'],
    'D.Sc (Doctor of Science)': ['Engineering', 'Science', 'Other'],
    'D.Litt (Doctor of Letters)': ['Arts', 'Humanities', 'Other'],
    'Post Doctorate': ['Engineering', 'Management', 'Medicine', 'Science', 'Other'],
    'CA (Chartered Accountant)': ['Chartered Accountancy', 'Other'],
    'CS (Company Secretary)': ['Company Secretaryship', 'Other'],
    'CMA / ICWA': ['Cost and Management Accountancy', 'Other'],
    'CFA (Chartered Financial Analyst)': ['Chartered Financial Analyst', 'Other'],
    'FRM (Financial Risk Manager)': ['Financial Risk Management', 'Other'],
    'CPA (Certified Public Accountant)': ['Public Accountancy', 'Other'],
    'PMP (Project Management)': ['Project Management', 'Other'],
    'AWS / Azure / GCP Cloud Certification': ['AWS', 'Azure', 'GCP', 'Multi-Cloud', 'Other'],
    'Cybersecurity Certification (CEH/CISSP)': ['CEH', 'CISM', 'CISSP', 'CompTIA Security+', 'Other'],
    'Data Science & AI Certification': ['AI Engineering', 'Data Science', 'Machine Learning', 'Other'],
    'Digital Marketing Certification': ['Content Marketing', 'SEO / SEM', 'Social Media Marketing', 'Other'],
    'Full Stack Development Bootcamp': ['Java / Spring', 'MEAN Stack', 'MERN Stack', 'Python / Django', 'Other'],
    'Other': ['Not Applicable'],
  };

  /// When selected in the profile wizard, shows “describe your business” and hides
  /// employer-focused fields. Must match the list entry below exactly.
  static const String ownBusinessOccupation = 'Own Business';

  /// Occupations / Professions
  /// Occupations / Professions — A-Z within groups, Other last
  static const List<String> occupations = [
    // ── Technology & IT ──────────────────────────────────────────────────────
    'AI / ML Engineer',
    'Business Analyst',
    'Cloud Architect / Engineer',
    'Cybersecurity Analyst',
    'Data Engineer',
    'Data Scientist / Analyst',
    'DevOps / SRE Engineer',
    'Embedded Systems Engineer',
    'IT Consultant',
    'Network Engineer',
    'Product Manager',
    'Project Manager (IT)',
    'Quality Assurance (QA) Engineer',
    'SAP Consultant',
    'Salesforce Developer',
    'Scrum Master / Agile Coach',
    'Software Engineer / Developer',
    'System Administrator',
    'Technical Writer / Documentation',
    'UI / UX Designer',
    'Database Administrator (DBA)',
    // ── Medical & Healthcare ─────────────────────────────────────────────────
    'Ayurvedic Doctor (BAMS)',
    'Cardiologist',
    'Dentist / BDS',
    'Dermatologist',
    'Doctor / Physician',
    'Homeopathic Doctor (BHMS)',
    'Neurologist',
    'Nurse / Nursing Staff',
    'Nutritionist / Dietitian',
    'Occupational Therapist',
    'Ophthalmologist / Eye Specialist',
    'Optometrist',
    'Orthodontist',
    'Orthopedic Surgeon',
    'Pediatrician',
    'Pharmacist',
    'Physiotherapist',
    'Psychiatrist',
    'Radiologist',
    'Speech Therapist',
    'Surgeon',
    'Veterinary Doctor',
    'Medical Researcher',
    // ── Education & Research ─────────────────────────────────────────────────
    'Professor / Associate Professor',
    'Research Scientist',
    'School Principal',
    'Teacher / Lecturer',
    // ── Finance & Banking ────────────────────────────────────────────────────
    'Auditor',
    'Bank Manager',
    'Bank Officer',
    'Chartered Accountant (CA)',
    'Company Secretary (CS)',
    'Cost Accountant (CMA)',
    'Financial Analyst',
    'Insurance Professional',
    'Investment Banker',
    'Stock Broker / Trader',
    // ── Legal ────────────────────────────────────────────────────────────────
    'Judge',
    'Lawyer / Advocate',
    'Legal Consultant',
    // ── Government & Civil Services ──────────────────────────────────────────
    'Agricultural Officer',
    'Central Government Officer',
    'Civil Services (IAS / IPS / IFS)',
    'Customs / Excise Officer',
    'Forest Officer (IFS)',
    'Police Services',
    'Revenue Officer',
    'State Government Officer',
    // ── Defense ──────────────────────────────────────────────────────────────
    'Air Force Officer',
    'Army Officer',
    'Defense Services',
    'Navy Officer',
    'Paramilitary Forces',
    // ── Engineering (Core) ───────────────────────────────────────────────────
    'Aerospace Engineer',
    'Agricultural Engineer',
    'Architect',
    'Automobile Engineer',
    'Chemical Engineer',
    'Civil Engineer',
    'Electrical Engineer',
    'Environmental Engineer',
    'Marine Engineer',
    'Mechanical Engineer',
    'Mining Engineer',
    'Structural Engineer',
    'Textile Engineer',
    // ── Business & Management ────────────────────────────────────────────────
    ownBusinessOccupation,
    'Entrepreneur / Business Owner',
    'HR Manager',
    'Marketing Manager',
    'Operations Manager',
    'Sales Manager',
    'Startup Founder',
    'Supply Chain Manager',
    // ── Media & Creative ─────────────────────────────────────────────────────
    'Artist / Painter',
    'Content Writer / Blogger',
    'Graphic Designer',
    'Journalist',
    'Musician / Singer',
    'Photographer / Videographer',
    'Social Media Manager',
    // ── Wellness & Spiritual ─────────────────────────────────────────────────
    'Astrologer',
    'Fitness Trainer / Gym Instructor',
    'Priest / Purohit',
    'Yoga Instructor',
    // ── Vedic & Religious Services ───────────────────────────────────────────
    'Vedic Pandit / Vadyar',
    'Ritual Priest (Homa / Pooja)',
    'Temple Archaka',
    'Veda Teacher / Veda Pathashala Instructor',
    'Agama Pundit',
    'Kramantha / Samhita / Pada Pathi (Vedic Chanting Expert)',
    'Shrauta Ritual Specialist',
    'Smartha Ritual Specialist',
    'Vivaha Purohit (Wedding Priest)',
    'Upanayana Priest (Sacred Thread)',
    'Shankaracharya Matha Seva',
    'Ashram Manager',
    'Religious Organization Administrator',
    'Tirtha Yatra Organizer',
    'Dharma Pracharak',
    'Satsang Coordinator',
    'Bhajan Singer / Kirtankar',
    // ── Other ────────────────────────────────────────────────────────────────
    'Homemaker',
    'Not Working',
    'Student',
    'Other',
  ];

  /// Employment types
  static const List<String> employmentTypes = [
    'Private Sector',
    'Government / PSU',
    'Self Employed / Business',
    'Defense',
    'Civil Services',
    'Freelancer / Consultant',
    'Not Working',
    'Student',
  ];

  /// Income / Salary ranges — used as quick-select suggestions.
  /// The wizard also shows a free-text entry field for exact salary input.
  static const List<String> incomeRanges = [
    'Not Disclosed',
    // ── Annual (India) ───────────────────────────────────────────────────────
    'Below ₹1 LPA',
    '₹1 – 2 LPA',
    '₹2 – 3 LPA',
    '₹3 – 5 LPA',
    '₹5 – 8 LPA',
    '₹8 – 12 LPA',
    '₹12 – 18 LPA',
    '₹18 – 25 LPA',
    '₹25 – 35 LPA',
    '₹35 – 50 LPA',
    '₹50 – 75 LPA',
    '₹75 LPA – 1 Cr',
    '₹1 Cr – 2 Cr',
    'Above ₹2 Cr',
    // ── NRI / Overseas (USD) ─────────────────────────────────────────────────
    'USD 30,000 – 50,000',
    'USD 50,000 – 75,000',
    'USD 75,000 – 1,00,000',
    'USD 1,00,000 – 1,50,000',
    'USD 1,50,000 – 2,00,000',
    'Above USD 2,00,000',
    // ── NRI / Overseas (GBP) ─────────────────────────────────────────────────
    'GBP 25,000 – 40,000',
    'GBP 40,000 – 60,000',
    'GBP 60,000 – 80,000',
    'Above GBP 80,000',
    // ── NRI / Overseas (AED / Gulf) ──────────────────────────────────────────
    'AED 5,000 – 10,000 / month',
    'AED 10,000 – 20,000 / month',
    'AED 20,000 – 40,000 / month',
    'Above AED 40,000 / month',
  ];

  // ============ PERSONAL DETAILS ============

  /// Height options (in feet and inches)
  static List<String> get heights {
    List<String> heightList = [];
    for (int feet = 4; feet <= 7; feet++) {
      for (int inches = 0; inches < 12; inches++) {
        if (feet == 7 && inches > 0) break;
        heightList.add("$feet' $inches\" (${_heightToCm(feet, inches)} cm)");
      }
    }
    return heightList;
  }

  static int _heightToCm(int feet, int inches) {
    return ((feet * 12 + inches) * 2.54).round();
  }

  /// Weight ranges
  static const List<String> weightRanges = [
    '40-50 kg',
    '50-60 kg',
    '60-70 kg',
    '70-80 kg',
    '80-90 kg',
    '90-100 kg',
    'Above 100 kg',
  ];

  /// Weights list
  static const List<String> weights = [
    '40 kg',
    '45 kg',
    '50 kg',
    '55 kg',
    '60 kg',
    '65 kg',
    '70 kg',
    '75 kg',
    '80 kg',
    '85 kg',
    '90 kg',
    '95 kg',
    '100 kg',
    'Above 100 kg',
  ];

  /// Complexion
  static const List<String> complexions = [
    'Very Fair',
    'Fair',
    'Wheatish',
    'Wheatish Brown',
    'Dark',
  ];

  /// Body Type
  static const List<String> bodyTypes = [
    'Slim',
    'Average',
    'Athletic',
    'Heavy',
  ];

  /// Physical Status
  static const List<String> physicalStatuses = [
    'Normal',
    'Physically Challenged',
  ];

  /// Marital Status
  static const List<String> maritalStatuses = [
    'Never Married',
    'Divorced',
    'Widowed',
    'Awaiting Divorce',
    'Annulled',
  ];

  /// Diet / Food Habits
  static const List<String> foodHabits = [
    'Strict Vegetarian (No Onion/Garlic)',
    'Vegetarian',
    'Eggetarian',
    'Vegan',
    'Occasionally Non-Veg',
  ];

  /// Smoking Habits
  static const List<String> smokingHabits = [
    'No',
    'Occasionally',
    'Yes',
  ];

  /// Drinking Habits
  static const List<String> drinkingHabits = [
    'No',
    'Occasionally',
    'Yes',
  ];

  // ============ FAMILY DETAILS ============

  /// Family Type
  static const List<String> familyTypes = [
    'Joint Family',
    'Nuclear Family',
    'Extended Family',
  ];

  /// Family Status
  static const List<String> familyStatuses = [
    'Middle Class',
    'Upper Middle Class',
    'Rich',
    'Affluent',
  ];

  /// Family Values
  static const List<String> familyValues = [
    'Traditional',
    'Moderate',
    'Liberal',
  ];

  /// Father's Occupation
  static const List<String> fatherOccupations = [
    'Employed - Private',
    'Employed - Government',
    'Business',
    'Professional',
    'Retired',
    'Not Working',
    'Passed Away',
    'Late (Shri)',
  ];

  /// Mother's Occupation
  static const List<String> motherOccupations = [
    'Homemaker',
    'Employed - Private',
    'Employed - Government',
    'Business',
    'Professional',
    'Retired',
    'Not Working',
    'Passed Away',
    'Late (Smt.)',
  ];

  // ============ LOCATION ============

  /// Countries for profile search / discovery filters (India first; then common diaspora destinations).
  /// `FilterScreen` adds "Any" and "Other" around this list — do not add those here.
  static const List<String> searchFilterCountries = [
    'India',
    'Australia',
    'Bahrain',
    'Bangladesh',
    'Belgium',
    'Canada',
    'Denmark',
    'France',
    'Germany',
    'Ireland',
    'Italy',
    'Japan',
    'Kenya',
    'Kuwait',
    'Malaysia',
    'Nepal',
    'Netherlands',
    'New Zealand',
    'Norway',
    'Oman',
    'Qatar',
    'Saudi Arabia',
    'Singapore',
    'South Africa',
    'Spain',
    'Sri Lanka',
    'Sweden',
    'Switzerland',
    'Thailand',
    'United Arab Emirates',
    'United Kingdom',
    'United States',
  ];

  /// Indian States and Union Territories — complete list, A-Z, Other last
  static const List<String> indianStates = [
    'Andaman & Nicobar Islands',
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chandigarh',
    'Chhattisgarh',
    'Dadra & Nagar Haveli and Daman & Diu',
    'Delhi',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jammu & Kashmir',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Ladakh',
    'Lakshadweep',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Puducherry',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Other',
  ];

  /// Major cities and towns for all Indian states and UTs — each list A-Z, Other last
  static const Map<String, List<String>> cities = {
    'Andaman & Nicobar Islands': [
      'Port Blair',
      'Other',
    ],
    'Andhra Pradesh': [
      'Adoni',
      'Amalapuram',
      'Amaravathi',
      'Anakapalle',
      'Anantapur',
      'Atmakur',
      'Avanigadda',
      'Banaganapalle',
      'Bapatla',
      'Bheemunipatnam',
      'Bhimavaram',
      'Bobbili',
      'Chandragiri',
      'Chirala',
      'Chodavaram',
      'Chittoor',
      'Denduluru',
      'Dharmavaram',
      'Eluru',
      'Gajuwaka',
      'Giddalur',
      'Gudivada',
      'Gudur',
      'Guntakal',
      'Guntur',
      'Gurazala',
      'Hindupur',
      'Ichchapuram',
      'Kadapa',
      'Kadiri',
      'Kakinada',
      'Kalyandurg',
      'Karlapalem',
      'Kavali',
      'Kothapeta',
      'Kovvur',
      'Kuppam',
      'Macherla',
      'Machilipatnam',
      'Madugula',
      'Madanapalle',
      'Mangalagiri',
      'Markapur',
      'Mummidivaram',
      'Mylavaram',
      'Nagari',
      'Nandyal',
      'Narasannapeta',
      'Narasapuram',
      'Narasaraopet',
      'Nellore',
      'Nidadavole',
      'Nuzvid',
      'Ongole',
      'Palakollu',
      'Palamaner',
      'Palasa',
      'Parvathipuram',
      'Peddapuram',
      'Pithapuram',
      'Ponnur',
      'Proddatur',
      'Puttaparthi',
      'Razole',
      'Rayachoti',
      'Renigunta',
      'Repalle',
      'Rolugunta',
      'Samalkot',
      'Sattenapalle',
      'Srikakulam',
      'Srikalahasti',
      'Tadepalligudem',
      'Tadipatri',
      'Tadpatri',
      'Tamballapalle',
      'Tanuku',
      'Tekkali',
      'Tenali',
      'Tirupati',
      'Tiruvuru',
      'Tuni',
      'Venkatagiri',
      'Vijayawada',
      'Visakhapatnam',
      'Vizianagaram',
      'Yemmiganur',
      'Other',
    ],
    'Arunachal Pradesh': [
      'Itanagar',
      'Naharlagun',
      'Pasighat',
      'Tawang',
      'Ziro',
      'Other',
    ],
    'Assam': [
      'Barpeta',
      'Bongaigaon',
      'Dhubri',
      'Dibrugarh',
      'Diphu',
      'Goalpara',
      'Guwahati',
      'Jorhat',
      'Karimganj',
      'Nagaon',
      'North Lakhimpur',
      'Silchar',
      'Sivasagar',
      'Tezpur',
      'Tinsukia',
      'Other',
    ],
    'Bihar': [
      'Arrah',
      'Begusarai',
      'Bettiah',
      'Bhagalpur',
      'Bihar Sharif',
      'Chapra',
      'Darbhanga',
      'Dehri',
      'Gaya',
      'Hajipur',
      'Jamalpur',
      'Katihar',
      'Motihari',
      'Munger',
      'Muzaffarpur',
      'Patna',
      'Purnia',
      'Sasaram',
      'Siwan',
      'Other',
    ],
    'Chandigarh': [
      'Chandigarh',
      'Other',
    ],
    'Chhattisgarh': [
      'Ambikapur',
      'Bhilai',
      'Bilaspur',
      'Dantewada',
      'Dhamtari',
      'Durg',
      'Jagdalpur',
      'Korba',
      'Mahasamund',
      'Raigarh',
      'Raipur',
      'Rajnandgaon',
      'Other',
    ],
    'Dadra & Nagar Haveli and Daman & Diu': [
      'Daman',
      'Diu',
      'Silvassa',
      'Other',
    ],
    'Delhi': [
      'Central Delhi',
      'Dwarka',
      'East Delhi',
      'New Delhi',
      'North Delhi',
      'North East Delhi',
      'North West Delhi',
      'Rohini',
      'Shahdara',
      'South Delhi',
      'South West Delhi',
      'West Delhi',
      'Other',
    ],
    'Goa': [
      'Bicholim',
      'Canacona',
      'Curchorem',
      'Mapusa',
      'Margao',
      'Panaji',
      'Ponda',
      'Valpoi',
      'Vasco da Gama',
      'Other',
    ],
    'Gujarat': [
      'Ahmedabad',
      'Anand',
      'Bharuch',
      'Bhavnagar',
      'Bhuj',
      'Gandhidham',
      'Gandhinagar',
      'Godhra',
      'Gondal',
      'Jamnagar',
      'Junagadh',
      'Mehsana',
      'Morbi',
      'Nadiad',
      'Navsari',
      'Palanpur',
      'Patan',
      'Porbandar',
      'Rajkot',
      'Surat',
      'Surendranagar',
      'Vadodara',
      'Valsad',
      'Vapi',
      'Veraval',
      'Other',
    ],
    'Haryana': [
      'Ambala',
      'Bahadurgarh',
      'Bhiwani',
      'Faridabad',
      'Gurgaon',
      'Hisar',
      'Jind',
      'Kaithal',
      'Karnal',
      'Palwal',
      'Panchkula',
      'Panipat',
      'Rewari',
      'Rohtak',
      'Sirsa',
      'Sonipat',
      'Thanesar',
      'Yamunanagar',
      'Other',
    ],
    'Himachal Pradesh': [
      'Bilaspur',
      'Chamba',
      'Dharamshala',
      'Hamirpur',
      'Kangra',
      'Kullu',
      'Mandi',
      'Palampur',
      'Shimla',
      'Solan',
      'Una',
      'Other',
    ],
    'Jammu & Kashmir': [
      'Anantnag',
      'Baramulla',
      'Jammu',
      'Kargil',
      'Kathua',
      'Leh',
      'Poonch',
      'Rajouri',
      'Sopore',
      'Srinagar',
      'Udhampur',
      'Other',
    ],
    'Jharkhand': [
      'Adityapur',
      'Bokaro',
      'Chas',
      'Deoghar',
      'Dhanbad',
      'Giridih',
      'Hazaribagh',
      'Jamshedpur',
      'Medininagar',
      'Phusro',
      'Ramgarh',
      'Ranchi',
      'Other',
    ],
    'Karnataka': [
      'Bagalkot',
      'Bangalore',
      'Belgaum',
      'Bellary',
      'Bidar',
      'Bijapur',
      'Chamrajnagar',
      'Chikkamagaluru',
      'Chitradurga',
      'Davangere',
      'Dharwad',
      'Gadag',
      'Gulbarga',
      'Hassan',
      'Hospet',
      'Hubli',
      'Kolar',
      'Mandya',
      'Mangalore',
      'Mysore',
      'Raichur',
      'Shimoga',
      'Tumkur',
      'Udupi',
      'Other',
    ],
    'Kerala': [
      'Alappuzha',
      'Aluva',
      'Calicut',
      'Chalakudy',
      'Kannur',
      'Kattappana',
      'Kayamkulam',
      'Kochi',
      'Kollam',
      'Kottayam',
      'Koyilandy',
      'Manjeri',
      'Palakkad',
      'Payyannur',
      'Ponnani',
      'Thalassery',
      'Thiruvananthapuram',
      'Thrissur',
      'Other',
    ],
    'Ladakh': [
      'Kargil',
      'Leh',
      'Other',
    ],
    'Lakshadweep': [
      'Kavaratti',
      'Other',
    ],
    'Madhya Pradesh': [
      'Bhind',
      'Bhopal',
      'Burhanpur',
      'Chhindwara',
      'Guna',
      'Gwalior',
      'Indore',
      'Jabalpur',
      'Khandwa',
      'Morena',
      'Murwara',
      'Ratlam',
      'Rewa',
      'Sagar',
      'Satna',
      'Shivpuri',
      'Singrauli',
      'Ujjain',
      'Vidisha',
      'Other',
    ],
    'Maharashtra': [
      'Achalpur',
      'Ahmednagar',
      'Akola',
      'Amravati',
      'Aurangabad',
      'Barshi',
      'Beed',
      'Bhusawal',
      'Chandrapur',
      'Gondia',
      'Ichalkaranji',
      'Jalgaon',
      'Jalna',
      'Kamptee',
      'Kolhapur',
      'Latur',
      'Mumbai',
      'Nagpur',
      'Nanded',
      'Nashik',
      'Osmanabad',
      'Panvel',
      'Parbhani',
      'Pune',
      'Sangli',
      'Satara',
      'Solapur',
      'Thane',
      'Udgir',
      'Wardha',
      'Yavatmal',
      'Other',
    ],
    'Manipur': [
      'Bishnupur',
      'Churachandpur',
      'Imphal',
      'Senapati',
      'Thoubal',
      'Other',
    ],
    'Meghalaya': [
      'Jowai',
      'Nongpoh',
      'Nongstoin',
      'Shillong',
      'Tura',
      'Other',
    ],
    'Mizoram': [
      'Aizawl',
      'Champhai',
      'Lunglei',
      'Other',
    ],
    'Nagaland': [
      'Dimapur',
      'Kohima',
      'Mokokchung',
      'Tuensang',
      'Wokha',
      'Other',
    ],
    'Odisha': [
      'Balangir',
      'Baleshwar',
      'Barbil',
      'Bargarh',
      'Baripada',
      'Bhadrak',
      'Bhawanipatna',
      'Bhubaneswar',
      'Cuttack',
      'Dhenkanal',
      'Jharsuguda',
      'Kendujhar',
      'Paradip',
      'Puri',
      'Rourkela',
      'Sambalpur',
      'Sunabeda',
      'Other',
    ],
    'Puducherry': [
      'Karaikal',
      'Mahe',
      'Puducherry',
      'Yanam',
      'Other',
    ],
    'Punjab': [
      'Abohar',
      'Amritsar',
      'Barnala',
      'Batala',
      'Bathinda',
      'Firozpur',
      'Hoshiarpur',
      'Jalandhar',
      'Kapurthala',
      'Khanna',
      'Ludhiana',
      'Malerkotla',
      'Moga',
      'Mohali',
      'Muktsar',
      'Pathankot',
      'Patiala',
      'Phagwara',
      'Other',
    ],
    'Rajasthan': [
      'Ajmer',
      'Alwar',
      'Banswara',
      'Barmer',
      'Beawar',
      'Bharatpur',
      'Bhilwara',
      'Bikaner',
      'Chittorgarh',
      'Churu',
      'Dausa',
      'Ganganagar',
      'Hanumangarh',
      'Jaipur',
      'Jhunjhunu',
      'Jodhpur',
      'Kota',
      'Nagaur',
      'Pali',
      'Sikar',
      'Tonk',
      'Udaipur',
      'Other',
    ],
    'Sikkim': [
      'Gangtok',
      'Gyalshing',
      'Mangan',
      'Namchi',
      'Other',
    ],
    'Tamil Nadu': [
      'Chennai',
      'Coimbatore',
      'Cuddalore',
      'Dindigul',
      'Erode',
      'Gobichettipalayam',
      'Hosur',
      'Kanchipuram',
      'Karaikudi',
      'Karur',
      'Kumarapalayam',
      'Madurai',
      'Nagercoil',
      'Neyveli',
      'Pollachi',
      'Pudukkottai',
      'Rajapalayam',
      'Ranipet',
      'Salem',
      'Sivakasi',
      'Thanjavur',
      'Thoothukudi',
      'Tiruchirappalli',
      'Tirunelveli',
      'Tiruppur',
      'Tiruvannamalai',
      'Udhagamandalam',
      'Vellore',
      'Other',
    ],
    'Telangana': [
      'Achampet',
      'Adilabad',
      'Alair',
      'Alampur',
      'Armoor',
      'Asifabad',
      'Bachannapet',
      'Banswada',
      'Bellampalli',
      'Bhadrachalam',
      'Bhainsa',
      'Bhongir',
      'Bhupalpally',
      'Bodhan',
      'Charminar',
      'Chevella',
      'Choutuppal',
      'Devarakonda',
      'Dornakal',
      'Dubbak',
      'Gadwal',
      'Gajwel',
      'Godavarikhani',
      'Huzurabad',
      'Huzurnagar',
      'Hyderabad',
      'Ibrahimpatnam',
      'Ieeja',
      'Jadcherla',
      'Jagtial',
      'Jainoor',
      'Jammikunta',
      'Jangaon',
      'Kalwakurthy',
      'Kamareddy',
      'Karimnagar',
      'Kazipet',
      'Keesara',
      'Khairyatabad',
      'Kodad',
      'Korutla',
      'Kothagudem',
      'Mahadevpur',
      'Mahbubabad',
      'Mahbubnagar',
      'Malkajgiri',
      'Mandamarri',
      'Manthani',
      'Maripeda',
      'Medak',
      'Metpally',
      'Miryalaguda',
      'Mudhole',
      'Mulugu',
      'Nagarkurnool',
      'Nalgonda',
      'Narnoor',
      'Narayanpet',
      'Narsampet',
      'Narsapur',
      'Nirmal',
      'Nizamabad',
      'Palwancha',
      'Parkal',
      'Parigi',
      'Pebbair',
      'Penukonda',
      'Ramagundam',
      'Sangareddy',
      'Sathupalli',
      'Secunderabad',
      'Siddipet',
      'Sirpur',
      'Sircilla',
      'Suryapet',
      'Tandur',
      'Toopran',
      'Utnoor',
      'Venkatapuram',
      'Vemulawada',
      'Wanaparthy',
      'Warangal',
      'Wyra',
      'Yadadri',
      'Yellandu',
      'Yellareddy',
      'Zaheerabad',
      'Other',
    ],
    'Tripura': [
      'Agartala',
      'Dharmanagar',
      'Kailasahar',
      'Udaipur',
      'Other',
    ],
    'Uttar Pradesh': [
      'Agra',
      'Aligarh',
      'Allahabad',
      'Bareilly',
      'Budaun',
      'Etawah',
      'Farrukhabad',
      'Firozabad',
      'Ghaziabad',
      'Gorakhpur',
      'Jhansi',
      'Kanpur',
      'Lucknow',
      'Mathura',
      'Meerut',
      'Moradabad',
      'Muzaffarnagar',
      'Noida',
      'Rampur',
      'Saharanpur',
      'Shahjahanpur',
      'Sitapur',
      'Unnao',
      'Varanasi',
      'Other',
    ],
    'Uttarakhand': [
      'Almora',
      'Dehradun',
      'Haldwani',
      'Haridwar',
      'Kashipur',
      'Mussoorie',
      'Nainital',
      'Pithoragarh',
      'Rishikesh',
      'Roorkee',
      'Rudrapur',
      'Other',
    ],
    'West Bengal': [
      'Asansol',
      'Baharampur',
      'Balurghat',
      'Bankura',
      'Bardhaman',
      'Chinsurah',
      'Cooch Behar',
      'Durgapur',
      'Habra',
      'Haldia',
      'Howrah',
      'Jalpaiguri',
      'Kharagpur',
      'Kolkata',
      'Krishnanagar',
      'Malda',
      'Raiganj',
      'Santipur',
      'Siliguri',
      'Other',
    ],
  };
  
  /// Get all cities and towns (combined list for native place)
  static List<String> getAllCitiesAndTowns() {
    final Set<String> allPlaces = {};
    
    // Collect all cities from all states
    for (final cityList in cities.values) {
      allPlaces.addAll(cityList);
    }
    
    // Remove duplicates and sort
    final sortedList = allPlaces.toList()..sort();
    
    // Ensure "Other" is at the end
    final result = <String>[];
    final others = <String>[];
    
    for (final item in sortedList) {
      if (item == 'Other') {
        others.add(item);
      } else {
        result.add(item);
      }
    }
    
    result.addAll(others);
    return result;
  }

  /// Countries for NRI profiles
  /// Countries — India first, rest A-Z, Other last
  static const List<String> countries = [
    'India',
    'Australia',
    'Bahrain',
    'Canada',
    'France',
    'Germany',
    'Ireland',
    'Japan',
    'Kuwait',
    'Malaysia',
    'Netherlands',
    'New Zealand',
    'Oman',
    'Qatar',
    'Saudi Arabia',
    'Singapore',
    'South Korea',
    'Switzerland',
    'United Arab Emirates',
    'United Kingdom',
    'United States',
    'Other',
  ];

  /// Cities and towns by country — each list A-Z, Other last
  static const Map<String, List<String>> citiesByCountry = {
    'Australia': [
      'Adelaide',
      'Albury',
      'Ballarat',
      'Bendigo',
      'Brisbane',
      'Bunbury',
      'Bundaberg',
      'Cairns',
      'Canberra',
      'Coffs Harbour',
      'Darwin',
      'Geelong',
      'Gold Coast',
      'Hervey Bay',
      'Hobart',
      'Launceston',
      'Mackay',
      'Melbourne',
      'Newcastle',
      'Perth',
      'Port Macquarie',
      'Rockhampton',
      'Shepparton',
      'Sunshine Coast',
      'Sydney',
      'Toowoomba',
      'Townsville',
      'Wagga Wagga',
      'Wollongong',
      'Other',
    ],
    'Bahrain': [
      'Isa Town',
      'Manama',
      'Muharraq',
      'Riffa',
      'Sitra',
      'Other',
    ],
    'Canada': [
      'Abbotsford',
      'Barrie',
      'Calgary',
      'Cambridge',
      'Coquitlam',
      'Edmonton',
      'Guelph',
      'Halifax',
      'Hamilton',
      'Kelowna',
      'Kingston',
      'Kitchener',
      'London',
      'Montreal',
      'Oshawa',
      'Ottawa',
      'Quebec City',
      'Regina',
      'Saguenay',
      'Saskatoon',
      'Sherbrooke',
      'Sudbury',
      'Toronto',
      'Trois-Rivières',
      'Vancouver',
      'Victoria',
      'Windsor',
      'Winnipeg',
      'Yellowknife',
      'Other',
    ],
    'France': [
      'Bordeaux',
      'Grenoble',
      'Lille',
      'Lyon',
      'Marseille',
      'Montpellier',
      'Nantes',
      'Nice',
      'Paris',
      'Rennes',
      'Strasbourg',
      'Toulouse',
      'Other',
    ],
    'Germany': [
      'Berlin',
      'Bielefeld',
      'Bochum',
      'Bonn',
      'Bremen',
      'Cologne',
      'Dortmund',
      'Dresden',
      'Duisburg',
      'Düsseldorf',
      'Essen',
      'Frankfurt',
      'Hamburg',
      'Hannover',
      'Leipzig',
      'Munich',
      'Münster',
      'Nuremberg',
      'Stuttgart',
      'Wuppertal',
      'Other',
    ],
    'Ireland': [
      'Bray',
      'Cork',
      'Drogheda',
      'Dublin',
      'Dundalk',
      'Galway',
      'Limerick',
      'Navan',
      'Swords',
      'Waterford',
      'Other',
    ],
    'Japan': [
      'Fukuoka',
      'Kawasaki',
      'Kobe',
      'Kyoto',
      'Nagoya',
      'Osaka',
      'Saitama',
      'Sapporo',
      'Tokyo',
      'Yokohama',
      'Other',
    ],
    'Kuwait': [
      'Al Ahmadi',
      'Al Farwaniyah',
      'Al Jahra',
      'Hawalli',
      'Kuwait City',
      'Mubarak Al-Kabeer',
      'Other',
    ],
    'Malaysia': [
      'George Town',
      'Ipoh',
      'Johor Bahru',
      'Kota Kinabalu',
      'Kuala Lumpur',
      'Kuching',
      'Melaka',
      'Petaling Jaya',
      'Seremban',
      'Shah Alam',
      'Other',
    ],
    'Netherlands': [
      'Almere',
      'Amsterdam',
      'Breda',
      'Eindhoven',
      'Groningen',
      'Nijmegen',
      'Rotterdam',
      'The Hague',
      'Tilburg',
      'Utrecht',
      'Other',
    ],
    'New Zealand': [
      'Auckland',
      'Christchurch',
      'Dunedin',
      'Hamilton',
      'Napier',
      'New Plymouth',
      'Palmerston North',
      'Rotorua',
      'Tauranga',
      'Wellington',
      'Other',
    ],
    'Oman': [
      'Barka',
      'Ibri',
      'Muscat',
      'Nizwa',
      'Rustaq',
      'Saham',
      'Salalah',
      'Seeb',
      'Sohar',
      'Sur',
      'Other',
    ],
    'Qatar': [
      'Al Daayen',
      'Al Khor',
      'Al Rayyan',
      'Al Wakrah',
      'Doha',
      'Dukhan',
      'Lusail',
      'Mesaieed',
      'Umm Salal',
      'Other',
    ],
    'Saudi Arabia': [
      'Abha',
      'Al Jubail',
      'Buraidah',
      'Dammam',
      'Hail',
      'Jazan',
      'Jeddah',
      'Khamis Mushait',
      'Khobar',
      'Mecca',
      'Medina',
      'Najran',
      'Riyadh',
      'Tabuk',
      'Taif',
      'Other',
    ],
    'Singapore': [
      'Ang Mo Kio',
      'Bishan',
      'Bukit Batok',
      'Bukit Panjang',
      'Choa Chu Kang',
      'Clementi',
      'Hougang',
      'Jurong East',
      'Pasir Ris',
      'Punggol',
      'Queenstown',
      'Sengkang',
      'Serangoon',
      'Singapore',
      'Tampines',
      'Toa Payoh',
      'Woodlands',
      'Yishun',
      'Other',
    ],
    'South Korea': [
      'Busan',
      'Changwon',
      'Daegu',
      'Daejeon',
      'Goyang',
      'Gwangju',
      'Incheon',
      'Seoul',
      'Suwon',
      'Ulsan',
      'Other',
    ],
    'Switzerland': [
      'Basel',
      'Bern',
      'Biel',
      'Geneva',
      'Lausanne',
      'Lucerne',
      'Lugano',
      'St. Gallen',
      'Winterthur',
      'Zurich',
      'Other',
    ],
    'United Arab Emirates': [
      'Abu Dhabi',
      'Ajman',
      'Al Ain',
      'Dibba',
      'Dubai',
      'Fujairah',
      'Khor Fakkan',
      'Ras Al Khaimah',
      'Sharjah',
      'Umm Al Quwain',
      'Other',
    ],
    'United Kingdom': [
      'Belfast',
      'Birmingham',
      'Bolton',
      'Bournemouth',
      'Bradford',
      'Brighton',
      'Bristol',
      'Cardiff',
      'Coventry',
      'Derby',
      'Edinburgh',
      'Glasgow',
      'Kingston upon Hull',
      'Leeds',
      'Leicester',
      'Liverpool',
      'London',
      'Luton',
      'Manchester',
      'Newcastle upon Tyne',
      'Northampton',
      'Norwich',
      'Nottingham',
      'Portsmouth',
      'Reading',
      'Sheffield',
      'Southampton',
      'Southend-on-Sea',
      'Stoke-on-Trent',
      'Swindon',
      'Other',
    ],
    'United States': [
      'Albuquerque',
      'Arlington',
      'Atlanta',
      'Austin',
      'Baltimore',
      'Boston',
      'Charlotte',
      'Chicago',
      'Cleveland',
      'Colorado Springs',
      'Columbus',
      'Dallas',
      'Denver',
      'Detroit',
      'El Paso',
      'Fort Worth',
      'Fresno',
      'Houston',
      'Indianapolis',
      'Jacksonville',
      'Kansas City',
      'Las Vegas',
      'Los Angeles',
      'Louisville',
      'Memphis',
      'Mesa',
      'Miami',
      'Milwaukee',
      'Minneapolis',
      'Nashville',
      'New Orleans',
      'New York',
      'Oakland',
      'Oklahoma City',
      'Omaha',
      'Philadelphia',
      'Phoenix',
      'Portland',
      'Raleigh',
      'Sacramento',
      'San Antonio',
      'San Diego',
      'San Francisco',
      'San Jose',
      'Seattle',
      'Tucson',
      'Tulsa',
      'Virginia Beach',
      'Washington',
      'Wichita',
      'Other',
    ],
  };

  /// Skip/disclosure options for optional fields
  static const List<String> disclosureOptions = [
    'Show to all',
    'Show to matches only',
    'Show on request',
    'Do not disclose',
  ];

  // ============ HELPER METHODS ============

  /// @deprecated Use brahminBranchesFor() or brahminRegionsFor() instead.
  /// Kept for call-site backward compatibility during migration.
  static List<String> subSectsFor(String subCaste) {
    final branches = brahminBranches[subCaste] ?? [];
    final regions = brahminRegions[subCaste] ?? [];
    return [...branches, ...regions];
  }

  /// Get specializations for given education
  static List<String> specializationsFor(String education) {
    // Check for exact match first
    if (specializations.containsKey(education)) {
      return specializations[education]!;
    }
    
    // Check for partial match (more precise)
    // Only match if the key is contained in education or vice versa, but be more specific
    for (var key in specializations.keys) {
      // Remove common suffixes/prefixes for better matching
      final normalizedEducation = education.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      final normalizedKey = key.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      
      // Check if key matches education (case insensitive)
      if (normalizedEducation.toLowerCase() == normalizedKey.toLowerCase() ||
          normalizedEducation.toLowerCase().contains(normalizedKey.toLowerCase()) ||
          normalizedKey.toLowerCase().contains(normalizedEducation.toLowerCase())) {
        return specializations[key]!;
      }
    }
    
    // If no match found, return default
    return ['Not Applicable'];
  }

  /// Get all specializations from all education levels (combined list)
  /// This includes all sub-categories and subjects from all specializations
  static List<String> getAllSpecializations() {
    final Set<String> allSpecializations = {};
    
    // Collect all specializations from all education levels
    for (final specializationList in specializations.values) {
      allSpecializations.addAll(specializationList);
    }
    
    // Remove duplicates and sort
    final sortedList = allSpecializations.toList()..sort();
    
    // Ensure "Other" and "Not Applicable" are at the end
    final result = <String>[];
    final others = <String>[];
    
    for (final item in sortedList) {
      if (item == 'Other' || item == 'Not Applicable') {
        others.add(item);
      } else {
        result.add(item);
      }
    }
    
    // Add "Other" and "Not Applicable" at the end
    result.addAll(others);
    
    return result;
  }

  /// Get cities for a given state
  static List<String> citiesFor(String state) {
    return cities[state] ?? ['Other'];
  }

  /// Get Rasi for given Nakshatra (simplified)
  static String getRasiForNakshatra(String nakshatra) {
    // Extract simple name from nakshatra
    String simpleName = nakshatra.split(' (').first;
    return nakshatraToRasi[simpleName] ?? '';
  }

  /// Birth time options (every 15 minutes)
  static List<String> get birthTimes {
    List<String> times = [];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 15) {
        String period = hour < 12 ? 'AM' : 'PM';
        int displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        String hourStr = displayHour.toString().padLeft(2, '0');
        String minuteStr = minute.toString().padLeft(2, '0');
        times.add('$hourStr:$minuteStr $period');
      }
    }
    return times;
  }

  // ============ PARTNER PREFERENCES ============

  /// Manglik status options
  static const List<String> manglikStatuses = [
    'Yes',
    'No',
    'Not Sure',
    'Does Not Matter',
  ];

  /// Partner age range options
  static const List<String> partnerAgeOptions = [
    '18-21',
    '21-24',
    '24-27',
    '27-30',
    '30-33',
    '33-36',
    '36-39',
    '39-42',
    '42-45',
    '45-48',
    '48-51',
    '51-54',
    '54-57',
    '57-60',
  ];

  /// Partner location preferences
  static const List<String> partnerLocationPreferences = [
    'Same City',
    'Same State',
    'Anywhere in India',
    'Abroad',
    'Does Not Matter',
  ];

  /// Languages known
  static const List<String> languages = [
    'Telugu',
    'Hindi',
    'English',
    'Tamil',
    'Marathi',
    'Gujarati',
    'Kannada',
    'Malayalam',
    'Punjabi',
    'Bengali',
    'Urdu',
    'Sanskrit',
    'Other',
  ];

  /// Hobbies and interests
  static const List<String> hobbies = [
    'Reading',
    'Music',
    'Traveling',
    'Cooking',
    'Painting',
    'Dancing',
    'Photography',
    'Gardening',
    'Writing',
    'Sports',
    'Yoga',
    'Meditation',
    'Movies',
    'Shopping',
    'Art',
    'Crafts',
    'Technology',
    'Gaming',
    'Fitness',
    'Nature',
    'Other',
  ];

  // ============ WORK DETAILS ============

  /// Work mode options
  static const List<String> workModes = [
    'Work From Office',
    'Remote',
    'Hybrid',
  ];

  /// Visa status options for NRI profiles
  static const List<String> visaStatus = [
    'Citizen',
    'Permanent Resident',
    'Work Visa',
    'Student Visa',
    'Dependent Visa',
    'Other',
  ];
}
