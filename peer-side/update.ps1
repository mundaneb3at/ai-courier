# update.ps1 - install an update that the host signed. ONLY you start it, from a PowerShell window you
# opened yourself (File Explorer -> ai-courier folder -> address bar -> powershell -> Enter):
#   powershell -ExecutionPolicy Bypass -File .\update.ps1
# It refuses if an AI or a scheduled task started it. Nothing else ever runs it: no timer, no watcher.
# (That start check stops mistakes; it is not a wall against a program already running as you. What
# protects you is the signature: only files the host signed can ever be installed.)
# Order: signature -> newer version -> zip hash -> every file hash -> stop if it would overwrite a file
# changed on this computer -> you type yes -> backup -> install -> safety test (canary) -> on a FAIL the
# old files are put back and checked byte for byte. ASCII-only (PS 5.1).
# No test switch on purpose (a switch an AI can pass is a way around the checks): every guard is ONE line
# tagged "# CHECK:<name>" or "# GATE", and tests delete that line in a scratch copy.
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')
. (Join-Path $PSScriptRoot 'doctor.ps1')
$utf8 = New-Object Text.UTF8Encoding($false)
function Stop-Update([string]$Msg, [int]$Code = 1) { Write-Host $Msg; exit $Code }
function Get-BytesSha([byte[]]$B) { -join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($B) | ForEach-Object { $_.ToString('x2') }) }
function Test-UpdateSig([byte[]]$Data, [string]$SigPath) {
    # ssh-keygen -Y verify over the exact bytes read once below, against the allowed_signers file installed
    # at setup. Exit 0 = good signature from principal "host" in namespace courier-update. The bytes go in
    # through a FILE redirect: Windows OpenSSH reads a piped stdin in text mode (CRLF -> LF) and then every
    # genuine signature fails (measured 2026-09-26: pipe "incorrect signature", file redirect "Good").
    $ssh = "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path -LiteralPath $ssh) -or -not (Test-Path -LiteralPath $SigPath)) { return $false }
    $dataPath = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllBytes($dataPath, $Data)
        $psi = New-Object Diagnostics.ProcessStartInfo "$env:SystemRoot\System32\cmd.exe"
        $psi.Arguments = '/d /s /c ""' + $ssh + '" -Y verify -f "' + (Join-Path $Root 'allowed_signers') + '" -I host -n courier-update -s "' + $SigPath + '" < "' + $dataPath + '""'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        return ($p.ExitCode -eq 0)
    } finally { Remove-Item -LiteralPath $dataPath -Force -ErrorAction SilentlyContinue }
}
$marker = Join-Path $Root 'update-in-progress.txt'   # exists only while files are being replaced
function Restore-Snapshot($Snap) {
    # Put every file back from the backup (keep going past errors), then prove it byte for byte.
    # Returns how many files still differ; the marker is removed only when that is 0.
    foreach ($s in $Snap) {
        try {
            if ($s.existed) { Copy-Item -LiteralPath $s.bak -Destination $s.dst -Force }
            elseif (Test-Path -LiteralPath $s.dst) { Remove-Item -LiteralPath $s.dst -Force }
        } catch { Write-Host "restore error: $($_.Exception.Message)" }
    }
    $diff = @($Snap | Where-Object { if ($_.existed) { -not (Test-Path -LiteralPath $_.dst) -or (Get-FileSha $_.dst -Raw) -ne $_.sha } else { Test-Path -LiteralPath $_.dst } })
    if (-not $diff.Count) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    $diff.Count
}

# 1. Who started us: a plain shell chain up to explorer.exe only (a window you opened). svchost (a
#    scheduled task) passes the watcher's rule but not this one.
$la = Test-LaunchAllowed -Mode Watch
if (-not $la.ok -or $la.reason -ne 'started from explorer.exe') { Stop-Update "REFUSED: $($la.reason). Only a PowerShell window you opened yourself may start an update." 2 }   # CHECK:ancestor
if ([Console]::IsInputRedirected) { Stop-Update 'REFUSED: input is piped. Start it yourself in a PowerShell window.' 2 }   # GATE

# 1b. An earlier run stopped half-way (window closed, Ctrl+C, power cut)? Undo it first, nothing else.
if (Test-Path -LiteralPath $marker) {
    # PS 5.1 ConvertFrom-Json emits a JSON array as ONE item; ForEach-Object unrolls it into its entries
    $snap = @(Get-Content -LiteralPath (Join-Path (Get-Content -LiteralPath $marker -Raw).Trim() 'snap.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    $left = Restore-Snapshot $snap
    if ($left) { Stop-Update "ROLLBACK MISMATCH: an interrupted update left $left file(s) that could not be put back. Don't use the messenger; text the host now." 3 }
    Stop-Update "RESTORED: an earlier update was interrupted; the old version was put back exactly ($($snap.Count) files checked byte for byte). Run update.ps1 again to retry." 4
}

# 2. Find the newest update in <from-host>\updates\ (never read by the watcher: it lists only the top folder).
$d = Get-InstallDirs $Root
if (-not $d.cfg) { Stop-Update 'REFUSED: settings.json not found. Finish INSTALL first.' }
$cur = Get-Content -LiteralPath (Join-Path $Root 'BASELINE.json') -Raw | ConvertFrom-Json
$upd = Join-Path $d.cfg.inbox_dir 'updates'
$cand = @(Get-ChildItem -LiteralPath $upd -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^update-\d{1,6}\.json$' } |
    Sort-Object { [int]($_.BaseName -replace '\D', '') }) | Select-Object -Last 1
if (-not $cand) { Stop-Update "No update waiting. Installed: v$($cur.version)." 0 }
$n = [int]($cand.BaseName -replace '\D', '')
$jsonBytes = [IO.File]::ReadAllBytes($cand.FullName)   # read ONCE; everything below uses these bytes

# 3. The checks. Any failure: nothing on this computer was changed.
if (-not (Test-UpdateSig $jsonBytes "$($cand.FullName).sig")) { Stop-Update "REFUSED: update-$n is not signed by the host's update key. Nothing was changed." }   # CHECK:sig
$new = $utf8.GetString($jsonBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
if ([int]$new.version -ne $n -or [int]$new.version -le [int]$cur.version) { Stop-Update "REFUSED: update-$n (signed as v$($new.version)) is not newer than the installed v$($cur.version). Nothing was changed." }   # CHECK:version
$zipBytes = [IO.File]::ReadAllBytes((Join-Path $upd "update-$n.zip"))
if ((Get-BytesSha $zipBytes) -ne $new.zip_sha256) { Stop-Update "REFUSED: update-$n.zip does not match its signed hash (damaged or changed). Nothing was changed." }   # CHECK:zip
$tmp = Join-Path $Root 'update-tmp'
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
New-Item -ItemType Directory -Force $tmp | Out-Null
[IO.File]::WriteAllBytes("$tmp\u.zip", $zipBytes)   # extract the bytes that were hashed, not the Drive file again
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory("$tmp\u.zip", "$tmp\x")   # refuses entries that point outside x
$got = @{}
foreach ($f in Get-ChildItem -LiteralPath "$tmp\x" -Recurse -File -Force) { $got[$f.FullName.Substring("$tmp\x".Length + 1).ToLowerInvariant()] = $f.FullName }
$bad = @()
foreach ($e in $new.files) { $k = "$($e.group)\$($e.path)".ToLowerInvariant(); if (-not $got[$k] -or (Get-FileSha $got[$k]) -ne $e.sha256) { $bad += $e.id }; $got.Remove($k) }
if ($bad.Count -or $got.Count) { Stop-Update "REFUSED: $($bad.Count) file(s) in update-$n.zip do not match the signed list ($($bad -join ' ')), $($got.Count) extra. Nothing was changed." }   # CHECK:files

# 4. What changes: files whose signed hash differs from the installed baseline (or are new). Stop if any of
#    them was changed on this computer since the last install (or a new one would replace a file of the peer's).
$old = @{}; foreach ($e in $cur.files) { $old["$($e.group)\$($e.path)".ToLowerInvariant()] = $e }
$apply = @($new.files | Where-Object { $o = $old["$($_.group)\$($_.path)".ToLowerInvariant()]; (-not $o) -or $o.sha256 -ne $_.sha256 })
if (-not $d.work -and @($apply | Where-Object { $_.group -eq 'work' }).Count) { Stop-Update 'REFUSED: the work folder is unknown (settings.json has no staging_dir). Nothing was changed.' }
function Get-LocalChanges {
    $m = @()
    foreach ($e in $apply) {
        $dst = Get-DestPath $d $e; $o = $old["$($e.group)\$($e.path)".ToLowerInvariant()]
        if (-not (Test-Path -LiteralPath $dst)) { continue }
        if ($o -and (Get-FileSha $dst) -ne $o.sha256) { $m += $o.id } elseif (-not $o) { $m += "$($e.id)-new" }
    }
    , $m
}
$stopMsg = 'STOPPED: this update would overwrite files changed on this computer: {0}. Nothing was changed. Tell your AI; it makes a support ticket (route U1).'
$mine = Get-LocalChanges
if ($mine.Count) { Stop-Update ($stopMsg -f ($mine -join ' ')) 5 }   # CHECK:local

# 5. Show what it is, and let the person decide.
Write-Host "Update v$($cur.version) -> v$($new.version) ($($new.date)), $($apply.Count) file(s) change:"
Write-Host $new.changelog
if ((Read-Host 'Type yes to install it') -ne 'yes') { Stop-Update 'Cancelled. Nothing was changed.' 0 }   # GATE
$mine = Get-LocalChanges   # again: the prompt can wait for hours while the peer's AI keeps working
if ($mine.Count) { Stop-Update ($stopMsg -f ($mine -join ' ')) 5 }   # CHECK:local2

# 6. Backup (every file about to be written, plus BASELINE.json) with its hashes saved next to it, then the
#    marker: if this run dies from here on, the next run of update.ps1 puts everything back (step 1b).
$mm = [regex]::Match([IO.File]::ReadAllText((Join-Path $Root 'messenger.md')), '(?m)^model:[^\r\n]*')
$bk = Join-Path $Root ("update-backup\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bk | Out-Null
$snap = @(); $i = 0
foreach ($dst in @($apply | ForEach-Object { Get-DestPath $d $_ }) + (Join-Path $Root 'BASELINE.json')) {
    $s = [pscustomobject]@{ dst = $dst; existed = (Test-Path -LiteralPath $dst); sha = $null; bak = (Join-Path $bk ('{0:d3}' -f $i)) }
    if ($s.existed) { $s.sha = Get-FileSha $dst -Raw; Copy-Item -LiteralPath $dst -Destination $s.bak }
    $snap += $s; $i++
}
[IO.File]::WriteAllText("$bk\snap.json", (ConvertTo-Json -InputObject $snap -Depth 3), $utf8)
[IO.File]::WriteAllText($marker, $bk, $utf8)
$pass = $false
try {
    foreach ($e in $apply) {
        $src = Join-Path "$tmp\x" "$($e.group)\$($e.path)"; $dst = Get-DestPath $d $e
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        if ($e.group -eq 'root' -and $e.path -eq 'messenger.md' -and $mm.Success) {   # keep the peer's model line
            [IO.File]::WriteAllText($dst, [regex]::Replace([IO.File]::ReadAllText($src), '(?m)^model:[^\r\n]*', $mm.Value.Replace('$', '$$')), $utf8)
        } else { Copy-Item -LiteralPath $src -Destination $dst -Force }
    }
    [IO.File]::WriteAllBytes((Join-Path $Root 'BASELINE.json'), $jsonBytes)
    Write-Host 'Installed. Running the safety test (canary), about a minute...'
    $cargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'canary.ps1'), '-Root', $Root)
    & powershell @cargs | Out-Host
    $pass = ($LASTEXITCODE -eq 0)
} catch { Write-Host "install error: $($_.Exception.Message)" }

# 7. FAIL (or an error while installing): put every file back and prove it byte for byte.
if (-not $pass) {
    $left = Restore-Snapshot $snap
    if ($left) { Stop-Update "ROLLBACK MISMATCH: $left file(s) differ from before the update. Don't use the messenger; text the host now." 3 }
    Stop-Update "ROLLED BACK: the safety test failed, so v$($cur.version) was put back exactly ($($snap.Count) files checked byte for byte). The messenger works as before. Tell the host (route U1)." 4
}
Remove-Item -LiteralPath $marker -Force
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "UPDATE DONE: v$($new.version) installed and the safety test passed. Now close the minimized watcher window and do INSTALL step 9 again, so the watcher runs the new version."
exit 0
