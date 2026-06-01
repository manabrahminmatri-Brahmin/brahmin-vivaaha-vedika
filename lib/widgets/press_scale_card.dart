import 'package:flutter/material.dart';

/// Light press-scale feedback for tappable cards (Home / Matches profile rows).
class PressScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const PressScaleCard({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<PressScaleCard> createState() => _PressScaleCardState();
}

class _PressScaleCardState extends State<PressScaleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 160),
      value: 1.0,
    );
    _scale = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // deferToChild (default): avoids "Cannot hit test a render box with no size"
    // when the scaled child lays out at zero (e.g. transient/empty row).
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTap: () {
        _ctrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
