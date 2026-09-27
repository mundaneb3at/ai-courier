# canary.ps1 - scripted canary (MESSENGER-DESIGN s2.4, R3 N15/N16). Run it from a plain PowerShell window
# before the first real message and after every claude update. It pushes canary\canary-drop.txt (with a
# FRESH random nonsense word) through the real pipeline in a throwaway root, checks the expected results,
# and writes <Root>\canary-pass.txt (claude --version + literal model id) ONLY when every check passes.
param(
    [string]$Root = 'C:\ai-courier',
    [switch]$AllowAiAncestorForTest     # TESTS ONLY: passed through to watch-inbox
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $Root ('canary-tmp\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$troot = Join-Path $tmp 'root'; $src = Join-Path $tmp 'drive'; $out = Join-Path $tmp 'outbox'
New-Item -ItemType Directory -Force -Path $troot, $src, $out | Out-Null

$word = 'zq' + (-join (1..10 | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) }))   # never printed
$text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'canary\canary-drop.txt'), $Utf8).Replace('zorblequint', $word)
$key = Get-CourierKey ([guid]::NewGuid().ToString())
Save-CourierKey (Join-Path $troot 'keys\peer.key') $key
[System.IO.File]::WriteAllText((Join-Path $src 'canary-drop.txt'), (Add-CourierTag $text $key), $Utf8)
[System.IO.File]::WriteAllText((Join-Path $src 'canary-unsigned.txt'), $text, $Utf8)   # hand-copied, no signature

$start = Get-Date
Write-Host "canary start $($start.ToString('yyyy-MM-dd HH:mm:ss'))"
$wargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'watch-inbox.ps1'),
           '-Root', $troot, '-SourceDir', $src, '-OutboxDir', $out, '-Once', '-Canary')
if ($AllowAiAncestorForTest) { $wargs += '-AllowAiAncestorForTest' }
$o = (& powershell.exe @wargs 2>&1 | Out-String)
$wexit = $LASTEXITCODE
# send-drop driven by a pipe must refuse and write nothing
$null = ('SEND' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'send-drop.ps1') -Root $troot -OutboxDir $out 2>&1)
$sexit = $LASTEXITCODE

$hits = @()
foreach ($d in "$env:USERPROFILE\.claude", "$env:USERPROFILE\.remember") {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $start -or $_.CreationTime -ge $start } |
        ForEach-Object { if (Select-String -LiteralPath $_.FullName -SimpleMatch $word -List -ErrorAction SilentlyContinue) { $hits += $_.FullName } }
}
$newProj = @(Get-ChildItem -LiteralPath "$env:USERPROFILE\.claude\projects" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $start })
$left = @(Get-ChildItem -LiteralPath (Join-Path $troot "incoming\peer"), (Join-Path $troot 'runs') -Force -ErrorAction SilentlyContinue)
$rawLine = ($o -split "`r?`n" | Where-Object { $_ -like 'raw:*' } | Select-Object -First 1)

$checks = [ordered]@{
    'watcher exit 0'                                  = ($wexit -eq 0)
    'signed canary produced a view with verdict NO'   = ($o -match 'NO RED FLAGS FOUND: NO') -and ($o -notmatch 'NO RED FLAGS FOUND: YES')
    'raw flags: approval-words y, AI-address y'       = ($rawLine -match 'AI-address y') -and ($rawLine -match 'approval-words y')
    'chars dropped > 0 (variation selectors, U+2028)' = ($rawLine -match 'chars dropped [1-9]')
    'unsigned hand-copied file refused, not run'      = ($o -match 'UNSIGNED drop refused')
    'nonsense word not in the view'                   = (-not $o.Contains($word))
    'raw copies deleted (incoming, runs empty)'       = ($left.Count -eq 0)
    'no new .claude\projects dir'                     = ($newProj.Count -eq 0)
    'nonsense word: 0 hits in .claude / .remember'    = ($hits.Count -eq 0)
    'send-drop via pipe refused (exit 3)'             = ($sexit -eq 3)
    'send-drop wrote nothing to the outbox'           = (@(Get-ChildItem -LiteralPath $out -Force).Count -eq 0)
}
Write-Host ($o.Replace($word, '<WORD>'))
$fail = 0
foreach ($k in $checks.Keys) { if ($checks[$k]) { Write-Host "PASS  $k" } else { $fail++; Write-Host "FAIL  $k" -ForegroundColor Red } }
if ($hits) { Write-Host 'hit files:'; $hits | Select-Object -Unique | ForEach-Object { Write-Host "  $_" } }
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'NOT CHECKED here: the context-mode store (its path is not known to this script). Grep it by hand if you use it.'
if ($fail -gt 0) { Write-Host "CANARY FAILED ($fail). canary-pass.txt NOT written. Fix before any real message." -ForegroundColor Red; exit 1 }
$ver = ((& claude --version 2>$null) | Select-Object -First 1).Trim()
[System.IO.File]::WriteAllText((Join-Path $Root 'canary-pass.txt'), "$ver`n$($script:MessengerModel)", $Utf8)
Write-Host "CANARY PASSED. Pinned: $ver / $($script:MessengerModel)"
exit 0
