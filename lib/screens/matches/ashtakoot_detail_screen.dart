import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/star_compatibility_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/telugu_translations.dart';
import '../../widgets/app_header.dart';

/// Detailed Ashtakoot (8-fold) matching result screen
class AshtakootDetailScreen extends StatefulWidget {
  final AshtakootResult result;
  final String? star1Name;
  final String? star2Name;

  const AshtakootDetailScreen({
    super.key,
    required this.result,
    this.star1Name,
    this.star2Name,
  });

  @override
  State<AshtakootDetailScreen> createState() => _AshtakootDetailScreenState();
}

class _AshtakootDetailScreenState extends State<AshtakootDetailScreen> {
  bool _showInTelugu = false;
  
  AshtakootResult get result => widget.result;
  String? get star1Name => widget.star1Name;
  String? get star2Name => widget.star2Name;

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: _showInTelugu
            ? TeluguTranslations.ashtakootMatching
            : 'Ashtakoot Matching',
        showLogo: false,
        additionalActions: [
          IconButton(
            icon: Icon(_showInTelugu ? Icons.language : Icons.translate),
            tooltip: _showInTelugu
                ? TeluguTranslations.viewInEnglish
                : TeluguTranslations.viewInTelugu,
            onPressed: () {
              setState(() {
                _showInTelugu = !_showInTelugu;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Language Toggle Button
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showInTelugu = !_showInTelugu;
                });
              },
              icon: Icon(_showInTelugu ? Icons.language : Icons.translate),
              label: Text(_showInTelugu 
                  ? TeluguTranslations.viewInEnglish 
                  : TeluguTranslations.viewInTelugu),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textMedium,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),

          // Header Card
            _buildHeaderCard(context).animate().fadeIn().slideY(begin: -0.1),

            const SizedBox(height: 20),

            // Stars being matched
            if (star1Name != null && star2Name != null)
              _buildStarsCard(context).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 20),

            // 8 Kootas List
            ...result.kootas.asMap().entries.map((entry) {
              return _buildKootaCard(context, entry.value)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 150 + (entry.key * 100)))
                  .slideX(begin: 0.1);
            }),

            const SizedBox(height: 20),

            // Summary Card
            _buildSummaryCard(context)
                .animate()
                .fadeIn(delay: const Duration(milliseconds: 950)),

            const SizedBox(height: 20),

            // Important Disclaimer Card
            _buildDisclaimerCard(context)
                .animate()
                .fadeIn(delay: const Duration(milliseconds: 1000)),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getCompatibilityColor(result.level).withAlpha(30),
            _getCompatibilityColor(result.level).withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _getCompatibilityColor(result.level).withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          // Score Circle
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _getCompatibilityColor(result.level).withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(
                color: _getCompatibilityColor(result.level),
                width: 4,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${result.score}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: _getCompatibilityColor(result.level),
                  ),
                ),
                Text(
                  'of ${result.maxScore}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Text(
            _showInTelugu 
                ? TeluguTranslations.ashtakoot 
                : 'Ashtakoot Score',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AC.textSub(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                result.level.emoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              Text(
                '${result.percentage}% - ${result.level.displayName}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _getCompatibilityColor(result.level),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (result.hasNadiDosha) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.kumkumRed.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.kumkumRed.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.kumkumRed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nadi Dosha detected. Consult astrologer for remedies.',
                      style: TextStyle(
                        color: AppTheme.kumkumRed,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStarsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.elevatedCard(context: context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Icon(Icons.star, color: AppTheme.primaryGold),
                SizedBox(height: 8),
                Text(
                  'Your Star',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  star1Name?.split(' (').first ?? 'N/A',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AC.textSub(context),
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.compare_arrows,
              color: AC.textSub(context),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Icon(Icons.star, color: AppTheme.primaryGold),
                SizedBox(height: 8),
                Text(
                  'Partner Star',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  star2Name?.split(' (').first ?? 'N/A',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AC.textSub(context),
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKootaCard(BuildContext context, KootaResult koota) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: koota.isPrimary || koota.isCritical
            ? Border.all(
                color: koota.isCritical
                    ? (koota.isMatched ? AppTheme.sacredGreen : AppTheme.kumkumRed)
                    : AppTheme.primaryGold,
                width: 2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: AC.textSub(context).withAlpha(8),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Checkmark / Cross
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: koota.isMatched
                    ? AppTheme.sacredGreen.withAlpha(30)
                    : AppTheme.kumkumRed.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                koota.isMatched ? Icons.check : Icons.close,
                color: koota.isMatched ? AppTheme.sacredGreen : AppTheme.kumkumRed,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Koota Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        koota.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AC.textSub(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (koota.isPrimary) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGold,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'PRIMARY',
                            style: TextStyle(
                              color: AC.textSub(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (koota.isCritical) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.kumkumRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'CRITICAL',
                            style: TextStyle(
                              color: AC.card(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    koota.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    koota.details,
                    style: TextStyle(
                      color: koota.isMatched
                          ? AppTheme.sacredGreen
                          : AppTheme.kumkumRed,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: koota.isMatched
                    ? AppTheme.sacredGreen.withAlpha(20)
                    : AppTheme.kumkumRed.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${koota.score}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: koota.isMatched
                          ? AppTheme.sacredGreen
                          : AppTheme.kumkumRed,
                    ),
                  ),
                  Text(
                    'of ${koota.maxScore}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    int matchedCount = result.kootas.where((k) => k.isMatched).length;
    int totalCount = result.kootas.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.elevatedCard(context: context),
      child: Column(
        children: [
          Text(
            'Summary',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AC.textSub(context),
                ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryItem(
                context,
                icon: Icons.check_circle,
                color: AppTheme.sacredGreen,
                value: matchedCount.toString(),
                label: 'Matched',
              ),
              _buildSummaryItem(
                context,
                icon: Icons.cancel,
                color: AppTheme.kumkumRed,
                value: (totalCount - matchedCount).toString(),
                label: 'Not Matched',
              ),
              _buildSummaryItem(
                context,
                icon: Icons.stars,
                color: AppTheme.primaryGold,
                value: '${result.score}/${result.maxScore}',
                label: 'Total Score',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.textSub(context).withAlpha(10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AC.textSub(context),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Minimum 18 points (50%) is recommended for marriage. '
                    'Tara Koota (Star) is primary, Nadi Koota is critical.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _buildDisclaimerCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF5F5F5),
            AppTheme.primaryOrange.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AC.border(context),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.primaryOrange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _showInTelugu 
                      ? TeluguTranslations.important 
                      : 'Important Disclaimer',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _showInTelugu
                ? 'ఈ అష్టకూట అనుకూలత గణన సూచన మరియు సమాచార ప్రయోజనాల కోసం మాత్రమే అందించబడింది. ఇక్కడ చూపిన గణనలు సుమారుగా ఉంటాయి మరియు 100% ఖచ్చితమైనవి కాకపోవచ్చు.'
                : 'This Ashtakoot compatibility calculation is provided for reference and informational purposes only. The calculations shown here are approximate and may not be 100% accurate.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: AC.text(context),
                ),
          ),
          SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.textSub(context).withAlpha(10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: AC.textSub(context),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _showInTelugu
                        ? 'ఖచ్చితమైన మరియు సమగ్ర జాతకం (హోరోస్కోప్) సరిపోలిక కోసం, దయచేసి అర్హమైన మరియు అనుభవజ్ఞుడైన జ్యోతిష్యుడిని సంప్రదించండి. ఒక వృత్తిపరమైన జ్యోతిష్యుడు దశ కాలాలు, గ్రహ స్థానాలు, మంగళ దోషం మరియు సమాచారం ఆధారంగా నిర్ణయాలు తీసుకోవడానికి అవసరమైన ఇతర ముఖ్యమైన అంశాలతో సహా వివరణాత్మక విశ్లేషణను అందించగలడు.'
                        : 'For accurate and comprehensive Jatakam (horoscope) matching, please consult a qualified and experienced astrologer. A professional astrologer can provide detailed analysis including Dasha periods, planetary positions, Mangal Dosha, and other important factors that are essential for making informed decisions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.5,
                          color: AC.text(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.sacredGreen.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on,
                  color: AppTheme.sacredGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _showInTelugu
                        ? 'గమనిక: జనన స్థలం (Place of Birth) అనేది జాతకం మరియు నక్షత్ర గణనలలో చాలా ముఖ్యమైనది. ఖచ్చితమైన గణనల కోసం జనన స్థలం యొక్క అక్షాంశం మరియు రేఖాంశం (latitude & longitude) అవసరం.'
                        : 'Note: Place of Birth is very important in Jatakam and star calculations. For accurate calculations, the latitude and longitude of the birth place are required.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.5,
                          color: AC.text(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Text(
            _showInTelugu
                ? 'ఈ యాప్ ప్రాథమిక స్క్రీనింగ్ కోసం ప్రాథమిక అనుకూలత స్కోర్లను మాత్రమే అందిస్తుంది. తుది నిర్ణయాలు ఎల్లప్పుడూ జ్యోతిష్యుడిని సంప్రదించిన తర్వాత తీసుకోవాలి.'
                : 'This app provides basic compatibility scores for initial screening only. Final decisions should always be made after consulting with an astrologer.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AC.textSub(context),
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getCompatibilityColor(CompatibilityLevel level) {
    switch (level) {
      case CompatibilityLevel.excellent:
        return AppTheme.sacredGreen;
      case CompatibilityLevel.good:
        return const Color(0xFF8BC34A);
      case CompatibilityLevel.average:
        return Colors.orange;
      case CompatibilityLevel.belowAverage:
        return Colors.deepOrange;
      case CompatibilityLevel.notRecommended:
        return AppTheme.kumkumRed;
      case CompatibilityLevel.unknown:
        return AppTheme.textLight;
    }
  }
}

