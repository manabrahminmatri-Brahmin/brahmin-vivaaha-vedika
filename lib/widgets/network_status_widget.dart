import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/network_connectivity_service.dart';
import '../theme/app_theme.dart';

/// Widget to display network connectivity status
class NetworkStatusWidget extends StatefulWidget {
  final bool showWhenOnline;
  final VoidCallback? onRetry;

  const NetworkStatusWidget({
    super.key,
    this.showWhenOnline = false,
    this.onRetry,
  });

  @override
  State<NetworkStatusWidget> createState() => _NetworkStatusWidgetState();
}

class _NetworkStatusWidgetState extends State<NetworkStatusWidget> {
  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // Start monitoring if not already started
    _networkService.startConnectivityMonitoring();
  }

  Future<void> _retryConnection() async {
    setState(() => _isChecking = true);
    
    await _networkService.isBackendReachable();
    
    if (!mounted) return;
    setState(() => _isChecking = false);
    
    if (widget.onRetry != null) {
      widget.onRetry!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _networkService.connectivityStream,
      initialData: _networkService.isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? true;
        
        // Hide if online and showWhenOnline is false
        if (isOnline && !widget.showWhenOnline) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isOnline ? AppTheme.sacredGreen.withValues(alpha: 0.1) : AppTheme.kumkumRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOnline ? AppTheme.sacredGreen : AppTheme.kumkumRed,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOnline ? AppTheme.sacredGreen.withValues(alpha: 0.2) : AppTheme.kumkumRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      color: isOnline ? AppTheme.sacredGreen : AppTheme.kumkumRed,
                      size: 56,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      isOnline ? 'Connected to Internet' : 'No Internet Connection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isOnline ? AppTheme.sacredGreen : AppTheme.kumkumRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              
              if (!isOnline) ...[
                const SizedBox(height: 12),
                
                // Error message
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.kumkumRed.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Issues:',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.kumkumRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _networkService.getErrorMessage(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.kumkumRed,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Retry button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _retryConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Retry Connection'),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Suggestions
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AC.surface2(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Try these solutions:',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSuggestion('• Switch to mobile hotspot'),
                      _buildSuggestion('• Try different WiFi network'),
                      _buildSuggestion('• Check if backend service is running'),
                      _buildSuggestion('• Restart app/emulator'),
                      _buildSuggestion('• Check firewall settings'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ).animate().scale(duration: 300.ms).fadeIn();
      },
    );
  }

  Widget _buildSuggestion(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AC.textMuted(context),
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Compact network status indicator
class CompactNetworkStatus extends StatelessWidget {
  const CompactNetworkStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NetworkConnectivityService().connectivityStream,
      initialData: NetworkConnectivityService().isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? true;
        
        if (isOnline) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.kumkumRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.kumkumRed, width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.wifi_off,
                  color: AppTheme.kumkumRed,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No Internet Connection',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.kumkumRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
