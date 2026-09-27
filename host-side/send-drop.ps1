# send-drop.ps1 - the ONE human step on the host's outbound side (MESSENGER-DESIGN s2.3, REDESIGN B3, R3 N1-N4).
# Open it only by double-clicking SEND.cmd (or a desktop shortcut to powershell.exe running this file).
# Release = typing YOUR send passphrase (never stored here). It signs the exact bytes shown; the peer's
# watcher runs only files whose signature verifies.
param(
    [string]$Root = 'C:\ai-courier',
    [string]$Draft,                                  # a file in outbox-staging; omitted = pick from a list
    [string]$OutboxDir = 'G:\My Drive\from-host',
    [int]$DailyCap = 3
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Staging = Join-Path $Root 'outbox-staging'
$SentLog = Join-Path $Root 'sent.log'
$Classes = @('study', 'schedule', 'workflow', 'project', 'logistics')
# Informs only; the human decides. A starter list of private-topic words: edit it for your own never-send topics.
$NeverAcross = '(?i)\b(?:password|passcode|pin\s+code|bank|account number|salary|income|debt|loan|diagnos\w*|medication|prescription|therap(?:y|ist)|doctor|hospital|medical|lawyer|legal|court|lawsuit|address|phone number)\b'

# 1. Refuse unless a human opened this window (R2 M7, R3 N4). Every reason prints.
$why = @()
if ([Console]::IsInputRedirected) { $why += 'stdin is redirected (not a keyboard)' }
$la = Test-LaunchAllowed -Mode Send
if (-not $la.ok) { $why += $la.reason }
if ($why) { Write-Host ('REFUSED: ' + ($why -join '; ') + '. Double-click SEND.cmd yourself.') -ForegroundColor Red; exit 3 }

# 2. Info only (R3 N1: the signature is the authority now): files in the outbox that send-drop did not write.
$sent = @{}; $today = Get-Date -Format 'yyyy-MM-dd'; $sentToday = 0
if (Test-Path -LiteralPath $SentLog) {
    foreach ($l in [System.IO.File]::ReadAllLines($SentLog)) {
        $c = $l -split "`t"; if ($c[0]) { $sent[$c[0]] = $true }
        if ($c.Count -ge 4 -and $c[3].StartsWith($today)) { $sentToday++ }
    }
}
if (Test-Path -LiteralPath $OutboxDir) {
    Get-ChildItem -LiteralPath $OutboxDir -File -Force | Where-Object { -not $sent.ContainsKey((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()) } |
        ForEach-Object { Write-Host "NOTE: file in outbox not written by send-drop: $($_.Name) (unsigned files are refused on the peer side)" -ForegroundColor Yellow }
}
if ($sentToday -ge $DailyCap) { Write-Host "REFUSED: $sentToday sends today already (cap $DailyCap, R3 N20)."; exit 8 }

# 3. Pick the draft and read it ONCE into memory (R3 N3). Everything below uses these bytes only.
if (-not $Draft) {
    $list = @(Get-ChildItem -LiteralPath $Staging -File | Sort-Object LastWriteTime)
    if ($list.Count -eq 0) { Write-Host 'No drafts in outbox-staging.'; exit 0 }
    for ($i = 0; $i -lt $list.Count; $i++) { Write-Host ("[{0}] {1}  ({2} B, {3:yyyy-MM-dd HH:mm})" -f ($i + 1), $list[$i].Name, $list[$i].Length, $list[$i].LastWriteTime) }
    $n = 0
    if (-not [int]::TryParse((Read-Host 'Number of the draft to review'), [ref]$n) -or $n -lt 1 -or $n -gt $list.Count) { Write-Host 'Cancelled.'; exit 0 }
    $Draft = $list[$n - 1].FullName
}
$c = ConvertTo-AllowedText ($Utf8.GetString([System.IO.File]::ReadAllBytes($Draft)).TrimStart([char]0xFEFF))
$text = $c.text
$bytes = $Utf8.GetByteCount($text) + 78   # + the signature line
if ($bytes -gt 8192) { Write-Host "REFUSED: $bytes B is over the 8 KB limit the other side accepts. Shorten the draft."; exit 6 }

# 4. Show exactly what will be signed and sent, then the flags, then the class.
Write-Host ('=' * 70); Write-Host $text; Write-Host ('=' * 70)
Write-Host "chars removed by the allowlist: $($c.chars_dropped)   size with signature: $bytes B"
$flags = @()
if ($text -match $script:RxLinks) { $flags += 'LINK' }
if ($text -match $script:RxCode) { $flags += 'CODE' }
if ($text -match $script:RxPaths) { $flags += 'PATH / FILE NAME' }
if ($text -match $script:RxAiAddr) { $flags += 'ADDRESSES AN AI' }
$m = [regex]::Matches($text, $NeverAcross) | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique
if ($m) { $flags += ('PRIVATE-TOPIC WORDS: ' + ($m -join ', ')) }
if ($flags) { Write-Host ('FLAGS: ' + ($flags -join ' | ')) -ForegroundColor Yellow } else { Write-Host 'FLAGS: none' }
Write-Host 'Never send: health or medical details, legal or financial matters, passwords, details about other people, verbatim personal conversation, paths, links, code.'
$class = (Read-Host ('Topic class (' + ($Classes -join ' / ') + ')')).Trim().ToLowerInvariant()
if ($Classes -notcontains $class) { Write-Host 'REFUSED: not an allowed class. Nothing sent.'; exit 7 }

# 5. The passphrase IS the release (R3 N1). Empty = cancel. Typed twice (O6): a typo used to reach
# The peer side as UNSIGNED with no local warning; now it's caught here, with one retry, before anything is sent.
function Read-Passphrase([string]$Prompt) {
    $ss = Read-Host -AsSecureString $Prompt
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
$pass = $null
for ($attempt = 1; $attempt -le 2; $attempt++) {
    $p1 = Read-Passphrase 'Type your SEND passphrase to sign and send (Enter alone cancels)'
    if (-not $p1) { Write-Host 'Cancelled. Nothing sent.'; exit 0 }
    $p2 = Read-Passphrase 'Same passphrase again'
    if ($p1 -ceq $p2) { $pass = $p1; break }
    if ($attempt -eq 1) { Write-Host 'The two passphrases differ. Nothing sent. Try once more.' }
    else { Write-Host 'The two passphrases differ again. Nothing sent.'; exit 0 }
}
$p1 = $null; $p2 = $null
$wire = Add-CourierTag $text (Get-CourierKey $pass)
$pass = $null
$name = 'from-host-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
$dest = Join-Path $OutboxDir $name
[System.IO.File]::WriteAllText($dest, $wire, $Utf8)   # the in-memory bytes, never a copy of the staging path
$hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::AppendAllText($SentLog, ($hash + "`t" + $name + "`t" + $class + "`t" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $Utf8)
$sentDir = Join-Path $Staging 'sent'
New-Item -ItemType Directory -Force -Path $sentDir | Out-Null
Move-Item -LiteralPath $Draft -Destination (Join-Path $sentDir ((Get-Date -Format 'yyyyMMdd-HHmmss-') + [System.IO.Path]::GetFileName($Draft)))
Write-Host "SENT as $name ($class). Drive for desktop uploads it."
