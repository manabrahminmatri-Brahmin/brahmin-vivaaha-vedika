// Patches Flutter plugin Android Gradle files so they do not declare KGP in source.
// Flutter's detector scans build.gradle text; built-in Kotlin is enabled via
// android/gradle.properties. Run after every `flutter pub get`:
//
//   dart run tool/patch_built_in_kotlin_plugins.dart
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

final _kgpLinePatterns = <RegExp>[
  RegExp(r'''^\s*apply\s+plugin:\s*['"]kotlin-android['"]\s*$''', multiLine: true),
  RegExp(
    r'''^\s*apply\s+plugin:\s*['"]org\.jetbrains\.kotlin\.android['"]\s*$''',
    multiLine: true,
  ),
  RegExp(r'''^\s*id\s*\(\s*["']kotlin-android["']\s*\)\s*$''', multiLine: true),
  RegExp(
    r'''^\s*id\s*\(\s*["']org\.jetbrains\.kotlin\.android["']\s*\)\s*$''',
    multiLine: true,
  ),
  RegExp(r'''^\s*id\s+['"]kotlin-android['"]\s*$''', multiLine: true),
  RegExp(
    r'''^\s*id\s+['"]org\.jetbrains\.kotlin\.android['"]\s*$''',
    multiLine: true,
  ),
];

final _conditionalKgpBlock = RegExp(
  r'''def\s+agpMajor\s*=\s*com\.android\.Version\.ANDROID_GRADLE_PLUGIN_VERSION\.tokenize\('\.'\)\[0\]\s+as\s+int\s*
if\s*\(\s*agpMajor\s*<\s*9\s*\)\s*\{\s*
\s*apply\s+plugin:\s*['"]kotlin-android['"]\s*
\}''',
  multiLine: true,
  dotAll: true,
);

final _conditionalKotlinOptions = RegExp(
  r'''\s*if\s*\(\s*agpMajor\s*<\s*9\s*\)\s*\{\s*
\s*kotlinOptions\s*\{[^}]*\}\s*
\}''',
  multiLine: true,
  dotAll: true,
);

final _buildscriptKgpClasspath = RegExp(
  r'''^\s*classpath\s*[\("].*kotlin-gradle-plugin.*[\)"]\s*$''',
  multiLine: true,
);

String _patchJvmTargets(String source) {
  var next = source;
  next = next.replaceAll('JavaVersion.VERSION_1_8', 'JavaVersion.VERSION_17');
  next = next.replaceAll('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17');
  next = next.replaceAll("jvmTarget = '1.8'", "jvmTarget = '17'");
  next = next.replaceAll('jvmTarget = "1.8"', 'jvmTarget = "17"');
  next = next.replaceAll('JvmTarget.JVM_1_8', 'JvmTarget.JVM_17');
  next = next.replaceAll('JvmTarget.JVM_11', 'JvmTarget.JVM_17');
  return next;
}

void main() {
  final packageConfig = File('.dart_tool/package_config.json');
  if (!packageConfig.existsSync()) {
    stderr.writeln('Run `flutter pub get` first.');
    exit(1);
  }

  final json =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>;
  final packages = json['packages'] as List<dynamic>;
  var patched = 0;

  for (final entry in packages) {
    final map = entry as Map<String, dynamic>;
    final name = map['name'] as String;
    final rootUri = map['rootUri'] as String;
    if (!rootUri.startsWith('file://')) continue;

    final root = Uri.parse(rootUri).toFilePath(windows: Platform.isWindows);
    final androidDir = Directory('$root${Platform.pathSeparator}android');
    if (!androidDir.existsSync()) continue;

    for (final gradleName in ['build.gradle', 'build.gradle.kts']) {
      final file = File('${androidDir.path}${Platform.pathSeparator}$gradleName');
      if (!file.existsSync()) continue;

      final original = file.readAsStringSync();
      var next = original;

      for (final pattern in _kgpLinePatterns) {
        next = next.replaceAll(pattern, '');
      }
      next = next.replaceAll(_conditionalKgpBlock, '');
      next = next.replaceAll(_conditionalKotlinOptions, '');
      next = next.replaceAll(_buildscriptKgpClasspath, '');
      next = _patchJvmTargets(next);

      // Collapse excessive blank lines introduced by removals.
      next = next.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      if (next == original) continue;

      file.writeAsStringSync(next);
      patched++;
      print('patched $name ($gradleName)');
    }
  }

  print(patched == 0
      ? 'No plugin Gradle files needed patching.'
      : 'Patched $patched Gradle file(s) for built-in Kotlin.');
}
