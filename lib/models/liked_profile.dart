import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for a liked profile
/// Clean unified like system - no shortlist confusion

class LikedProfile {
  final String userId;
  final String? name;
  final String profileId;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  
  // Profile display fields
  final String? photo;
  final String? age;
  final String? location;
  final String? occupation;
  final DateTime? addedAt;

  LikedProfile({
    required this.userId,
    this.name,
    required this.profileId,
    required this.index,
    required this.onTap,
    required this.onDismiss,
    this.photo,
    this.age,
    this.location,
    this.occupation,
    this.addedAt,
  });

  /// Factory constructor for Firestore data
  factory LikedProfile.fromJson(Map<String, dynamic> json) {
    return LikedProfile(
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String?,
      profileId: json['profile_id'] as String? ?? '',
      index: 0, // Default index for fromJson
      onTap: () {}, // Empty callback for fromJson
      onDismiss: () {}, // Empty callback for fromJson
      photo: json['photo'] as String?,
      age: json['age'] as String?,
      location: json['location'] as String?,
      occupation: json['occupation'] as String?,
      addedAt: (json['added_at'] ?? json['addedAt']) != null 
          ? ((json['added_at'] ?? json['addedAt']) as Timestamp).toDate()
          : null,
    );
  }
}
