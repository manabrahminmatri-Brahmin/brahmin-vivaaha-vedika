import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/admin_support_service.dart';
import '../../theme/app_theme.dart';
import '../support/support_chat_screen.dart';

/// Admin dashboard inbox for in-app support threads.
class AdminSupportInboxTab extends StatelessWidget {
  const AdminSupportInboxTab({super.key});

  String _formatTime(dynamic raw) {
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AdminSupportService.watchAdminInbox(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        final rows = snap.data ?? [];
        if (snap.connectionState == ConnectionState.waiting && rows.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No support chats yet.\nMembers can start from Help & Support.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final t = rows[i];
            final threadId = (t['thread_id'] as String? ?? '').trim();
            final name = (t['user_display_name'] as String? ?? 'Member').trim();
            final mobile = (t['user_mobile'] as String? ?? '').trim();
            final profileId = (t['user_profile_id'] as String? ?? '').trim();
            final preview = (t['last_message'] as String? ?? '').trim();
            final unread = (t['unread_admin'] as num?)?.toInt() ?? 0;
            final updated = t['updated_at'];

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryOrange.withAlpha(40),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (profileId.isNotEmpty) 'ID: $profileId',
                  if (mobile.isNotEmpty) mobile,
                  if (preview.isNotEmpty) preview,
                ].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(updated),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.kumkumRed,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                if (threadId.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportChatScreen.admin(
                      threadId: threadId,
                      memberDisplayName: name,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
