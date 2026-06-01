import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/support_links.dart';
import '../theme/app_theme.dart';

/// Opens the official mana Vivaaha Vedika WhatsApp channel.
class WhatsAppChannelCard extends StatelessWidget {
  final bool compact;

  const WhatsAppChannelCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 12.0 : 16.0;
    return Material(
      color: AppTheme.sacredGreen.withAlpha(18),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => SupportLinks.openWhatsAppChannel(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.sacredGreen.withAlpha(80),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.campaign_outlined,
                  color: AppTheme.sacredGreen,
                  size: compact ? 22 : 24,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp Channel',
                      style: GoogleFonts.poppins(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w600,
                        color: AC.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Follow mana Vivaaha Vedika for app updates & tips',
                      style: GoogleFonts.poppins(
                        fontSize: compact ? 11 : 12,
                        color: AC.textMuted(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppTheme.sacredGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
