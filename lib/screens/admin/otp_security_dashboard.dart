import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/app_firebase_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../services/otp_security_service.dart';
import '../../theme/app_theme.dart';

/// Admin dashboard for monitoring OTP security
/// Shows rate limiting status, audit logs, and allows admin actions
class OtpSecurityDashboard extends StatefulWidget {
  final bool embedded;
  const OtpSecurityDashboard({super.key, this.embedded = false});

  @override
  State<OtpSecurityDashboard> createState() => _OtpSecurityDashboardState();
}

class _OtpSecurityDashboardState extends State<OtpSecurityDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _mpinUserIdController = TextEditingController();
  final TextEditingController _mpinValueController = TextEditingController();
  
  Map<String, dynamic>? _rateLimitStatus;
  List<Map<String, dynamic>> _otpAttempts = [];
  List<Map<String, dynamic>> _bindingFailures = [];
  List<Map<String, dynamic>> _rateLimitResets = [];
  
  bool _isLoading = false;

  /// Hash MPIN using same salt as auth_controller.dart for compatibility
  String _hashMpin(String mpin) {
    const salt = 'mana_matrimony_mpin_salt';
    return sha256.convert(utf8.encode('$salt$mpin')).toString();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSecurityData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mobileController.dispose();
    _mpinUserIdController.dispose();
    _mpinValueController.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      // Load audit logs
      final attempts = await OtpSecurityService.instance.getAuditLogs('otp_attempt');
      final bindingFailures = await OtpSecurityService.instance.getAuditLogs('session_binding_failed');
      final rateLimitResets = await OtpSecurityService.instance.getAuditLogs('rate_limit_reset');

      if (!mounted) return;
      setState(() {
        _otpAttempts = attempts.reversed.toList(); // Most recent first
        _bindingFailures = bindingFailures.reversed.toList();
        _rateLimitResets = rateLimitResets.reversed.toList();
      });
    } catch (e) {
      debugPrint('Failed to load security data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkRateLimit() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) {
      _showError('Please enter a mobile number');
      return;
    }

    try {
      final status = await OtpSecurityService.instance.getRateLimitStatus(mobile);
      if (!mounted) return;
      setState(() => _rateLimitStatus = status);
    } catch (e) {
      _showError('Failed to check rate limit: $e');
    }
  }

  Future<void> _resetRateLimit() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) {
      _showError('Please enter a mobile number');
      return;
    }

    try {
      await OtpSecurityService.instance.resetRateLimit(mobile);
      if (!mounted) return;
      setState(() {
        _rateLimitStatus = null;
      });
      _showSuccess('Rate limit reset successfully');
      await _loadSecurityData(); // Refresh data
    } catch (e) {
      _showError('Failed to reset rate limit: $e');
    }
  }

  Future<void> _clearAllOtpData() async {
    final confirmed = await _showConfirmationDialog(
      'Clear All OTP Data',
      'This will permanently delete all OTP verification data, rate limits, and audit logs for ALL users. This action cannot be undone.\n\nAre you sure?',
    );
    
    if (!confirmed) return;

    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      await OtpSecurityService.instance.clearAllOtpData();
      _showSuccess('All OTP verification data cleared successfully');
      await _loadSecurityData(); // Refresh data
    } catch (e) {
      _showError('Failed to clear all OTP data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setMpinDiagnostic() async {
    final userId = _mpinUserIdController.text.trim();
    final mpin = _mpinValueController.text.trim();
    if (userId.isEmpty) {
      _showError('Enter user doc ID');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(mpin)) {
      _showError('Enter a valid 4-digit MPIN');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await appFirebaseFunctions
          .httpsCallable('setUserMpinSecure')
          .call({
        'userId': userId,
        'mpin_hash': _hashMpin(mpin),
        'mobileNumber': '',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      _showSuccess('MPIN diagnostic success: ${data.toString()}');
    } on FirebaseFunctionsException catch (e) {
      _showError('MPIN diagnostic failed: ${e.code} ${e.message ?? ''}'.trim());
    } catch (e) {
      _showError('MPIN diagnostic failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.kumkumRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.sacredGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildMainContent();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Security Dashboard'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildRateLimitChecker(),
        const SizedBox(height: 16),
        _buildTabBar(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildTabBarView(),
        ),
      ],
    );
  }

  Widget _buildRateLimitChecker() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate Limit Checker',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Enter mobile number',
                      border: OutlineInputBorder(),
                      prefixText: '+91 ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _checkRateLimit,
                  child: const Text('Check'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _clearAllOtpData,
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'MPIN Diagnostic (Callable)',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mpinUserIdController,
              decoration: const InputDecoration(
                hintText: 'Enter user doc ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mpinValueController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                hintText: 'Enter 4-digit MPIN (test only)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _setMpinDiagnostic,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Test setUserMpinSecure'),
              ),
            ),
            if (_rateLimitStatus != null) ...[
              const SizedBox(height: 12),
              _buildRateLimitStatus(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRateLimitStatus() {
    final status = _rateLimitStatus!;
    final isLimited = status['is_limited'] as bool;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLimited ? Colors.red.shade50 : Colors.green.shade50,
        border: Border.all(
          color: isLimited ? Colors.red.shade200 : Colors.green.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLimited ? Icons.block : Icons.check_circle,
                color: isLimited ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                isLimited ? 'RATE LIMITED' : 'NOT LIMITED',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: isLimited ? Colors.red : Colors.green,
                ),
              ),
              if (isLimited) ...[
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await _showConfirmationDialog(
                      'Reset Rate Limit',
                      'Reset rate limit for +91${_mobileController.text.trim()}?',
                    );
                    if (ok) await _resetRateLimit();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('Attempts: ${status['attempts']}/${status['max_attempts']}'),
          if (status['reset_time'] != null)
            Text('Resets at: ${_formatDateTime(status['reset_time'])}'),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'OTP Attempts'),
        Tab(text: 'Binding Failures'),
        Tab(text: 'Rate Resets'),
      ],
      labelColor: AppTheme.primaryOrange,
      indicatorColor: AppTheme.primaryOrange,
    );
  }

  Widget _buildTabBarView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildAuditLog(_otpAttempts, 'otp_attempt'),
        _buildAuditLog(_bindingFailures, 'session_binding_failed'),
        _buildAuditLog(_rateLimitResets, 'rate_limit_reset'),
      ],
    );
  }

  Widget _buildAuditLog(List<Map<String, dynamic>> logs, String logType) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${_getLogTypeName(logType)} yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogCard(log, logType);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, String logType) {
    final data = log['data'] as Map<String, dynamic>;
    final timestamp = log['timestamp'] as String;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getLogIcon(logType),
                  color: _getLogColor(logType),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getLogTypeName(logType),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatTimeAgo(timestamp),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._buildLogDetails(data, logType),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLogDetails(Map<String, dynamic> data, String logType) {
    switch (logType) {
      case 'otp_attempt':
        return [
          _buildDetailRow('Mobile', '+91${data['mobile']}'),
          _buildDetailRow('Attempts', '${data['attempts']}'),
        ];
      case 'session_binding_failed':
        return [
          _buildDetailRow('Mobile', '+91${data['mobile']}'),
          _buildDetailRow('Reason', 'Device fingerprint mismatch'),
        ];
      case 'rate_limit_reset':
        return [
          _buildDetailRow('Mobile', '+91${data['mobile']}'),
          _buildDetailRow('Action', 'Rate limit manually reset'),
        ];
      default:
        return [];
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getLogIcon(String logType) {
    switch (logType) {
      case 'otp_attempt':
        return Icons.sms;
      case 'session_binding_failed':
        return Icons.security;
      case 'rate_limit_reset':
        return Icons.refresh;
      default:
        return Icons.info;
    }
  }

  Color _getLogColor(String logType) {
    switch (logType) {
      case 'otp_attempt':
        return Colors.blue;
      case 'session_binding_failed':
        return Colors.orange;
      case 'rate_limit_reset':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getLogTypeName(String logType) {
    switch (logType) {
      case 'otp_attempt':
        return 'OTP Attempt';
      case 'session_binding_failed':
        return 'Device Binding Failed';
      case 'rate_limit_reset':
        return 'Rate Limit Reset';
      default:
        return 'Unknown Event';
    }
  }

  String _formatDateTime(String isoString) {
    final dateTime = DateTime.parse(isoString);
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatTimeAgo(String isoString) {
    final dateTime = DateTime.parse(isoString);
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

}
