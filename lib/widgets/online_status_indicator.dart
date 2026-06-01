import 'dart:async';
import 'package:flutter/material.dart';
import '../services/presence_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OnlineStatusIndicator
//
// A live-updating badge that shows whether [userId] is currently online and,
// if not, how long ago they were last active.
//
// Usage (compact dot only — e.g. on a profile photo):
//   OnlineStatusIndicator(userId: user.id)
//
// Usage (dot + label — e.g. in profile detail header):
//   OnlineStatusIndicator(userId: user.id, showLabel: true)
// ─────────────────────────────────────────────────────────────────────────────

class OnlineStatusIndicator extends StatefulWidget {
  const OnlineStatusIndicator({
    super.key,
    required this.userId,
    this.showLabel = false,
    this.dotSize = 10.0,
    this.labelStyle,
  });

  final String userId;

  /// When true, shows "Online now" / "Last seen Xm ago" text beside the dot.
  final bool showLabel;

  /// Diameter of the green/grey dot. Defaults to 10.
  final double dotSize;

  /// Override text style for the label.
  final TextStyle? labelStyle;

  @override
  State<OnlineStatusIndicator> createState() => _OnlineStatusIndicatorState();
}

class _OnlineStatusIndicatorState extends State<OnlineStatusIndicator> {
  Timer? _labelRefreshTimer;

  @override
  void initState() {
    super.initState();
    _configureTimer();
  }

  void _configureTimer() {
    _labelRefreshTimer?.cancel();
    // Tick periodically so stale "online" decays to grey without waiting for
    // another Firestore snapshot, and labels like "5m ago" stay current.
    _labelRefreshTimer =
        Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _labelRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = PresenceService();
    return StreamBuilder<PresenceData>(
      stream: presence.watchUser(widget.userId),
      initialData: presence.lastPresenceFor(widget.userId),
      builder: (context, snapshot) {
        // Use available data, fallback to unknown on error or no data
        PresenceData data;
        if (snapshot.hasError) {
          debugPrint(
              '⚠️ OnlineStatusIndicator: stream error for ${widget.userId}: ${snapshot.error}');
          data = PresenceData.unknown();
        } else {
          data = (snapshot.data ?? PresenceData.unknown()).applyStaleness();
        }

        return _StatusBadge(
          data: data,
          showLabel: widget.showLabel,
          dotSize: widget.dotSize,
          labelStyle: widget.labelStyle,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal badge widget (no async — just renders PresenceData)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.data,
    required this.showLabel,
    required this.dotSize,
    this.labelStyle,
  });

  final PresenceData data;
  final bool showLabel;
  final double dotSize;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final color =
        data.isOnline ? const Color(0xFF22C55E) : Colors.grey.shade400;
    final dotBorder = AC.card(context);

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: dotBorder, width: dotSize * 0.18),
        boxShadow: data.isOnline
            ? [
                BoxShadow(
                  color: color.withAlpha(120),
                  blurRadius: dotSize * 0.8,
                  spreadRadius: dotSize * 0.1,
                ),
              ]
            : null,
      ),
    );

    if (!showLabel) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing animation only when online
        data.isOnline
            ? _PulsingDot(
                dotSize: dotSize,
                color: color,
                borderColor: dotBorder,
              )
            : dot,
        const SizedBox(width: 6),
        Text(
          data.lastSeenText,
          style: (labelStyle ??
              TextStyle(
                fontSize: 12,
                color: data.isOnline
                    ? const Color(0xFF22C55E)
                    : Colors.grey.shade500,
                fontWeight: data.isOnline ? FontWeight.w600 : FontWeight.normal,
              )),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing green dot (shown only when the user is online)
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({
    required this.dotSize,
    required this.color,
    required this.borderColor,
  });
  final double dotSize;
  final Color color;
  final Color borderColor;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _scale = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.dotSize;
    return SizedBox(
      width: size * 1.8,
      height: size * 1.8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ring
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Transform.scale(
              scale: _scale.value,
              child: Opacity(
                opacity: _opacity.value,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          // Solid dot
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: widget.borderColor, width: size * 0.18),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withAlpha(100),
                  blurRadius: size * 0.6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live "Live now" / "Last seen …" label (Firestore stream, not cached User).
// ─────────────────────────────────────────────────────────────────────────────

class LivePresenceLabel extends StatefulWidget {
  const LivePresenceLabel({
    super.key,
    required this.userId,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.compact = false,
  });

  final String userId;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final bool compact;

  @override
  State<LivePresenceLabel> createState() => _LivePresenceLabelState();
}

class _LivePresenceLabelState extends State<LivePresenceLabel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.userId.trim();
    if (id.isEmpty) return const SizedBox.shrink();

    final presence = PresenceService();
    return StreamBuilder<PresenceData>(
      stream: presence.watchUser(id),
      initialData: presence.lastPresenceFor(id),
      builder: (context, snapshot) {
        final data = snapshot.hasError
            ? PresenceData.unknown()
            : (snapshot.data ?? PresenceData.unknown()).applyStaleness();

        final defaultStyle = TextStyle(
          fontSize: widget.compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: data.isOnline
              ? const Color(0xFF22C55E)
              : Colors.grey.shade600,
          height: 1.2,
        );

        return Text(
          data.lastSeenText,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: widget.style ?? defaultStyle,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience overlay — wraps any widget and adds a dot in the corner.
// Useful for profile photo stacks.
//
// Example:
//   OnlineStatusOverlay(userId: user.id, child: CircleAvatar(...))
// ─────────────────────────────────────────────────────────────────────────────

class OnlineStatusOverlay extends StatefulWidget {
  const OnlineStatusOverlay({
    super.key,
    required this.userId,
    required this.child,
    this.dotSize = 12.0,
    this.alignment = Alignment.bottomRight,
  });

  final String userId;
  final Widget child;
  final double dotSize;
  final Alignment alignment;

  @override
  State<OnlineStatusOverlay> createState() => _OnlineStatusOverlayState();
}

class _OnlineStatusOverlayState extends State<OnlineStatusOverlay> {
  Timer? _stalenessTimer;

  @override
  void initState() {
    super.initState();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stalenessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = PresenceService();
    return StreamBuilder<PresenceData>(
      stream: presence.watchUser(widget.userId),
      initialData: presence.lastPresenceFor(widget.userId),
      builder: (context, snapshot) {
        final PresenceData data;
        if (snapshot.hasError) {
          data = PresenceData.unknown();
        } else {
          data = (snapshot.data ?? PresenceData.unknown()).applyStaleness();
        }
        final hasError = snapshot.hasError;

        // Show dot for online users (green), offline users (grey), or on error
        final showDot = data.isOnline || !data.isOnline || hasError;
        final dotColor = data.isOnline
            ? const Color(0xFF22C55E) // Green for online
            : Colors.grey.shade400; // Grey for offline/unknown

        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (showDot)
              Positioned(
                right: widget.alignment == Alignment.bottomRight ||
                        widget.alignment == Alignment.topRight
                    ? 0
                    : null,
                left: widget.alignment == Alignment.bottomLeft ||
                        widget.alignment == Alignment.topLeft
                    ? 0
                    : null,
                bottom: widget.alignment == Alignment.bottomRight ||
                        widget.alignment == Alignment.bottomLeft
                    ? 0
                    : null,
                top: widget.alignment == Alignment.topRight ||
                        widget.alignment == Alignment.topLeft
                    ? 0
                    : null,
                child: data.isOnline
                    ? _PulsingDot(
                        dotSize: widget.dotSize,
                        color: dotColor,
                        borderColor: AC.card(context),
                      )
                    : Container(
                        width: widget.dotSize,
                        height: widget.dotSize,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AC.card(context),
                            width: widget.dotSize * 0.18,
                          ),
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }
}
