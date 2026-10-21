# Builds Gargosy and packs the release zip (spec §9): it unpacks to Gargosy\
# with the app, empty roms\ emulators\ bios\ userdata\ folders, the
# licence files and app-files.txt (what GargosyUpdate.exe replaces). There
# is no installer.
#
#   pwsh tool/make_release.ps1                            # build, then pack
#   pwsh tool/make_release.ps1 -NoBuild                   # pack the last build
#   pwsh tool/make_release.ps1 -Version 0.2.0-preview.4   # another version (previews)
param([switch]$NoBuild, [string]$Version)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$version = if ($Version) { $Version } else { (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^\s+]+)').Matches[0].Groups[1].Value }
if (-not $NoBuild) {
    # Flutter's incremental build can keep an old icon font subset, so icons
    # first used since then show as nothing: its assets are made fresh.
    foreach ($assets in @('build\flutter_assets', 'build\windows\x64\runner\Release\data\flutter_assets')) {
        if (Test-Path $assets) { Remove-Item -Recurse -Force $assets }
    }
    # --build-name puts the version in Gargosy.exe, where About reads it.
    flutter build windows --release --build-name $version
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

# The in-app updater (issue #16) ships beside Gargosy.exe.
if (-not (Test-Path (Join-Path $stage 'GargosyUpdate.exe'))) { throw 'GargosyUpdate.exe is not in the build' }

# app-files.txt: every app file, the list GargosyUpdate.exe replaces and
# nothing else (the user's folders are never on it).
$userFolders = 'roms', 'emulators', 'bios', 'userdata'
$appFiles = Get-ChildItem -Recurse -File $stage | ForEach-Object {
    $_.FullName.Substring($stage.Length).TrimStart('\', '/')
} | Where-Object { $userFolders -notcontains ($_ -split '[\\/]')[0].ToLowerInvariant() }
$appFiles = @($appFiles) + 'app-files.txt' | Sort-Object -Unique
# CRLF, no BOM: the updater and Gargosy both read it.
[System.IO.File]::WriteAllText((Join-Path $stage 'app-files.txt'), (($appFiles -join "`r`n") + "`r`n"))

$zip = Join-Path $dist "Gargosy-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
# includeBaseDirectory: the zip holds Gargosy\..., empty folders included.
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Output "Wrote $zip"
