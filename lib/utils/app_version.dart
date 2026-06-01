/// Centralized app version management
/// This ensures version consistency across the entire app
class AppVersion {
  // App version and build number - update here only!
  static const String version = '1.1.0';
  static const String buildNumber = '2';
  static const String versionWithBuild = '$version+$buildNumber';
  
  // App metadata
  static const String appName = 'Mana Vivaaha Vedika';
  static const String appTagline = 'Connecting Brahmin Hearts';
  static const String appDescription = 'Premium Vivaaha Vedika App for Brahmin Community';
  
  // Version display formats
  static String get displayVersion => 'Version $version';
  static String get displayVersionWithBuild => 'Version $version ($buildNumber)';
  static String get displayVersionTelugu => 'వెర్షన్ $version';
  static String get displayVersionWithBuildTelugu => 'వెర్షన్ $version ($buildNumber)';
  
  // For package_info integration
  static String get packageName => 'com.manavivaahavedika.brahmin';
  
  // Version history for changelog
  static const List<Map<String, String>> versionHistory = [
    {
      'version': '1.1.0',
      'build': '2',
      'date': '2026-03-13',
      'changes': 'Enhanced parent details entry with 100-word limit, improved recently added profiles',
    },
    {
      'version': '1.0.0', 
      'build': '1',
      'date': '2026-02-01',
      'changes': 'Initial release with core Vivaaha Vedika features',
    },
  ];
  
  /// Get current version info
  static Map<String, String> getCurrentVersion() {
    return {
      'version': version,
      'build': buildNumber,
      'full': versionWithBuild,
      'display': displayVersion,
      'displayWithBuild': displayVersionWithBuild,
      'name': appName,
      'tagline': appTagline,
    };
  }
  
  /// Check if current version is newer than given version
  static bool isNewerThan(String compareVersion) {
    final currentParts = version.split('.').map(int.parse).toList();
    final compareParts = compareVersion.split('.').map(int.parse).toList();
    
    for (int i = 0; i < currentParts.length && i < compareParts.length; i++) {
      if (currentParts[i] > compareParts[i]) return true;
      if (currentParts[i] < compareParts[i]) return false;
    }
    
    return currentParts.length > compareParts.length;
  }
}
