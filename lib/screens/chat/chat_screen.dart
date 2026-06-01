import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/premium_entitlement_service.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../widgets/app_header.dart';
import '../../core/app_router.dart';
import '../../services/privacy_enforcement_service.dart';
import '../../core/app_identity.dart';
import '../../core/constants.dart';
import '../../core/contract.dart';
import '../../core/safe_profile_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/chat_intro_template.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String? otherUserName;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;
  bool _isDeleting = false;
  bool _isMarkingRead = false;
  bool _canDeleteForEveryone = false;
  User? _otherUser;
  Map<String, dynamic>? _otherUserDoc;
  bool _isChatVisibleByPrivacy = true;
  final PrivacyEnforcementService _privacyService = PrivacyEnforcementService();
  /// From Firestore `intro_message_sent_by` (one intro message per user per chat).
  bool _introQuotaFromServer = false;
  bool? _serverChatPremium;
  bool _introBackfillStarted = false;
  bool _introTemplateSeeded = false;

  String _peerGreet() =>
      (_otherUser?.profile?.firstName ?? widget.otherUserName ?? '').trim();

  bool get _hasTargetUserContext =>
      widget.otherUserId.trim().isNotEmpty;

  void _applyIntroTemplate() {
    final me = context.read<AuthService>().currentUser;
    if (me == null || !_hasTargetUserContext) return;
    final greet = _peerGreet();
    setState(() {
      _messageController.text = ChatIntroTemplate.build(
        me: me,
        peerFirstName: greet.isEmpty ? null : greet,
      );
      _introTemplateSeeded = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadOtherUser();
    _loadChatMetaAndDeleteWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showIntroQuotaDialogOnce();
      _seedIntroTemplateIfNeeded();
    });
    unawaited(_loadServerChatPremium());
  }

  Future<void> _loadServerChatPremium() async {
    final ok = await PremiumEntitlementService.isEntitled(
      feature: PremiumEntitlementService.featureChat,
    );
    if (mounted) setState(() => _serverChatPremium = ok);
  }

  void _seedIntroTemplateIfNeeded() {
    final me = context.read<AuthService>().currentUser;
    if (me == null || _introTemplateSeeded || !_hasTargetUserContext) return;
    if (_messageController.text.trim().isNotEmpty) return;
    _messageController.text = ChatIntroTemplate.build(
      me: me,
      peerFirstName: _peerGreet().isEmpty ? null : _peerGreet(),
    );
    _introTemplateSeeded = true;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOtherUser() async {
    try {
      final me = context.read<AuthService>().currentUser;
      final authService = AuthService();
      final otherUser = await authService.getUserById(widget.otherUserId);
      final otherDoc = await FirebaseFirestore.instance.collection(Collections.users).doc(widget.otherUserId).get();
      if (mounted) {
        final hadPeerHint = (widget.otherUserName ?? '').trim().isNotEmpty;
        setState(() {
          _otherUser = otherUser;
          _otherUserDoc = otherDoc.data();
          _isChatVisibleByPrivacy = me == null || otherUser == null
              ? true
              : _privacyService.canViewerSeeProfile(
                  viewer: me,
                  candidate: otherUser,
                  candidateDoc: _otherUserDoc,
                );
        });
        if (!hadPeerHint && _peerGreet().isNotEmpty && me != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_messageController.text.trim().isEmpty) {
              _applyIntroTemplate();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading other user: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty ||
        _isLoading ||
        !_isChatVisibleByPrivacy ||
        !_hasTargetUserContext) {
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final result = await _chatService.sendMessage(
        chatId: widget.chatId,
        message: _messageController.text.trim(),
        messageType: 'text',
        recipientId: widget.otherUserId,
      );
      if (!mounted) return;
      switch (result) {
        case ChatSendResult.success:
          setState(() => _introQuotaFromServer = true);
          _messageController.clear();
          _scrollToBottom();
          break;
        case ChatSendResult.notSignedIn:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your session expired. Please go back and sign in again, then reopen chat.',
              ),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
          break;
        case ChatSendResult.introQuotaUsed:
          setState(() => _introQuotaFromServer = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You already sent your introductory message. Use profile or Interests to connect further.',
              ),
              backgroundColor: AppTheme.primaryOrange,
            ),
          );
          break;
        case ChatSendResult.failed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send message. Try again.'),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadChatMetaAndDeleteWindow() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      final data = snap.data();
      final createdAtRaw = data?['created_at'];
      final updatedAtRaw = data?['updated_at'];
      final ts = createdAtRaw is Timestamp
          ? createdAtRaw
          : (updatedAtRaw is Timestamp ? updatedAtRaw : null);
      final canDelete = ts != null &&
          DateTime.now().difference(ts.toDate()) <= const Duration(hours: 1);
      final me = IdentityProvider.userDocId.trim();
      final sentBy = (data?['intro_message_sent_by'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toSet();
      final introUsed = me.isNotEmpty && sentBy.contains(me);
      if (!mounted) return;
      setState(() {
        _canDeleteForEveryone = canDelete;
        _introQuotaFromServer = introUsed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _canDeleteForEveryone = false);
    }
  }

  Future<void> _showIntroQuotaDialogOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = 'chat_intro_1msg_tip_v1_${widget.chatId}';
      if (p.getBool(key) == true) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('One introductory message'),
          content: const Text(
            'Each of you can send only one message in this chat to keep the service efficient. '
            'After you send yours, continue the connection from their profile, Interests, or Premium options.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) await p.setBool(key, true);
    } catch (_) {}
  }

  bool _messageIsFromMe(
    Map<String, dynamic> m,
    String myDocId,
    String authUid,
  ) {
    final senderId = (m['sender_id'] as String? ?? '').trim();
    final senderAuthUid = (m['sender_auth_uid'] as String? ?? '').trim();
    return senderId == myDocId ||
        (authUid.isNotEmpty && (senderId == authUid || senderAuthUid == authUid));
  }

  bool _messagesIncludeMine(List<Map<String, dynamic>> messages) {
    final myDocId = IdentityProvider.userDocId;
    final authUid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
    return messages.any((m) => _messageIsFromMe(m, myDocId, authUid));
  }

  void _scheduleIntroBackfillIfNeeded(bool hasMyIntro) {
    if (!hasMyIntro || _introQuotaFromServer || _introBackfillStarted) return;
    _introBackfillStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _chatService.ensureIntroQuotaRecorded(widget.chatId).then((_) {
          if (mounted) setState(() => _introQuotaFromServer = true);
        }),
      );
    });
  }

  Future<void> _deleteChatForMe() async {
    if (_isDeleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for me?'),
        content: const Text(
          'This chat will be removed from your inbox only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _chatService.deleteChatForMe(widget.chatId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted for you')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete chat: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _deleteChatForEveryone() async {
    if (_isDeleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for everyone?'),
        content: const Text(
          'This removes the full conversation for both members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _chatService.deleteChatForEveryone(widget.chatId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted for everyone')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete chat: $e'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _markMessagesSeen(List<Map<String, dynamic>> messages) {
    if (_isMarkingRead || messages.isEmpty) return;
    final authUid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
    final docId = IdentityProvider.userDocId;
    final hasUnreadIncoming = messages.any((m) {
      final recipient = (m['recipient_id'] as String? ?? '').trim();
      final isRead = m[FirebaseConstants.isReadField] == true;
      final sender = (m['sender_id'] as String? ?? '').trim();
      final isMine = sender == docId || (authUid.isNotEmpty && sender == authUid);
      return !isMine &&
          !isRead &&
          (recipient == docId || (authUid.isNotEmpty && recipient == authUid));
    });
    if (!hasUnreadIncoming) return;

    _isMarkingRead = true;
    unawaited(
      _chatService.markMessagesAsRead(widget.chatId).whenComplete(() {
        _isMarkingRead = false;
      }),
    );
  }

  Timestamp? _messageTimestamp(Map<String, dynamic> m) {
    final c = m[FirebaseConstants.timestampField];
    if (c is Timestamp) return c;
    final legacy = m['timestamp'];
    if (legacy is Timestamp) return legacy;
    return null;
  }

  bool _messageWithinDeleteWindow(Map<String, dynamic> m) {
    final ts = _messageTimestamp(m);
    if (ts == null) return false;
    return DateTime.now().difference(ts.toDate()) <= const Duration(hours: 1);
  }

  Future<void> _onMessageLongPress(Map<String, dynamic> message, bool isMe) async {
    if (!_isChatVisibleByPrivacy) return;
    final id = message['id'] as String? ?? '';
    if (id.isEmpty) return;

    final canEveryone = isMe && _messageWithinDeleteWindow(message);

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Delete for me'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await _chatService.hideMessageForMe(widget.chatId, id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message removed for you')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not delete: $e'),
                        backgroundColor: AppTheme.kumkumRed,
                      ),
                    );
                  }
                }
              },
            ),
            if (canEveryone)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete for everyone'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _chatService.revokeMessageForEveryone(widget.chatId, id);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message deleted for everyone')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$e'),
                          backgroundColor: AppTheme.kumkumRed,
                        ),
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = _serverChatPremium == true;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppHeader(
        title: _otherUser?.profile?.firstName ?? widget.otherUserName ?? 'Chat',
        showLogo: false,
        showUpgradeButton: false,
        additionalActions: [
          PopupMenuButton<String>(
            icon: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.more_vert),
            enabled: !_isDeleting,
            onSelected: (value) {
              if (value == 'delete_me') {
                _deleteChatForMe();
              } else if (value == 'delete_all') {
                _deleteChatForEveryone();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'delete_me',
                child: Text('Delete for me'),
              ),
              if (_canDeleteForEveryone)
                const PopupMenuItem<String>(
                  value: 'delete_all',
                  child: Text('Delete for everyone'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isChatVisibleByPrivacy)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.kumkumRed.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.kumkumRed.withAlpha(80)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, color: AppTheme.kumkumRed),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This conversation is hidden by member privacy settings.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (!isPremium)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: AppTheme.primaryOrange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'You have messages from a Premium user. Upgrade to view and reply.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, Routes.premiumUpgrade),
                    child: const Text('Get Premium'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.getMessages(widget.chatId),
              builder: (context, snapshot) {
                final hasTargetUser = _hasTargetUserContext;
                if (!_isChatVisibleByPrivacy) {
                  return const Center(
                    child: Text('Chat unavailable due to privacy controls.'),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages: ${snapshot.error}',
                      style: const TextStyle(color: AppTheme.kumkumRed),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                _markMessagesSeen(messages);

                final hasMyIntro = _messagesIncludeMine(messages);
                _scheduleIntroBackfillIfNeeded(hasMyIntro);
                final introConsumed = _introQuotaFromServer || hasMyIntro;

                if (snapshot.connectionState == ConnectionState.waiting &&
                    messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryOrange),
                  );
                }

                Widget listOrEmpty;
                if (messages.isEmpty) {
                  listOrEmpty = const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppTheme.textMedium,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textMedium,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'You can send one short introductory message here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  final reversedMessages = messages.reversed.toList();
                  listOrEmpty = ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: reversedMessages.length,
                    itemBuilder: (context, index) {
                      final message = reversedMessages[index];
                      final authUid =
                          fb_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
                      final myDocId = IdentityProvider.userDocId;
                      final senderId =
                          (message['sender_id'] as String? ?? '').trim();
                      final senderAuthUid =
                          (message['sender_auth_uid'] as String? ?? '').trim();
                      final isMe = senderId == myDocId ||
                          (authUid.isNotEmpty &&
                              (senderId == authUid ||
                                  senderAuthUid == authUid));

                      return _MessageBubble(
                        message: message,
                        isMe: isMe,
                        hideIncomingContent: !isPremium && !isMe,
                        showSeenStatus: isMe,
                        onLongPress: () => _onMessageLongPress(message, isMe),
                      );
                    },
                  );
                }

                return Column(
                  children: [
                    if (!hasTargetUser)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange.withAlpha(22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryOrange.withAlpha(80),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.person_search_outlined,
                              color: AppTheme.primaryOrange,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Select a specific member to start targeted chat.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: listOrEmpty),
                    if (introConsumed)
                      _IntroFollowUpPanel(
                        isPremium: isPremium,
                        userHasSentIntro: hasMyIntro,
                        peerFirstName: _otherUser?.profile?.firstName ??
                            widget.otherUserName,
                        onOpenProfile: () {
                          SafeProfileNav.safeOpenProfileByUserId(
                            context,
                            userId: widget.otherUserId,
                          );
                        },
                        onOpenInterests: () {
                          Navigator.pushNamed(
                            context,
                            Routes.interests,
                            arguments: const {'initialTabIndex': 0},
                          );
                        },
                        onUpgrade: () {
                          Navigator.pushNamed(context, Routes.premiumUpgrade);
                        },
                      )
                    else
                      _MessageInput(
                        controller: _messageController,
                        isLoading: _isLoading,
                        onSend: _sendMessage,
                        canSend:
                            isPremium && _isChatVisibleByPrivacy && hasTargetUser,
                        showIntroAssist: hasTargetUser,
                        hasTargetUser: hasTargetUser,
                        onReloadSuggestedIntro: () => _applyIntroTemplate(),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroFollowUpPanel extends StatelessWidget {
  final bool isPremium;
  final bool userHasSentIntro;
  final String? peerFirstName;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenInterests;
  final VoidCallback onUpgrade;

  const _IntroFollowUpPanel({
    required this.isPremium,
    required this.userHasSentIntro,
    required this.peerFirstName,
    required this.onOpenProfile,
    required this.onOpenInterests,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final name = (peerFirstName ?? 'this member').trim();
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: AppTheme.sacredGreen, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !isPremium && !userHasSentIntro
                        ? 'Intro chat is limited'
                        : userHasSentIntro
                            ? 'Your introductory message is sent.'
                            : 'Chat messaging is limited',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              !isPremium && !userHasSentIntro
                  ? 'Upgrade to Premium to send your one introductory message here, or open $name\'s profile and use Interests for other actions.'
                  : isPremium
                      ? 'Continue with $name from their profile, or use Interests for requests and updates.'
                      : userHasSentIntro
                          ? 'Continue with $name from their profile, or use Interests. Upgrade anytime for full Premium features.'
                          : 'Open profile or Interests to connect. Upgrade to Premium if you want to send your intro message in chat.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMedium,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenProfile,
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Open profile'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenInterests,
                  icon: const Icon(Icons.favorite_outline, size: 18),
                  label: const Text('Interests'),
                ),
                if (!isPremium)
                  FilledButton.icon(
                    onPressed: onUpgrade,
                    icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                    label: const Text('Get Premium'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final bool hideIncomingContent;
  final bool showSeenStatus;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.hideIncomingContent = false,
    this.showSeenStatus = false,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final revoked = message['revoked_for_everyone'] == true;
    final messageText = revoked
        ? 'This message was deleted.'
        : hideIncomingContent
            ? 'Message hidden. Upgrade to Premium to view.'
            : (message['message'] as String? ?? '');
    final timestamp = message[FirebaseConstants.timestampField] as Timestamp? ??
        message['timestamp'] as Timestamp?;
    final isRead = message[FirebaseConstants.isReadField] == true;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: AppTheme.primaryOrange,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? AppTheme.primaryOrange : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(8),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      messageText,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppTheme.textDark,
                        fontSize: 16,
                        fontStyle: revoked ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatTimestamp(timestamp),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : const Color(0xFF757575),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (showSeenStatus && !revoked) ...[
                      const SizedBox(height: 2),
                      Text(
                        isRead ? 'Seen' : 'Sent',
                        style: TextStyle(
                          color: isMe ? Colors.white70 : const Color(0xFF757575),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.sacredGreen.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: AppTheme.sacredGreen,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final messageTime = timestamp.toDate();
    final diff = now.difference(messageTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${messageTime.day}/${messageTime.month}/${messageTime.year}';
    }
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;
  final bool canSend;
  final bool hasTargetUser;
  final bool showIntroAssist;
  final VoidCallback onReloadSuggestedIntro;

  const _MessageInput({
    required this.controller,
    required this.isLoading,
    required this.onSend,
    required this.canSend,
    required this.hasTargetUser,
    this.showIntroAssist = false,
    required this.onReloadSuggestedIntro,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showIntroAssist && canSend) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suggested intro (English) — edit freely or write your own',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMedium,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: canSend ? onReloadSuggestedIntro : null,
                  icon: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: AppTheme.primaryOrange,
                  ),
                  label: Text(
                    'Reset to suggested',
                    style: TextStyle(
                      color: AppTheme.primaryOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: canSend,
                  decoration: InputDecoration(
                    hintText: canSend
                        ? 'Your message…'
                        : (hasTargetUser
                            ? 'Premium required to reply'
                            : 'Select a member to start targeted chat'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  minLines: 2,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.primaryOrange,
                borderRadius: BorderRadius.circular(25),
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: (isLoading || !canSend) ? null : onSend,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
