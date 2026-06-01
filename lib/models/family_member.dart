import 'package:uuid/uuid.dart';
import 'user.dart';

/// Family member profile model
class FamilyMember {
  final String id;
  final String familyHeadId; // Main user's ID
  final UserProfile profile;
  final String relationship;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FamilyMember({
    String? id,
    required this.familyHeadId,
    required this.profile,
    required this.relationship,
    this.isActive = true,
    DateTime? createdAt,
    this.updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyHeadId': familyHeadId,
    'profile': profile.toJson(),
    'relationship': relationship,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    id: json['id'],
    familyHeadId: json['familyHeadId'],
    profile: UserProfile.fromJson(json['profile']),
    relationship: json['relationship'] ?? 'Family Member',
    isActive: json['is_active'] ?? true,
    createdAt: json['created_at'] != null 
        ? DateTime.tryParse(json['created_at'] as String? ?? '')
        : null,
    updatedAt: json['updated_at'] != null 
        ? DateTime.tryParse(json['updated_at'] as String? ?? '')
        : null,
  );

  FamilyMember copyWith({
    String? id,
    String? familyHeadId,
    UserProfile? profile,
    String? relationship,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      familyHeadId: familyHeadId ?? this.familyHeadId,
      profile: profile ?? this.profile,
      relationship: relationship ?? this.relationship,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
