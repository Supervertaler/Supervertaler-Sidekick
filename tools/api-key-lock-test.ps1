<#
  Offline tests for step 1 of "API keys locked to the computer" in Sidekick
  (lib\sharedkeys.ahk; Plugin Core, docs/design/api-key-protection.md).

      powershell -NoProfile -File tools\api-key-lock-test.ps1 [-CoreDll <path>] [-Keep]

  Runs tools\api-key-lock-test.ahk phase by phase in 64-bit and 32-bit
  AutoHotkey, with APPDATA pointed at a scratch folder, so that the data root
  (config.json) and the locked key file are both the scratch folder's. Nothing
  here starts Sidekick or registers a hotkey.

  -CoreDll is a build of Plugin Core (dotnet build build\Supervertaler.Core.Build.csproj),
  for the checks against core itself: each reads what the other locked, the
  same sentences, the same file byte for byte, two writers at once. Without
  it those checks are skipped, and said to be.

  The user's own key files - the plain one in the real data folder, the locked
  one in the real %APPDATA%, and anything named api-keys* beside them - are
  compared by name, size and timestamps before and after every phase, never
  opened. Any change stops the run as a failure. (If a Supervertaler product
  saved a key meanwhile, run again.)

  Never prints a key. Exit code 0 when everything passed.
#>
param(
    [string]$CoreDll = '',
    [string]$Ahk64 = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
    [string]$Ahk32 = 'C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe',
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:passed = 0
$script:failed = 0

function Say([string]$line) {
    Write-Host $line
    if ($line.StartsWith('PASS')) { $script:passed++ }
    elseif ($line.StartsWith('FAIL') -or $line.StartsWith('ABORT')) { $script:failed++ }
}
function Check([bool]$ok, [string]$name) { Say ($(if ($ok) { 'PASS  ' } else { 'FAIL  ' }) + $name) }

# --- The user's own key files: name, size and times only, never opened ------
$realAppData = [Environment]::GetFolderPath('ApplicationData')     # not the variable this script changes
$realFolders = @(Join-Path $realAppData 'Supervertaler')
$realConfig = Join-Path $realAppData 'Supervertaler\config.json'
if (Test-Path -LiteralPath $realConfig) {
    try {
        $realRoot = (Get-Content -LiteralPath $realConfig -Raw -Encoding UTF8 | ConvertFrom-Json).user_data_path
        if ($realRoot) { $realFolders += (Join-Path $realRoot 'settings') }
    } catch { }
}
function Get-RealKeyFiles {
    $lines = foreach ($folder in $realFolders) {
        if (Test-Path -LiteralPath $folder) {
            Get-ChildItem -LiteralPath $folder -Filter 'api-keys*' -Force | Sort-Object Name | ForEach-Object {
                '{0}|{1}|{2}|{3}' -f $_.FullName, $_.Length, $_.CreationTimeUtc.Ticks, $_.LastWriteTimeUtc.Ticks }
        } else { "$folder|no folder" }
    }
    ($lines -join "`n")
}
$realBefore = Get-RealKeyFiles
Write-Host "INFO  watching the user's key files in: $($realFolders -join '; ')"
function Assert-RealUntouched([string]$after) {
    $now = Get-RealKeyFiles
    if ($now -ne $realBefore) {
        Say "ABORT  the user's own key files changed during $after (names, sizes and times only):"
        Write-Host "      before: $realBefore"
        Write-Host "      after:  $now"
        exit 1
    }
}

# --- The scratch folder: APPDATA, data root, and where the tests run --------
$root = Join-Path ([IO.Path]::GetTempPath()) ('sk-keylock-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
$appData = Join-Path $root 'appdata'
$dataRoot = Join-Path $root 'data'
$run = Join-Path $root 'run'
foreach ($d in @((Join-Path $appData 'Supervertaler'), (Join-Path $dataRoot 'settings'), $run)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
[IO.File]::WriteAllText((Join-Path $appData 'Supervertaler\config.json'),
    (@{ user_data_path = $dataRoot } | ConvertTo-Json), $utf8)
$plainPath = Join-Path $dataRoot 'settings\api-keys.json'
$lockedPath = Join-Path $appData 'Supervertaler\api-keys.locked.json'
if ($plainPath.StartsWith($realAppData) -or $lockedPath -eq (Join-Path $realAppData 'Supervertaler\api-keys.locked.json')) {
    Say 'ABORT  the scratch paths are not scratch'; exit 2
}
Write-Host "INFO  scratch folder: $root"

# A small script that includes Sidekick's lib files and the tests, and nothing
# that registers a hotkey. Warnings go to stdout, never a dialog; an error
# ends the phase as a failure.
$libs = 'jxon', 'sharedkeys', 'data', 'menu_builder', 'ai', 'quicktrans', 'providers'
$wrapper = Join-Path $run 'test.ahk'
$lines = @('#Requires AutoHotkey v2.0', '#NoTrayIcon', '#SingleInstance Off', '#Warn All, StdOut', 'OnError(T_OnError)')
$lines += $libs | ForEach-Object { '#Include "' + (Join-Path $repo "lib\$_.ahk") + '"' }
$lines += '#Include "' + (Join-Path $repo 'tools\api-key-lock-test.ahk') + '"'
$lines += @(
    'T_OnError(e, mode) {',
    '    FileAppend("FAIL  error: " e.Message " (" e.What ", line " e.Line ")`n", A_ScriptDir "\results-" (A_Args.Length >= 2 ? A_Args[2] : "") "-" (A_PtrSize * 8) ".txt", "UTF-8")',
    '    ExitApp(3)',
    '}')
[IO.File]::WriteAllText($wrapper, ($lines -join "`r`n"), $utf8)

$exes = @()
foreach ($exe in @($Ahk64, $Ahk32)) {
    if (Test-Path -LiteralPath $exe) { $exes += $exe } else { Write-Host "SKIP  no AutoHotkey at $exe" }
}

function Start-Phase([string]$exe, [string]$phase) {
    $bits = $(if ($exe -match '32\.exe$') { 32 } else { 64 })
    Remove-Item -LiteralPath (Join-Path $run "results-$phase-$bits.txt") -ErrorAction SilentlyContinue
    $saved = $env:APPDATA
    $env:APPDATA = $appData             # for the child only; restored at once
    try {
        $p = Start-Process -FilePath $exe -PassThru -NoNewWindow `
            -ArgumentList '/ErrorStdOut', "`"$wrapper`"", "`"$root`"", $phase `
            -RedirectStandardOutput (Join-Path $run "stdout-$phase-$bits.txt") `
            -RedirectStandardError (Join-Path $run "stderr-$phase-$bits.txt")
    } finally {
        $env:APPDATA = $saved
    }
    $p | Add-Member -NotePropertyName Phase -NotePropertyValue $phase
    $p | Add-Member -NotePropertyName Bits -NotePropertyValue $bits
    $p
}

function Wait-Phase($p, [int]$timeoutSec = 300, [switch]$Killed) {
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force
        Say "FAIL  $($p.Phase) ($($p.Bits)-bit): did not finish within $timeoutSec s"
    }
    $results = Join-Path $run "results-$($p.Phase)-$($p.Bits).txt"
    if (Test-Path -LiteralPath $results) {
        foreach ($line in [IO.File]::ReadAllLines($results, $utf8)) {
            if ($line.StartsWith('ABORT')) { Say $line; exit 2 }
            if ($line.StartsWith('PASS') -or $line.StartsWith('FAIL')) { Say ($line.Substring(0, 6) + "[$($p.Bits)] " + $line.Substring(6)) }
            else { Write-Host ("      [$($p.Bits)] " + $line) }
        }
    } elseif (-not $Killed) {
        Say "FAIL  $($p.Phase) ($($p.Bits)-bit): no results"
    }
    # Warnings about the files this change touched, other than a local that
    # shares a global's name (Sidekick's code had those before).
    $out = Join-Path $run "stdout-$($p.Phase)-$($p.Bits).txt"
    if (Test-Path -LiteralPath $out) {
        $warn = (Get-Content -LiteralPath $out -Raw) -split '(?=\r?\n[A-Z]:\\)' |
            Where-Object { $_ -match '(sharedkeys|providers|quicktrans|\\ai)\.ahk \(\d+\) : ==> Warning' -and $_ -notmatch 'same name as a global' }
        if ($warn) { Say "FAIL  $($p.Phase) ($($p.Bits)-bit): AutoHotkey warnings in the changed files:"; $warn | ForEach-Object { Write-Host $_.Trim() } }
    }
    Assert-RealUntouched "$($p.Phase) ($($p.Bits)-bit)"
}

function Invoke-Phase([string]$exe, [string]$phase) { Wait-Phase (Start-Phase $exe $phase) }

function Wait-File([string]$path, [int]$ms = 10000) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $path) -and $clock.ElapsedMilliseconds -lt $ms) { Start-Sleep -Milliseconds 5 }
    Test-Path -LiteralPath $path
}

# Plain files are deleted; locked files and set-aside copies go to scan\, for
# the check at the end that no key text is in any of them.
$script:cleared = 0
function Clear-KeyFiles {
    Get-ChildItem -LiteralPath (Split-Path $plainPath) -Filter 'api-keys*' | Remove-Item -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'scan') | Out-Null
    Get-ChildItem -LiteralPath (Split-Path $lockedPath) -Filter 'api-keys*' | ForEach-Object {
        $script:cleared++
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $root "scan\runner-$($script:cleared)-$($_.Name)")
    }
}

# --- Plugin Core, redirected the same way before anything touches it --------
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Web.Extensions
$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$store = $null
if ($CoreDll) {
    $asm = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $CoreDll).Path)
    $store = $asm.GetType('Supervertaler.Core.ApiKeyStore', $true)
    $dpapi = $asm.GetType('Supervertaler.Core.DpapiSecret', $true)
    $paths = $asm.GetType('Supervertaler.Core.SupervertalerPaths', $true)
    $paths::Set($dataRoot)
    $store.GetMethod('RedirectLockedFile', [Reflection.BindingFlags]'NonPublic, Static').Invoke($null, [object[]]@([string]$lockedPath)) | Out-Null
    if ($store::FilePath -ne $plainPath -or $store::LockedFilePath -ne $lockedPath) {
        Say "ABORT  Plugin Core's key files are not redirected: $($store::FilePath) / $($store::LockedFilePath)"; exit 2
    }
    $coreLog = Join-Path $root 'core.log'
    $store::Log = [Action[string]] { param($m) [IO.File]::AppendAllText($coreLog, $m + "`r`n", $utf8) }
    Write-Host "INFO  Plugin Core: $CoreDll, redirected to the scratch folder"
} else {
    Write-Host 'SKIP  no -CoreDll: the checks against Plugin Core are not run'
}

$K1 = 'sk-ant-test-K1-PROJ-001'
$UNI = 'sk-test-Acm' + [char]0xE9 + '-' + [char]0xDC + 'ber-PROJ-001'
$DL = 'deepl-test-Acme-PROJ-001:fx'
$GT = 'gt-test-Acme-PROJ-001'
$GEM = 'AIza-test-Acme-PROJ-001'
$MI = 'mistral-test-Acme-PROJ-001'
$KeyAcme = 'sk-test-AcmeServer-PROJ-001'
$DS = 'deepseek-test-PROJ-001'
$place = 'Settings ' + [char]0x2192 + ' AI providers'

function Lock-WithEntropy([string]$key) {
    [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect(
        $utf8.GetBytes($key), $utf8.GetBytes('PROJ-001'), 'CurrentUser'))
}

foreach ($exe in $exes) {
    $bits = $(if ($exe -match '32\.exe$') { 32 } else { 64 })
    Write-Host ''
    Write-Host "=== $bits-bit AutoHotkey ==="

    Invoke-Phase $exe 'unit'

    if ($store) {
        # Each reads what the other locked, with the plain file gone.
        Invoke-Phase $exe 'cross-lock'
        Check ($store::Get('claude') -ceq $K1) "[$bits] core: reads the Anthropic key Sidekick locked"
        Check ($store::Get('openai') -ceq $UNI) "[$bits] core: and the one that is not plain ASCII"
        Check (($store::Get('deepl') -ceq $DL) -and ($store::Get('google') -ceq $GT)) "[$bits] core: and the DeepL and Google keys"
        $acmeId = $store::PrivateId('trados', 'custom_openai', "Acme & <PROJ-001>'s server")
        Check ($store::Set('gemini', $GEM) -and $store::Set($acmeId, $KeyAcme)) "[$bits] core: locks a Gemini key and a Trados profile key"
        Remove-Item -LiteralPath $plainPath
        Invoke-Phase $exe 'cross-read'
        Check ($store::Get('mistral') -ceq $MI) "[$bits] core: reads the key Sidekick saved after core's"
        Check ($store::Get($acmeId) -ceq $KeyAcme) "[$bits] core: its own profile key survived Sidekick's rewrite"

        # The same file, byte for byte: core writes it, Sidekick re-renders it.
        Check ($store::Set('deepseek', $DS)) "[$bits] core: rewrites the locked file"
        $coreBytes = [IO.File]::ReadAllBytes($lockedPath)
        Invoke-Phase $exe 'render'
        $skPath = Join-Path $root 'sidekick-render.json'
        $same = (Test-Path -LiteralPath $skPath) -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes($skPath)) -ceq [Convert]::ToBase64String($coreBytes))
        Check $same "[$bits] format: Sidekick writes the locked file byte for byte as core does ($($coreBytes.Length) bytes, ids with & < > ' escaped as core escapes them)"
        Remove-Item -LiteralPath $skPath -ErrorAction SilentlyContinue

        # The same sentences as core, word for word.
        Invoke-Phase $exe 'messages'
        $mine = Join-Path $root 'sidekick-messages.txt'
        $lines = $(if (Test-Path -LiteralPath $mine) { [IO.File]::ReadAllLines($mine, $utf8) } else { @() })
        Remove-Item -LiteralPath $mine -ErrorAction SilentlyContinue
        $states = @{}
        foreach ($l in $lines) { $f = $l.Split("`t"); if ($f.Count -eq 4) { $states["$($f[0])|$($f[1])|$($f[2])"] = $f[3] } }
        $ids = 'claude', 'openai', 'gemini', 'mistral', 'deepseek', 'openrouter'
        $entries = [ordered]@{}
        foreach ($id in $ids) { $entries[$id] = Lock-WithEntropy "sk-test-$id-PROJ-001" }
        Clear-KeyFiles
        [IO.File]::WriteAllText($lockedPath, ($entries | ConvertTo-Json), $utf8)
        $same = $states.Count -eq 24
        foreach ($id in $ids) {
            $same = $same -and $states["refused|$id|M1"] -ceq $store::UnreadableKeyNote($id) -and $states["refused|$id|M2"] -ceq $store::MissingKeyMessage($id, $place)
        }
        [IO.File]::WriteAllText($lockedPath, '{ damaged', $utf8)
        foreach ($id in $ids) {
            $same = $same -and $states["damaged|$id|M1"] -ceq $store::UnreadableKeyNote($id) -and $states["damaged|$id|M2"] -ceq $store::MissingKeyMessage($id, $place)
        }
        Check $same "[$bits] messages: M1 and M2, for a key locked elsewhere and for a damaged file, word for word as core says them (6 providers)"
        Clear-KeyFiles

        # Two writers at once: Sidekick and core, 40 saves each.
        Remove-Item -LiteralPath (Join-Path $root 'race.ready'), (Join-Path $root 'race.go') -ErrorAction SilentlyContinue
        $p = Start-Phase $exe 'race'
        if (Wait-File (Join-Path $root 'race.ready')) {
            [IO.File]::WriteAllText((Join-Path $root 'race.go'), 'go')
            $coreOk = 0
            1..40 | ForEach-Object { if ($store::Set("race-core-$_", "core-race-$_-PROJ-001")) { $coreOk++ } }
        }
        Wait-Phase $p
        $plain = $store::Load()
        $locked = $json.DeserializeObject([IO.File]::ReadAllText($lockedPath, $utf8))
        $lost = 0
        foreach ($i in 1..40) {
            foreach ($pair in @(@("race-sk-$i", "sk-race-$i-PROJ-001"), @("race-core-$i", "core-race-$i-PROJ-001"))) {
                $inPlain = $plain.ContainsKey($pair[0]) -and $plain[$pair[0]] -ceq $pair[1]
                $have = $null; $err = 0
                $inLocked = $locked.ContainsKey($pair[0]) -and $dpapi::TryUnprotect($locked[$pair[0]], [ref]$have, [ref]$err) -and $have -ceq $pair[1]
                if (-not ($inPlain -and $inLocked)) { $lost++ }
            }
        }
        Check ($coreOk -eq 40 -and $lost -eq 0) "[$bits] race: Sidekick and core saving 40 keys each at the same moment - all 80 kept, in both files"
        Remove-Item -LiteralPath (Join-Path $root 'race.ready'), (Join-Path $root 'race.go') -ErrorAction SilentlyContinue
        Clear-KeyFiles
    }

    # Another process holds the locked file, then the plain file.
    Invoke-Phase $exe 'held-setup'
    $held = [IO.File]::Open($lockedPath, 'Open', 'Read', 'None')
    try { Invoke-Phase $exe 'held-locked' } finally { $held.Dispose() }
    Invoke-Phase $exe 'after-held'
    $held = [IO.File]::Open($plainPath, 'Open', 'Read', 'None')
    try { Invoke-Phase $exe 'held-plain' } finally { $held.Dispose() }
    Clear-KeyFiles

    # Killed part-way through saves, ten times: each file is always whole.
    $whole = 0; $found = 0
    foreach ($n in 1..10) {
        Remove-Item -LiteralPath (Join-Path $root 'kill.ready') -ErrorAction SilentlyContinue
        $p = Start-Phase $exe 'kill-loop'
        Wait-File (Join-Path $root 'kill.ready') | Out-Null
        Start-Sleep -Milliseconds (Get-Random -Minimum 20 -Maximum 300)
        Stop-Process -Id $p.Id -Force
        $p.WaitForExit()
        Wait-Phase $p -timeoutSec 5 -Killed
        $ok = $true
        if (Test-Path -LiteralPath $lockedPath) {
            $found++
            try {
                $m = $json.DeserializeObject([IO.File]::ReadAllText($lockedPath, $utf8))
                $b = [Convert]::FromBase64String($m['claude'])
                $ok = ([Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($b, $null, 'CurrentUser'))) -like 'sk-ant-test-Kill-*'
            } catch { $ok = $false }
        }
        if (Test-Path -LiteralPath $plainPath) {
            try { $ok = $ok -and ((Get-Content -LiteralPath $plainPath -Raw -Encoding UTF8 | ConvertFrom-Json).claude -like 'sk-ant-test-Kill-*') } catch { $ok = $false }
        }
        if ($ok) { $whole++ }
    }
    Check ($whole -eq 10) "[$bits] kill: Sidekick killed part-way through saves 10 times - both files whole every time ($found with a locked file)"
    Clear-KeyFiles
    Get-ChildItem -LiteralPath (Split-Path $lockedPath), (Split-Path $plainPath) -Filter '*.tmp' | Remove-Item -Force
}

# --- No key text anywhere but the files meant to hold it in plain ------------
$keys = @()
$keyList = Join-Path $root 'keys.txt'
if (Test-Path -LiteralPath $keyList) { $keys += [IO.File]::ReadAllLines($keyList, $utf8) | Where-Object { $_ } }
$keys += $DS, 'sk-race-', 'core-race-', 'sk-ant-test-Kill-'
$plainOnPurpose = @((Join-Path $run 'settings.ini'), (Join-Path $run 'ChatGptAPI.ini'), $keyList, $wrapper)
$leaks = @()
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $plainOnPurpose -notcontains $_.FullName -and $_.Name -notlike 'stdout-*' -and $_.Name -notlike 'api-keys.json'
} | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $asText8 = [Text.Encoding]::UTF8.GetString($bytes)
    $asText16 = [Text.Encoding]::Unicode.GetString($bytes)
    foreach ($needle in $keys) {
        if ($asText8.Contains($needle) -or $asText16.Contains($needle)) { $leaks += "$($_.FullName.Substring($root.Length + 1))" ; break }
    }
}
$checked = (Get-ChildItem -LiteralPath $root -Recurse -File).Count
Check ($keys.Count -gt 10 -and $leaks.Count -eq 0) "no key text (UTF-8 or UTF-16) in any log, locked file, set-aside copy or result - $($keys.Count) keys, $checked files$(if ($leaks) { ': ' + ($leaks -join ', ') })"

Assert-RealUntouched 'the whole run'
Write-Host ''
Write-Host "$($script:passed) passed, $($script:failed) failed"
if ($script:failed -eq 0 -and -not $Keep) { Remove-Item -LiteralPath $root -Recurse -Force }
else { Write-Host "Scratch folder kept: $root" }
exit $(if ($script:failed -eq 0) { 0 } else { 1 })
