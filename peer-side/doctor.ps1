# doctor.ps1 - compare this computer's messenger + work setup with BASELINE.json (what the host shipped).
# READ-ONLY: it changes nothing, so your AI may run it. The output uses file ids (listed in BASELINE.json)
# instead of paths, and avoids words the message checker flags, so it can go into a support ticket as-is.
#   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\doctor.ps1"
#   . .\doctor.ps1      functions only (update.ps1 and the host's make-release.ps1 use them)
# ASCII-only (PS 5.1).
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$script:ModelPlaceholder = 'model: <cheap model you already have>'
# Files the messenger itself writes into its folder at setup / run time: never "added".
$script:RuntimeRx = '^(?:settings\.json|start-watcher\.cmd|seen\.jsonl|canary-pass\.txt|canary-auto-tried\.txt|sent\.log|BASELINE\.json|update-in-progress\.txt|(?:keys|sent|incoming|runs|canary-tmp|update-backup|update-tmp|oc-config\\agent|oc-config\\xdg)\\.*)$'

function Get-FileSha([string]$Path, [switch]$Raw) {
    # messenger.md gets the peer's model written into its model: line at setup, so (unless -Raw) it is hashed
    # with that line put back to the template text. Every other file: plain SHA-256 of the bytes.
    $b = [IO.File]::ReadAllBytes($Path)
    if (-not $Raw -and (Split-Path $Path -Leaf) -eq 'messenger.md') {
        $u = New-Object Text.UTF8Encoding($false)
        $b = $u.GetBytes([regex]::Replace($u.GetString($b), '(?m)^model:[^\r\n]*', $script:ModelPlaceholder))
    }
    -join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($b) | ForEach-Object { $_.ToString('x2') })
}

function Get-PackageMap([string]$Pkg) {
    # Where each shipped file lands. group root = the ai-courier folder (INSTALL step 6 copies
    # messenger\* there); group work = Desktop\work (kit setup.ps1 copies these; templates are the peer's).
    $m = Join-Path $Pkg 'messenger'; $k = Join-Path $Pkg 'kit'; $out = @()
    foreach ($f in Get-ChildItem -LiteralPath $m -Recurse -File -Force) {
        $r = $f.FullName.Substring($m.Length + 1)
        if ($r -eq '_HOW-TO-DRAFT.md') { $out += [pscustomobject]@{ group = 'work'; path = 'outbox-staging\_HOW-TO-DRAFT.md'; src = $f.FullName } }
        elseif ($r -ne 'BASELINE.json') { $out += [pscustomobject]@{ group = 'root'; path = $r; src = $f.FullName } }
    }
    foreach ($n in 'AGENTS.md', 'CLAUDE.md', 'WORKFLOWS.md', 'SEATS.md', '.gitignore') {
        if (Test-Path -LiteralPath "$k\$n") { $out += [pscustomobject]@{ group = 'work'; path = $n; src = "$k\$n" } }
    }
    foreach ($f in Get-ChildItem -LiteralPath "$k\skills" -Recurse -File -Force) {
        $out += [pscustomobject]@{ group = 'work'; path = 'skills\' + $f.FullName.Substring("$k\skills".Length + 1); src = $f.FullName }
    }
    $oc = "$k\tools\opencode"
    $out += [pscustomobject]@{ group = 'work'; path = 'opencode.json'; src = "$oc\opencode.json" }
    foreach ($f in Get-ChildItem -LiteralPath "$oc\commands" -File -Force) {
        $out += [pscustomobject]@{ group = 'work'; path = '.opencode\commands\' + $f.Name; src = $f.FullName }
    }
    $out | Sort-Object group, path
}

function Get-InstallDirs([string]$Root) {
    $cfg = $null; $p = Join-Path $Root 'settings.json'
    if (Test-Path -LiteralPath $p) { $cfg = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json }
    $work = if ($cfg -and $cfg.staging_dir) { Split-Path $cfg.staging_dir -Parent } else { $null }
    @{ root = $Root.TrimEnd('\'); work = $work; cfg = $cfg }
}

function Get-DestPath($Dirs, $Entry) { $b = $Dirs[[string]$Entry.group]; if ($b) { Join-Path $b $Entry.path } }

function Get-Drift([string]$Root, $Baseline) {
    # changed / missing = baseline ids; added = untracked files (group + type only, no names).
    $d = Get-InstallDirs $Root
    $changed = @(); $missing = @(); $tracked = @{}
    foreach ($e in $Baseline.files) {
        $p = Get-DestPath $d $e
        if (-not $p) { $missing += $e.id; continue }
        $tracked[$p.ToLowerInvariant()] = 1
        if (-not (Test-Path -LiteralPath $p)) { $missing += $e.id }
        elseif ((Get-FileSha $p) -ne $e.sha256) { $changed += $e.id }
    }
    $scan = @(@{ g = 'root'; dir = $d.root })
    if ($d.work) { $scan += @{ g = 'work'; dir = "$($d.work)\skills" }, @{ g = 'work'; dir = "$($d.work)\.opencode" } }
    $added = @()
    foreach ($s in $scan) {
        foreach ($f in @(Get-ChildItem -LiteralPath $s.dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            if ($tracked[$f.FullName.ToLowerInvariant()]) { continue }
            if ($s.g -eq 'root' -and $f.FullName.Substring($d.root.Length + 1) -match $script:RuntimeRx) { continue }
            $added += '{0} {1}' -f $s.g, $(if ($f.Extension) { $f.Extension.TrimStart('.').ToLowerInvariant() } else { 'noext' })
        }
    }
    [pscustomobject]@{ changed = $changed; missing = $missing; added = $added; dirs = $d }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced: functions only

$Root = $Root.TrimEnd('\')
$bp = Join-Path $Root 'BASELINE.json'
if (-not (Test-Path -LiteralPath $bp)) { Write-Output 'DOCTOR: no baseline in this folder. Ask the host for the current package.'; exit 1 }
$b = Get-Content -LiteralPath $bp -Raw | ConvertFrom-Json
$r = Get-Drift $Root $b
$list = { param($a) if (-not @($a).Count) { '-' } else { ((@($a) | Select-Object -First 12) -join ' ') + $(if (@($a).Count -gt 12) { " (+$(@($a).Count - 12) more)" }) } }
$addedTxt = if ($r.added.Count) { (@($r.added | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ') } else { '-' }
$ok = @($b.files).Count - $r.changed.Count - $r.missing.Count

# Run from the Windows folder: cmd looks in the CURRENT folder first, so an opencode.cmd dropped into
# Desktop\work (where the peer's AI runs this) would otherwise be what runs.
Push-Location $env:SystemRoot
$ver = try { ((& cmd /d /c 'opencode --version' 2>&1) | Select-Object -Last 1).ToString().Trim() } catch { 'not found' } finally { Pop-Location }
$mm = Select-String -LiteralPath (Join-Path $Root 'messenger.md') -Pattern '^model:\s*(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1
$model = if ($mm) { $mm.Matches[0].Groups[1].Value.Trim() } else { 'not set' }
$pinPath = Join-Path $Root 'canary-pass.txt'
$canary = if (-not (Test-Path -LiteralPath $pinPath)) { 'never passed' }
          elseif ((Get-Content -LiteralPath $pinPath -TotalCount 1).Trim() -eq "opencode $ver | model $model") { 'pin matches' } else { 'pin stale (versions changed since the last pass)' }
$watch = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'watch-inbox\.ps1' -and $_.CommandLine -notmatch '-DryRun' }).Count
$inbox = if (-not $r.dirs.cfg) { 'no settings' } elseif (Test-Path -LiteralPath $r.dirs.cfg.inbox_dir) { 'ok' } else { 'missing' }
$key = if (Test-Path -LiteralPath (Join-Path $Root 'keys\host.key')) { 'saved' } else { 'missing' }

Write-Output "DOCTOR $(Get-Date -Format 'yyyy-MM-dd HH:mm') (read-only; file ids are listed in the baseline)"
Write-Output "package = v$($b.version) from $($b.date) | tracked $(@($b.files).Count) | ok $ok | changed $($r.changed.Count) | missing $($r.missing.Count) | added $($r.added.Count)"
Write-Output "changed = $(& $list $r.changed)"
Write-Output "missing = $(& $list $r.missing)"
Write-Output "added = $addedTxt"
Write-Output "opencode version = $ver (shipped with $($b.opencode_version))"
Write-Output "model pin = $model (shipped with $($b.model))"
Write-Output "canary = $canary"
Write-Output "watcher = $(if ($watch) { 'running' } else { 'not running' })"
Write-Output "inbox = $inbox"
Write-Output "key = $key"
if (Test-Path -LiteralPath (Join-Path $Root 'update-in-progress.txt')) { Write-Output 'update = INTERRUPTED half-way; run the update again by hand, it puts the old version back first' }
$seenPath = Join-Path $Root 'seen.jsonl'
$seen = if (Test-Path -LiteralPath $seenPath) { @(Get-Content -LiteralPath $seenPath -Tail 5 | Where-Object { $_ }) } else { @() }
Write-Output "last $($seen.Count) watcher results (newest last) ="
foreach ($l in $seen) { try { $o = $l | ConvertFrom-Json; Write-Output ("  {0} {1} {2}" -f $o.at, $o.result, $(if ($o.verdict) { "red-flags-none=$($o.verdict)" } else { '' })) } catch { Write-Output '  (unreadable line)' } }
$lc = if ($r.dirs.work) { Join-Path $r.dirs.work 'LOCAL-CHANGES.md' } else { $null }
$lines = if ($lc -and (Test-Path -LiteralPath $lc)) { @(Get-Content -LiteralPath $lc | Where-Object { $_ -match '^(\d{4}-\d{2}-\d{2})' -and $Matches[1] -ge $b.date }) } else { @() }
Write-Output "local changes since v$($b.version) = $($lines.Count) line(s)$(if ($lines.Count -gt 15) { ', last 15 shown' })"
# The peer's AI writes these lines; blank out anything shaped like a link, path or file name so the ticket
# is not held back by the host's checker (the log rule asks for plain words, this catches slips).
foreach ($l in ($lines | Select-Object -Last 15)) {
    $l = [regex]::Replace($l, '(?i)\b(?:https?|ftp|file)://\S*|\bwww\.\S*|\S*[\\/]\S*|%\w+%|\b[\w-]+\.[A-Za-z][A-Za-z0-9]{0,5}\b', '[name]')
    Write-Output ('  ' + $(if ($l.Length -gt 140) { $l.Substring(0, 140) } else { $l }))
}
