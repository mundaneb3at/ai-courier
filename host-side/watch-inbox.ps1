# watch-inbox.ps1 - Host-side AI courier watcher (REDESIGN s1 A5-A7, s2 B2, s3, s4 + R3 fixes).
# Deterministic poll loop. The only model is the locked messenger (claude -p, REDESIGN s3).
# The view prints in THIS console only (no views log on disk, R3 N6). Push bodies are fixed strings.
#
# Real:    powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1
# Key:     ... -SetKey peer        (once; type the PEER'S passphrase, agreed in person/phone)
# Release: ... -Release -Once     (run files held by the daily cap)
# Test:    ... -SourceDir <local folder standing in for Drive> -Root <temp root> -Once (-DryRun | -AllowAiAncestorForTest)
# Stop:    create <Root>\STOP  (checked before every tick)
param(
    [string]$Root = 'C:\ai-courier',
    [string]$SourceDir,                 # TEST MODE only (with -DryRun, -AllowAiAncestorForTest or -Canary)
    [switch]$Once,
    [switch]$DryRun,                    # list + gate only: no download, no messenger, no push
    [int]$PollSeconds = 300,
    [switch]$Canary,                    # used by canary.ps1: skips the version pin; requires -SourceDir
    [switch]$AllowAiAncestorForTest,    # TESTS ONLY: skip the launch allowlist (logged loudly)
    [string]$SetKey,                    # store <sender>'s verify key (DPAPI) and exit
    [switch]$Release,                   # ignore the daily cap for this run
    [string]$ConfigDir = $PSScriptRoot, # messenger-prompt.txt + schema.json
    [string]$ClaudeExe = 'claude',
    [string]$RcloneExe = 'rclone',
    [string]$Sender = 'peer',
    [string]$ExpectedOwner,             # the peer's Google address; checked against lsjson -M owner (UNVERIFIED field)
    [string]$OutboxDir = 'G:\My Drive\from-host',
    [int]$DailyCap = 10,
    [int]$TimeoutSeconds = 120,
    [int]$MaxBytes = 8192
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# ---- -SetKey: typed by the human, once per sender -------------------------------------------
if ($SetKey) {
    if ($SetKey -notmatch '^[a-z0-9-]{1,32}$') { Write-Host 'REFUSED: sender name must be a-z 0-9 -'; exit 2 }
    if ([Console]::IsInputRedirected -or (Test-AncestorIsAi)) { Write-Host 'REFUSED: -SetKey must be typed by you in a plain window.'; exit 3 }
    $plain = @()
    foreach ($q in "Passphrase $SetKey uses to sign", 'Same passphrase again') {
        $ss = Read-Host -AsSecureString $q
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
        try { $plain += [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    }
    if ($plain[0] -cne $plain[1] -or $plain[0].Length -lt 12) { Write-Host 'REFUSED: the two entries differ or are shorter than 12 characters.'; exit 2 }
    Save-CourierKey (Join-Path $Root "keys\$SetKey.key") (Get-CourierKey $plain[0])
    $plain = $null
    Write-Host "Verify key for '$SetKey' stored (DPAPI, this Windows user only). The passphrase itself is not stored."
    exit 0
}

$TestMode = [bool]$SourceDir -or $AllowAiAncestorForTest
$Quiet = $DryRun -or $TestMode        # no push, no notepad
$dirs = @{ incoming = (Join-Path $Root "incoming\$Sender"); runs = (Join-Path $Root 'runs')
           staging = (Join-Path $Root 'outbox-staging'); tmp = (Join-Path $Root 'tmp') }
$LogFile = Join-Path $Root 'watch.log'
$SeenFile = Join-Path $Root 'seen.jsonl'

function Write-Log([string]$m) {
    # Content-free log: states, counts, hashed IDs. Never names, topics or text.
    [System.IO.File]::AppendAllText($LogFile, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $m + "`r`n"), $Utf8)
}
function Get-IdTag([string]$id) {
    $h = (New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($Utf8.GetBytes($id))
    'id#' + (-join ($h[0..3] | ForEach-Object { $_.ToString('x2') }))
}
function Send-Push([string]$msg) {
    # Fixed, content-free bodies only (R3 N7/N22).
    if ($Quiet) { Write-Log "push SUPPRESSED (test/dry-run): $msg"; Write-Host "[push suppressed: test/dry-run] $msg"; return }
    try { & (Join-Path $Root 'push.ps1') -Message $msg; Write-Log "push sent: $msg" }
    catch { Write-Log "push failed: $($_.Exception.Message)" }
}
function Test-DayMarker([string]$name, [string]$value) {
    # True once per distinct value (a date, a version). Persists across restarts.
    $p = Join-Path $Root $name
    if ((Test-Path -LiteralPath $p) -and ([System.IO.File]::ReadAllText($p).Trim() -eq $value)) { return $false }
    if (-not $DryRun) { [System.IO.File]::WriteAllText($p, $value, $Utf8) }
    return $true
}

# ---- startup guards --------------------------------------------------------------------------
if ($SourceDir -and -not ($DryRun -or $AllowAiAncestorForTest -or $Canary)) { Write-Host 'REFUSED: -SourceDir is test-only (use with -DryRun, -AllowAiAncestorForTest or via canary.ps1).'; exit 2 }
if ($Canary -and -not $SourceDir) { Write-Host 'REFUSED: -Canary needs -SourceDir (canary.ps1 sets it).'; exit 2 }
foreach ($d in $dirs.Values) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'CLAUDE.md'))) {
    [System.IO.File]::WriteAllText((Join-Path $Root 'CLAUDE.md'), '', $Utf8)   # empty on purpose (M13)
}
if ($AllowAiAncestorForTest) {
    Write-Warning '!!! TEST OVERRIDE: launch allowlist skipped (-AllowAiAncestorForTest). Never use this for real messages. !!!'
    Write-Log '!!! TEST OVERRIDE -AllowAiAncestorForTest: launch allowlist skipped'
} else {
    $la = Test-LaunchAllowed -Mode Watch
    if (-not $la.ok) { Write-Host "REFUSED: $($la.reason). Start the watcher from a plain PowerShell window (Start menu) or your own logon task."; exit 3 }
}
$Key = Read-CourierKey (Join-Path $Root "keys\$Sender.key")
if ($null -eq $Key -and -not $DryRun) { Write-Host "REFUSED: no verify key for '$Sender'. Run: watch-inbox.ps1 -SetKey $Sender"; exit 2 }
# The messenger child gets an explicit env allowlist (R3 N5); the watcher itself also never forces persistence.
$EnvKeep = @('PATH','SystemRoot','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP','HOMEDRIVE','HOMEPATH',
             'SystemDrive','windir','ComSpec','PATHEXT','USERNAME')
$mutexName = 'Local\courier-watch'
if ($Root -ne 'C:\ai-courier') { $mutexName += '-' + (Get-IdTag $Root.ToLowerInvariant()).Substring(3) }   # canary/test roots
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { Write-Host 'REFUSED: another watch-inbox is already running on this root.'; exit 4 }

$ClaudePath = (Get-Command $ClaudeExe -ErrorAction Stop).Source
$PromptFile = Join-Path $ConfigDir 'messenger-prompt.txt'
$SchemaText = ([System.IO.File]::ReadAllText((Join-Path $ConfigDir 'schema.json'))).Trim()
Write-Log "start mode=$(if ($SourceDir) {'test-sourcedir'} else {'rclone'}) once=$Once dryrun=$DryRun canary=$Canary release=$Release"

# ---- helpers ---------------------------------------------------------------------------------
function Invoke-Sweep {
    # R3 N9: raw copies must not outlive a run. incoming\ + runs\ items older than 5 min; tmp views older than 1 day.
    $ok = $true
    $old = @(Get-ChildItem -LiteralPath $dirs.incoming, $dirs.runs -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-5) })
    $old += @(Get-ChildItem -LiteralPath $dirs.tmp -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) })
    foreach ($i in $old) {
        Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $i.FullName) { $ok = $false }
    }
    if (-not $ok) { Write-Log 'cleanup FAILED'; Send-Push 'courier inbox: cleanup failed' }
    return $ok
}
function Invoke-Retention {
    # R3 N17: my own outbox keeps 7 days.
    if ($DryRun -or $TestMode -or -not (Test-Path -LiteralPath $OutboxDir)) { return }
    Get-ChildItem -LiteralPath $OutboxDir -File -Force | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; Write-Log 'outbox retention: 1 file older than 7 days removed' }
}
function Get-Seen {
    $set = @{}; $ranToday = 0; $today = Get-Date -Format 'yyyy-MM-dd'
    if (Test-Path -LiteralPath $SeenFile) {
        foreach ($l in [System.IO.File]::ReadAllLines($SeenFile)) {
            if (-not $l.Trim()) { continue }
            try { $o = $l | ConvertFrom-Json } catch { continue }
            $set[$o.id] = $o.status
            if ($o.status -eq 'ran' -and ([string]$o.at).StartsWith($today)) { $ranToday++ }
        }
    }
    [pscustomobject]@{ set = $set; ranToday = $ranToday }
}
function Add-Seen($c, [string]$status) {
    if ($DryRun) { return }
    $line = (@{ id = $c.ID; status = $status; bytes = $c.Size; at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText($SeenFile, $line + "`n", $Utf8)
}
function Get-RcloneConf { Join-Path $Root 'rclone\rclone.conf' }

function Get-Candidates {
    if ($SourceDir) {
        return @(Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {
            [pscustomobject]@{ ID = 'local-' + $_.Name; Name = $_.Name; Size = [int64]$_.Length; MimeType = 'text/plain'; Owner = $null
                               ModTime = $_.LastWriteTime; Src = $_.FullName } })
    }
    $out = & $RcloneExe lsjson 'peer-in:' --files-only -M --drive-skip-gdocs --drive-skip-shortcuts --config (Get-RcloneConf) 2>$null
    if ($LASTEXITCODE -ne 0) { throw "rclone lsjson exit $LASTEXITCODE" }
    $arr = ($out -join "`n") | ConvertFrom-Json
    return @(foreach ($x in $arr) {
        $own = $null
        if ($x.PSObject.Properties['Metadata'] -and $x.Metadata -and $x.Metadata.PSObject.Properties['owner']) { $own = [string]$x.Metadata.owner }
        [pscustomobject]@{ ID = [string]$x.ID; Name = [string]$x.Name; Size = [int64]$x.Size; MimeType = [string]$x.MimeType
                           Owner = $own; ModTime = [datetime]$x.ModTime; Src = [string]$x.Path }
    })
}
function Test-Gate($c) {
    if (-not (Test-DropName $c.Name)) { return 'name' }
    if ($c.Size -lt 1 -or $c.Size -gt $MaxBytes) { return 'size' }
    if ($c.MimeType -notin @('text/plain', 'text/markdown')) { return 'type' }
    if ($ExpectedOwner -and $c.Owner -and $c.Owner -ne $ExpectedOwner) { return 'owner' }
    return $null
}

function Receive-One($c, [string]$destDir) {
    # Fetch by Drive file ID (R3 N10), never by name. Returns the downloaded file path.
    if ($SourceDir) { Copy-Item -LiteralPath $c.Src -Destination (Join-Path $destDir $c.Name) }
    else {
        & $RcloneExe backend copyid 'peer-in:' $c.ID (($destDir -replace '\\', '/') + '/') --max-size 8k --config (Get-RcloneConf) 2>$null
        if ($LASTEXITCODE -ne 0) { throw "rclone copyid exit $LASTEXITCODE" }
    }
    $got = @(Get-ChildItem -LiteralPath $destDir -File -Force)
    if ($got.Count -ne 1) { throw "expected 1 downloaded file, got $($got.Count)" }
    return $got[0].FullName
}

function ConvertTo-Arg([string]$s) {
    # CommandLineToArgvW quoting, so --json-schema keeps its double quotes under PS 5.1.
    if ($s.Length -gt 0 -and $s -notmatch '[\s"]') { return $s }
    $r = [regex]::Replace($s, '(\\*)"', '$1$1\"')
    $r = [regex]::Replace($r, '(\\+)$', '$1$1')
    return '"' + $r + '"'
}

function Invoke-Messenger([string]$runDir) {
    # Exactly the REDESIGN s3 flags (model pinned to the literal id). cwd = work\ (msg-1.txt only).
    # Env allowlist only (R3 N5). 120 s, then kill the tree.
    $argv = @('-p', 'Summarize msg-1.txt per your rules.', '--safe-mode', '--restricted',
              '--system-prompt-file', $PromptFile, '--tools', 'Read',
              '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
              '--strict-mcp-config', '--no-session-persistence', '--model', $script:MessengerModel,
              '--output-format', 'json', '--json-schema', $SchemaText)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ClaudePath
    $psi.Arguments = ($argv | ForEach-Object { ConvertTo-Arg $_ }) -join ' '
    $psi.WorkingDirectory = Join-Path $runDir 'work'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.EnvironmentVariables.Clear()
    foreach ($k in $EnvKeep) { $v = [Environment]::GetEnvironmentVariable($k); if ($v) { $psi.EnvironmentVariables[$k] = $v } }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { & taskkill.exe /T /F /PID $p.Id 2>$null | Out-Null; $p.WaitForExit(5000) | Out-Null }
    $code = if ($timedOut) { 124 } else { $p.ExitCode }
    $stdout = if ($outTask.Wait(5000)) { $outTask.Result } else { '' }
    [pscustomobject]@{ timedOut = $timedOut; exit = $code; stdout = $stdout }
}

function New-StubFields($c) {
    [pscustomobject]@{ sender = $Sender; claimed_date = $c.ModTime.ToString('yyyy-MM-dd HH:mm'); drive_name = $(if (Test-DropName $c.Name) { $c.Name } else { '[refused name]' })
        bytes = $c.Size; sha8 = '-'; chars_dropped = '-'; raw_links = $null; raw_code = $null; raw_paths = $null
        raw_ai_address = $null; raw_approval_claim = $null; drive_name_ok = $false }
}

function Invoke-One($c) {
    # Returns {kind = view|unsigned|error; view; paste_safe}. Seen is written only after cleanup succeeds (R3 N9).
    $tag = Get-IdTag $c.ID
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $dlDir = Join-Path $dirs.incoming $stamp
    $runDir = Join-Path $dirs.runs $stamp
    $res = $null; $status = 'ran'
    try {
        New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
        $dl = Receive-One $c $dlDir
        $len = (Get-Item -LiteralPath $dl).Length
        if ($len -lt 1 -or $len -gt $MaxBytes) {
            Write-Log "$tag on-disk size outside 1..$MaxBytes"; $status = 'refused'
            $res = [pscustomobject]@{ kind = 'error'; paste_safe = 'NO'; view = (Format-View -Fields (New-StubFields $c) -Obj $null -Note $script:FailedText) }
            return $res
        }
        $sig = Test-CourierTag ([System.IO.File]::ReadAllText($dl, $Utf8)) $Key
        if (-not $sig.ok) {
            Write-Log "$tag UNSIGNED or bad tag: not run"; $status = 'unsigned'
            $res = [pscustomobject]@{ kind = 'unsigned'; paste_safe = 'NO'; view = $null }
            return $res
        }
        [System.IO.File]::WriteAllText($dl, $sig.body, $Utf8)   # tag line stripped before the messenger
        $f = Get-ScriptFields -Path $dl -Sender $Sender -DriveName $c.Name -ClaimedDate $c.ModTime.ToString('yyyy-MM-dd HH:mm')
        New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'work') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $runDir 'work\msg-1.txt'), $f.clean_text, $Utf8)
        $m = Invoke-Messenger $runDir
        Write-Log "$tag messenger exit=$($m.exit) timedOut=$($m.timedOut)"
        if ($m.timedOut) {
            $res = [pscustomobject]@{ kind = 'view'; paste_safe = 'NO'; view = (Format-View -Fields $f -Obj $null -Note $script:FailedText) }
            return $res
        }
        $r = Get-ViewFromOutput -Fields $f -Stdout $m.stdout
        Write-Log "$tag valid=$($r.valid) no_red_flags=$($r.paste_safe) errors=$(@($r.errors).Count)"
        $res = [pscustomobject]@{ kind = 'view'; paste_safe = $r.paste_safe; view = $r.view }
    } catch {
        Write-Log "$tag error: $($_.Exception.Message)"
        $res = [pscustomobject]@{ kind = 'error'; paste_safe = 'NO'; view = (Format-View -Fields (New-StubFields $c) -Obj $null -Note $script:FailedText) }
    } finally {
        Remove-Item -LiteralPath $dlDir, $runDir -Recurse -Force -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $dlDir) -or (Test-Path -LiteralPath $runDir)) { Write-Log "$tag cleanup FAILED: not marked seen"; Send-Push 'courier inbox: cleanup failed' }
        else { Add-Seen $c $status }
    }
    return $res
}

function Show-View($r) {
    Write-Host ''
    Write-Host $r.view
    Write-Host ('-' * 60)
    # Notepad only for views with no red flags; temp file deleted when notepad closes (R3 N6).
    if ($r.paste_safe -ne 'YES') { return }
    if ($Quiet) { Write-Host '[notepad suppressed: test/dry-run]'; return }
    $tf = Join-Path $dirs.tmp ('view-' + [guid]::NewGuid().ToString('n') + '.txt')
    [System.IO.File]::WriteAllText($tf, $r.view, $Utf8)
    $cmd = "Start-Process notepad.exe -ArgumentList '`"$tf`"' -Wait; Remove-Item -LiteralPath '$tf' -Force"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd
}

$script:versionWarned = @{}
function Invoke-Tick {
    [void](Invoke-Sweep)
    Invoke-Retention
    # Outbox drafts: at most one push a day (R3 N20). Never opens send-drop.
    $drafts = @(Get-ChildItem -LiteralPath $dirs.staging -File -ErrorAction SilentlyContinue)
    if ($drafts.Count -gt 0 -and (Test-DayMarker 'drafts-pushed.txt' (Get-Date -Format 'yyyy-MM-dd'))) { Send-Push 'courier outbox: drafts waiting' }

    $seen = Get-Seen
    $cands = @()
    foreach ($c in @(Get-Candidates | Where-Object { -not $seen.set.ContainsKey($_.ID) })) {
        # gate BEFORE anything else: refused files are never downloaded; refused IDs go into seen (R3 N13)
        $why = Test-Gate $c
        if (-not $why) { $cands += $c; continue }
        Write-Log "$(Get-IdTag $c.ID) refused ($why), never downloaded"
        Add-Seen $c 'refused'
        if ($why -eq 'owner') { Send-Push 'courier inbox: 1 refused (owner)' }
    }
    if ($cands.Count -eq 0) { return }

    # Version pin (M23, R3 N16): claude version + literal model id must match what the canary passed.
    $ver = ((& $ClaudePath --version 2>$null) | Select-Object -First 1).Trim()
    $want = "$ver`n$($script:MessengerModel)"
    $pinFile = Join-Path $Root 'canary-pass.txt'
    $pinned = (Test-Path -LiteralPath $pinFile) -and ((([System.IO.File]::ReadAllText($pinFile)) -replace "`r", '').Trim() -eq $want)
    if (-not $pinned -and -not $Canary) {
        # O3: try the canary itself, once per new version, before holding anything (0 human steps on a pass).
        if (-not $DryRun -and (Test-DayMarker 'canary-auto-tried.txt' $ver)) {
            Write-Log "version pin mismatch: running auto-canary for $ver"
            $cargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'canary.ps1'), '-Root', $Root)
            if ($AllowAiAncestorForTest) { $cargs += '-AllowAiAncestorForTest' }   # threaded one hop further, tests only (see docs/test-evidence/auto-canary.md DESIGN)
            try { & powershell.exe @cargs *>$null } catch { Write-Log "auto-canary failed to start: $($_.Exception.Message)" }
            $pinned = (Test-Path -LiteralPath $pinFile) -and ((([System.IO.File]::ReadAllText($pinFile)) -replace "`r", '').Trim() -eq $want)
            Write-Log "auto-canary result: pinned=$pinned"
        }
        if ($pinned) { Write-Log 'auto-canary PASS: pin updated, continuing tick' }
        else {
            foreach ($c in $cands) {
                if ($script:versionWarned.ContainsKey($c.ID + '|' + $ver)) { continue }
                $script:versionWarned[$c.ID + '|' + $ver] = $true
                Show-View ([pscustomobject]@{ paste_safe = 'NO'; view = (Format-View -Fields (New-StubFields $c) -Obj $null -Note 'canary FAILED after update: messages held') })
            }
            Write-Log "version pin mismatch (canary FAIL or not run): $($cands.Count) file(s) held, no messenger run"
            if (Test-DayMarker 'canary-needed-pushed.txt' $ver) { Send-Push 'canary FAILED after update, messages held' }
            return
        }
    }

    $ran = $seen.ranToday; $held = 0
    foreach ($c in @($cands | Sort-Object ModTime -Descending)) {   # newest first (R3 N13)
        if ($ran -ge $DailyCap -and -not $Release) { $held++; continue }
        if ($DryRun) { Write-Host "[dry-run] would fetch + verify + run messenger for $(Get-IdTag $c.ID)"; continue }
        $ran++
        $r = Invoke-One $c
        if ($r.kind -eq 'unsigned') { Write-Host 'UNSIGNED drop refused (not run). Ask the peer whether they sent it.'; Send-Push 'courier inbox: 1 UNSIGNED'; continue }
        Show-View $r
        Send-Push 'courier inbox: 1 new'
    }
    if ($held -gt 0) {
        Write-Log "held $held file(s) (daily cap $DailyCap)"
        Write-Host "$held file(s) held by the daily cap. Run with -Release -Once to process them."
        if (Test-DayMarker 'held-pushed.txt' (Get-Date -Format 'yyyy-MM-dd')) { Send-Push "courier inbox: $held held" }
    }
}

# ---- loop + heartbeat (R3 N14) ------------------------------
$lastOk = 'never'; $fails = 0
try {
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $Root 'STOP')) { Write-Log 'STOP file found, exiting'; Write-Host 'STOP file found, exiting.'; break }
        try { Invoke-Tick; $fails = 0; $lastOk = Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
        catch {
            $fails++
            Write-Log "tick error ($fails in a row): $($_.Exception.Message)"
            Write-Host "tick error (logged): $($_.Exception.Message)"
            if ($fails -eq 3) { Send-Push 'courier inbox: pull failing' }
        }
        Write-Host "last-ok $lastOk"
        if ($Once) { break }
        Start-Sleep -Seconds $PollSeconds
    }
} finally { $mutex.ReleaseMutex(); Write-Log 'exit' }
