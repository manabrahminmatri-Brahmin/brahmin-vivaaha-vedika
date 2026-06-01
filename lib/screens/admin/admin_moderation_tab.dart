import 'package:flutter/material.dart';

import '../../services/admin_moderation_service.dart';
import '../../theme/app_theme.dart';

/// Reports, security audit trail, and moderation queue (admin-only reads).
class AdminModerationTab extends StatelessWidget {
  const AdminModerationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final mod = AdminModerationService.instance;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: AppTheme.primaryOrange,
            tabs: [
              Tab(text: 'Reports'),
              Tab(text: 'Audit log'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: mod.watchOpenReports(),
                  builder: (context, snap) {
                    final rows = snap.data ?? [];
                    if (snap.hasError) {
                      return Center(child: Text('${snap.error}'));
                    }
                    if (rows.isEmpty) {
                      return const Center(child: Text('No open reports'));
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        return ListTile(
                          title: Text(
                            (r['type'] as String?) ?? 'report',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Reporter: ${r['reporter_id'] ?? '—'}\n'
                            'Reported: ${r['reported_user_id'] ?? r['target_user_id'] ?? '—'}\n'
                            '${r['reason'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: Text((r['status'] as String?) ?? 'open'),
                        );
                      },
                    );
                  },
                ),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: mod.watchSecurityAuditLogs(),
                  builder: (context, snap) {
                    final rows = snap.data ?? [];
                    if (snap.hasError) {
                      return Center(child: Text('${snap.error}'));
                    }
                    if (rows.isEmpty) {
                      return const Center(child: Text('No audit events'));
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            (r['event'] as String?) ?? 'event',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Actor: ${r['actor_user_id'] ?? '—'}\n'
                            'Target: ${r['target_user_id'] ?? '—'}\n'
                            'Doc: ${r['document_id'] ?? '—'}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
