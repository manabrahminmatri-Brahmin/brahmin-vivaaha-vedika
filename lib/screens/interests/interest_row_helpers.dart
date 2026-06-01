import '../../core/interest_identity_resolver.dart';
import '../../features/profile/profile_repository.dart';
import '../../models/user.dart';

/// Shared field resolution for interest hub rows (received / sent / activity).
abstract final class InterestRowHelpers {
  InterestRowHelpers._();

  static String peerUserId(Map<String, dynamic> data, {required bool isReceived}) =>
      InterestIdentityResolver.peerUserId(data, isReceived: isReceived);

  static String peerProfileId(
    Map<String, dynamic> data, {
    required bool isReceived,
  }) =>
      InterestIdentityResolver.peerProfileId(data, isReceived: isReceived);

  static String peerName(Map<String, dynamic> data, {required bool isReceived}) {
    final name = InterestIdentityResolver.peerDisplayName(
      data,
      isReceived: isReceived,
    );
    return name == InterestIdentityResolver.unknownMember ? '' : name;
  }

  static bool hasSnapshotIdentity(
    Map<String, dynamic> data, {
    required bool isReceived,
  }) =>
      InterestIdentityResolver.hasResolvableIdentity(
        data,
        isReceived: isReceived,
      );

  /// Stored snapshot URL — UI must not use when [canViewPhoto] is false.
  static String? peerPhotoUrl(Map<String, dynamic> data, {required bool isReceived}) =>
      InterestIdentityResolver.snapshotPhotoUrl(data, isReceived: isReceived);

  static int peerAge(Map<String, dynamic> data, User? user, {required bool isReceived}) =>
      InterestIdentityResolver.peerAgeFromRow(
        data,
        isReceived: isReceived,
        liveAge: user?.profile?.age ?? 0,
      );

  static String peerLocation(
    Map<String, dynamic> data,
    User? user, {
    required bool isReceived,
  }) =>
      InterestIdentityResolver.peerLocationText(
        data,
        isReceived: isReceived,
        liveCity: user?.profile?.city,
        liveState: user?.profile?.state,
      );

  static Future<User?> loadPeerUser(
    Map<String, dynamic> data, {
    required bool isReceived,
  }) async {
    final pid = peerProfileId(data, isReceived: isReceived);
    if (pid.isNotEmpty) {
      final byPid = await ProfileRepository().lookupUserByAnyId(pid);
      if (byPid != null) return byPid;
    }
    final uid = peerUserId(data, isReceived: isReceived);
    if (uid.isEmpty) return null;
    return ProfileRepository().lookupUserByAnyId(uid);
  }

  static String incomingRequesterLabel(Map<String, dynamic> row) =>
      InterestIdentityResolver.accessRequesterDisplayName(row);
}
