import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Full-screen celebration: sparkles + petals; marriage flow adds a banner.
abstract final class CelebrationEffects {
  CelebrationEffects._();

  static Future<void> showInterestBurst(BuildContext context) async {
    if (!context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CelebrationLayer(
        variant: _CelebrationKind.interestSent,
        onDone: () {
          entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }

  static Future<void> showMarriageCongratulations(BuildContext context) async {
    if (!context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CelebrationLayer(
        variant: _CelebrationKind.marriageFarewell,
        onDone: () {
          entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }

  /// Sparkles + flower petals + short banner when profile hits 100% completion.
  static Future<void> showProfileCompleteCelebration(BuildContext context) async {
    if (!context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CelebrationLayer(
        variant: _CelebrationKind.profileComplete,
        onDone: () {
          entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

enum _CelebrationKind { interestSent, profileComplete, marriageFarewell }

class _CelebrationLayer extends StatefulWidget {
  final _CelebrationKind variant;
  final VoidCallback onDone;

  const _CelebrationLayer({
    required this.variant,
    required this.onDone,
  });

  @override
  State<_CelebrationLayer> createState() => _CelebrationLayerState();
}

class _CelebrationLayerState extends State<_CelebrationLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  List<_Sparkle>? _sparkles;
  List<_Petal>? _petals;

  @override
  void initState() {
    super.initState();
    final marriage = widget.variant == _CelebrationKind.marriageFarewell;
    final profileComplete = widget.variant == _CelebrationKind.profileComplete;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: marriage
            ? 2600
            : profileComplete
                ? 1450
                : 950,
      ),
    );
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onDone();
      }
    });
    _ctrl.forward();
  }

  void _ensureParticles(Size size) {
    if (_sparkles != null) return;
    final rnd = math.Random();
    final marriage = widget.variant == _CelebrationKind.marriageFarewell;
    final profileComplete = widget.variant == _CelebrationKind.profileComplete;
    final w = size.width;
    final h = size.height;

    final sparkleCount = marriage ? 72 : profileComplete ? 58 : 42;
    final petalCount = marriage ? 38 : profileComplete ? 28 : 14;

    _sparkles = List.generate(sparkleCount, (i) {
      final baseX = w * (0.15 + rnd.nextDouble() * 0.7);
      final baseY = h *
          (marriage
              ? 0.12 + rnd.nextDouble() * 0.38
              : profileComplete
                  ? 0.18 + rnd.nextDouble() * 0.35
                  : 0.48 + rnd.nextDouble() * 0.22);
      return _Sparkle(
        origin: Offset(baseX, baseY),
        angle: rnd.nextDouble() * math.pi * 2,
        speed: 120 + rnd.nextDouble() * 220,
        color: [
          Colors.white,
          AppTheme.templeGold,
          AppTheme.primaryOrange,
          AppTheme.kumkumRed.withValues(alpha: 0.85),
        ][rnd.nextInt(4)],
        rot: rnd.nextDouble() * math.pi * 2,
      );
    });

    _petals = List.generate(petalCount, (i) {
      return _Petal(
        startX: rnd.nextDouble() * w,
        startY: -30 - rnd.nextDouble() * 140,
        drift: 40 + rnd.nextDouble() * 90,
        phase: rnd.nextDouble() * math.pi * 2,
        hue: rnd.nextBool()
            ? const Color(0xFFFFB7C5)
            : const Color(0xFFFFF3E0),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marriage = widget.variant == _CelebrationKind.marriageFarewell;
    final profileComplete = widget.variant == _CelebrationKind.profileComplete;
    final size = MediaQuery.sizeOf(context);
    _ensureParticles(size);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_ctrl.value);
          return Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _CelebrationPainter(
                    t: t,
                    sparkles: _sparkles!,
                    petals: _petals!,
                    marriage: marriage,
                    profileComplete: profileComplete,
                  ),
                ),
                if (marriage) _MarriageBanner(t: _ctrl.value),
                if (profileComplete) _ProfileCompleteBanner(t: _ctrl.value),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileCompleteBanner extends StatelessWidget {
  final double t;

  const _ProfileCompleteBanner({required this.t});

  @override
  Widget build(BuildContext context) {
    final fadeOutStart = 0.72;
    final opacity = (t * 2.4).clamp(0.0, 1.0) *
        (t < fadeOutStart
            ? 1.0
            : ((1.0 - (t - fadeOutStart) / (1.0 - fadeOutStart))).clamp(0.0, 1.0));
    final scale =
        0.9 + 0.1 * Curves.easeOutBack.transform((t * 2).clamp(0.0, 1.0));
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryOrange.withValues(alpha: 0.95),
                  AppTheme.templeGold.withValues(alpha: 0.92),
                  AppTheme.sacredGreen.withValues(alpha: 0.88),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryOrange.withValues(alpha: 0.35),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🌸  ✨  🌺',
                  style: TextStyle(fontSize: 30, height: 1.1),
                ),
                const SizedBox(height: 8),
                Text(
                  'Profile 100% complete!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                          blurRadius: 6,
                          color: Colors.black26,
                          offset: Offset(0, 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You\'re ready to connect — wishing you the best!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.95),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarriageBanner extends StatelessWidget {
  final double t;

  const _MarriageBanner({required this.t});

  @override
  Widget build(BuildContext context) {
    final fadeOutStart = 0.68;
    final opacity = (t * 2.2).clamp(0.0, 1.0) *
        (t < fadeOutStart
            ? 1.0
            : ((1.0 - (t - fadeOutStart) / (1.0 - fadeOutStart))).clamp(0.0, 1.0));
    final scale = 0.88 + 0.12 * Curves.easeOutBack.transform((t * 1.8).clamp(0.0, 1.0));
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.sacredGreen.withValues(alpha: 0.95),
                  const Color(0xFF2E7D32),
                  AppTheme.primaryOrange.withValues(alpha: 0.88),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.templeGold.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🌸  💒  🌺',
                  style: TextStyle(fontSize: 34, height: 1.1),
                ),
                const SizedBox(height: 10),
                Text(
                  'Congratulations!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                          blurRadius: 8,
                          color: Colors.black26,
                          offset: Offset(0, 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wishing you a beautiful, blessed married life together.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.95),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sparkle {
  final Offset origin;
  final double angle;
  final double speed;
  final Color color;
  final double rot;

  _Sparkle({
    required this.origin,
    required this.angle,
    required this.speed,
    required this.color,
    required this.rot,
  });
}

class _Petal {
  final double startX;
  final double startY;
  final double drift;
  final double phase;
  final Color hue;

  _Petal({
    required this.startX,
    required this.startY,
    required this.drift,
    required this.phase,
    required this.hue,
  });
}

class _CelebrationPainter extends CustomPainter {
  final double t;
  final List<_Sparkle> sparkles;
  final List<_Petal> petals;
  final bool marriage;
  final bool profileComplete;

  _CelebrationPainter({
    required this.t,
    required this.sparkles,
    required this.petals,
    required this.marriage,
    this.profileComplete = false,
  });

  double get _vignetteAlpha {
    if (marriage) return 0.08;
    if (profileComplete) return 0.065;
    return 0.05;
  }

  double get _sparkleSpread {
    if (marriage) return 1.05;
    if (profileComplete) return 0.96;
    return 0.82;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.amber.withValues(alpha: _vignetteAlpha),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide * 0.95,
      ));
    canvas.drawRect(Offset.zero & size, bg);

    for (final p in petals) {
      final y = p.startY +
          size.height * 0.88 * t +
          math.sin(t * math.pi * 3 + p.phase) * 20 * t;
      final x = p.startX +
          math.sin(t * math.pi * 2 + p.phase * 1.3) * p.drift * t * 0.38;
      final op = (0.5 * (1 - t * 0.4)).clamp(0.0, 0.5);
      _drawPetal(canvas, Offset(x, y), p.hue.withValues(alpha: op), 0.42 + t * 0.55);
    }

    for (final s in sparkles) {
      final dist = s.speed * t * _sparkleSpread;
      final pos = s.origin +
          Offset(math.cos(s.angle), math.sin(s.angle)) * dist;
      final fade = ((1.0 - t) * (1.0 - t * 0.15)).clamp(0.0, 1.0);
      final r = 2.5 + 6.5 * (1 - t);
      _drawSparkle(
        canvas,
        pos,
        s.color.withValues(alpha: 0.12 + 0.78 * fade),
        r,
        s.rot + t * 4.2,
      );
    }
  }

  void _drawPetal(Canvas canvas, Offset c, Color color, double scale) {
    final p = Paint()..color = color;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    final path = Path()
      ..moveTo(0, -8)
      ..quadraticBezierTo(10, 0, 0, 14)
      ..quadraticBezierTo(-10, 0, 0, -8);
    canvas.drawPath(path, p);
    canvas.restore();
  }

  void _drawSparkle(Canvas canvas, Offset c, Color color, double r, double rot) {
    final p = Paint()
      ..color = color
      ..strokeWidth = math.max(1.2, r * 0.32)
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
      canvas.rotate(math.pi / 4);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.marriage != marriage ||
      oldDelegate.profileComplete != profileComplete;
}
