# make-release.ps1 - build and sign an update for the peer's messenger. Run it yourself in a plain PowerShell
# window (it asks for your update-key passphrase). INSTALL.md step 14 has the paste.
# The package folder may be writable by other AI tools on this machine. So this script runs NO code from the
# package (the two helpers below are copies of the peer's doctor.ps1's), and before the passphrase prompt it
# prints every file that differs from your LAST SIGNED release: read that list; Ctrl+C if anything on it
# is not a change you made.
# Writes into -OutDir: update-<N>.zip, update-<N>.json (the signed baseline), update-<N>.json.sig.
# Only after a good signature: messenger\allowed_signers, messenger\CHANGELOG.md, messenger\BASELINE.json
# in the package (so the next fresh zip matches). Signs with Windows' built-in OpenSSH:
# ssh-keygen -Y sign -n courier-update. ASCII-only (PS 5.1).
param(
    [Parameter(Mandatory)][int]$Version,
    [Parameter(Mandatory)][string]$Notes,
    [string]$Package = (Join-Path $PSScriptRoot '..\package'),
    [string]$OutDir = (Join-Path $env:USERPROFILE 'courier-releases'),   # outside C:\ai-courier: Claude may read it (triage)
    [string]$KeyFile = (Join-Path $env:USERPROFILE '.ssh\courier-update'),
    [string]$Model = 'opencode-go/deepseek-v4-flash',   # the model the peer's canary last passed with (docs/test-evidence/auto-canary.md)
    [string]$OpenCodeVersion                            # default: your own `opencode --version`
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
$ssh = "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe"
$msg = Join-Path $Package 'messenger'

# ---- copies of doctor.ps1's Get-FileSha / Get-PackageMap (keep in step; tests prove they agree) ----
function Get-FileSha([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ((Split-Path $Path -Leaf) -eq 'messenger.md') {
        $u = New-Object Text.UTF8Encoding($false)
        $b = $u.GetBytes([regex]::Replace($u.GetString($b), '(?m)^model:[^\r\n]*', 'model: <cheap model you already have>'))
    }
    -join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash($b) | ForEach-Object { $_.ToString('x2') })
}
function Get-PackageMap([string]$Pkg) {
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

foreach ($p in $ssh, $KeyFile, "$KeyFile.pub") { if (-not (Test-Path -LiteralPath $p)) { throw "missing: $p (INSTALL step 13 makes the key)" } }
if (-not $OpenCodeVersion) { $OpenCodeVersion = try { ((& cmd /d /c 'opencode --version' 2>&1) | Select-Object -Last 1).ToString().Trim() } catch { 'unknown' } }

# Version only goes up (the peer's update.ps1 refuses anything else too). The last SIGNED release in -OutDir is
# the reference for both the version and the review diff; the package's own BASELINE.json only as a
# fallback (the package folder may be writable by AI tools; -OutDir should not be).
$prev = 0; $prevJson = $null; $pb = Join-Path $msg 'BASELINE.json'
foreach ($f in @(Get-ChildItem -LiteralPath $OutDir -File -ErrorAction SilentlyContinue)) {
    if ($f.Name -match '^update-(\d+)\.json$' -and [int]$Matches[1] -gt $prev -and (Test-Path -LiteralPath "$($f.FullName).sig")) { $prev = [int]$Matches[1]; $prevJson = $f.FullName }
}
if (-not $prevJson -and (Test-Path -LiteralPath $pb)) { $prevJson = $pb; $prev = [int](Get-Content -LiteralPath $pb -Raw | ConvertFrom-Json).version }
if ($Version -le $prev) { throw "version $Version is not above the last release ($prev)" }
$date = Get-Date -Format 'yyyy-MM-dd'

# Stage group\path copies; the new allowed_signers + CHANGELOG are written into the STAGE only (the package
# is touched after a good signature). Hashes are taken from the staged bytes, i.e. exactly what is zipped.
$stage = Join-Path $env:TEMP ('courier-release-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$entries = @(Get-PackageMap $Package)
if (-not @($entries | Where-Object { $_.group -eq 'root' -and $_.path -eq 'allowed_signers' }).Count) { $entries += [pscustomobject]@{ group = 'root'; path = 'allowed_signers'; src = $null } }
if (-not @($entries | Where-Object { $_.group -eq 'root' -and $_.path -eq 'CHANGELOG.md' }).Count) { $entries += [pscustomobject]@{ group = 'root'; path = 'CHANGELOG.md'; src = $null } }
$entries = @($entries | Sort-Object group, path)
$pub = (Get-Content -LiteralPath "$KeyFile.pub" -Raw).Trim()
$signers = "host namespaces=`"courier-update`" $pub`n"
$cl = Join-Path $msg 'CHANGELOG.md'
$rest = if (Test-Path -LiteralPath $cl) { [regex]::Replace([IO.File]::ReadAllText($cl), '\A# Changelog[^\n]*\n\s*', '') } else { '' }
$changelog = "# Changelog (newest first)`n`n## v$Version - $date`n$($Notes.Trim())`n`n$rest"
$files = @(); $count = @{ root = 0; work = 0 }
foreach ($e in $entries) {
    $count[$e.group]++
    $dst = Join-Path $stage "$($e.group)\$($e.path)"
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    if ($e.group -eq 'root' -and $e.path -eq 'allowed_signers') { [IO.File]::WriteAllText($dst, $signers, $utf8) }
    elseif ($e.group -eq 'root' -and $e.path -eq 'CHANGELOG.md') { [IO.File]::WriteAllText($dst, $changelog, $utf8) }
    else { Copy-Item -LiteralPath $e.src -Destination $dst }
    $files += [ordered]@{ id = ('{0}{1:d2}' -f $e.group.Substring(0, 1), $count[$e.group]); group = $e.group; path = $e.path; sha256 = (Get-FileSha $dst) }
}

# Review list: every file that differs from the last signed release.
$was = @{}; if ($prevJson) { foreach ($e in (Get-Content -LiteralPath $prevJson -Raw | ConvertFrom-Json).files) { $was["$($e.group)\$($e.path)"] = $e.sha256 } }
$now = @{}; foreach ($e in $files) { $now["$($e.group)\$($e.path)"] = $e.sha256 }
Write-Host "Release v$Version vs $(if ($prevJson) { "v$prev (signed)" } else { 'nothing (first release: every file is new)' }). Files that differ:"
foreach ($k in @(@($was.Keys) + @($now.Keys) | Sort-Object -Unique)) {
    if (-not $was.ContainsKey($k)) { Write-Host "  added    $k" } elseif (-not $now.ContainsKey($k)) { Write-Host "  removed  $k (stays on the peer's computer)" } elseif ($was[$k] -ne $now[$k]) { Write-Host "  changed  $k" }
}
Write-Host 'Read the list. Anything you did not change yourself: press Ctrl+C now instead of typing the passphrase.'

New-Item -ItemType Directory -Force $OutDir | Out-Null
$zip = Join-Path $OutDir "update-$Version.zip"; $jp = Join-Path $OutDir "update-$Version.json"
foreach ($p in $zip, $jp, "$jp.sig") { if (Test-Path -LiteralPath $p) { throw "already exists: $p" } }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::NoCompression, $false)
Remove-Item -LiteralPath $stage -Recurse -Force
$zipSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$json = [ordered]@{ format = 'courier-baseline/1'; version = $Version; date = $date; opencode_version = $OpenCodeVersion
    model = $Model; changelog = "v$Version - $date`n$($Notes.Trim())"; zip_sha256 = $zipSha; files = $files } | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($jp, $json, $utf8)

# Sign (asks the key passphrase). Only a good signature updates the package.
& $ssh -Y sign -f $KeyFile -n courier-update $jp
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$jp.sig")) { Remove-Item -LiteralPath $zip, $jp -Force -ErrorAction SilentlyContinue; throw 'signing failed: nothing was released and the package is unchanged' }
[IO.File]::WriteAllText("$msg\allowed_signers", $signers, $utf8)
[IO.File]::WriteAllText($cl, $changelog, $utf8)
[IO.File]::WriteAllText($pb, $json, $utf8)
Write-Host "RELEASE v$Version ready ($($files.Count) files): $zip, $jp, $jp.sig"
Write-Host "Deliver: copy those 3 files into G:\My Drive\from-host\updates\ (INSTALL step 14), then text the peer `"update ready`"."
