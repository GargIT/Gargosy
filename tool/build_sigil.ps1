# Builds sigil.dll into build\sigil\Release for the tests (flutter test doesn't
# run the Windows build). The app's own build compiles sigil through
# windows\CMakeLists.txt. Needs the submodule: git submodule update --init --recursive
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
if (-not $cmake) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $vs = & $vswhere -latest -prerelease -products * -property installationPath
  $cmake = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
}
& $cmake -B "$root\build\sigil" -S "$root\third_party\argosy-sigil" `
  -DSIGIL_BUILD_SHARED=ON -DSIGIL_BUILD_CLI=OFF -DSIGIL_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw 'configuring sigil failed' }
& $cmake --build "$root\build\sigil" --config Release
if ($LASTEXITCODE -ne 0) { throw 'building sigil failed' }
if (-not (Test-Path "$root\build\sigil\Release\sigil.dll")) { throw 'sigil.dll was not built' }
