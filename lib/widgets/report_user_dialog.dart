import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/block_report.dart';
import '../services/block_service.dart';

/// Dialog to report a user with reason selection
class ReportUserDialog extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final VoidCallback? onReported;

  const ReportUserDialog({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.onReported,
  });

  @override
  State<ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends State<ReportUserDialog> {
  ReportReason? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Report User',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.reportedUserName,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Why are you reporting this user?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...ReportReason.values.map((reason) => _buildReasonTile(reason)),
            const SizedBox(height: 16),
            const Text(
              'Additional details (optional):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Provide more context about the issue...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedReason == null
              ? null
              : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }

  Widget _buildReasonTile(ReportReason reason) {
    final isSelected = _selectedReason == reason;
    
    return InkWell(
      onTap: () => setState(() => _selectedReason = reason),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.withAlpha(20) : Colors.grey[100],
          border: Border.all(
            color: isSelected ? Colors.red : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Radio<ReportReason>(
              value: reason,
              // ignore: deprecated_member_use
              groupValue: _selectedReason,
              // ignore: deprecated_member_use
              onChanged: (value) => setState(() => _selectedReason = value),
              activeColor: Colors.red,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.red : Colors.black87,
                    ),
                  ),
                  Text(
                    reason.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) return;

    setState(() => _isSubmitting = true);

    try {
      // 🔥 FIX: Use Provider singleton instead of creating new instance
      final blockService = context.read<BlockService>();
      await blockService.reportUser(
        reportedId: widget.reportedUserId,
        reason: _selectedReason!.label,
        details: _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
        reporterId: null, // Will use current Firebase Auth user
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you for helping keep our community safe.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReported?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Confirmation dialog for blocking a user
class BlockUserDialog extends StatelessWidget {
  final String userName;
  final VoidCallback onConfirm;

  const BlockUserDialog({
    super.key,
    required this.userName,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.block, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          const Text('Block User'),
        ],
      ),
      content: Text(
        'Are you sure you want to block $userName?\n\n'
        'They will not be able to:\n'
        '• View your profile\n'
        '• Send you messages\n'
        '• See you in matches\n\n'
        'You can unblock them anytime from your settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Block'),
        ),
      ],
    );
  }
}

/// Menu button for block/report actions
class BlockReportMenu extends StatelessWidget {
  final String targetUserId;
  final String targetUserName;
  final VoidCallback? onBlocked;
  final VoidCallback? onReported;

  const BlockReportMenu({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    this.onBlocked,
    this.onReported,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Block User', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.flag, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text('Report User', style: TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      ],
    );
  }

  void _handleSelection(BuildContext context, String value) {
    switch (value) {
      case 'block':
        showDialog(
          context: context,
          builder: (context) => BlockUserDialog(
            userName: targetUserName,
            onConfirm: () async {
              try {
                // 🔥 FIX: Use Provider singleton instead of creating new instance
                final blockService = context.read<BlockService>();
                await blockService.blockUser(
                  profileId: targetUserId,
                  name: targetUserName,
                );
                onBlocked?.call();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$targetUserName has been blocked'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to block user: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        );
        break;
      case 'report':
        showDialog(
          context: context,
          builder: (context) => ReportUserDialog(
            reportedUserId: targetUserId,
            reportedUserName: targetUserName,
            onReported: onReported,
          ),
        );
        break;
    }
  }
}
