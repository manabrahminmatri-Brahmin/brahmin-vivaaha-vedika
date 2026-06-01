import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'auth_branding_header.dart';

/// Bank-style auth layout: logo + mana / Vivaaha Vedika, optional title, body, footer.
class AuthScreenShell extends StatelessWidget {
  final bool showBack;
  final VoidCallback? onBack;
  final String? screenTitle;
  final String? screenSubtitle;
  final bool showBranding;
  final Widget body;
  final Widget? footer;
  final bool scrollable;
  final EdgeInsetsGeometry bodyPadding;
  final bool resizeToAvoidBottomInset;

  const AuthScreenShell({
    super.key,
    this.showBack = true,
    this.onBack,
    this.screenTitle,
    this.screenSubtitle,
    this.showBranding = true,
    required this.body,
    this.footer,
    this.scrollable = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: bodyPadding,
      child: body,
    );

    if (scrollable) {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Container(
        color: AC.card(context),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack && onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AC.text(context),
                      size: 18,
                    ),
                    onPressed: onBack,
                  ),
                )
              else
                const SizedBox(height: 4),
              if (showBranding) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: AuthBrandingHeader(compact: true),
                ),
                const SizedBox(height: 6),
              ],
              if (screenTitle != null) ...[
                Text(
                  screenTitle!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AC.text(context),
                  ),
                ),
                if (screenSubtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    screenSubtitle!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AC.textMuted(context),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              Expanded(child: content),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}
