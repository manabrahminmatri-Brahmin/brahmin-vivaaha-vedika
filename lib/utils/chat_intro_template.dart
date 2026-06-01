import '../models/gender.dart';
import '../models/user.dart';

/// Builds a ready-to-send English intro: interest + brief profile + contact (no network).
/// Copy is first-person when [UserProfile.profileCreatedBy] is Self; otherwise it reflects
/// the creator (e.g. parents → "my son/daughter", sibling → "my brother/sister").
class ChatIntroTemplate {
  ChatIntroTemplate._();

  static const int _maxAboutLen = 220;

  static bool _isSelfProfile(User me) {
    final by = me.profile?.profileCreatedBy?.trim();
    return by == null || by.isEmpty || by == 'Self';
  }

  /// Noun phrase for the candidate when someone else manages the profile (e.g. "son", "brother").
  static String? _kinshipNoun(String? createdBy, Gender g) {
    switch (createdBy) {
      case 'Father':
      case 'Mother':
        return g == Gender.female ? 'daughter' : 'son';
      case 'Brother':
        return 'brother';
      case 'Sister':
        return 'sister';
      case 'Uncle (Maternal)':
      case 'Uncle (Paternal)':
      case 'Aunt (Maternal)':
      case 'Aunt (Paternal)':
        return g == Gender.female ? 'niece' : 'nephew';
      case 'Grandfather':
      case 'Grandmother':
        return g == Gender.female ? 'granddaughter' : 'grandson';
      case 'Friend':
        return 'friend';
      case 'Guardian':
        return 'ward';
      case 'Relative':
        return 'relative';
      case 'Other':
        return null;
      default:
        return null;
    }
  }

  /// Closing line after "Regards," — e.g. "Rahul's father", or the candidate name for Self.
  static String _regardsSignature(User me, String name) {
    if (_isSelfProfile(me)) return name;

    final by = me.profile?.profileCreatedBy?.trim() ?? '';
    final otherRelation = me.profile?.profileCreatedByRelation?.trim();

    if (by == 'Other' && otherRelation != null && otherRelation.isNotEmpty) {
      return "$name's $otherRelation";
    }

    switch (by) {
      case 'Father':
        return "$name's father";
      case 'Mother':
        return "$name's mother";
      case 'Brother':
        return "$name's brother";
      case 'Sister':
        return "$name's sister";
      case 'Uncle (Maternal)':
        return "$name's maternal uncle";
      case 'Uncle (Paternal)':
        return "$name's paternal uncle";
      case 'Aunt (Maternal)':
        return "$name's maternal aunt";
      case 'Aunt (Paternal)':
        return "$name's paternal aunt";
      case 'Grandfather':
        return "$name's grandfather";
      case 'Grandmother':
        return "$name's grandmother";
      case 'Friend':
        return "$name's friend";
      case 'Guardian':
        return "$name's guardian";
      case 'Relative':
        return "$name's family";
      default:
        return "$name's family";
    }
  }

  static String build({
    required User me,
    String? peerFirstName,
  }) {
    final displayName = '${me.firstName} ${me.lastName}'.trim();
    final name = displayName.isNotEmpty ? displayName : me.profileId;
    final given = (me.profile?.firstName ?? me.firstName).trim();
    final aboutSubject = given.isNotEmpty ? given : name;

    final phone = me.mobileNumber.trim();
    final alt = me.alternativeMobileNumber?.trim();
    final contact = [
      if (phone.isNotEmpty) phone,
      if (alt != null && alt.isNotEmpty) alt,
    ].join(' / ');
    final contactLine = contact.isNotEmpty ? contact : '—';

    final about = (me.profile?.aboutMe ?? '').trim();
    final aboutShort = about.isEmpty
        ? ''
        : (about.length > _maxAboutLen
            ? '${about.substring(0, _maxAboutLen)}…'
            : about);

    final city = (me.profile?.city ?? '').trim();
    final occ = (me.profile?.occupation ?? '').trim();
    final edu = (me.profile?.education ?? '').trim();
    final age = me.age;
    final greet = (peerFirstName ?? '').trim();
    final g = me.gender;

    final createdBy = me.profile?.profileCreatedBy?.trim();
    final selfProfile = _isSelfProfile(me);
    final kin = selfProfile ? null : _kinshipNoun(createdBy, g);
    final otherRelation = me.profile?.profileCreatedByRelation?.trim();

    final salutation =
        greet.isNotEmpty ? 'Namaskaram $greet,\n\n' : 'Namaskaram,\n\n';

    final String interestBlock;
    if (selfProfile) {
      interestBlock =
          'I came across your profile on the platform and would like to '
          'express my interest in getting to know you better.\n\n';
    } else if (createdBy == 'Other' &&
        otherRelation != null &&
        otherRelation.isNotEmpty) {
      interestBlock =
          'I am reaching out on behalf of my $otherRelation, $name. We came across '
          'your profile on the platform and would like to express our interest in '
          'getting to know you better.\n\n';
    } else if (kin != null) {
      interestBlock =
          'I am reaching out on behalf of my $kin, $name. We came across your '
          'profile on the platform and would like to express our interest in '
          'getting to know you better.\n\n';
    } else {
      interestBlock =
          'On behalf of $name, we came across your profile on the platform and would '
          'like to express our interest in getting to know you better.\n\n';
    }

    final aboutHeading =
        selfProfile ? 'A little about me:\n' : 'A little about $aboutSubject:\n';

    final loc = city.isNotEmpty ? ' • Based in $city' : '';
    final eduLine = edu.isNotEmpty ? '\n• Education: $edu' : '';
    final occLine = occ.isNotEmpty ? '\n• Profession: $occ' : '';
    final aboutBlock = aboutShort.isNotEmpty ? '\n\n$aboutShort\n' : '\n';

    final regards = _regardsSignature(me, name);
    final reachLine = selfProfile
        ? 'You can reach me at: $contactLine\n\n'
        : 'You can reach us at: $contactLine\n\n';

    return '$salutation'
        '$interestBlock'
        '$aboutHeading'
        '• Name: $name (Profile ID: ${me.profileId})\n'
        '• Age: $age$loc$eduLine$occLine'
        '$aboutBlock'
        '$reachLine'
        'Looking forward to your response.\n\n'
        'Regards,\n'
        '$regards';
  }
}
