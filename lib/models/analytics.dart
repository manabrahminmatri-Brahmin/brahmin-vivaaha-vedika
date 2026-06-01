import 'package:uuid/uuid.dart';

/// Analytics model for user statistics (Premium feature)
class UserAnalytics {
  final String id;
  final String userId;
  final DateTime date;
  final int profileViews;
  final int interestsReceived;
  final int interestsSent;
  final int contactRequestsReceived;
  final int contactRequestsSent;
  final int messagesReceived;
  final int messagesSent;
  final int likesAdded;
  final int likesReceived;
  final int searchViews;
  final int profileUpdates;

  UserAnalytics({
    String? id,
    required this.userId,
    DateTime? date,
    this.profileViews = 0,
    this.interestsReceived = 0,
    this.interestsSent = 0,
    this.contactRequestsReceived = 0,
    this.contactRequestsSent = 0,
    this.messagesReceived = 0,
    this.messagesSent = 0,
    this.likesAdded = 0,
    this.likesReceived = 0,
    this.searchViews = 0,
    this.profileUpdates = 0,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'date': date.toIso8601String(),
        'profileViews': profileViews,
        'interests_received': interestsReceived,
        'interests_sent': interestsSent,
        'contactRequestsReceived': contactRequestsReceived,
        'contactRequestsSent': contactRequestsSent,
        'messagesReceived': messagesReceived,
        'messagesSent': messagesSent,
        'likesAdded': likesAdded,
        'likes_received': likesReceived,
        'searchViews': searchViews,
        'profileUpdates': profileUpdates,
      };

  factory UserAnalytics.fromJson(Map<String, dynamic> json) => UserAnalytics(
        id: json['id'],
        userId: json['user_id'],
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        profileViews: json['profileViews'] ?? 0,
        interestsReceived: json['interests_received'] ?? 0,
        interestsSent: json['interests_sent'] ?? 0,
        contactRequestsReceived: json['contactRequestsReceived'] ?? 0,
        contactRequestsSent: json['contactRequestsSent'] ?? 0,
        messagesReceived: json['messagesReceived'] ?? 0,
        messagesSent: json['messagesSent'] ?? 0,
        likesAdded: json['likesAdded'] ?? 0,
        likesReceived: json['likes_received'] ?? 0,
        searchViews: json['searchViews'] ?? 0,
        profileUpdates: json['profileUpdates'] ?? 0,
      );
}

/// Analytics summary for dashboard
class AnalyticsSummary {
  final int totalProfileViews;
  final int totalInterestsReceived;
  final int totalInterestsSent;
  final int totalContactRequests;
  final int totalMessages;
  final int totalLikes;
  final double profileCompletionPercentage;
  final DateTime? lastProfileUpdate;
  final int profileRank; // Based on engagement

  AnalyticsSummary({
    this.totalProfileViews = 0,
    this.totalInterestsReceived = 0,
    this.totalInterestsSent = 0,
    this.totalContactRequests = 0,
    this.totalMessages = 0,
    this.totalLikes = 0,
    this.profileCompletionPercentage = 0.0,
    this.lastProfileUpdate,
    this.profileRank = 0,
  });

  Map<String, dynamic> toJson() => {
        'totalProfileViews': totalProfileViews,
        'totalInterestsReceived': totalInterestsReceived,
        'totalInterestsSent': totalInterestsSent,
        'totalContactRequests': totalContactRequests,
        'totalMessages': totalMessages,
        'totalLikes': totalLikes,
        'profileCompletionPercentage': profileCompletionPercentage,
        'lastProfileUpdate': lastProfileUpdate?.toIso8601String(),
        'profileRank': profileRank,
      };

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) =>
      AnalyticsSummary(
        totalProfileViews: json['totalProfileViews'] ?? 0,
        totalInterestsReceived: json['totalInterestsReceived'] ?? 0,
        totalInterestsSent: json['totalInterestsSent'] ?? 0,
        totalContactRequests: json['totalContactRequests'] ?? 0,
        totalMessages: json['totalMessages'] ?? 0,
        totalLikes: json['totalLikes'] ?? 0,
        profileCompletionPercentage:
            (json['profileCompletionPercentage'] ?? 0.0).toDouble(),
        lastProfileUpdate: json['lastProfileUpdate'] != null
            ? DateTime.tryParse(json['lastProfileUpdate'] as String? ?? '')
            : null,
        profileRank: json['profileRank'] ?? 0,
      );
}
