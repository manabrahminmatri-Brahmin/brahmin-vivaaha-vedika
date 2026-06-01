import 'package:flutter/material.dart';

/// User badge types for profile verification and premium status
enum BadgeType {
  verified,      // Document verified
  premium,       // Premium/platinum member
  featured,      // Featured profile
  admin,         // Admin user
  newUser,       // Recently joined
  goldMember,    // Gold tier member
}

/// Badge configuration including display properties
class UserBadge {
  final BadgeType type;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final String? tooltip;

  const UserBadge({
    required this.type,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    this.tooltip,
  });

  /// Get badge configuration by type
  static UserBadge forType(BadgeType type) {
    switch (type) {
      case BadgeType.verified:
        return const UserBadge(
          type: BadgeType.verified,
          label: 'Verified',
          icon: Icons.verified,
          backgroundColor: Color(0xFFE3F2FD),
          textColor: Color(0xFF1976D2),
          tooltip: 'Document Verified',
        );
      case BadgeType.premium:
        return const UserBadge(
          type: BadgeType.premium,
          label: 'Premium',
          icon: Icons.workspace_premium,
          backgroundColor: Color(0xFFF3E5F5),
          textColor: Color(0xFF7B1FA2),
          tooltip: 'Premium Member',
        );
      case BadgeType.featured:
        return const UserBadge(
          type: BadgeType.featured,
          label: 'Featured',
          icon: Icons.star,
          backgroundColor: Color(0xFFFFF3E0),
          textColor: Color(0xFFEF6C00),
          tooltip: 'Featured Profile',
        );
      case BadgeType.admin:
        return const UserBadge(
          type: BadgeType.admin,
          label: 'Admin',
          icon: Icons.admin_panel_settings,
          backgroundColor: Color(0xFFFFEBEE),
          textColor: Color(0xFFC62828),
          tooltip: 'Administrator',
        );
      case BadgeType.newUser:
        return const UserBadge(
          type: BadgeType.newUser,
          label: 'New',
          icon: Icons.fiber_new,
          backgroundColor: Color(0xFFE8F5E9),
          textColor: Color(0xFF2E7D32),
          tooltip: 'New Member',
        );
      case BadgeType.goldMember:
        return const UserBadge(
          type: BadgeType.goldMember,
          label: 'Gold',
          icon: Icons.card_membership,
          backgroundColor: Color(0xFFFFFDE7),
          textColor: Color(0xFFF9A825),
          tooltip: 'Gold Member',
        );
    }
  }

  /// Parse badge from string
  static BadgeType? parse(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'verified':
        return BadgeType.verified;
      case 'premium':
      case 'platinum':
        return BadgeType.premium;
      case 'featured':
        return BadgeType.featured;
      case 'admin':
        return BadgeType.admin;
      case 'new':
      case 'newuser':
        return BadgeType.newUser;
      case 'gold':
        return BadgeType.goldMember;
      default:
        return null;
    }
  }

  @override
  String toString() => 'UserBadge(type: $type, label: $label)';
}

/// Extension to get badge from user data
extension UserBadgeExtension on Map<String, dynamic> {
  List<UserBadge> get badges {
    final badges = <UserBadge>[];
    
    // Check for verification
    final isVerified = this['is_verified'] == true || 
                       this['document_verified'] == true;
    if (isVerified) {
      badges.add(UserBadge.forType(BadgeType.verified));
    }
    
    // Check for premium status
    final tier = (this['membership_tier'] as String? ?? '').toLowerCase();
    if (tier == 'platinum' || tier == 'premium') {
      badges.add(UserBadge.forType(BadgeType.premium));
    } else if (tier == 'gold') {
      badges.add(UserBadge.forType(BadgeType.goldMember));
    }
    
    // Check for featured
    if (this['is_featured'] == true) {
      badges.add(UserBadge.forType(BadgeType.featured));
    }
    
    // Check for new user (joined within last 7 days)
    final createdAt = this['created_at'] as String?;
    if (createdAt != null) {
      try {
        final created = DateTime.parse(createdAt);
        if (DateTime.now().difference(created).inDays <= 7) {
          badges.add(UserBadge.forType(BadgeType.newUser));
        }
      } catch (_) {}
    }
    
    // Check for admin
    if (this['is_admin'] == true) {
      badges.add(UserBadge.forType(BadgeType.admin));
    }
    
    return badges;
  }
}
