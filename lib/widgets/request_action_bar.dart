import 'package:flutter/material.dart';

class RequestActionItem {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isPrimary;
  final Color? color;

  const RequestActionItem({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.isPrimary = false,
    this.color,
  });
}

class RequestActionBar extends StatelessWidget {
  final RequestActionItem first;
  final RequestActionItem second;
  final double collapseBreakpoint;
  final EdgeInsetsGeometry? padding;

  const RequestActionBar({
    super.key,
    required this.first,
    required this.second,
    this.collapseBreakpoint = 340,
    this.padding,
  });

  Widget _buildButton(BuildContext context, RequestActionItem item) {
    final iconWidget = item.isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(item.icon, size: 16);

    if (item.isPrimary) {
      return ElevatedButton.icon(
        onPressed: item.onPressed,
        icon: iconWidget,
        label: Text(item.label),
        style: ElevatedButton.styleFrom(
          backgroundColor: item.color ?? Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: item.onPressed,
      icon: iconWidget,
      label: Text(item.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: item.color,
        side: item.color != null ? BorderSide(color: item.color!) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final collapse = constraints.maxWidth < collapseBreakpoint;
          final firstBtn = _buildButton(context, first);
          final secondBtn = _buildButton(context, second);
          if (collapse) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                firstBtn,
                const SizedBox(height: 8),
                secondBtn,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: firstBtn),
              const SizedBox(width: 8),
              Expanded(child: secondBtn),
            ],
          );
        },
      ),
    );
  }
}
