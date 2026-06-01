import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/identity_service.dart';
import '../../services/admin_support_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

/// User ↔ admin support chat (banking-style help desk inbox).
class SupportChatScreen extends StatefulWidget {
  /// Member view: opens their own thread.
  const SupportChatScreen({super.key})
      : threadId = null,
        memberDisplayName = null,
        isAdminView = false;

  /// Admin view: reply to a member thread from dashboard.
  const SupportChatScreen.admin({
    super.key,
    required this.threadId,
    required this.memberDisplayName,
  }) : isAdminView = true;

  final String? threadId;
  final String? memberDisplayName;
  final bool isAdminView;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _resolvedThreadId;
  bool _bootstrapping = true;
  bool _sending = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.isAdminView) {
        final id = (widget.threadId ?? '').trim();
        if (id.isEmpty) {
          setState(() {
            _bootError = 'Invalid support thread';
            _bootstrapping = false;
          });
          return;
        }
        _resolvedThreadId = id;
        await AdminSupportService.markRead(threadId: id, asAdmin: true);
      } else {
        final userId = await IdentityService().getUserId();
        final threadId = await AdminSupportService.ensureUserThread(
          requesterId: userId,
        );
        if (threadId == null || threadId.isEmpty) {
          setState(() {
            _bootError = 'Could not start support chat. Try again.';
            _bootstrapping = false;
          });
          return;
        }
        _resolvedThreadId = threadId;
        await AdminSupportService.markRead(
          threadId: threadId,
          asAdmin: false,
          requesterId: userId,
        );
      }
    } catch (e) {
      _bootError = 'Could not open support chat: $e';
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
  }

  @override
  void dispose() {
    final threadId = _resolvedThreadId;
    if (threadId != null && threadId.isNotEmpty) {
      unawaited(
        AdminSupportService.markRead(
          threadId: threadId,
          asAdmin: widget.isAdminView,
        ),
      );
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final threadId = _resolvedThreadId;
    if (body.isEmpty || threadId == null || _sending) return;

    setState(() => _sending = true);
    try {
      final ok = await AdminSupportService.sendMessage(
        threadId: threadId,
        body: body,
        asAdmin: widget.isAdminView,
      );
      if (!mounted) return;
      if (ok) {
        _controller.clear();
        _scrollToBottom();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message. Try again.'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _title {
    if (widget.isAdminView) {
      final name = (widget.memberDisplayName ?? '').trim();
      return name.isEmpty ? 'Support reply' : name;
    }
    return 'Chat with Support';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(title: _title, showLogo: false),
      body: _bootstrapping
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryOrange),
            )
          : _bootError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _bootError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AC.textSub(context)),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (!widget.isAdminView)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          'Messages here reach our support team. You can also use Call or WhatsApp on Help & Support.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AC.textMuted(context),
                              ),
                        ),
                      ),
                    Expanded(child: _buildMessageList()),
                    _buildComposer(),
                  ],
                ),
    );
  }

  Widget _buildMessageList() {
    final threadId = _resolvedThreadId!;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AdminSupportService.watchMessages(threadId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final messages = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            messages.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }
        if (messages.isEmpty) {
          return const Center(child: Text('No messages yet'));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final m = messages[index];
            final role = (m['sender_role'] as String? ?? '').trim();
            final isMe = widget.isAdminView
                ? role == 'admin'
                : role == 'user';
            return _SupportBubble(
              isMe: isMe,
              body: (m['body'] as String? ?? '').trim(),
              label: (m['sender_label'] as String? ?? '').trim(),
              createdAt: m['created_at'],
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.isAdminView
                      ? 'Reply to member…'
                      : 'Type your question…',
                  filled: true,
                  fillColor: AC.surface(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AC.border(context)),
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportBubble extends StatelessWidget {
  const _SupportBubble({
    required this.isMe,
    required this.body,
    required this.label,
    this.createdAt,
  });

  final bool isMe;
  final String body;
  final String label;
  final dynamic createdAt;

  String _timeLabel() {
    Timestamp? ts;
    if (createdAt is Timestamp) ts = createdAt as Timestamp;
    if (ts == null) return '';
    final dt = ts.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMe ? AppTheme.primaryOrange : AC.card(context);
    final fg = isMe ? Colors.white : AC.text(context);

    return Align(
      alignment: align,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMe ? Colors.white70 : AC.textMuted(context),
                ),
              ),
            if (label.isNotEmpty) const SizedBox(height: 4),
            Text(body, style: TextStyle(color: fg, height: 1.35)),
            if (_timeLabel().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _timeLabel(),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white60 : AC.textMuted(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
