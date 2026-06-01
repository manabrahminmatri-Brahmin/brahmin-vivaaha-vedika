import '../models/user.dart';

/// Best-effort profile photo URL for list/detail widgets.
///
/// Photos are often stored only on the Firestore user root while [UserProfile]
/// was parsed from a partial nested `profile` map — without this helper list
/// cards show initial-letter avatars even when the member has a photo.
String resolveProfilePhotoUrl({
  UserProfile? profile,
  Map<String, dynamic>? userDoc,
}) {
  String? pick(String? s) {
    final t = (s ?? '').trim();
    return t.isNotEmpty ? t : null;
  }

  String? pickDynamic(dynamic v) {
    if (v == null) return null;
    if (v is String) return pick(v);
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return s;
    }
    return null;
  }

  String? fromMap(Map<String, dynamic> m) {
    for (final key in const [
      'profile_picture',
      'profilePicture',
      'photo_url',
      'photoUrl',
      'avatar',
      'photo',
      'image',
      'profile_image',
      'display_photo',
    ]) {
      final u = pickDynamic(m[key]);
      if (u != null) return u;
    }
    final photos = m['photos'];
    if (photos is List) {
      for (final e in photos) {
        if (e is String) {
          final u = pick(e);
          if (u != null) return u;
        } else if (e is Map) {
          for (final key in const ['url', 'photo_url', 'photoUrl', 'src']) {
            final u = pickDynamic(e[key]);
            if (u != null) return u;
          }
        }
      }
    }
    return null;
  }

  final fromProfile = pick(profile?.profilePicture);
  if (fromProfile != null) return fromProfile;

  final gallery = profile?.photos;
  if (gallery != null) {
    for (final url in gallery) {
      final u = pick(url);
      if (u != null) return u;
    }
  }

  if (userDoc != null) {
    final root = fromMap(userDoc);
    if (root != null) return root;
    final nested = userDoc['profile'];
    if (nested is Map<String, dynamic>) {
      final inner = fromMap(nested);
      if (inner != null) return inner;
    }
  }

  return '';
}

/// True when we should mount the authenticated photo proxy even without a
/// legacy direct URL on the profile object.
bool shouldAttemptProfilePhotoProxy({
  required String? ownerUserId,
  bool isOwner = false,
}) {
  if (isOwner) return false;
  final owner = (ownerUserId ?? '').trim();
  if (owner.isEmpty) return false;
  return true;
}
