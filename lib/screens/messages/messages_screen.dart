import 'package:flutter/material.dart';
import '../interests/interests_analytics_screen.dart';

/// MessagesScreen — consolidated into InterestsAnalyticsScreen.
///
/// Conversations (accepted mutual interests) now live in the Messages tab
/// (index 3) of the unified Interests hub. Every entry-point that previously
/// pushed MessagesScreen will now open the hub directly at that tab so the
/// user has full context: Overview, Received, Sent, Messages, Likes,
/// Views — all reachable with one swipe.
///
/// Routes.messages (/messages) still works via app_router.dart.
/// NavHelper.push(context, Routes.messages) continues to work unchanged.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const InterestsAnalyticsScreen(initialTabIndex: 3);
}
