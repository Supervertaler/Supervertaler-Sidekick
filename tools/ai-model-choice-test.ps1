<#
  Offline tests for "AI menu actions use:" in Settings -> AI providers & keys...
  (lib\providers.ahk, lib\ai.ahk): which provider and model answer the AI
  actions on the menu.

      powershell -NoProfile -File tools\ai-model-choice-test.ps1 [-Keep]

  Runs tools\ai-model-choice-test.ahk phase by phase in 64-bit and 32-bit
  AutoHotkey, with APPDATA pointed at a scratch folder, so that the data root
  (config.json) and the locked key file are both the scratch folder's;
  settings.ini is the scratch folder's too, beside the test script. Nothing
  here starts Sidekick, registers a hotkey or shows a window.

  The "send" phase runs real AI actions against a fake provider served here,
  on 127.0.0.1, which answers with what it was sent - provider, model, which
  key header and how long - never the key itself. No real provider is asked.

  The user's own key files - the plain one in the real data folder, the locked
  one in the real %APPDATA%, and anything named api-keys* beside them - and
  the settings.ini and ChatGptAPI.ini of this checkout and of the main one are
  compared by name, size and timestamps before and after every phase, never
  opened. Any change stops the run as a failure. (If a Supervertaler product
  saved a key meanwhile, or Sidekick wrote its settings, run again.)

  Never prints a key. Exit code 0 when everything passed.
#>
param(
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

# --- The user's own files: name, size and times only, never opened ----------
$realAppData = [Environment]::GetFolderPath('ApplicationData')     # not the variable this script changes
$realFolders = @(Join-Path $realAppData 'Supervertaler')
$realConfig = Join-Path $realAppData 'Supervertaler\config.json'
if (Test-Path -LiteralPath $realConfig) {
    try {
        $realRoot = (Get-Content -LiteralPath $realConfig -Raw -Encoding UTF8 | ConvertFrom-Json).user_data_path
        if ($realRoot) { $realFolders += (Join-Path $realRoot 'settings') }
    } catch { }
}
# Sidekick keeps settings.ini beside Sidekick.ahk: this checkout's, and - when
# this is a worktree - the main checkout's, which is the one that runs.
$checkouts = @($repo)
try {
    $common = & git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($common) {
        $main = (Resolve-Path -LiteralPath (Split-Path -Parent $common)).Path
        if ($main -ne $repo) { $checkouts += $main }
    }
} catch { }
$realFiles = foreach ($c in $checkouts) { Join-Path $c 'settings.ini'; Join-Path $c 'ChatGptAPI.ini' }
function Get-RealFiles {
    $lines = foreach ($folder in $realFolders) {
        if (Test-Path -LiteralPath $folder) {
            Get-ChildItem -LiteralPath $folder -Filter 'api-keys*' -Force | Sort-Object Name | ForEach-Object {
                '{0}|{1}|{2}|{3}' -f $_.FullName, $_.Length, $_.CreationTimeUtc.Ticks, $_.LastWriteTimeUtc.Ticks }
        } else { "$folder|no folder" }
    }
    $lines += foreach ($f in $realFiles) {
        if (Test-Path -LiteralPath $f) {
            $i = Get-Item -LiteralPath $f -Force
            '{0}|{1}|{2}|{3}' -f $i.FullName, $i.Length, $i.CreationTimeUtc.Ticks, $i.LastWriteTimeUtc.Ticks
        } else { "$f|none" }
    }
    ($lines -join "`n")
}
$realBefore = Get-RealFiles
Write-Host "INFO  watching the user's key files in: $($realFolders -join '; ')"
Write-Host "INFO  and: $($realFiles -join '; ')"
function Assert-RealUntouched([string]$after) {
    $now = Get-RealFiles
    if ($now -ne $realBefore) {
        Say "ABORT  the user's own files changed during $after (names, sizes and times only):"
        Write-Host "      before: $realBefore"
        Write-Host "      after:  $now"
        exit 1
    }
}

# --- The scratch folder: APPDATA, data root, and where the tests run --------
$root = Join-Path ([IO.Path]::GetTempPath()) ('sk-aimodel-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
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
if ($plainPath.StartsWith($realAppData) -or $lockedPath -eq (Join-Path $realAppData 'Supervertaler\api-keys.locked.json') -or
    $realFiles -contains (Join-Path $run 'settings.ini')) {
    Say 'ABORT  the scratch paths are not scratch'; exit 2
}
Write-Host "INFO  scratch folder: $root"

# A small script that includes Sidekick's lib files and the tests, and nothing
# that registers a hotkey. Warnings go to stdout, never a dialog; an error
# ends the phase as a failure.
$libs = 'jxon', 'sharedkeys', 'data', 'menu_builder', 'ai', 'markdown', 'quicktrans', 'providers'
$wrapper = Join-Path $run 'test.ahk'
$lines = @('#Requires AutoHotkey v2.0', '#NoTrayIcon', '#SingleInstance Off', '#Warn All, StdOut', 'OnError(T_OnError)')
$lines += $libs | ForEach-Object { '#Include "' + (Join-Path $repo "lib\$_.ahk") + '"' }
$lines += '#Include "' + (Join-Path $repo 'tools\ai-model-choice-test.ahk') + '"'
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

function Invoke-Phase([string]$exe, [string]$phase, [int]$timeoutSec = 300) {
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
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force
        Say "FAIL  $phase ($bits-bit): did not finish within $timeoutSec s"
    }
    $results = Join-Path $run "results-$phase-$bits.txt"
    if (Test-Path -LiteralPath $results) {
        foreach ($line in [IO.File]::ReadAllLines($results, $utf8)) {
            if ($line.StartsWith('ABORT')) { Say $line; exit 2 }
            if ($line.StartsWith('PASS') -or $line.StartsWith('FAIL')) { Say ($line.Substring(0, 6) + "[$bits] " + $line.Substring(6)) }
            else { Write-Host ("      [$bits] " + $line) }
        }
    } else {
        Say "FAIL  $phase ($bits-bit): no results"
    }
    # Warnings about the files this change touched, other than a local that
    # shares a global's name (Sidekick's code had those before).
    $out = Join-Path $run "stdout-$phase-$bits.txt"
    if (Test-Path -LiteralPath $out) {
        $warn = (Get-Content -LiteralPath $out -Raw) -split '(?=\r?\n[A-Z]:\\)' |
            Where-Object { $_ -match '(providers|\\ai)\.ahk \(\d+\) : ==> Warning' -and $_ -notmatch 'same name as a global' }
        if ($warn) { Say "FAIL  $phase ($bits-bit): AutoHotkey warnings in the changed files:"; $warn | ForEach-Object { Write-Host $_.Trim() } }
    }
    Assert-RealUntouched "$phase ($bits-bit)"
}

# --- The fake provider ---------------------------------------------------------
# One request at a time on 127.0.0.1, answered in the shape of the provider
# named by the first part of the path, with a sentence saying what came in.
# The key is never written down: only which header carried it, and its length.
Add-Type -AssemblyName System.Web.Extensions
$fakeServer = {
    param($listener, [string]$logPath, $json)
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $n = 0
    while ($true) {
        try { $client = $listener.AcceptTcpClient() } catch { return }
        try {
            $client.ReceiveTimeout = 5000
            $s = $client.GetStream()
            $data = New-Object IO.MemoryStream
            $buf = New-Object byte[] 8192
            $headEnd = -1
            while ($headEnd -lt 0) {
                $r = $s.Read($buf, 0, $buf.Length)
                if ($r -le 0) { break }
                $data.Write($buf, 0, $r)
                $headEnd = $latin1.GetString($data.ToArray()).IndexOf("`r`n`r`n")
            }
            if ($headEnd -lt 0) { continue }
            $all = $data.ToArray()
            $head = $latin1.GetString($all, 0, $headEnd) -split "`r`n"
            $path = ($head[0] -split ' ')[1]
            $headers = @{}
            foreach ($l in ($head | Select-Object -Skip 1)) {
                $i = $l.IndexOf(':')
                if ($i -gt 0) { $headers[$l.Substring(0, $i).Trim().ToLower()] = $l.Substring($i + 1).Trim() }
            }
            $len = $(if ($headers['content-length']) { [int]$headers['content-length'] } else { 0 })
            while ($all.Length - ($headEnd + 4) -lt $len) {
                $r = $s.Read($buf, 0, $buf.Length)
                if ($r -le 0) { break }
                $data.Write($buf, 0, $r)
                $all = $data.ToArray()
            }
            $body = $utf8.GetString($all, $headEnd + 4, [Math]::Min($len, $all.Length - ($headEnd + 4)))
            $n++
            $provider = $path.Trim('/').Split('/')[0]
            $model = ''
            if ($provider -eq 'gemini') {
                if ($path -match '/models/([^/:]+):generateContent') { $model = [Uri]::UnescapeDataString($Matches[1]) }
            } else {
                try { $model = $json.DeserializeObject($body)['model'] } catch { }
            }
            $auth = 'none'
            foreach ($h in 'x-api-key', 'x-goog-api-key', 'authorization') {
                if ($headers.ContainsKey($h)) { $auth = "$h $($headers[$h].Length)"; break }
            }
            $text = "fake $provider #$n | model $model | $auth"
            [IO.File]::AppendAllText($logPath, "$text`r`n", $utf8)
            if ($provider -eq 'anthropic') { $reply = @{ content = @(@{ type = 'text'; text = $text }) } }
            elseif ($provider -eq 'gemini') { $reply = @{ candidates = @(@{ content = @{ parts = @(@{ text = $text }) } }) } }
            else { $reply = @{ choices = @(@{ message = @{ role = 'assistant'; content = $text } }) } }
            $out = $utf8.GetBytes($json.Serialize($reply))
            $hdr = $latin1.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`n" +
                "Content-Length: $($out.Length)`r`nConnection: close`r`n`r`n")
            $s.Write($hdr, 0, $hdr.Length)
            $s.Write($out, 0, $out.Length)
            $s.Flush()
        } catch {
            [IO.File]::AppendAllText($logPath, "error: $($_.Exception.Message)`r`n", $utf8)
        } finally {
            $client.Close()
        }
    }
}

function Invoke-SendPhase([string]$exe) {
    $bits = $(if ($exe -match '32\.exe$') { 32 } else { 64 })
    $log = Join-Path $root 'fake-requests.txt'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    [IO.File]::WriteAllText((Join-Path $root 'fake-port.txt'), "$port", $utf8)
    $ps = [powershell]::Create()
    [void]$ps.AddScript($fakeServer).AddArgument($listener).AddArgument($log).AddArgument(
        (New-Object System.Web.Script.Serialization.JavaScriptSerializer))
    $handle = $ps.BeginInvoke()
    try {
        Invoke-Phase $exe 'send'
    } finally {
        $listener.Stop()
        [void]$handle.AsyncWaitHandle.WaitOne(5000)
        $ps.Dispose()
    }
    $got = $(if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllLines($log, $utf8) } else { @() })
    $errors = @($got | Where-Object { $_ -like 'error:*' })
    Check ($errors.Count -eq 0) "[$bits] fake provider: every request read and answered$(if ($errors) { ' - ' + ($errors -join '; ') })"
    Write-Host "      [$bits] fake provider on 127.0.0.1:$port was asked $($got.Count) times"
}

foreach ($exe in $exes) {
    $bits = $(if ($exe -match '32\.exe$') { 32 } else { 64 })
    Write-Host ''
    Write-Host "=== $bits-bit AutoHotkey ==="
    Invoke-Phase $exe 'window'
    Invoke-SendPhase $exe
}

# --- No key text anywhere but the files meant to hold it in plain ------------
$keys = @()
$keyList = Join-Path $root 'keys.txt'
if (Test-Path -LiteralPath $keyList) { $keys += [IO.File]::ReadAllLines($keyList, $utf8) | Where-Object { $_ } }
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
Check ($keys.Count -ge 6 -and $leaks.Count -eq 0) "no key text (UTF-8 or UTF-16) in any log, locked file, fake-provider record or result - $($keys.Count) keys, $checked files$(if ($leaks) { ': ' + ($leaks -join ', ') })"

Assert-RealUntouched 'the whole run'
Write-Host ''
Write-Host "$($script:passed) passed, $($script:failed) failed"
if ($script:failed -eq 0 -and -not $Keep) { Remove-Item -LiteralPath $root -Recurse -Force }
else { Write-Host "Scratch folder kept: $root" }
exit $(if ($script:failed -eq 0) { 0 } else { 1 })
