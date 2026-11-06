<#
.SYNOPSIS
  Builds the release APK and copies it to a file you can send to friends.

.DESCRIPTION
  Every APK that reaches dist\ is checked against android\weeds-keystore.jks,
  the key all Weed ID Trainer APKs are signed with. A release build made without
  that key falls back to Flutter's debug key, and Android refuses to install a
  differently signed APK over an existing one - the friend would have to
  uninstall first and lose their saved deck. So an unsigned or wrong-key APK is
  never copied into dist; ask for it on purpose with -AllowDebugKey.

  android\key.properties and android\weeds-keystore.jks are gitignored: they are
  the only copy, so keep a backup off this machine.

.EXAMPLE
  .\build_apk.ps1                 # one universal APK (works on every phone)
  .\build_apk.ps1 -SplitAbi       # smaller per-CPU APKs (arm64 + armeabi-v7a)
  .\build_apk.ps1 -Both           # the universal APK and the per-CPU ones
  .\build_apk.ps1 -Open           # open the dist folder in Explorer when done
#>
param(
    [switch]$SplitAbi,
    [switch]$Both,
    [switch]$Open,
    [switch]$AllowDebugKey
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\flutter\bin\flutter.bat' }
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value

# Gradle needs a JDK. Use JAVA_HOME if it is set, otherwise the one the Android
# Studio installer drops in.
if (-not $env:JAVA_HOME) {
    $guess = Get-ChildItem 'C:\Program Files\Microsoft','C:\Program Files\Android\Android Studio' -Recurse -Filter java.exe -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
    if ($guess) {
        $env:JAVA_HOME = (Get-Item $guess.FullName).Directory.Parent.FullName
        Write-Host "JAVA_HOME was not set; using $env:JAVA_HOME" -ForegroundColor DarkGray
    }
}

Write-Host "Building Weed ID Trainer v$version ..." -ForegroundColor Cyan
# flutter writes only the flavours it is asked for and never cleans the output
# folder, so every flavour wanted in this run has to be built explicitly.
$wanted = @()
if ($SplitAbi -or $Both) { $wanted += '--split-per-abi' }
if ($Both -or (-not $SplitAbi)) { $wanted += $null }
$started = Get-Date
foreach ($flag in $wanted) {
    & $flutter build apk --release $(if ($flag) { $flag })
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed$(if ($flag) { " ($flag)" })" }
}

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# Only APKs this build actually wrote. flutter does not clean that folder, so
# an old -SplitAbi run leaves app-arm64-v8a-release.apk behind; copying it too
# would put a stale build in a file named after the current version.
$built = Get-ChildItem build\app\outputs\flutter-apk\*.apk |
    Where-Object { $_.LastWriteTime -ge $started }
if (-not $built) { throw "no APK came out of the build (expected build\app\outputs\flutter-apk)" }

# --- signing verification (before anything lands in dist) -----------------
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$apksigner = Get-ChildItem (Join-Path $sdk 'build-tools\*\apksigner.bat') -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $apksigner) {
    throw "apksigner.bat not found under $sdk\build-tools - install the Android SDK build-tools, or rebuild with -AllowDebugKey if you really mean an unsigned-key test build"
}

# What the release key's certificate looks like, straight from the keystore.
$expected = $null
$keyProps = Join-Path $PSScriptRoot 'android\key.properties'
if (Test-Path $keyProps) {
    $p = @{}
    foreach ($line in Get-Content $keyProps) {
        if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { $p[$matches[1]] = $matches[2] }
    }
    # Gradle resolves storeFile relative to android\app (that is where the
    # "../weeds-keystore.jks" in key.properties is written from), so do the same.
    $appDir = Join-Path $PSScriptRoot 'android\app'
    $ks = [IO.Path]::GetFullPath((Join-Path $appDir $p['storeFile']))
    if (-not (Test-Path $ks)) { throw "key.properties points at a missing keystore: $ks" }
    $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    if (-not (Test-Path $keytool)) { throw "keytool not found under JAVA_HOME=$env:JAVA_HOME - cannot check the release key" }
    # :env keeps the password out of the command line / process list.
    $alias = $p['keyAlias']
    $env:WEEDS_STOREPASS = $p['storePassword']
    try {
        $kt = & $keytool -list -v -keystore $ks -alias $alias '-storepass:env' 'WEEDS_STOREPASS' 2>&1
    } finally {
        Remove-Item Env:WEEDS_STOREPASS -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -ne 0) { throw "keytool could not read $ks (alias '$alias'): $($kt -join ' ')" }
    $fp = $kt | Select-String 'SHA-?256:\s*([0-9a-fA-F:]{40,})' | Select-Object -First 1
    if (-not $fp) { throw "no SHA-256 fingerprint in keytool output for $ks" }
    $expected = $fp.Matches[0].Groups[1].Value -replace ':', ''
    Write-Host "release key: $ks" -ForegroundColor DarkGray
} elseif (-not $AllowDebugKey) {
    throw "android\key.properties is missing, so this APK is signed with Flutter's debug key and your friends could not update over their installed copy. Restore it (back it up!) or use -AllowDebugKey."
}

$written = @()
foreach ($apk in $built) {
    $sig = & $apksigner.FullName verify --print-certs $apk.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$($apk.Name) is not signed correctly: $($sig -join ' ')"
    }
    $who = ($sig | Select-String 'Signer #1 certificate DN:\s*(.+)' | Select-Object -First 1)
    $got = ($sig | Select-String 'certificate SHA-256 digest:\s*([0-9a-fA-F:]+)' | Select-Object -First 1)
    if (-not $who -or -not $got) {
        throw "could not read the signer from $($apk.Name): $($sig -join ' ')"
    }
    $who = $who.Matches[0].Groups[1].Value
    $got = $got.Matches[0].Groups[1].Value -replace ':', ''
    if ($who -match 'Android Debug') {
        if (-not $AllowDebugKey) { throw "$($apk.Name) is signed with a debug key ('$who'). Friends cannot update in place - see -AllowDebugKey." }
        Write-Host "  WARNING: $($apk.Name) uses the debug key ('$who'); do not send this one" -ForegroundColor Yellow
    } elseif ($expected -and $got -ne $expected) {
        throw "$($apk.Name) is signed with the wrong key ($who, SHA-256 $got). Expected the weeds key ($expected)."
    } else {
        Write-Host "  signed: $who" -ForegroundColor DarkGray
    }

    $flavour = $apk.BaseName -replace '^app-', '' -replace '-?release$', ''
    $name = "Weed-ID-Trainer-$version" + $(if ($flavour) { "-$flavour" } else { '' }) + '.apk'
    $target = Join-Path $dist $name
    Copy-Item $apk.FullName $target -Force
    $written += $name
    Write-Host ("  -> {0}  ({1:N1} MB)" -f $target, ($apk.Length / 1MB)) -ForegroundColor Green
}

# -SplitAbi does not write the universal APK, and flutter never cleans dist, so a
# previous build's file can sit there under the very same version name. Warn
# about it rather than delete something the user may still want.
$stale = Get-ChildItem (Join-Path $dist "Weed-ID-Trainer-$version*.apk") |
    Where-Object { $written -notcontains $_.Name }
if ($stale) {
    Write-Host ""
    Write-Warning ("dist also holds " + (($stale | ForEach-Object Name) -join ', ') +
        ", which this build did not write (LastWriteTime " +
        (($stale | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime.ToString('dd/MM HH:mm')) +
        "). Same version name, older code - send the files listed above, or delete those.")
}

Write-Host "`nPut the .apk on the repo's Releases page, or send it to your friends (email, Drive,"
Write-Host "WeTransfer). On the phone they tap it once, allow 'install unknown apps', and it"
Write-Host "installs. Updates install over the top and keep the saved deck."
if ($Open) { Invoke-Item $dist }
