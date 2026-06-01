import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// OFF/ON (or custom) labels beside an adaptive [Switch], scaled to fit tight rows.
class LabeledAdaptiveSwitch extends StatelessWidget {
  const LabeledAdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.inactiveLabel = 'OFF',
    this.activeLabel = 'ON',
    this.semanticsPrefix = '',
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String inactiveLabel;
  final String activeLabel;
  final String semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppTheme.primaryOrange;
    final muted = AC.textMuted(context);
    final semLabel = semanticsPrefix.isEmpty
        ? (value ? activeLabel : inactiveLabel)
        : '$semanticsPrefix: ${value ? activeLabel : inactiveLabel}';

    return Semantics(
      label: semLabel,
      toggled: value,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              inactiveLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: value ? muted : accent,
                  ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: cs.onPrimary,
                activeTrackColor: accent,
                inactiveThumbColor: cs.surfaceContainerHighest,
                inactiveTrackColor: muted.withAlpha(120),
              ),
            ),
            Text(
              activeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: value ? accent : muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + title/subtitle with a labeled switch; stacks on narrow widths.
class SettingRowWithLabeledSwitch extends StatelessWidget {
  const SettingRowWithLabeledSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.switchValue,
    required this.onSwitchChanged,
    this.iconColor,
    this.inactiveLabel = 'OFF',
    this.activeLabel = 'ON',
    this.semanticsPrefix = '',
    this.trailing,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final bool switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final String inactiveLabel;
  final String activeLabel;
  final String semanticsPrefix;
  final Widget? trailing;

  static const double _stackBreakpoint = 360;

  @override
  Widget build(BuildContext context) {
    final control = trailing ??
        LabeledAdaptiveSwitch(
          value: switchValue,
          onChanged: onSwitchChanged,
          inactiveLabel: inactiveLabel,
          activeLabel: activeLabel,
          semanticsPrefix: semanticsPrefix,
        );

    final textBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor ?? AppTheme.primaryOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AC.text(context),
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AC.textSub(context),
                    ),
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textBlock,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: control),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor ?? AppTheme.primaryOrange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AC.text(context),
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                        ),
                  ),
                ],
              ),
            ),
            Flexible(fit: FlexFit.loose, child: control),
          ],
        );
      },
    );
  }
}
