<#
.SYNOPSIS
  Builds the DB Client release files into binary\ at the project root.

.DESCRIPTION
  Produces, from the current app\ source:
    binary\db-client-windows-x64-setup.exe   Windows installer (Inno Setup)
    binary\db-client-windows-x64.zip         Windows portable zip
    binary\db-client-linux-x64.tar.gz        Linux bundle (built in Podman)
    binary\db-client-android.apk             Android app (all CPU types)

  macOS and iOS can only be built on a Mac (or by the GitHub release
  workflow, for macOS).

  Needs: Flutter, Visual Studio Build Tools (C++ and ATL), Inno Setup 6
  (winget install JRSoftware.InnoSetup), the Android SDK and, for Linux, a
  running Podman machine. The first Linux build creates a reusable
  container image with Flutter in it, which takes a while; later builds
  reuse it.

  The APK is signed with the release key named in app\android\key.properties
  (kept out of git). Without that file it is signed with this PC's debug key,
  and phones that installed a release-signed APK can't update to it.

.EXAMPLE
  .\scripts\build-release.ps1
.EXAMPLE
  .\scripts\build-release.ps1 -SkipLinux -SkipTests
#>
[CmdletBinding()]
param(
  # Installer version; defaults to the version in app\pubspec.yaml.
  [string]$Version,
  [switch]$SkipWindows,
  [switch]$SkipLinux,
  [switch]$SkipAndroid,
  # Skip `flutter analyze` and `flutter test` before building.
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$out = Join-Path $root 'binary'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }

# Runs a native command and stops the script if it fails.
function Run([string]$exe, [string[]]$arguments) {
  & $exe @arguments
  if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed (exit $LASTEXITCODE)" }
}

function Find-Tool([string]$name, [string[]]$candidates) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

$flutter = Find-Tool 'flutter' @(
  $(if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' }),
  (Join-Path $env:USERPROFILE 'dev\flutter\bin\flutter.bat'))
if (-not $flutter) { throw 'Flutter not found. Add it to PATH or set FLUTTER_ROOT.' }

if (-not $Version) {
  $line = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)'
  $Version = $line.Matches[0].Groups[1].Value
}
Write-Host "DB Client $Version -> $out"

New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $app
try {
  if (-not $SkipTests) {
    Step 'Analyze and test'
    Run $flutter @('analyze')
    Run $flutter @('test')
  }

  if (-not $SkipWindows) {
    $iscc = Find-Tool 'iscc' @(
      (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'))
    if (-not $iscc) { throw 'Inno Setup 6 not found: winget install JRSoftware.InnoSetup' }

    Step 'Build Windows'
    Run $flutter @('build', 'windows', '--release')

    Step 'Package Windows zip'
    $stage = Join-Path ([IO.Path]::GetTempPath()) 'db-client-zip'
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    $folder = Join-Path $stage 'DB Client'
    New-Item -ItemType Directory -Force $folder | Out-Null
    Copy-Item -Recurse 'build\windows\x64\runner\Release\*' $folder
    # The Visual C++ runtime, so the app starts on PCs without it.
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
      Copy-Item (Join-Path $env:WINDIR "System32\$dll") $folder
    }
    $zip = Join-Path $out 'db-client-windows-x64.zip'
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path $folder -DestinationPath $zip
    Remove-Item -Recurse -Force $stage

    Step 'Build Windows installer'
    Run $iscc @('/Q', "/DAppVersion=$Version", 'windows\installer\db-client.iss')
    Copy-Item -Force 'build\installer\db-client-windows-x64-setup.exe' $out
  }

  if (-not $SkipAndroid) {
    Step 'Build Android'
    if (-not (Test-Path 'android\key.properties')) {
      Write-Warning 'android\key.properties not found: the APK is signed with the debug key.'
    }
    Run $flutter @('build', 'apk', '--release')
    Copy-Item -Force 'build\app\outputs\flutter-apk\app-release.apk' (Join-Path $out 'db-client-android.apk')
  }

  if (-not $SkipLinux) {
    $podman = Find-Tool 'podman' @()
    if (-not $podman) { throw 'Podman not found; install it or pass -SkipLinux.' }

    # Same Flutter version as this machine, so both builds match.
    $flutterVersion = (& $flutter --version --machine | ConvertFrom-Json).frameworkVersion
    $image = "localhost/db-client-linux-build:$flutterVersion"
    & $podman image exists $image
    if ($LASTEXITCODE -ne 0) {
      Step "Create Linux build image (Flutter $flutterVersion, first time only)"
      Run $podman @('build', '-t', $image, '--build-arg', "FLUTTER_VERSION=$flutterVersion",
        (Join-Path $root 'scripts\linux'))
    }

    Step 'Build Linux'
    # The current source, uncommitted edits included (untracked files are
    # not); written to a file because PowerShell pipes corrupt binary data.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'db-client-linux-src'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $ref = (& git -C $root stash create)
    if (-not $ref) { $ref = 'HEAD' }
    Run 'git' @('-C', $root, 'archive', '-o', (Join-Path $tmp 'source.tar'), $ref, 'app')
    Run $podman @('run', '--rm',
      '-v', "$($tmp -replace '\\', '/'):/in:ro",
      '-v', "$($out -replace '\\', '/'):/out",
      '-v', 'db-client-pub-cache:/root/.pub-cache',
      $image, 'bash', '/usr/local/bin/build-db-client')
    Remove-Item -Recurse -Force $tmp
  }
}
finally {
  Pop-Location
}

Step 'Done'
Get-ChildItem $out -File | ForEach-Object {
  '{0,-36} {1,6:N1} MB' -f $_.Name, ($_.Length / 1MB)
}
