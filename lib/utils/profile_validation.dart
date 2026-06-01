import '../models/user.dart';

/// Utility class for profile validation
class ProfileValidation {
  /// Check if profile is complete (all required fields filled)
  static bool isProfileComplete(UserProfile profile) {
    if (profile.firstName.isEmpty) return false;
    if (profile.education == null || profile.education!.isEmpty) return false;
    if (profile.occupation == null || profile.occupation!.isEmpty) return false;
    if (profile.nakshatra == null || profile.nakshatra!.isEmpty) return false;
    if (profile.city == null || profile.city!.isEmpty) return false;
    
    return true;
  }

  /// Get profile completion percentage
  static double getProfileCompletionPercentage(UserProfile profile) {
    int totalFields = 10;
    int completedFields = 0;

    if (profile.firstName.isNotEmpty) completedFields++;
    if (profile.lastName.isNotEmpty) completedFields++;
    completedFields++;
    if (profile.education != null && profile.education!.isNotEmpty) completedFields++;
    if (profile.occupation != null && profile.occupation!.isNotEmpty) completedFields++;
    if (profile.nakshatra != null && profile.nakshatra!.isNotEmpty) completedFields++;
    if (profile.city != null && profile.city!.isNotEmpty) completedFields++;
    if (profile.height != null && profile.height!.isNotEmpty) completedFields++;
    if (profile.sect != null && profile.sect!.isNotEmpty) completedFields++;
    if (profile.profilePicture != null && profile.profilePicture!.isNotEmpty) completedFields++;

    return (completedFields / totalFields) * 100;
  }

  /// Get missing required fields
  static List<String> getMissingRequiredFields(UserProfile profile) {
    List<String> missingFields = [];

    if (profile.firstName.isEmpty) {
      missingFields.add('First Name');
    }
    if (profile.education == null || profile.education!.isEmpty) {
      missingFields.add('Education');
    }
    if (profile.occupation == null || profile.occupation!.isEmpty) {
      missingFields.add('Occupation');
    }
    if (profile.nakshatra == null || profile.nakshatra!.isEmpty) {
      missingFields.add('Nakshatra');
    }
    if (profile.city == null || profile.city!.isEmpty) {
      missingFields.add('City');
    }

    return missingFields;
  }

  /// Get profile quality score (0-100)
  static double getProfileQualityScore(UserProfile profile) {
    double score = 0.0;
    
    // Basic info (30 points)
    if (profile.firstName.isNotEmpty) score += 5;
    if (profile.lastName.isNotEmpty) score += 5;
    score += 10;
    if (profile.age >= 18 && profile.age <= 65) score += 10;

    // Education & Career (25 points)
    if (profile.education != null && profile.education!.isNotEmpty) score += 10;
    if (profile.occupation != null && profile.occupation!.isNotEmpty) score += 10;
    if (profile.incomeRange != null && profile.incomeRange!.isNotEmpty) score += 5;

    // Astrological (20 points)
    if (profile.nakshatra != null && profile.nakshatra!.isNotEmpty) score += 10;
    if (profile.manglikStatus != null && profile.manglikStatus!.isNotEmpty) score += 5;
    if (profile.sect != null && profile.sect!.isNotEmpty) score += 5;

    // Physical (15 points)
    if (profile.height != null && profile.height!.isNotEmpty) score += 5;
    if (profile.complexion != null && profile.complexion!.isNotEmpty) score += 5;
    if (profile.bodyType != null && profile.bodyType!.isNotEmpty) score += 5;

    // Photo (10 points)
    if (profile.profilePicture != null && profile.profilePicture!.isNotEmpty) score += 10;

    return score;
  }

  /// Get profile quality level
  static String getProfileQualityLevel(double score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Very Good';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }

  /// Get suggestions to improve profile
  static List<String> getProfileImprovementSuggestions(UserProfile profile) {
    List<String> suggestions = [];

    if (profile.firstName.isEmpty) {
      suggestions.add('Add your first name');
    }
    if (profile.lastName.isEmpty) {
      suggestions.add('Add your last name');
    }
    if (profile.education == null || profile.education!.isEmpty) {
      suggestions.add('Add your education details');
    }
    if (profile.occupation == null || profile.occupation!.isEmpty) {
      suggestions.add('Add your occupation details');
    }
    if (profile.incomeRange == null || profile.incomeRange!.isEmpty) {
      suggestions.add('Add your income range');
    }
    if (profile.nakshatra == null || profile.nakshatra!.isEmpty) {
      suggestions.add('Add your nakshatra details');
    }
    if (profile.manglikStatus == null || profile.manglikStatus!.isEmpty) {
      suggestions.add('Add your manglik status');
    }
    if (profile.sect == null || profile.sect!.isEmpty) {
      suggestions.add('Add your religious sect');
    }
    if (profile.height == null || profile.height!.isEmpty) {
      suggestions.add('Add your height');
    }
    if (profile.complexion == null || profile.complexion!.isEmpty) {
      suggestions.add('Add your complexion');
    }
    if (profile.bodyType == null || profile.bodyType!.isEmpty) {
      suggestions.add('Add your body type');
    }
    if (profile.profilePicture == null || profile.profilePicture!.isEmpty) {
      suggestions.add('Upload a profile photo');
    }

    return suggestions;
  }
}
