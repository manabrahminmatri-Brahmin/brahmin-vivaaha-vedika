/// Reasons for profile deletion
enum DeletionReason {
  marriageFixed,
  notSatisfied,
  foundBetterPlatform,
  privacyConcerns,
  tooManyNotifications,
  takingBreak,
  other,
}

extension DeletionReasonExtension on DeletionReason {
  String get displayName {
    switch (this) {
      case DeletionReason.marriageFixed:
        return 'Marriage is Fixed';
      case DeletionReason.notSatisfied:
        return 'Not Satisfied with Service';
      case DeletionReason.foundBetterPlatform:
        return 'Found Better Platform';
      case DeletionReason.privacyConcerns:
        return 'Privacy Concerns';
      case DeletionReason.tooManyNotifications:
        return 'Too Many Notifications';
      case DeletionReason.takingBreak:
        return 'Taking a Break';
      case DeletionReason.other:
        return 'Other Reason';
    }
  }

  String get description {
    switch (this) {
      case DeletionReason.marriageFixed:
        return 'Congratulations! Your profile will be deleted immediately.';
      case DeletionReason.notSatisfied:
        return 'We\'re sorry to hear that. Your profile will be kept for 7 days in case you change your mind.';
      case DeletionReason.foundBetterPlatform:
        return 'Thank you for your feedback. Your profile will be kept for 7 days.';
      case DeletionReason.privacyConcerns:
        return 'We take privacy seriously. Your profile will be kept for 7 days.';
      case DeletionReason.tooManyNotifications:
        return 'You can adjust notification settings. Profile will be kept for 7 days.';
      case DeletionReason.takingBreak:
        return 'You can return anytime within 7 days to restore your profile.';
      case DeletionReason.other:
        return 'Your profile will be kept for 7 days in case you change your mind.';
    }
  }

  bool get isImmediate {
    return this == DeletionReason.marriageFixed;
  }
  
  static List<DeletionReason> get allReasons => DeletionReason.values;
}
