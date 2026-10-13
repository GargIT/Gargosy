# Tests GargosyUpdate.exe (issue #16) against fake Gargosy folders: each case
# has roms\, emulators\, bios\ and userdata\, an old app with its
# app-files.txt, a file the user put there, and a new version unpacked in
# userdata\app\update\Gargosy. Windows PowerShell 5.1 (it compiles the fake
# Gargosy.exe with Add-Type).
#
#   powershell -File tool/test_updater.ps1                 # build, then test
#   powershell -File tool/test_updater.ps1 -Exe <path>     # test that build
param([string]$Exe)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Exe) {
    $build = Join-Path $repo 'build\updater'
    cmake -S (Join-Path $repo 'windows\updater') -B $build -A x64 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
    cmake --build $build --config Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }
    $Exe = Join-Path $build 'Release\GargosyUpdate.exe'
}
if (-not (Test-Path $Exe)) { throw "No updater at $Exe" }

# A space in the path: the arguments must be quoted right.
$work = Join-Path ([IO.Path]::GetTempPath()) "gargosy update test $PID"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory $work | Out-Null

# The fake Gargosy.exe: writes which version it is and its arguments to
# launched.txt beside itself.
function New-FakeGargosy([string]$variant, [string]$path) {
    $src = @"
using System; using System.IO;
public static class FakeGargosy {
    public static void Main(string[] args) {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(dir, "launched.txt"), "$variant\n" + string.Join("\n", args));
    }
}
"@
    Add-Type -TypeDefinition $src -OutputAssembly $path -OutputType ConsoleApplication -Language CSharp
}
$oldExe = Join-Path $work 'old.exe'
$newExe = Join-Path $work 'new.exe'
New-FakeGargosy 'old' $oldExe
New-FakeGargosy 'new' $newExe

function Write-Text([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text)
}

function New-Case([string]$name, [string[]]$newList) {
    $root = Join-Path $work $name
    # The user's things.
    Write-Text "$root\roms\psx\Game (USA).cue" 'FILE "Game (USA).bin" BINARY'
    Write-Text "$root\emulators\duckstation\duckstation-qt-x64-ReleaseLTCG.exe" 'MZ emulator'
    Write-Text "$root\bios\scph1001.bin" 'bios'
    Write-Text "$root\userdata\settings.json" '{"update.channel":"preview"}'
    Write-Text "$root\userdata\profiles\p1\emulators\duckstation\memcards\SLUS-00001_1.mcd" 'card'
    Write-Text "$root\my notes.txt" 'the user put this here'
    # The old app.
    Copy-Item $oldExe "$root\Gargosy.exe"
    Write-Text "$root\flutter_windows.dll" 'old flutter'
    Write-Text "$root\old_plugin.dll" 'dropped in the new version'
    Write-Text "$root\GargosyUpdate.exe" 'old updater'
    Write-Text "$root\data\icudtl.dat" 'old icu'
    Write-Text "$root\data\flutter_assets\old\asset.txt" 'old asset'
    Write-Text "$root\app-files.txt" ((@('Gargosy.exe', 'flutter_windows.dll', 'old_plugin.dll', 'GargosyUpdate.exe',
                'data\icudtl.dat', 'data\flutter_assets\old\asset.txt', 'app-files.txt') -join "`r`n") + "`r`n")
    # The new version, unpacked.
    $from = "$root\userdata\app\update\Gargosy"
    New-Item -ItemType Directory -Force $from | Out-Null
    Copy-Item $newExe "$from\Gargosy.exe"
    Write-Text "$from\flutter_windows.dll" 'new flutter'
    Write-Text "$from\GargosyUpdate.exe" 'new updater'
    Write-Text "$from\data\icudtl.dat" 'new icu'
    Write-Text "$from\data\flutter_assets\new\asset.txt" 'new asset'
    Write-Text "$from\sigil.dll" 'new sigil'
    if (-not $newList) {
        $newList = @('Gargosy.exe', 'flutter_windows.dll', 'GargosyUpdate.exe', 'data\icudtl.dat',
            'data\flutter_assets\new\asset.txt', 'sigil.dll', 'app-files.txt')
    }
    Write-Text "$from\app-files.txt" (($newList -join "`r`n") + "`r`n")
    return $root
}

# SHA-256 of every file under [dir] (relative path => hash), for "byte for byte the same".
function Get-Tree([string]$dir) {
    $map = @{}
    if (Test-Path $dir) {
        Get-ChildItem -Recurse -File $dir | ForEach-Object {
            $map[$_.FullName.Substring($dir.Length)] = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash
        }
    }
    return $map
}

function Get-UserTrees([string]$root) {
    $t = @{}
    foreach ($d in 'roms', 'emulators', 'bios') { $t[$d] = Get-Tree "$root\$d" }
    # userdata\app\update is the updater's own folder (log, previous\).
    $t['userdata'] = Get-Tree "$root\userdata" | ForEach-Object { $m = $_; $o = @{}; foreach ($k in $m.Keys) { if ($k -notlike '\app\update\*') { $o[$k] = $m[$k] } }; $o }
    $t['notes'] = (Get-FileHash -Algorithm SHA256 "$root\my notes.txt").Hash
    return $t
}

function Assert-SameTrees($before, $after, [string]$what) {
    foreach ($k in $before.Keys) {
        if ($k -eq 'notes') {
            if ($before[$k] -ne $after[$k]) { throw "$what`: my notes.txt changed" }
            continue
        }
        $b = $before[$k]; $a = $after[$k]
        if ($b.Count -ne $a.Count) { throw "$what`: $k has $($a.Count) files, had $($b.Count)" }
        foreach ($f in $b.Keys) { if ($b[$f] -ne $a[$f]) { throw "$what`: $k$f changed" } }
    }
}

function Quote([string]$s) { if ($s -match '[\s"]') { '"' + $s + '"' } else { $s } }

function Invoke-Updater([string]$root, [int]$waitPid = 0, [int]$waitSeconds = 10) {
    if ($waitPid -eq 0) {
        # A process that has already exited, as Gargosy has by then.
        $gone = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'exit' -PassThru -WindowStyle Hidden
        $gone.WaitForExit()
        $waitPid = $gone.Id
    }
    $argList = @('--silent', '--pid', $waitPid, '--wait-seconds', $waitSeconds, '--root', (Quote $root),
        '--from', (Quote "$root\userdata\app\update\Gargosy"), '--version', '0.2.0', '--old-version', '0.1.0',
        '--', '--fullscreen', '"--root=D:\My Games"')
    $p = Start-Process -FilePath $Exe -ArgumentList $argList -PassThru -WindowStyle Hidden
    $null = $p.Handle # without it, Windows PowerShell loses the exit code
    $p.WaitForExit()
    return $p.ExitCode
}

function Get-Launched([string]$root) {
    $file = "$root\launched.txt"
    for ($i = 0; $i -lt 100 -and -not (Test-Path $file); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $file)) { return $null }
    Start-Sleep -Milliseconds 200
    return [IO.File]::ReadAllText($file) -split "`n"
}

function Assert-OldApp([string]$root, [string]$what) {
    if ((Get-Content -Raw "$root\flutter_windows.dll") -ne 'old flutter') { throw "$what`: flutter_windows.dll isn't the old one" }
    if (-not (Test-Path "$root\old_plugin.dll")) { throw "$what`: old_plugin.dll is gone" }
    if (Test-Path "$root\sigil.dll") { throw "$what`: the new sigil.dll is there" }
    if (-not (Test-Path "$root\data\flutter_assets\old\asset.txt")) { throw "$what`: an old asset is gone" }
}

$failures = 0
function Test-Case([string]$name, [scriptblock]$body) {
    try {
        & $body
        Write-Output "PASS  $name"
    } catch {
        $script:failures++
        Write-Output "FAIL  $name`n      $($_.Exception.Message)"
    }
}

Test-Case 'an update succeeds; the user''s folders are byte for byte the same' {
    $root = New-Case 'success'
    $before = Get-UserTrees $root
    $code = Invoke-Updater $root
    if ($code -ne 0) { throw "exit code $code; log: $(Get-Content -Raw "$root\userdata\app\update\update.log")" }
    if ((Get-Content -Raw "$root\flutter_windows.dll") -ne 'new flutter') { throw 'flutter_windows.dll is not the new one' }
    if ((Get-Content -Raw "$root\sigil.dll") -ne 'new sigil') { throw 'sigil.dll is missing' }
    if ((Get-Content -Raw "$root\app-files.txt") -notmatch 'sigil.dll') { throw 'app-files.txt is not the new list' }
    Assert-SameTrees $before (Get-UserTrees $root) 'success'
    $launched = Get-Launched $root
    if (-not $launched) { throw 'Gargosy was not started' }
    if ($launched[0] -ne 'new') { throw "the $($launched[0]) Gargosy was started" }
    if ($launched -notcontains '--fullscreen' -or $launched -notcontains '--root=D:\My Games') { throw "arguments not passed on: $launched" }
    if ($launched -notcontains '--updated-from=0.1.0') { throw "no --updated-from: $launched" }
    if (-not (Test-Path "$root\userdata\app\update\previous\flutter_windows.dll")) { throw 'the old files are not in previous\' }
}

Test-Case 'a file dropped from the new list is gone, and its empty folder too' {
    $root = New-Case 'dropped'
    if ((Invoke-Updater $root) -ne 0) { throw 'update failed' }
    if (Test-Path "$root\old_plugin.dll") { throw 'old_plugin.dll is still there' }
    if (Test-Path "$root\data\flutter_assets\old") { throw 'the old asset folder is still there' }
}

Test-Case 'a file outside the list (the user''s) stays' {
    $root = New-Case 'user-file'
    if ((Invoke-Updater $root) -ne 0) { throw 'update failed' }
    if ((Get-Content -Raw "$root\my notes.txt") -ne 'the user put this here') { throw 'my notes.txt changed' }
}

foreach ($bad in @('..\evil.txt', 'C:\Windows\evil.dll', 'userdata\settings.json', 'USERDA~1\settings.json', 'roms.\x', '\abs.dll')) {
    Test-Case "a list with '$bad' is refused before anything moves" {
        $root = New-Case "refused-$([Math]::Abs($bad.GetHashCode()))" @('Gargosy.exe', $bad, 'app-files.txt')
        $before = Get-UserTrees $root
        $code = Invoke-Updater $root
        if ($code -ne 4) { throw "exit code $code, not 4" }
        Assert-OldApp $root 'refused'
        Assert-SameTrees $before (Get-UserTrees $root) 'refused'
        if (Test-Path "$root\userdata\app\update\previous") { throw 'files were moved to previous\' }
        $launched = Get-Launched $root
        if (-not $launched -or $launched[0] -ne 'old' -or $launched -notcontains '--update-failed') { throw "the old Gargosy was not started with --update-failed: $launched" }
    }
}

Test-Case 'a file the update lacks is refused' {
    $root = New-Case 'missing' @('Gargosy.exe', 'nothere.dll', 'app-files.txt')
    if ((Invoke-Updater $root) -ne 4) { throw 'not refused' }
    Assert-OldApp $root 'missing'
}

Test-Case 'a locked file rolls back; the old Gargosy starts with --update-failed' {
    $root = New-Case 'locked'
    $before = Get-UserTrees $root
    $oldTree = Get-Tree $root
    # Locked part way down the list: the files moved before it must come back.
    $lock = [IO.File]::Open("$root\data\icudtl.dat", 'Open', 'ReadWrite', 'None')
    try { $code = Invoke-Updater $root } finally { $lock.Close() }
    if ($code -ne 1) { throw "exit code $code, not 1" }
    Assert-OldApp $root 'locked'
    Assert-SameTrees $before (Get-UserTrees $root) 'locked'
    $now = Get-Tree $root
    foreach ($f in $oldTree.Keys) {
        if ($f -like '\userdata\*') { continue }
        if ($now[$f] -ne $oldTree[$f]) { throw "$f is not as it was" }
    }
    $last = (Get-Content "$root\userdata\app\update\update.log" | Where-Object { $_.Trim() })[-1]
    if ($last -notmatch 'old version is back') { throw "the log's last line: $last" }
    $launched = Get-Launched $root
    if (-not $launched -or $launched[0] -ne 'old' -or $launched -notcontains '--update-failed') { throw "the old Gargosy was not started with --update-failed: $launched" }
}

Test-Case 'a Gargosy that never exits: it gives up, changes nothing and starts nothing' {
    $root = New-Case 'never-exits'
    $stay = Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -PassThru -WindowStyle Hidden
    try {
        $tree = Get-Tree $root
        $code = Invoke-Updater $root $stay.Id 2
        if ($code -ne 2) { throw "exit code $code, not 2" }
        $now = Get-Tree $root
        foreach ($f in $tree.Keys) { if ($now[$f] -ne $tree[$f] -and $f -notlike '\userdata\app\update\*') { throw "$f changed" } }
        Start-Sleep -Seconds 1
        if (Test-Path "$root\launched.txt") { throw 'Gargosy was started' }
    } finally {
        Stop-Process -Id $stay.Id -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
if ($failures -gt 0) { throw "$failures updater test(s) failed" }
Write-Output 'All updater tests passed.'
