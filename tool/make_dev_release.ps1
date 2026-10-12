# Builds the release zip with make_release.ps1 and installs it into a local
# Gargosy folder (C:\Retro\apps\gargosy by default), the way an update does:
# only the app files are replaced; roms\ emulators\ bios\ userdata\ stay.
#
#   pwsh tool/make_dev_release.ps1                          # build, pack, install
#   pwsh tool/make_dev_release.ps1 -NoBuild                 # pack the last build, install
#   pwsh tool/make_dev_release.ps1 -Target D:\Games\Gargosy # another folder
#   pwsh tool/make_dev_release.ps1 -Version 0.2.0-dev.3     # another version
param(
    [switch]$NoBuild,
    [string]$Version,
    [string]$Target = 'C:\Retro\apps\gargosy'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if (-not $Version) {
    $base = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^\s+]+)').Matches[0].Groups[1].Value
    $Version = "$base-dev"
}

# Files in use can't be replaced: stop before building if Gargosy runs from there.
$exe = Join-Path $Target 'Gargosy.exe'
$running = Get-Process -Name Gargosy -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and ($_.Path -ieq $exe) }
if ($running) { throw "Gargosy is running from $Target; close it first." }

$release = @{ Version = $Version }
if ($NoBuild) { $release.NoBuild = $true }
& (Join-Path $PSScriptRoot 'make_release.ps1') @release
if (-not $?) { throw 'make_release.ps1 failed' }

$zip = Join-Path $repo "dist\Gargosy-$Version.zip"
if (-not (Test-Path $zip)) { throw "No zip at $zip" }

$unpacked = Join-Path $repo 'dist\dev-install'
if (Test-Path $unpacked) { Remove-Item -Recurse -Force $unpacked }
Expand-Archive -Path $zip -DestinationPath $unpacked
$source = Join-Path $unpacked 'Gargosy'

# The user's folders are never touched; everything else is the app.
$keep = 'roms', 'emulators', 'bios', 'userdata'
New-Item -ItemType Directory -Force $Target | Out-Null
Get-ChildItem -Force $Target | Where-Object { $keep -notcontains $_.Name } |
    Remove-Item -Recurse -Force
Get-ChildItem -Force $source | Where-Object { $keep -notcontains $_.Name } |
    Copy-Item -Destination $Target -Recurse -Force
foreach ($d in $keep) {
    New-Item -ItemType Directory -Force (Join-Path $Target $d) | Out-Null
}

Remove-Item -Recurse -Force $unpacked
Write-Output "Installed Gargosy $Version in $Target"
