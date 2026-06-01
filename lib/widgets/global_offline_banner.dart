import 'dart:async';

import 'package:flutter/material.dart';

import '../services/network_service.dart';
import '../theme/app_theme.dart';

/// Non-blocking banner when device has no network (Wi‑Fi / mobile data off).
class GlobalOfflineBanner extends StatefulWidget {
  final Widget child;

  const GlobalOfflineBanner({super.key, required this.child});

  @override
  State<GlobalOfflineBanner> createState() => _GlobalOfflineBannerState();
}

class _GlobalOfflineBannerState extends State<GlobalOfflineBanner> {
  late bool _online;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _online = NetworkService.isConnected;
    _sub = NetworkService.connectionStream.listen((ok) {
      if (mounted) setState(() => _online = ok);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_online)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 6,
              color: AppTheme.kumkumRed,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No Internet Connection',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Check your Wi-Fi or mobile data settings',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withAlpha(230),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
