import 'package:flutter_test/flutter_test.dart';

void main() {
  group('User Model', () {
    test('should create User from JSON correctly', () {
      // Arrange
      final json = {
        'id': 'user-123',
        'phone_number': '+919876543210',
        'profile_id': 'profile-456',
        'created_at': '2024-01-15T10:30:00Z',
      };

      // Act
      final user = User.fromJson(json);

      // Assert
      expect(user.id, 'user-123');
      expect(user.phoneNumber, '+919876543210');
      expect(user.profileId, 'profile-456');
      expect(user.createdAt, DateTime.parse('2024-01-15T10:30:00Z'));
    });

    test('should convert User to JSON correctly', () {
      // Arrange
      final user = User(
        id: 'user-123',
        phoneNumber: '+919876543210',
        profileId: 'profile-456',
        createdAt: DateTime.parse('2024-01-15T10:30:00Z'),
      );

      // Act
      final json = user.toJson();

      // Assert
      expect(json['id'], 'user-123');
        expect(json['phone_number'], '+919876543210');
      expect(json['profile_id'], 'profile-456');
    });

    test('should handle null values gracefully', () {
      // Arrange
      final json = {
        'id': 'user-123',
        'phone_number': '+919876543210',
      };

      // Act
      final user = User.fromJson(json);

      // Assert
      expect(user.profileId, isNull);
      expect(user.createdAt, isNull);
    });

    test('should support equality comparison', () {
      // Arrange
      final user1 = User(id: 'user-123', phoneNumber: '+919876543210');
      final user2 = User(id: 'user-123', phoneNumber: '+919876543210');
      final user3 = User(id: 'user-456', phoneNumber: '+919876543210');

      // Assert
      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });
  });

  group('Profile Model', () {
    test('should create Profile from JSON with all fields', () {
      // Arrange
      final json = {
        'id': 'profile-123',
        'full_name': 'John Doe',
        'date_of_birth': '1990-05-15',
        'gender': 'male',
        'height': 175,
        'education': 'B.Tech',
        'occupation': 'Software Engineer',
        'income': 1000000,
        'religion': 'Hindu',
        'caste': 'Brahmin',
        'location': 'Hyderabad',
      };

      // Act
      final profile = Profile.fromJson(json);

      // Assert
      expect(profile.id, 'profile-123');
      expect(profile.fullName, 'John Doe');
      expect(profile.gender, 'male');
      expect(profile.height, 175);
    });

    test('should calculate age correctly', () {
      // Arrange
      final profile = Profile(
        id: 'profile-123',
        fullName: 'Test User',
        dateOfBirth: DateTime(1990, 5, 15),
      );

      // Act
      final age = profile.age;

      // Assert
      expect(age, greaterThan(30));
    });

    test('should validate profile completeness', () {
      // Arrange
      final incompleteProfile = Profile(
        id: 'profile-123',
        fullName: 'Test',
      );
      
      final completeProfile = Profile(
        id: 'profile-456',
        fullName: 'Complete User',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'male',
        height: 175,
        education: 'B.Tech',
        occupation: 'Engineer',
      );

      // Assert
      expect(incompleteProfile.isComplete, false);
      expect(completeProfile.isComplete, true);
    });
  });

  group('Interest Model', () {
    test('should create Interest from JSON', () {
      // Arrange
      final json = {
        'id': 'interest-123',
        'sender_id': 'user-1',
        'receiver_id': 'user-2',
        'status': 'pending',
        'message': 'Hello, interested in your profile',
        'created_at': '2024-01-15T10:30:00Z',
      };

      // Act
      final interest = Interest.fromJson(json);

      // Assert
      expect(interest.id, 'interest-123');
      expect(interest.senderId, 'user-1');
      expect(interest.receiverId, 'user-2');
      expect(interest.status, InterestStatus.pending);
    });

    test('should support status transitions', () {
      // Arrange
      final interest = Interest(
        id: 'interest-123',
        senderId: 'user-1',
        receiverId: 'user-2',
        status: InterestStatus.pending,
      );

      // Act - Accept
      final acceptedInterest = interest.copyWith(status: InterestStatus.accepted);

      // Assert
      expect(acceptedInterest.status, InterestStatus.accepted);
      expect(interest.status, InterestStatus.pending); // Original unchanged
    });
  });
}

// Model classes for testing
class User {
  final String id;
  final String phoneNumber;
  final String? profileId;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.phoneNumber,
    this.profileId,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    phoneNumber: json['phone_number'] as String,
    profileId: json['profile_id'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone_number': phoneNumber,
    'profile_id': profileId,
    'created_at': createdAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Profile {
  final String id;
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? gender;
  final int? height;
  final String? education;
  final String? occupation;
  final int? income;
  final String? religion;
  final String? caste;
  final String? location;

  Profile({
    required this.id,
    this.fullName,
    this.dateOfBirth,
    this.gender,
    this.height,
    this.education,
    this.occupation,
    this.income,
    this.religion,
    this.caste,
    this.location,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    fullName: json['full_name'] as String?,
    dateOfBirth: json['date_of_birth'] != null
        ? DateTime.parse(json['date_of_birth'] as String)
        : null,
    gender: json['gender'] as String?,
    height: json['height'] as int?,
    education: json['education'] as String?,
    occupation: json['occupation'] as String?,
    income: json['income'] as int?,
    religion: json['religion'] as String?,
    caste: json['caste'] as String?,
    location: json['location'] as String?,
  );

  int? get age => dateOfBirth != null
      ? DateTime.now().difference(dateOfBirth!).inDays ~/ 365
      : null;

  bool get isComplete =>
      fullName != null &&
      fullName!.isNotEmpty &&
      dateOfBirth != null &&
      gender != null &&
      height != null &&
      education != null &&
      occupation != null;
}

enum InterestStatus { pending, accepted, rejected, cancelled }

class Interest {
  final String id;
  final String senderId;
  final String receiverId;
  final InterestStatus status;
  final String? message;
  final DateTime? createdAt;

  Interest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    this.message,
    this.createdAt,
  });

  factory Interest.fromJson(Map<String, dynamic> json) => Interest(
    id: json['id'] as String,
    senderId: json['sender_id'] as String,
    receiverId: json['receiver_id'] as String,
    status: InterestStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => InterestStatus.pending,
    ),
    message: json['message'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Interest copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    InterestStatus? status,
    String? message,
    DateTime? createdAt,
  }) =>
      Interest(
        id: id ?? this.id,
        senderId: senderId ?? this.senderId,
        receiverId: receiverId ?? this.receiverId,
        status: status ?? this.status,
        message: message ?? this.message,
        createdAt: createdAt ?? this.createdAt,
      );
}
