<#
.SYNOPSIS
  Builds the web version (the one you send to iPhone friends as a link).

.DESCRIPTION
  The build is deliberately self-contained: --no-web-resources-cdn makes
  Flutter ship its own CanvasKit and Roboto inside build\web instead of
  fetching them from Google's CDN, so the page works on a network that blocks
  gstatic, and offline once opened (web\app_service_worker.js).

.EXAMPLE
  .\build_web.ps1                          # build for a site root (netlify, cloudflare, your own domain)
  .\build_web.ps1 -BaseHref /weeds/        # GitHub Pages project site: username.github.io/weeds/
  .\build_web.ps1 -Serve                   # build, then preview at http://127.0.0.1:8899
  .\build_web.ps1 -Zip                     # also write dist\weeds-web.zip for drag-and-drop hosts
  .\build_web.ps1 -Full                    # keep the wasm-renderer copies this app never loads
#>
param(
    [string]$BaseHref = '/',
    [switch]$Serve,
    [switch]$Zip,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Compress-Archive writes '\' into zip entry names, which some hosts turn into
# one giant file name. Build the archive by hand with '/' separators instead.
function New-WebZip {
    param([string]$Source, [string]$ZipPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression   # for ZipArchiveMode (PS 5.1)
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $root = (Get-Item $Source).FullName.TrimEnd('\', '/')
        Get-ChildItem $root -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relative)
        }
    } finally {
        $zip.Dispose()
    }
}

$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\flutter\bin\flutter.bat' }

Write-Host "Building web release (base href $BaseHref) ..." -ForegroundColor Cyan
& $flutter build web --release --base-href $BaseHref --no-web-resources-cdn
if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }

$out = Join-Path $PSScriptRoot 'build\web'

# --- prove the self-containment actually happened -------------------------
# useLocalCanvasKit is the switch that keeps the page from phoning home to
# gstatic. If a Flutter upgrade changes the flag, fail here rather than ship a
# build that needs the internet.
$bootstrap = Get-Content (Join-Path $out 'flutter_bootstrap.js') -Raw
if ($bootstrap -notmatch '"useLocalCanvasKit":true') {
    throw "build\web\flutter_bootstrap.js does not use the local CanvasKit; the page would need Google's CDN."
}

# --- stamp the service worker so browsers notice each new build ----------
$sw = Join-Path $out 'app_service_worker.js'
if (Test-Path $sw) {
    $version = Get-Date -Format 'yyyyMMddHHmmss'
    (Get-Content $sw -Raw).Replace('__BUILD_VERSION__', $version) | Set-Content $sw -NoNewline -Encoding utf8
    Write-Host "  service worker version: $version"
}

# --- the deck must be in there -------------------------------------------
# 90 images (45 fronts + 45 backs) ship inside the bundle; a stale or empty
# assets folder means the page loads and shows "Missing asset" for every card.
$images = @(Get-ChildItem (Join-Path $out 'assets\assets') -Recurse -File -Filter *.jpg -ErrorAction SilentlyContinue)
$deckCards = (Select-String -Path (Join-Path $PSScriptRoot 'lib\main.dart') -Pattern "^\s+FlashCard\(id: '").Count
if ($images.Count -ne 2 * $deckCards) {
    throw "the web bundle has $($images.Count) card images but kDeck has $deckCards cards (expected $(2 * $deckCards): one front + one back each)"
}
Write-Host "  card images bundled: $($images.Count) ($deckCards cards)"

# --- drop files this build can never request -----------------------------
# *.symbols are for de-obfuscating --wasm stack traces, and skwasm/wimp are the
# renderers used by `flutter build wasm`. This app compiles to dart2js with the
# canvaskit renderer, so only canvaskit/ and canvaskit\chromium\ are used.
if (-not $Full) {
    # -Filter, not -Include: -Include binds oddly to a plain -Path on PS 5.1
    # and has failed this line once already.
    $dead = @(Get-ChildItem $out -Recurse -File -Filter '*.symbols') +
            @(Get-ChildItem (Join-Path $out 'canvaskit') -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(skwasm|skwasm_heavy|wimp)\.(js|wasm)$' })
    $freed = ($dead | Measure-Object Length -Sum).Sum
    $dead | Remove-Item -Force
    Write-Host ("  pruned {0:N1} MB of renderer copies this build does not use" -f ($freed / 1MB))
}

$mb = (Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("  -> {0}  ({1:N1} MB on disk, images load one card at a time)" -f $out, $mb) -ForegroundColor Green

if ($Zip) {
    $dist = Join-Path $PSScriptRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    # NB: not "$zip" - PowerShell names are case-insensitive, so that would
    # collide with the -Zip switch parameter.
    $zipPath = Join-Path $dist 'weeds-web.zip'
    New-WebZip -Source $out -ZipPath $zipPath
    Write-Host ("  -> {0}  ({1:N1} MB to upload)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
}

if ($Serve) {
    Write-Host "`nServing at http://127.0.0.1:8899  (Ctrl+C to stop)" -ForegroundColor Cyan
    Push-Location $out
    try { python -m http.server 8899 --bind 127.0.0.1 } finally { Pop-Location }
}
