# send-drop.ps1 - the ONE human step: send one draft from outbox-staging to your Drive folder.
# Start it only by double-clicking SEND (SEND.cmd). It refuses unless Windows Explorer started it.
# Your PASSPHRASE is the release: it signs the exact text you were shown. It is never stored.
# Paths come from <Root>\settings.json (written at setup). ASCII-only source (PS 5.1).
param([string]$Root = (Join-Path $env:USERPROFILE 'ai-courier'))
$ErrorActionPreference = 'Stop'
$Classes = 'study', 'schedule', 'workflow', 'project', 'logistics'
$SendCap = 3
. (Join-Path $PSScriptRoot 'messenger-lib.ps1')   # shared: allowlist, launch check, signing, regexes

function Get-Flags([string]$Text) {
    $f = @()
    if ($Text -match $script:RxLinks) { $f += 'LINK' }
    if ($Text -match $script:RxPaths) { $f += 'FILE PATH or FILE NAME' }
    if ($Text -match $script:RxCode)  { $f += 'CODE/COMMAND' }
    if ($Text -match $script:RxAiAddr) { $f += 'TEXT ADDRESSED TO AN AI' }
    if ($Text -match '(?i)\b(password|passcode|bank|account number|sin|ssn|diagnos\w*|medication|therapist|lawyer|debt|salary|drugs?|alcohol)\b') { $f += 'PRIVATE-TOPIC WORD (check it)' }
    $f
}
function Stop-Send([string]$Msg, [int]$Code = 1) { Write-Host $Msg; Read-Host 'Press Enter to close' | Out-Null; exit $Code }

# Dot-sourced (". .\send-drop.ps1") = define the functions only, for testing. Nothing is sent.
if ($MyInvocation.InvocationName -eq '.') { return }

# 1. Refuse unless a human started it (N4 allowlist) and input is a real keyboard.
if ([Console]::IsInputRedirected) { Write-Host 'REFUSED: input is piped. Double-click SEND yourself.'; exit 2 }
$la = Test-LaunchAllowed -Mode Send
if (-not $la.ok) { Write-Host "REFUSED: $($la.reason). Double-click SEND on your desktop yourself."; exit 2 }

$cfg = Get-Content -LiteralPath (Join-Path $Root 'settings.json') -Raw | ConvertFrom-Json
$OutboxDir = $cfg.outbox_dir; $StagingDir = $cfg.staging_dir
$sentLog = Join-Path $Root 'sent.log'   # information only (an AI could edit it); the signature is the gate
$sentDir = Join-Path $Root 'sent'
New-Item -ItemType Directory -Force $sentDir | Out-Null
if (-not (Test-Path -LiteralPath $OutboxDir)) { Stop-Send "Your Drive send folder was not found: $OutboxDir. Is Google Drive running?" }
$today = Get-Date -Format 'yyyy-MM-dd'
$sentToday = @(Get-Content $sentLog -ErrorAction SilentlyContinue | Where-Object { $_.StartsWith($today) }).Count
if ($sentToday -ge $SendCap) { Stop-Send "You already sent $SendCap today. That is the daily limit; try tomorrow." }

# 2. Pick the oldest draft. Read its bytes ONCE; everything below uses only this in-memory copy (N3).
$draft = Get-ChildItem -LiteralPath $StagingDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.txt', '.md' -and -not $_.Name.StartsWith('_') } | Sort-Object LastWriteTime | Select-Object -First 1
if (-not $draft) { Stop-Send "No draft waiting in $StagingDir" 0 }
$bytes = [IO.File]::ReadAllBytes($draft.FullName)
if ($bytes.Length -gt 8KB) { Stop-Send "REFUSED: $($draft.Name) is over 8 KB. Ask your AI for a shorter draft." }
$raw = (New-Object Text.UTF8Encoding $false).GetString($bytes).TrimStart([char]0xFEFF)
$clean = ConvertTo-AllowedText $raw
$body = $clean.text.Replace("`r`n", "`n").TrimEnd()

# 3. Show exactly what will be sent.
Clear-Host
Write-Host "===== DRAFT: $($draft.Name) =====" -ForegroundColor Cyan
Write-Host $body
Write-Host '===== END OF DRAFT =====' -ForegroundColor Cyan
if ($clean.chars_dropped) { Write-Host "Note: $($clean.chars_dropped) hidden/odd characters were removed." -ForegroundColor Yellow }
foreach ($f in (Get-Flags $body)) { Write-Host "CHECK: contains $f" -ForegroundColor Yellow }
Write-Host 'Never send health, money, passwords, legal matters, or other people''s details.'
$class = Read-Host "Topic ($($Classes -join ' / '))"
if ($Classes -notcontains $class) { Stop-Send 'Not one of the topics. Nothing sent.' }

# 4. The passphrase signs exactly $body. Typed twice so a typo does not silently fail on the host's side.
Write-Host 'To send it, type your passphrase. To cancel, just press Enter.'
$p1 = Read-Host 'Passphrase' -AsSecureString
$p2 = Read-Host 'Passphrase again' -AsSecureString
$plain = { param($s) $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
$a = & $plain $p1; $b2 = & $plain $p2
if (-not $a) { Stop-Send 'Cancelled. Nothing sent.' 0 }
if ($a -cne $b2) {
    Write-Host 'The two passphrases differ. Nothing sent. Try once more.'
    $p1 = Read-Host 'Passphrase' -AsSecureString
    $p2 = Read-Host 'Passphrase again' -AsSecureString
    $a = & $plain $p1; $b2 = & $plain $p2
    if (-not $a) { Stop-Send 'Cancelled. Nothing sent.' 0 }
    if ($a -cne $b2) { Stop-Send 'The two passphrases differ again. Nothing sent.' }
}
$signed = Add-CourierTag $body (Get-CourierKey $a)
$a = $null; $b2 = $null

# 5. Write the in-memory bytes (never Copy-Item the staging file), log, archive the draft.
$name = '{0}-{1}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $class
[IO.File]::WriteAllText((Join-Path $OutboxDir $name), $signed, (New-Object Text.UTF8Encoding $false))
Add-Content -LiteralPath $sentLog -Value ("{0}`t{1}`t{2}" -f (Get-Date -Format 's'), $class, $name)
Move-Item -LiteralPath $draft.FullName -Destination (Join-Path $sentDir ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $draft.Name))
Write-Host "SENT as $name" -ForegroundColor Green
Read-Host 'Press Enter to close' | Out-Null
