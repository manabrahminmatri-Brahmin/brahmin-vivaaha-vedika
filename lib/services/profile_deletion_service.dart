import '../core/contract.dart';

/// Profile deletion policy — keep in sync with Cloud Functions grace window.
abstract final class ProfileDeletionService {
  ProfileDeletionService._();

  static const int gracePeriodDays = 7;

  static const String reasonMarriageFixed = 'Marriage Fixed';
  static const String matchSourceManaPrefix = 'mana_Vivaaha Vedika';

  /// True when the account must not appear in likes, interests, viewers, discover.
  /// During the 7-day grace period, related Firestore rows are kept (for restore)
  /// but the profile is hidden everywhere in the app.
  static bool isUserHiddenFromEngagement(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return true;
    if (data[Fields.isDeleted] == true) return true;
    if (data['deletion_requested'] == true) return true;
    final status = (data[Fields.status] as String? ?? '').toLowerCase();
    return status == StatusValues.deleted ||
        status == StatusValues.inactive ||
        status == 'suspended' ||
        status == 'banned';
  }
}
