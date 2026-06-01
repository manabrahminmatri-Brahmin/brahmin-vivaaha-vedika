import 'dart:async';
import 'package:flutter/material.dart';
import '../services/presence_service.dart';

Widget buildStatus(Map<String, dynamic> user) {
  final presence = PresenceData.fromMap(user).applyStaleness();
  if (presence.isOnline) {
    return const Text('Live now', style: TextStyle(color: Colors.green));
  }
  return Text(presence.lastSeenText, style: const TextStyle(color: Colors.grey));
}

/// Enhanced online status widget with better formatting
class OnlineStatusWidget extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool showIcon;

  const OnlineStatusWidget({
    super.key,
    required this.user,
    this.showIcon = true,
  });

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = PresenceData.fromMap(widget.user).applyStaleness();
    final isOnline = presence.isOnline;

    if (isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            'Live now',
            style: TextStyle(
              color: Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showIcon) ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          presence.lastSeenText,
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
