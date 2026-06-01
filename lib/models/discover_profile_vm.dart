class DiscoverProfileVm {
  final String userId;
  final String profileId;
  final String name;
  final int age;
  final String profession;
  final String city;
  final String imageUrl;
  final bool isPremium;
  /// Owner set photo hidden/private — hide in discover/carousel for strangers.
  final bool isPhotoHiddenFromOthers;
  final String compatibilityLabel;
  final String heroTag;

  const DiscoverProfileVm({
    required this.userId,
    required this.profileId,
    required this.name,
    required this.age,
    required this.profession,
    required this.city,
    required this.imageUrl,
    required this.isPremium,
    this.isPhotoHiddenFromOthers = false,
    required this.compatibilityLabel,
    required this.heroTag,
  });
}
