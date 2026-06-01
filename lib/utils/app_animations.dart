import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AppAnimations — single source of truth for EVERY animation in the app.
///
/// Rules:
///   • Screen transitions  → AppTransitions.slide()   (280 ms, easeOutCubic)
///   • Tab switches        → AppAnimations.tabSwitch  (fade, 180 ms)
///   • Bottom sheets       → AppAnimations.bottomSheet (slide-up, 260 ms)
///   • Content entry       → AppAnimations.contentEntry extensions (fade+slideY)
///   • Dialogs             → AppAnimations.dialog (fade+scale, 200 ms)
///
/// Never use flutter_animate delays > 400 ms, never mix slideX/slideY directions.
/// ─────────────────────────────────────────────────────────────────────────────
class AppAnimations {
  AppAnimations._();

  // ── Durations ───────────────────────────────────────────────────────────────
  static const Duration fast     = Duration(milliseconds: 100);  // Reduced from 180ms for faster tab switching
  static const Duration normal   = Duration(milliseconds: 260);
  static const Duration slow     = Duration(milliseconds: 360);

  // ── Curves ──────────────────────────────────────────────────────────────────
  static const Curve curve       = Curves.easeOut;  // Faster than easeOutCubic for tab switching
  static const Curve curveIn     = Curves.easeIn;

  // ── Stagger step (for lists/cards entering sequentially) ────────────────────
  static const Duration stagger  = Duration(milliseconds: 60);

  // ── Tab switch ──────────────────────────────────────────────────────────────
  /// Wrap IndexedStack with this to animate tab changes with quick fade.
  static Widget tabSwitch({
    required int index,
    required List<Widget> children,
  }) {
    return _AnimatedIndexedStack(index: index, children: children);
  }

  // ── Bottom sheet helper ─────────────────────────────────────────────────────
  /// Use instead of showModalBottomSheet everywhere.
  static Future<T?> showSheet<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      builder: (_) => child,
    );
  }

  // ── Dialog helper ───────────────────────────────────────────────────────────
  /// Use instead of showDialog everywhere — identical fade+scale on all screens.
  static Future<T?> showAppDialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dialog',
      barrierColor: Colors.black54,
      transitionDuration: fast,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

// ── Content entry animation extensions ────────────────────────────────────────
/// Consistent flutter_animate presets.  Use these instead of raw .animate().
///
/// Usage:
///   myWidget.appFadeIn()
///   myWidget.appFadeIn(delay: AppAnimations.stagger * 2)
///   myWidget.appSlideIn()          // slides up from below
///   myWidget.appSlideIn(i: 3)      // auto-staggered by index
extension AppAnimateExtension on Widget {
  /// Fade in — use for static content blocks.
  Widget appFadeIn({Duration delay = Duration.zero}) {
    return animate()
        .fadeIn(duration: AppAnimations.normal, curve: AppAnimations.curve, delay: delay);
  }

  /// Fade + slide up — use for cards and list items.
  Widget appSlideIn({int i = 0, Duration baseDelay = Duration.zero}) {
    final delay = baseDelay + AppAnimations.stagger * i;
    return animate()
        .fadeIn(duration: AppAnimations.normal, curve: AppAnimations.curve, delay: delay)
        .slideY(
          begin: 0.08,
          end: 0,
          duration: AppAnimations.normal,
          curve: AppAnimations.curve,
          delay: delay,
        );
  }

  /// Fade + scale up — use for hero containers and featured cards.
  Widget appScaleIn({Duration delay = Duration.zero}) {
    return animate()
        .fadeIn(duration: AppAnimations.slow, curve: AppAnimations.curve, delay: delay)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          duration: AppAnimations.slow,
          curve: AppAnimations.curve,
          delay: delay,
        );
  }
}

// ── Internal: AnimatedIndexedStack (with directional slide animations) ────────────────────────────────
class _AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _AnimatedIndexedStack({required this.index, required this.children});

  @override
  State<_AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<_AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  // FIX 2: Track _displayIndex (what the IndexedStack currently shows) and
  // _slideDirection separately. _displayIndex is only updated inside setState
  // BEFORE forward() runs — this means _slideDirection is set at the right
  // time and never falls back to Offset.zero due to equal index comparison.
  int _displayIndex = 0;
  Offset _slideDirection = Offset.zero;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: AppAnimations.curve);
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Compute direction NOW — before _displayIndex changes — so we know
      // which way the new screen slides in from.
      final isForward = widget.index > old.index;
      _slideDirection = isForward
          ? const Offset(0.12, 0)   // new screen enters from right
          : const Offset(-0.12, 0); // new screen enters from left

      _controller.reverse().then((_) {
        if (mounted) {
          setState(() => _displayIndex = widget.index);
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: _slideDirection,
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: AppAnimations.curve,
          )),
          child: FadeTransition(
            opacity: _opacity,
            child: IndexedStack(index: _displayIndex, children: widget.children),
          ),
        );
      },
    );
  }
}
