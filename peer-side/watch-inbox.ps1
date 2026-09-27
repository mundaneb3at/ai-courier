# watch-inbox.ps1 - the peer side of the AI courier (REDESIGN B5-B7, A2; R3 fixes). ASCII-only (PS 5.1).
# Every 60 s: a new, stable file in the from-host Drive folder -> name/type/size gate -> signature
# check with the host's verify key -> one zero-tool OpenCode messenger run -> messenger-lib validation ->
# shown to you (Notepad if no red flags, else a short popup) -> raw copies deleted. Nothing is kept on
# disk except seen.jsonl (IDs only). It NEVER sends anything and NEVER opens the SEND window.
#
#   watch-inbox.ps1                  normal (paths from <Root>\settings.json)
#   watch-inbox.ps1 -SetKey host   store the host's verify key once (you type their passphrase)
#   canary.ps1                       the canary (it calls this script with -DryRun -Canary)
param(
    [string]$Root = (Join-Path $env:USERPROFILE 'ai-courier'),
    [string]$InboxDir, [string]$StagingDir, [string]$OutboxDir,   # overrides: only with -DryRun / test
    [int]$IntervalSec = 60, [int]$TimeoutSec = 120, [int]$DailyCap = 10,
    [string]$SetKey,
    [switch]$Once,
    [switch]$DryRun,                  # one pass, no popups/Notepad, prints views + RESULT lines (tests, canary)
    [switch]$Canary,                  # with -DryRun: skip the version pin
    [switch]$AllowAiAncestorForTest   # ONLY for the host's test run inside an AI session
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$Quiet = $DryRun -or $AllowAiAncestorForTest   # test runs: no popups/Notepad, printed instead
if ($DryRun) { $Once = $true }
if ($Canary -and -not $DryRun) { Write-Host '-Canary needs -DryRun (use canary.ps1).'; exit 1 }

# ---- who started us (R3 N4) ----
if ($AllowAiAncestorForTest) { Write-Host 'TEST MODE: launch check skipped (-AllowAiAncestorForTest).' }
else {
    $la = Test-LaunchAllowed -Mode Watch
    if (-not $la.ok) { Write-Host "REFUSED: $($la.reason). Start it from the Startup folder or a window you opened."; exit 2 }
}

function Show-Popup([string]$Text) {
    if ($Quiet) { Write-Host "POPUP: $Text"; return }
    $t = $Text -replace "'", "''"   # non-blocking: a hidden PowerShell shows a 60 s WScript popup
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', "(New-Object -ComObject WScript.Shell).Popup('$t', 60, 'AI courier', 64) | Out-Null"
}

# ---- one-time key setup ----
$keyPath = Join-Path $Root 'keys\host.key'
if ($SetKey) {
    if ($SetKey -ne 'host') { Write-Host 'Only "-SetKey host" is supported.'; exit 1 }
    $s1 = Read-Host "The host's passphrase (they told you in person or by phone)" -AsSecureString
    $s2 = Read-Host 'Again' -AsSecureString
    $pl = { param($s) $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
    $a = & $pl $s1; if (-not $a -or $a -cne (& $pl $s2)) { Write-Host 'Empty or different. Nothing saved.'; exit 1 }
    Save-CourierKey $keyPath (Get-CourierKey $a); $a = $null
    Write-Host "Saved (encrypted for your Windows user): $keyPath"; exit 0
}

# ---- settings: paths come from settings.json; overrides only in test modes (R3 N21) ----
$cfg = $null; $cfgPath = Join-Path $Root 'settings.json'
if (Test-Path -LiteralPath $cfgPath) { $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json }
$testMode = $DryRun -or $AllowAiAncestorForTest
if (($InboxDir -or $StagingDir -or $OutboxDir -or $PSBoundParameters.ContainsKey('Root')) -and -not $testMode) {
    Write-Host 'REFUSED: path overrides need -DryRun. Paths come from settings.json.'; exit 2
}
if (-not $InboxDir)   { $InboxDir   = $cfg.inbox_dir }
if (-not $StagingDir) { $StagingDir = $cfg.staging_dir }
if (-not $OutboxDir -and -not $DryRun) { $OutboxDir = $cfg.outbox_dir }
$providerEnv = @(); if ($cfg -and $cfg.provider_env) { $providerEnv = @($cfg.provider_env) }
if (-not $InboxDir) { Write-Host 'No inbox folder set (settings.json missing?)'; exit 1 }

# ---- Root must have no ancestor rule/repo files (R3 N19) ----
$bad = @(); $d = Split-Path $Root -Parent
while ($d) {
    foreach ($n in 'AGENTS.md', 'CLAUDE.md', '.git', '.opencode') { if (Test-Path -LiteralPath (Join-Path $d $n)) { $bad += (Join-Path $d $n) } }
    $d = Split-Path $d -Parent
}
if ($bad) {
    if ($AllowAiAncestorForTest) { Write-Host "TEST MODE WARNING: $($bad.Count) rule/repo file(s) above Root (ignored in test mode)." }
    else { Write-Host "REFUSED: found $($bad -join ', ') above $Root. Tell the host."; Show-Popup 'AI courier stopped: a rules file sits above its folder. Tell the host.'; exit 2 }
}

# ---- single instance (R3 N21); the canary's dry run uses its own temp Root, so it skips this ----
if (-not $DryRun) {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\courier-watch')
    if (-not $mutex.WaitOne(0)) { Write-Host 'Already running.'; exit 0 }
}

$dirs = @{ in = "$Root\incoming\host"; runs = "$Root\runs"; cfg = "$Root\oc-config"; agent = "$Root\oc-config\agent"; xdg = "$Root\oc-config\xdg" }
$dirs.Values | ForEach-Object { New-Item -ItemType Directory -Force $_ | Out-Null }
# One source of truth for the agent: messenger.md next to this script (the model is pinned there).
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'messenger.md') -Destination "$($dirs.agent)\messenger.md" -Force
$ocJson = Join-Path $PSScriptRoot 'oc-config\opencode.json'
if (Test-Path -LiteralPath $ocJson) { Copy-Item -LiteralPath $ocJson -Destination "$($dirs.cfg)\opencode.json" -Force }
$seenPath = "$Root\seen.jsonl"; $pinPath = "$Root\canary-pass.txt"
$notified = @{}; $script:prevSnap = @{}; $script:missing = 0

function Get-ModelId { ((Select-String -LiteralPath (Join-Path $PSScriptRoot 'messenger.md') -Pattern '^model:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value).Trim() }
function Get-OcVersion { try { ((& cmd /d /c 'opencode --version' 2>&1) | Select-Object -Last 1).ToString().Trim() } catch { 'unknown' } }
function Get-Seen { if (Test-Path $seenPath) { @(Get-Content $seenPath | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() } }
function Add-Seen($Obj) { if (-not $DryRun) { Add-Content -LiteralPath $seenPath -Value ($Obj | ConvertTo-Json -Compress) -Encoding UTF8 } }
function Get-TextSha([string]$s) { -join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($utf8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) }

function Clear-Stale {
    # R3 N9: nothing raw may outlive a run. Sweep anything older than 5 minutes.
    Get-ChildItem $dirs.in, $dirs.runs -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-5) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-Messenger([string]$RunDir) {
    # Env ALLOWLIST (R3 N5): the child sees only these variables. Message BEFORE -f (S-opencode P3b).
    # PROJECT_CONFIG=1 stops the AGENTS.md walk-up (probed on 1.18.32, TEST-LOG T0). Hard timeout + tree
    # kill; exit code ignored (the validator is the only success signal).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
    $psi.Arguments = '/d /c opencode run --agent messenger --dir "' + $RunDir + '" "Summarize the attached message per your rules." -f "' + $RunDir + '\msg-1.txt"'
    $psi.WorkingDirectory = $RunDir
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = $utf8; $psi.StandardErrorEncoding = $utf8
    $keep = @('PATH','PATHEXT','SystemRoot','SystemDrive','windir','ComSpec','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP','HOMEDRIVE','HOMEPATH') + $providerEnv
    $psi.EnvironmentVariables.Clear()
    foreach ($k in $keep) { $v = [Environment]::GetEnvironmentVariable($k); if ($v) { $psi.EnvironmentVariables[$k] = $v } }
    $psi.EnvironmentVariables['OPENCODE_CONFIG_DIR'] = $dirs.cfg
    $psi.EnvironmentVariables['XDG_CONFIG_HOME'] = $dirs.xdg
    $psi.EnvironmentVariables['OPENCODE_DISABLE_CLAUDE_CODE'] = '1'
    $psi.EnvironmentVariables['OPENCODE_DISABLE_PROJECT_CONFIG'] = '1'
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) { & taskkill /T /F /PID $p.Id 2>&1 | Out-Null; $p.WaitForExit(5000) | Out-Null }
    $out = ''; if ($outTask.Wait(5000)) { $out = $outTask.Result }
    [pscustomobject]@{ stdout = $out; timed_out = $timedOut }
}

function Get-JsonFromOcOutput([string]$Text) {
    # Strip ANSI, keep first '{' .. last '}'. The lib does the strict parse + key/enum/length checks.
    $t = [regex]::Replace($Text, '\x1B\[[0-9;?]*[ -/]*[@-~]', '')
    $a = $t.IndexOf('{'); $b = $t.LastIndexOf('}')
    if ($a -lt 0 -or $b -le $a) { return '' }
    $t.Substring($a, $b - $a + 1)
}

function Show-View([string]$View, [string]$Verdict, [string]$Name, [string]$Status, $Valid) {
    # R3 N6/N7: no views log. YES -> temp file in Notepad, deleted when Notepad closes.
    # NO -> header + "flagged" only (popup + window); the summary is not kept anywhere.
    if ($DryRun) { Write-Host $View; Write-Host "RESULT name=$Name status=$Status valid=$Valid verdict=$Verdict"; return }
    $lines = $View -split "`r`n"
    if ($Verdict -eq 'YES') {
        Write-Host $View
        if ($Quiet) { Write-Host '(test mode: Notepad not opened)'; return }
        $tmp = Join-Path $env:TEMP ("courier-view-{0}.txt" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        [IO.File]::WriteAllText($tmp, $View + "`r`n", $utf8)
        try { Start-Process notepad.exe -ArgumentList "`"$tmp`"" -Wait } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    } else {
        $short = (($lines | Select-Object -First 4) + 'flagged: open the file named on the from: line in your from-host Drive folder and read it yourself; never paste it into your AI. Want a clean version? Text the host for a resend.') -join "`r`n"
        Write-Host $short; Show-Popup $short
    }
}

function Get-StableFiles {
    # R3 N24: only files whose size + time did not change since the last look (Drive may still be writing).
    $files = @(Get-ChildItem -LiteralPath $InboxDir -File -ErrorAction SilentlyContinue)
    $snap = @{}; foreach ($f in $files) { $snap[$f.Name] = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)" }
    $stable = @($files | Where-Object { $script:prevSnap[$_.Name] -eq $snap[$_.Name] })
    $script:prevSnap = $snap
    return $stable
}

function Invoke-Tick {
    Clear-Stale
    $today = Get-Date -Format 'yyyy-MM-dd'
    if (-not (Test-Path -LiteralPath $InboxDir)) {
        $script:missing++
        if ($script:missing -ge 3 -and -not $notified['missing']) { $notified['missing'] = 1; Show-Popup 'courier inbox: folder missing (is Google Drive running?)' }
        return
    }
    $script:missing = 0; $notified.Remove('missing')
    if ($Once) { Get-StableFiles | Out-Null; Start-Sleep -Seconds 3 }   # -Once: two looks, 3 s apart
    $files = @(Get-StableFiles | Sort-Object LastWriteTime -Descending)   # newest first (R3 N13)
    $seen = Get-Seen
    $seenIds = @{}; foreach ($s in $seen) { $seenIds[$s.id] = 1 }
    $runsToday = @($seen | Where-Object { $_.result -eq 'run' -and ([string]$_.at).StartsWith($today) }).Count
    $key = Read-CourierKey $keyPath
    $version = $null; $unsigned = 0
    foreach ($f in $files) {
        $stamp = Get-Date -Format s
        # 1. Gate BEFORE reading: name, type (.txt/.md only: skips .gdoc/.gsheet/shortcuts), size.
        if (-not (Test-DropName $f.Name) -or $f.Length -gt 8KB) {
            $id = 'ref-' + (Get-TextSha "$($f.Name)|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)")
            if (-not $seenIds[$id]) {
                Write-Host "$stamp refused (name/type/size)"; Add-Seen @{ id = $id; at = $stamp; result = 'refused' }; $seenIds[$id] = 1
                if ($DryRun) { Write-Host "RESULT name=$($f.Name) status=refused valid= verdict=" }
            }
            continue
        }
        # 2. Read once; signature check with the host's verify key (R3 N1/N2).
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $id = -join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        if ($seenIds[$id]) { continue }
        $tag = Test-CourierTag ($utf8.GetString($bytes).TrimStart([char]0xFEFF)) $key
        if (-not $tag.ok) {
            $unsigned++; Add-Seen @{ id = $id; at = $stamp; result = 'unsigned' }; $seenIds[$id] = 1
            if ($DryRun) { Write-Host "RESULT name=$($f.Name) status=unsigned valid= verdict=" }
            continue
        }
        # 3. Daily cap, then the version + model pin.
        if (-not $Canary -and $runsToday -ge $DailyCap) {
            if (-not $notified["cap$today"]) { $notified["cap$today"] = 1; Show-Popup "Messages held: daily limit of $DailyCap reached. They run tomorrow." }
            continue
        }
        if (-not $version) { $version = "opencode $(Get-OcVersion) | model $(Get-ModelId)" }
        $pin = if (Test-Path $pinPath) { (Get-Content $pinPath -TotalCount 1).Trim() } else { '' }
        if (-not $Canary -and $version -ne $pin) {
            # O3: try the canary itself, once per new version, before holding anything (0 human steps on a pass).
            $autoOk = $false
            if (-not $DryRun) {
                $triedPath = Join-Path $Root 'canary-auto-tried.txt'
                $already = (Test-Path -LiteralPath $triedPath) -and ((Get-Content -LiteralPath $triedPath -Raw).Trim() -eq $version)
                if (-not $already) {
                    [IO.File]::WriteAllText($triedPath, $version, $utf8)
                    $cargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'canary.ps1'), '-Root', $Root)
                    if ($AllowAiAncestorForTest) { $cargs += '-AllowAiAncestorForTest' }   # threaded one hop further, tests only (see docs/test-evidence/auto-canary.md DESIGN)
                    try { & powershell @cargs *>$null } catch { Write-Host "auto-canary failed to start: $($_.Exception.Message)" }
                    $pin = if (Test-Path $pinPath) { (Get-Content $pinPath -TotalCount 1).Trim() } else { '' }
                    $autoOk = ($version -eq $pin)
                }
            }
            if (-not $autoOk) {
                if (-not $notified["ver$id"]) { $notified["ver$id"] = 1
                    Show-Popup "the safety test failed after an update; don't read messages, text the host a photo of this window"
                    if ($DryRun) { Write-Host "RESULT name=$($f.Name) status=version-changed valid= verdict=" } }
                continue   # not marked seen: it runs after the canary passes
            }
        }
        # 4. Run. The raw copy + run folder exist only inside try; seen is written after cleanup.
        $copy = "$($dirs.in)\$($id.Substring(0,8)).txt"
        $run = "$($dirs.runs)\$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($id.Substring(0,8))"
        $res = $null; $fields = $null
        try {
            [IO.File]::WriteAllText($copy, $tag.body, $utf8)
            $fields = Get-ScriptFields -Path $copy -Sender 'host' -DriveName $f.Name -ClaimedDate $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            New-Item -ItemType Directory -Force $run | Out-Null
            [IO.File]::WriteAllText("$run\msg-1.txt", $fields.clean_text, $utf8)
            $r = Invoke-Messenger $run
            if ($r.timed_out) { $res = [pscustomobject]@{ valid = $false; errors = @('timeout'); paste_safe = 'NO'; view = (Format-View -Fields $fields -Obj $null -Note 'messenger timed out: ask for a resend') } }
            else { $res = Get-ViewFromOutput -Fields $fields -Stdout (Get-JsonFromOcOutput $r.stdout) }
        } finally {
            Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
            if (Test-Path $run) { Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Add-Seen @{ id = $id; at = $stamp; result = 'run'; valid = $res.valid; verdict = $res.paste_safe }; $seenIds[$id] = 1; $runsToday++
        if (-not $res.valid) { Write-Host "$stamp messenger output failed checks ($(@($res.errors) -join ', ')); summary not shown" }
        if ($DryRun) { Write-Host "FIELDS name=$($f.Name) raw_approval=$($fields.raw_approval_claim) raw_ai_address=$($fields.raw_ai_address) chars_dropped=$($fields.chars_dropped)" }
        Show-View $res.view $res.paste_safe $f.Name 'run' $res.valid
    }
    if ($unsigned) { Show-Popup "$unsigned unsigned message ignored (not from the host's SEND). Tell the host." }
    # R3 N17: retention - delete your own sent files older than 7 days from your Drive send folder.
    if ($OutboxDir -and (Test-Path -LiteralPath $OutboxDir)) {
        Get-ChildItem -LiteralPath $OutboxDir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    # A2 + R3 N20: drafts waiting -> popup at most once a day. Never opens SEND.
    if ($StagingDir) {
        $drafts = @(Get-ChildItem -LiteralPath $StagingDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.txt', '.md' -and -not $_.Name.StartsWith('_') })
        if ($drafts.Count -and -not $notified["drafts$today"]) { $notified["drafts$today"] = 1; Show-Popup "$($drafts.Count) draft waiting: double-click SEND" }
    }
}

Write-Host 'AI courier watcher. Leave this window open (minimized is fine).'
if (-not (Test-Path -LiteralPath $keyPath)) { Write-Host 'No key for the host yet: every message will be ignored as unsigned. Run: watch-inbox.ps1 -SetKey host' }
do {
    try { Invoke-Tick } catch { Write-Host "$(Get-Date -Format s) error: $($_.Exception.Message)" }
    if (-not $Once) { Start-Sleep -Seconds $IntervalSec }
} while (-not $Once)
Clear-Stale
