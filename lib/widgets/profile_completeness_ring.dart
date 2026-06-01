import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_router.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ProfileCompletenessRing
//
//  Drop anywhere.  Supply the current UserProfile — the widget derives the
//  percentage from UserProfile.computedCompletionPercentage and the missing
//  field list from UserProfile.getMissingFields().
//
//  Tapping a missing-field chip navigates to the Profile Wizard on the
//  correct step (via Routes.profileWizard with {initialStep: N}).
// ─────────────────────────────────────────────────────────────────────────────

class ProfileCompletenessRing extends StatefulWidget {
  final UserProfile profile;
  final bool animate;

  const ProfileCompletenessRing({
    super.key,
    required this.profile,
    this.animate = true,
  });

  @override
  State<ProfileCompletenessRing> createState() =>
      _ProfileCompletenessRingState();
}

class _ProfileCompletenessRingState extends State<ProfileCompletenessRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final target = widget.profile.computedCompletionPercentage / 100.0;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progress = Tween<double>(begin: 0, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _ctrl.forward();
      });
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(ProfileCompletenessRing old) {
    super.didUpdateWidget(old);
    final target = widget.profile.computedCompletionPercentage / 100.0;
    if ((target - _progress.value).abs() > 0.01) {
      _progress = Tween<double>(begin: _progress.value, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct  = widget.profile.computedCompletionPercentage;
    final miss = widget.profile.getMissingFields();

    // Don't show at 100 %
    if (pct >= 100) return const SizedBox.shrink();

    final ringColor  = _ringColor(pct);
    final trackColor = ringColor.withAlpha(30);
    final label      = _label(pct);
    final labelColor = _labelColor(pct);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ringColor.withAlpha(25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: ringColor.withAlpha(50), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: ring + labels ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated ring
                AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) => CustomPaint(
                    size: const Size(72, 72),
                    painter: _RingPainter(
                      progress: _progress.value,
                      ringColor: ringColor,
                      trackColor: trackColor,
                    ),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(_progress.value * 100).round()}%',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ringColor,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),

                // Text block
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile Completeness',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AC.textMuted(context),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Linear sub-bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (_, __) => LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 5,
                            backgroundColor: trackColor,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(ringColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        miss.isEmpty
                            ? 'All done!'
                            : '${miss.length} field${miss.length == 1 ? '' : 's'} to complete',
                        style: TextStyle(
                          fontSize: 11,
                          color: AC.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),

                // Chevron tap target
                GestureDetector(
                  onTap: () {
                    final firstMissingStep =
                        miss.isNotEmpty ? _stepForField(miss.first) : 0;
                    _navigateToWizard(context, firstMissingStep);
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ringColor.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.edit_outlined,
                        size: 16, color: ringColor),
                  ),
                ),
              ],
            ),
          ),

          // ── Missing field chips ───────────────────────────────────────────
          if (miss.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 4),
              child: Text(
                'Tap to complete:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AC.textMuted(context),
                  letterSpacing: 0.2,
                ),
              ),
            ),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                itemCount: miss.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final field = miss[i];
                  final step  = _stepForField(field);
                  return GestureDetector(
                    onTap: () => _navigateToWizard(context, step),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ringColor.withAlpha(18),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: ringColor.withAlpha(70)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline,
                              size: 13, color: ringColor),
                          const SizedBox(width: 5),
                          Text(
                            field,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ringColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _ringColor(int pct) {
    if (pct >= 80) return const Color(0xFF2E7D32);   // green
    if (pct >= 55) return const Color(0xFFF9A825);   // amber
    if (pct >= 30) return AppTheme.primaryOrange;     // orange
    return const Color(0xFFC62828);                   // red
  }

  Color _labelColor(int pct) => _ringColor(pct);

  String _label(int pct) {
    if (pct >= 80) return 'Looking great! 🌟';
    if (pct >= 55) return 'Almost there ✨';
    if (pct >= 30) return 'Getting started 🌱';
    return 'Just begun 🚀';
  }

  // Maps a missing-field display name → the wizard step index (0–5).
  // Falls back to step 0 for anything unknown.
  int _stepForField(String field) {
    switch (field) {
      // Step 0 — Basic Info
      case 'First Name':
      case 'Last Name':
      case 'Height':
      case 'Complexion':
      case 'Body Type':
      case 'Physical Status':
        return 0;

      // Step 1 — Birth Details
      case 'Time of Birth':
      case 'Place of Birth':
      case 'Nakshatra':
      case 'Pada':
      case 'Rasi':
      case 'Manglik':
        return 1;

      // Step 2 — Religious
      case 'Sect':
      case 'Sub-Sect':
      case 'Gothram':
        return 2;

      // Step 3 — Education & Career
      case 'Education':
      case 'Occupation':
      case 'State':
      case 'City/Town':
      case 'Income Range':
        return 3;

      // Step 4 — Family
      case 'Marital Status':
      case 'Family Type':
      case "Father's Name":
      case "Father's Occupation":
      case "Mother's Name":
      case "Mother's Occupation":
        return 4;

      // Step 5 — Lifestyle & About
      case 'About Me':
      case 'Hobbies':
      case 'Languages':
      case 'Food Habit':
      case 'Profile Picture':
        return 5;

      default:
        return 0;
    }
  }

  void _navigateToWizard(BuildContext context, int? step) {
    Navigator.of(context).pushNamed(
      Routes.profileWizard,
      arguments: {
        'isEditMode': true,
        if (step != null) 'initialStep': step,
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _RingPainter — draws the arc ring
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  const _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width / 2;
    final cy     = size.height / 2;
    const stroke = 6.5;
    final radius = (size.width / 2) - stroke / 2;
    final rect   = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    const startAngle = -math.pi / 2; // 12-o'clock

    // Track
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // Filled arc
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;

      // Gradient paint via shader
      final grad = SweepGradient(
        startAngle: startAngle,
        endAngle:   startAngle + sweepAngle,
        colors: [
          ringColor.withAlpha(180),
          ringColor,
        ],
      ).createShader(rect);

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..shader = grad
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.trackColor != trackColor;
}
