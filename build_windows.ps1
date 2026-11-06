<#
.SYNOPSIS
  Builds the Windows 11 version and zips it into one file you can send.

.DESCRIPTION
  The Release folder is self-contained: the exe, flutter_windows.dll, the ICU
  data file and the data\ folder (which holds the 90 card images). Nothing is
  installed and nothing is fetched at runtime, so the zip runs from any folder
  on any Windows 11 PC - no Flutter, no Visual Studio, no internet.

.EXAMPLE
  .\build_windows.ps1            # -> dist\Weed-ID-Trainer-Windows-<version>.zip
  .\build_windows.ps1 -Open      # open the dist folder in Explorer when done
#>
param(
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Compress-Archive writes '\' into zip entry names, which some unzip tools turn
# into one giant file name. Build the archive by hand with '/' separators.
function New-RunnerZip {
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
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value

Write-Host "Building Windows release v$version ..." -ForegroundColor Cyan
& $flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$release = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'

# --- prove the bundle is complete before zipping it ------------------------
# A Release folder missing data\flutter_assets ships an app that opens and
# shows nothing but "Missing asset" placeholders.
$needed = @('weeds_flashcards.exe', 'flutter_windows.dll', 'data\app.so',
            'data\flutter_assets\AssetManifest.bin', 'data\icudtl.dat')
foreach ($f in $needed) {
    if (-not (Test-Path (Join-Path $release $f))) {
        throw "build\windows\x64\runner\Release\$f is missing - the bundle is incomplete"
    }
}

$assets = Get-ChildItem (Join-Path $release 'data\flutter_assets\assets') -Recurse -File -Filter *.jpg -ErrorAction SilentlyContinue
# Every card needs a front and a back in the bundle, so the count must match
# kDeck. A deck line without its two images ships an app that shows "Missing
# asset" for that card - same for a build that packed a stale asset folder.
$deckCards = (Select-String -Path (Join-Path $PSScriptRoot 'lib\main.dart') -Pattern "^\s+FlashCard\(id: '").Count
$have = ($assets | Measure-Object).Count
if ($have -ne 2 * $deckCards) {
    throw "the bundle has $have card images but kDeck has $deckCards cards (expected $(2 * $deckCards): one front + one back each)"
}
Write-Host "  card images bundled: $have ($deckCards cards)"

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist ("Weed-ID-Trainer-Windows-{0}.zip" -f $version.Split('+')[0])
New-RunnerZip -Source $release -ZipPath $zipPath

$mb = (Get-ChildItem $release -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("  -> {0}  ({1:N1} MB on disk, {2:N1} MB to send)" -f $zipPath, $mb, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
Write-Host "`nThey unzip it anywhere and double-click weeds_flashcards.exe."
if ($Open) { Invoke-Item $dist }
