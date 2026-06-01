# Run after every `flutter pub get` to strip KGP declarations from plugin Gradle files
# (required for zero built-in Kotlin warnings until all plugins publish migrated builds).
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dart run tool/patch_built_in_kotlin_plugins.dart
exit $LASTEXITCODE
