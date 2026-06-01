import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import 'interest_message_dialog.dart';
import 'soft_touch.dart';
import '../services/auth_service.dart';
import '../services/interest_service_v2.dart';
import '../services/like_service_v2.dart';

/// Action types for user interactions
enum ActionType {
  like,
  interest,
}

/// Unified action button for Like and Interest
/// Uses bidirectional UserActionService for consistency
class ActionButton extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final ActionType type;
  final bool isActive;
  final bool isPremium;
  final VoidCallback? onPremiumUpgrade;
  final Function(bool success)? onActionComplete;
  final Size size;

  const ActionButton({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.type,
    this.isActive = false,
    this.isPremium = false,
    this.onPremiumUpgrade,
    this.onActionComplete,
    this.size = const Size(120, 44),
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  final _likes = LikeService();
  bool _isLoading = false;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.isActive;
  }

  @override
  void didUpdateWidget(ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _isActive = widget.isActive;
    }
  }

  Future<void> _handleAction() async {
    if (_isLoading) return;

    // INTEREST: Show message dialog first
    if (widget.type == ActionType.interest && !_isActive) {
      SoftTouch.impact();
      final sent = await InterestMessageDialog.show(
        context: context,
        targetUserId: widget.targetUserId,
        targetUserName: widget.targetUserName,
        isPremium: widget.isPremium,
        onPremiumUpgrade: widget.onPremiumUpgrade,
      );

      if (sent && mounted) {
        setState(() => _isActive = true);
        widget.onActionComplete?.call(true);
      }
      return;
    }

    // LIKE or WITHDRAW INTEREST: Direct action (optimistic toggle + frame for spinner)
    final priorActive = _isActive;
    SoftTouch.impact();
    setState(() {
      _isActive = !priorActive;
      _isLoading = true;
    });
    await Future<void>.delayed(Duration.zero);

    bool success;
    if (widget.type == ActionType.like) {
      final Map<String, dynamic> res = priorActive
          ? await _likes.unlikeProfile(targetUserId: widget.targetUserId)
          : await _likes.likeProfile(targetUserId: widget.targetUserId);
      final err = res['error'] ?? res['errorCode'];
      if (priorActive) {
        success = err == null;
      } else {
        success = err == null &&
            (res['liked'] == true ||
                res['likeId'] != null ||
                res.containsKey('likeId'));
      }
    } else {
      final meId = context.read<AuthService>().currentUser?.id.trim() ?? '';
      final targetId = widget.targetUserId.trim();
      final interestId =
          meId.isNotEmpty && targetId.isNotEmpty ? '${meId}_$targetId' : '';
      if (priorActive) {
        if (interestId.isEmpty) {
          success = false;
        } else {
          final res = await context
              .read<InterestService>()
              .withdrawInterestWithResult(interestId: interestId);
          success = res['success'] == true;
        }
      } else {
        success = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (!success) {
        _isActive = !_isActive;
      }
    });

    widget.onActionComplete?.call(success);

    // Show feedback
    if (success && mounted) {
      final message = _isActive
          ? widget.type == ActionType.like
              ? 'Liked! ❤️'
              : 'Interested! 💌'
          : widget.type == ActionType.like
              ? 'Unliked'
              : 'Interest withdrawn';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _isActive ? AppTheme.sacredGreen : Colors.grey,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLike = widget.type == ActionType.like;

    // Active state styling
    final activeColor = isLike ? Colors.red : AppTheme.primaryOrange;
    final activeIcon = isLike ? Icons.favorite : Icons.mark_email_read;
    final activeText = isLike ? 'Unlike' : 'Interested';

    // Inactive state styling
    final inactiveColor = Colors.grey[400]!;
    final inactiveIcon = isLike ? Icons.favorite_border : Icons.mail_outline;
    final inactiveText = isLike ? 'Like' : 'Interest';

    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _handleAction,
        icon: _isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _isActive ? Colors.white : activeColor,
                ),
              )
            : Icon(
                _isActive ? activeIcon : inactiveIcon,
                size: 20,
              ),
        label: Text(
          _isActive ? activeText : inactiveText,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isActive ? activeColor : Colors.white,
          foregroundColor: _isActive ? Colors.white : inactiveColor,
          elevation: _isActive ? 2 : 0,
          side: BorderSide(
            color: _isActive ? activeColor : inactiveColor,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }
}

/// Compact icon-only version for cards
class ActionIconButton extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final ActionType type;
  final bool isActive;
  final bool isPremium;
  final VoidCallback? onPremiumUpgrade;
  final Function(bool success)? onActionComplete;

  const ActionIconButton({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.type,
    this.isActive = false,
    this.isPremium = false,
    this.onPremiumUpgrade,
    this.onActionComplete,
  });

  @override
  State<ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<ActionIconButton> {
  final _likes = LikeService();
  bool _isLoading = false;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.isActive;
  }

  @override
  void didUpdateWidget(ActionIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _isActive = widget.isActive;
    }
  }

  Future<void> _handleAction() async {
    if (_isLoading) return;

    // INTEREST: Show message dialog
    if (widget.type == ActionType.interest && !_isActive) {
      SoftTouch.impact();
      final sent = await InterestMessageDialog.show(
        context: context,
        targetUserId: widget.targetUserId,
        targetUserName: widget.targetUserName,
        isPremium: widget.isPremium,
        onPremiumUpgrade: widget.onPremiumUpgrade,
      );

      if (sent && mounted) {
        setState(() => _isActive = true);
        widget.onActionComplete?.call(true);
      }
      return;
    }

    final priorActive = _isActive;
    SoftTouch.impact();
    setState(() {
      _isActive = !priorActive;
      _isLoading = true;
    });
    await Future<void>.delayed(Duration.zero);

    bool success;
    if (widget.type == ActionType.like) {
      final Map<String, dynamic> res = priorActive
          ? await _likes.unlikeProfile(targetUserId: widget.targetUserId)
          : await _likes.likeProfile(targetUserId: widget.targetUserId);
      final err = res['error'] ?? res['errorCode'];
      if (priorActive) {
        success = err == null;
      } else {
        success = err == null &&
            (res['liked'] == true ||
                res['likeId'] != null ||
                res.containsKey('likeId'));
      }
    } else {
      final meId = context.read<AuthService>().currentUser?.id.trim() ?? '';
      final targetId = widget.targetUserId.trim();
      final interestId =
          meId.isNotEmpty && targetId.isNotEmpty ? '${meId}_$targetId' : '';
      if (priorActive) {
        if (interestId.isEmpty) {
          success = false;
        } else {
          final res = await context
              .read<InterestService>()
              .withdrawInterestWithResult(interestId: interestId);
          success = res['success'] == true;
        }
      } else {
        success = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (!success) {
        _isActive = !_isActive;
      }
    });

    widget.onActionComplete?.call(success);
  }

  @override
  Widget build(BuildContext context) {
    final isLike = widget.type == ActionType.like;

    final activeColor = isLike ? Colors.red : AppTheme.primaryOrange;
    final inactiveColor = Colors.grey[400]!;
    final activeIcon = isLike ? Icons.favorite : Icons.mark_email_read;
    final inactiveIcon = isLike ? Icons.favorite_border : Icons.mail_outline;

    return IconButton(
      onPressed: _isLoading ? null : _handleAction,
      icon: _isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _isActive ? activeColor : inactiveColor,
              ),
            )
          : Icon(
              _isActive ? activeIcon : inactiveIcon,
              color: _isActive ? activeColor : inactiveColor,
            ),
      tooltip: isLike ? 'Like' : 'Send Interest',
    );
  }
}
