# Copy published site from web_deploy/ to repo root (for GitHub Pages branch deploy).
# Run after editing web_deploy/:  .\scripts\sync-web-deploy-to-root.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root "web_deploy"

$logoRoot = Join-Path $src "app_logo.png"
$logo256 = Join-Path $src "assets\app_logo-256.png"
$logoFull = Join-Path $src "assets\app_logo.png"
if (-not (Test-Path $logoRoot)) {
  if (Test-Path $logo256) { Copy-Item -Force $logo256 $logoRoot }
  elseif (Test-Path $logoFull) { Copy-Item -Force $logoFull $logoRoot }
}

foreach ($f in @("index.html", "privacy.html", "terms.html", "app_logo.png", "favicon.png")) {
  $from = Join-Path $src $f
  if (Test-Path $from) { Copy-Item -Force $from (Join-Path $root $f) }
}
$assetsSrc = Join-Path $src "assets"
$assetsDst = Join-Path $root "assets"
if (Test-Path $assetsSrc) {
  New-Item -ItemType Directory -Force -Path $assetsDst | Out-Null
  Copy-Item -Force -Recurse "$assetsSrc\*" $assetsDst
}
Write-Host "Synced web_deploy -> repo root."
