import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeService', () {
    test('should toggle dark mode', () {
      final service = ThemeService();
      expect(service.isDarkMode, false);
      service.toggleDarkMode();
      expect(service.isDarkMode, true);
    });

    test('should set theme color', () {
      final service = ThemeService();
      service.setPrimaryColor(0xFFE85D04);
      expect(service.primaryColor, 0xFFE85D04);
    });
  });

  group('BlockService', () {
    test('should block user', () {
      final service = BlockService();
      service.blockUser('user-1');
      expect(service.isBlocked('user-1'), true);
    });

    test('should unblock user', () {
      final service = BlockService();
      service.blockUser('user-1');
      service.unblockUser('user-1');
      expect(service.isBlocked('user-1'), false);
    });

    test('should get blocked users list', () {
      final service = BlockService();
      service.blockUser('user-1');
      service.blockUser('user-2');
      expect(service.blockedUsers.length, 2);
    });
  });

  group('likeService', () {
    test('should like profile', () {
      final service = likeService();
      service.likeProfile('profile-1');
      expect(service.isliked('profile-1'), true);
    });

    test('should remove from like', () {
      final service = likeService();
      service.likeProfile('profile-1');
      service.removelike('profile-1');
      expect(service.isliked('profile-1'), false);
    });

    test('should get liked count', () {
      final service = likeService();
      service.likeProfile('profile-1');
      service.likeProfile('profile-2');
      expect(service.likeCount, 2);
    });
  });

  group('InterestService', () {
    test('should send interest', () {
      final service = InterestService();
      service.sendInterest('user-1');
      expect(service.hasSentInterest('user-1'), true);
    });

    test('should cancel interest', () {
      final service = InterestService();
      service.sendInterest('user-1');
      service.cancelInterest('user-1');
      expect(service.hasSentInterest('user-1'), false);
    });
  });

  group('FilterService', () {
    test('should set age filter', () {
      final service = FilterService();
      service.setAgeRange(25, 35);
      expect(service.minAge, 25);
      expect(service.maxAge, 35);
    });

    test('should set location filter', () {
      final service = FilterService();
      service.setLocation('Hyderabad');
      expect(service.location, 'Hyderabad');
    });

    test('should clear all filters', () {
      final service = FilterService();
      service.setAgeRange(25, 35);
      service.setLocation('Hyderabad');
      service.clearFilters();
      expect(service.minAge, isNull);
      expect(service.location, isNull);
    });
  });
}

class ThemeService {
  bool _isDarkMode = false;
  int _primaryColor = 0xFFE85D04;

  bool get isDarkMode => _isDarkMode;
  int get primaryColor => _primaryColor;

  void toggleDarkMode() => _isDarkMode = !_isDarkMode;
  void setPrimaryColor(int color) => _primaryColor = color;
}

class BlockService {
  final Set<String> _blockedUsers = {};

  void blockUser(String userId) => _blockedUsers.add(userId);
  void unblockUser(String userId) => _blockedUsers.remove(userId);
  bool isBlocked(String userId) => _blockedUsers.contains(userId);
  List<String> get blockedUsers => _blockedUsers.toList();
}

class likeService {
  final Set<String> _liked = {};

  void likeProfile(String profileId) => _liked.add(profileId);
  void removelike(String profileId) => _liked.remove(profileId);
  bool isliked(String profileId) => _liked.contains(profileId);
  int get likeCount => _liked.length;
}

class InterestService {
  final Set<String> _sentInterests = {};

  void sendInterest(String userId) => _sentInterests.add(userId);
  void cancelInterest(String userId) => _sentInterests.remove(userId);
  bool hasSentInterest(String userId) => _sentInterests.contains(userId);
}

class FilterService {
  int? _minAge;
  int? _maxAge;
  String? _location;

  int? get minAge => _minAge;
  int? get maxAge => _maxAge;
  String? get location => _location;

  void setAgeRange(int min, int max) {
    _minAge = min;
    _maxAge = max;
  }

  void setLocation(String location) => _location = location;

  void clearFilters() {
    _minAge = null;
    _maxAge = null;
    _location = null;
  }
}
