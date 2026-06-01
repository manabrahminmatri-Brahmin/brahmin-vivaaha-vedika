# Re-apply Android namespace fix after `flutter pub get` (pub cache is mutable).
$pkgRoot = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
$dirs = Get-ChildItem -Path $pkgRoot -Filter "flutter_jailbreak_detection-*" -Directory -ErrorAction SilentlyContinue
if (-not $dirs) {
    Write-Error "flutter_jailbreak_detection not found under $pkgRoot"
    exit 1
}
$buildGradle = Join-Path $dirs[0].FullName "android\build.gradle"
$content = Get-Content $buildGradle -Raw
if ($content -match "namespace\s+'appmire\.be\.flutterjailbreakdetection'") {
    Write-Host "Already patched: $buildGradle"
    exit 0
}
$content = $content -replace "android \{\r?\n", "android {`n    namespace 'appmire.be.flutterjailbreakdetection'`n"
Set-Content -Path $buildGradle -Value $content -NoNewline
Write-Host "Patched namespace in $buildGradle"
