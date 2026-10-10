# Builds Gargosy and packs the release zip (spec §9): it unpacks to Gargosy\
# with the app, empty roms\ emulators\ bios\ userdata\ folders and the
# licence files. There is no installer.
#
#   pwsh tool/make_release.ps1            # build, then pack
#   pwsh tool/make_release.ps1 -NoBuild   # pack the last build
param([switch]$NoBuild)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^\s+]+)').Matches[0].Groups[1].Value
if (-not $NoBuild) {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

$built = Join-Path $repo 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $built 'Gargosy.exe'))) { throw "No build in $built" }

$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist 'Gargosy'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

Copy-Item -Recurse (Join-Path $built '*') $stage
foreach ($d in 'roms', 'emulators', 'bios', 'userdata') {
    New-Item -ItemType Directory -Force (Join-Path $stage $d) | Out-Null
}
Copy-Item LICENSE, NOTICE.md, README.md, CHANGELOG.md, SECURITY.md $stage
Copy-Item -Recurse LICENSES (Join-Path $stage 'LICENSES')

$zip = Join-Path $dist "Gargosy-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
# includeBaseDirectory: the zip holds Gargosy\..., empty folders included.
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Output "Wrote $zip"
