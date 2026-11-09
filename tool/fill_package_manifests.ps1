# Fills the package managers' manifests in packaging\ (#244) for a release:
# the version, the release zip's address and its SHA-256. Writes
#   <Out>\scoop\gargosy.json                       (the GargIT/scoop-gargosy bucket's)
#   <Out>\winget\GargIT.Gargosy*.yaml              (for wingetcreate submit)
#   pwsh tool/fill_package_manifests.ps1 -Version 0.10.0 -Zip dist\Gargosy-0.10.0.zip -Out dist\packages
param(
  [Parameter(Mandatory)][string]$Version,
  [Parameter(Mandatory)][string]$Zip,
  [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Not a release version: $Version (previews aren't packaged)" }
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash.ToLowerInvariant()
$values = @{
  '{{VERSION}}' = $Version
  '{{URL}}'     = "https://github.com/GargIT/Gargosy/releases/download/v$Version/Gargosy-$Version.zip"
  '{{SHA256}}'  = $sha
  '{{DATE}}'    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
}
$here = Split-Path -Parent $PSScriptRoot
foreach ($kind in 'scoop', 'winget') {
  $to = Join-Path $Out $kind
  New-Item -ItemType Directory -Force $to | Out-Null
  foreach ($file in Get-ChildItem (Join-Path $here "packaging\$kind") -File) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($k in $values.Keys) { $text = $text.Replace($k, $values[$k]) }
    if ($text -match '\{\{[A-Z0-9]+\}\}') { throw "$($file.Name) has a value left to fill: $($Matches[0])" }
    [IO.File]::WriteAllText((Join-Path $to $file.Name), $text.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  }
}
Write-Host "Manifests for $Version (SHA-256 $sha) in $Out"
