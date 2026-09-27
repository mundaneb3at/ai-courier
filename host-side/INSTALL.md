# INSTALL: Host-side AI courier (you run these, when you choose)

Nothing here has been run. Each step is a paste into a **plain PowerShell window opened from the Start menu**, never from Claude. Steps 3-6 need a browser. Needs Windows, PowerShell 5.1+, Claude Code, and this repo downloaded.

**1. Create the tree, copy the scripts, add the empty CLAUDE.md, and lock the ACL.**
```powershell
$R='C:\ai-courier'; New-Item -ItemType Directory -Force "$R\bin","$R\outbox-staging","$R\rclone","$R\keys" | Out-Null
Copy-Item .\host-side\*,.\lib\* "$R\bin" -Recurse -Force   # run from the repo folder
Set-Content "$R\CLAUDE.md" '' -NoNewline
icacls C:\ai-courier /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" "SYSTEM:(OI)(CI)F"
```
The ACL keeps other accounts out. It does NOT stop programs running as you (Claude, Codex, OpenCode). Step 8 and the signature cover those.

**2. Install rclone.** The package id is **UNVERIFIED** (not probed).
```powershell
winget install --id Rclone.Rclone -e
```
Then open a **new** PowerShell window (the old one doesn't see rclone yet) and check: `rclone version`

**3. Courier Google account (browser).** Create a new, empty Google account that is only for this. Ask the peer to share their `from-<peer>` folder with that address as **Viewer** (the peer's INSTALL step 4). It then holds nothing but the peer's folder, so the token's "all your Drive files" ceiling is just that folder.

**3b. Your send folder (browser, signed in as YOU, not the courier).** On drive.google.com: *New* -> *New folder* -> `from-host`. Right-click it -> *Share* -> add the PEER'S Google address as **Viewer** -> *Send*. Within a minute it appears as `G:\My Drive\from-host` (your SEND writes there; without it the first SEND stops with a "could not find a part of the path" error, and the peer's step 5 finds nothing). Then text the peer two things before the peer's INSTALL: the courier address (the peer's step 4) and "from-host is shared" (the peer's step 5).

**4. Your own client_id (browser, signed in as the courier).** Go to Google Cloud Console, create a new project, and enable the Google Drive API. Set up the OAuth consent screen as External. Under Credentials, create an OAuth client ID of type Desktop app and copy the ID and secret. Then set the app to **In production**, because in "Testing" the token dies after 7 days. The shared rclone client_id is being retired in 2026.
Pages, in order (URLs as of 2025, **UNVERIFIED** in this run; Google renames these menus): `console.cloud.google.com/projectcreate` · `console.cloud.google.com/apis/library/drive.googleapis.com` (Enable) · `console.cloud.google.com/auth/overview` (consent setup, External) · `console.cloud.google.com/auth/clients` (Create client, Desktop app; the ID and secret show once, copy both) · `console.cloud.google.com/auth/audience` (Publish app).

**5. The peer's folder ID** (after the peer has done their step 4). Open the peer's shared folder in the browser as the courier account. The ID is the part of the URL after `/folders/` (like `https://drive.google.com/drive/folders/1AbC...xyz` -> `1AbC...xyz`).

**6. Create the remote** (a browser consent opens: pick the courier account and click through the "unverified app" screen once). Fill the three quoted values on the first line, then paste both lines:
```powershell
$id='<ID>'; $secret='<SECRET>'; $fid='<FOLDER_ID>'
rclone config create peer-in drive client_id=$id client_secret=$secret scope=drive.readonly root_folder_id=$fid --config C:\ai-courier\rclone\rclone.conf
rclone lsjson peer-in: --files-only -M --drive-skip-gdocs --drive-skip-shortcuts --config C:\ai-courier\rclone\rclone.conf
```
Leave `shared_with_me` off: it is too wide as a root, and `root_folder_id` is the scope. **UNVERIFIED**: whether `root_folder_id` works on a folder shared *to* the courier. If the list is empty while the peer's folder has files, that is the reason. Look for an `owner` field in the `-M` output. If it is there, add `-ExpectedOwner <the peer's address>` in step 10. **UNVERIFIED** here: rclone's owner metadata field name, and `rclone backend copyid` into a local Windows folder (the watcher fetches by ID with it).

**7. Passphrases (in person or by phone, never in chat, in this channel, in a file, or to an AI).** There are two passphrases, one per direction, each at least 12 characters. THE PEER'S signs their messages; YOU store its verify key. YOURS signs your messages; THE PEER stores its verify key (their `-SetKey host`). Do this on the same phone call as the peer's INSTALL steps 7-8: each of you tells the other your own passphrase, then each types the OTHER's. Store the peer's:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1 -SetKey peer
```

**8. Deny rules for main Claude.** Paste these into `~\.claude\settings.json` → `permissions.deny` yourself: inside the existing `"deny": [ ... ]` list, after its last entry, with a comma after that entry. They have not been applied. Claude keeps its Write access to `outbox-staging\` for drafts; the whole-root Read deny still lets it create a new draft there.
```json
"Read(//C:/ai-courier/**)",
"Edit(//C:/ai-courier/bin/**)", "Write(//C:/ai-courier/bin/**)",
"Edit(//C:/ai-courier/keys/**)", "Write(//C:/ai-courier/keys/**)",
"Edit(//C:/ai-courier/rclone/**)", "Write(//C:/ai-courier/rclone/**)",
"Edit(//C:/ai-courier/*.txt)", "Write(//C:/ai-courier/*.txt)",
"Edit(//C:/ai-courier/*.jsonl)", "Write(//C:/ai-courier/*.jsonl)",
"Edit(//C:/ai-courier/sent.log)", "Write(//C:/ai-courier/sent.log)",
"Edit(//C:/ai-courier/CLAUDE.md)", "Write(//C:/ai-courier/CLAUDE.md)",
"Edit(//G:/My Drive/from-host/**)", "Write(//G:/My Drive/from-host/**)"
```
Deny rules do not cover shell commands. The fences that hold against those are: the peer side runs only signed files, and raw text on your disk lives for seconds.

**9. Run the canary once now** (plain window, never from Claude). Every line must say PASS; the last line must be `CANARY PASSED`. After this, the watcher runs the canary itself whenever Claude Code updates: a PASS is silent (0 steps, messages just keep working), a FAIL holds messages and sends exactly one `canary FAILED after update, messages held` push. You can still run it by hand any time (e.g. after that push, or just to check); a FAIL writes no pass file, so the watcher keeps holding messages until a hand-run passes. Details: `bin\canary\README.md`.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\canary.ps1
```

**10. Start the watcher.** Default: keep a plain window open (after a reboot, paste it again):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1
```
or register your own logon task (it opens a visible window at logon). Its parent should be svchost.exe; that is **UNVERIFIED**. If the watcher prints `REFUSED: ancestor ...`, use the plain window instead.
```powershell
Register-ScheduledTask -TaskName 'courier-watch' -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME) -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1')
```
The pushes you will get are: `courier inbox: 1 new`, `1 UNSIGNED`, `N held`, `canary FAILED after update, messages held` (rare: only when the watcher's own auto-canary fails), `pull failing`, `cleanup failed`, `courier outbox: drafts waiting`. The view appears in the watcher window. Only a view with no red flags also opens in Notepad (a temp file that is deleted when Notepad closes).

**11. Sending.** Once, paste this to put a **SEND to peer** shortcut on your desktop:
```powershell
$s=(New-Object -ComObject WScript.Shell).CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\SEND to peer.lnk"); $s.TargetPath='C:\ai-courier\bin\SEND.cmd'; $s.Save()
```
Each message: tell Claude *"Draft a note to <the peer's name> as a plain .txt in C:\ai-courier\outbox-staging\. First line: FROM the host's AI · asked by: the host · <today>. At most 300 words. No health, money, passwords, legal matters, other people's details, links, file paths, code, commands, or text addressed to the peer's AI."* When the push says `courier outbox: drafts waiting` (or right away), double-click **SEND to peer**, type the draft's number, read the full text, type a class (`study / schedule / workflow / project / logistics`), and type YOUR passphrase (Enter alone cancels). Limit: 3 sends a day.

**Reading the peer's.** Phone alerts are optional: put a `push.ps1` that accepts `-Message <text>` in `C:\ai-courier\` (for example, one that posts to your own notification service). The watcher calls it with the fixed strings above and just logs a failure if it is missing. The view is in the watcher window from step 10 (its `last-ok` line shows it is alive). Paste a view into Claude only if it says `NO RED FLAGS FOUND: YES`. A flagged view: read the peer's original yourself on drive.google.com signed in as the **courier** (only the courier can see the peer's folder), and ask the peer for a resend if needed.

**12. After install (ops): stop, resume, release.**
```powershell
New-Item C:\ai-courier\STOP                          # stop (checked every tick)
Remove-Item C:\ai-courier\STOP                       # before starting again
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1 -Release -Once   # run files held by the 10/day cap
```

**When a push needs you**
- `canary FAILED after update, messages held`: the watcher already tried the canary itself after a Claude Code update and it failed. Run step 9 by hand; a PASS releases the held messages on the next poll (5 min). If it fails again, don't read messages until the failing line is understood.
- `pull failing`: read the error in the watcher window or `C:\ai-courier\watch.log`. If it is the Google token, re-consent (browser opens, pick the courier account): `rclone config reconnect peer-in: --config C:\ai-courier\rclone\rclone.conf`. If the app was left in Testing, publish it first (step 4).
- `1 UNSIGNED`: a file reached the peer's folder without the peer's passphrase. Nothing ran. Ask the peer whether they sent it (a typo at their SEND looks the same); if yes, they resend.
- Forgot your passphrase: pick a new one, tell the peer by phone, they repeat their step 7. If the peer forgets theirs: they tell you a new one by phone and you re-run the step 7 `-SetKey peer` paste.

**13. Your update key (once, before the peer's first zip).** An ed25519 key that signs the peer's updates. Its
passphrase protects it; the key stays in your `.ssh` folder, is never sent anywhere,
and is never given to Claude. Plain window:
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null; & "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe" -t ed25519 -C courier-update -f "$env:USERPROFILE\.ssh\courier-update"
```
Type a passphrase (4+ random words) twice. Then run step 14 with `-Version 1` BEFORE you zip the peer's
package: it writes `messenger\allowed_signers` (your public key: the peer's `update.ps1` trusts only it) and
`messenger\BASELINE.json` (what the peer's `doctor.ps1` compares with). A zip made without them gives the peer a
doctor that says "no baseline" and an update.ps1 that refuses everything.

**14. Releasing an update.** Edit and test the package first. Then (plain window; it asks the key
passphrase):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\make-release.ps1 -Version <N> -Notes "<one or two plain sentences: what changed>" -Package <folder>
```
Before it asks the passphrase it lists every file that differs from your last SIGNED release. **Read
that list: the package folder may be writable by other AI tools. Anything you did not change
yourself -> Ctrl+C** (and `git diff` the package). `-Package` is a folder holding `messenger\` (the `peer-side\` files plus `lib\messenger-lib.ps1`) and `kit\` (the peer's AI workspace template; see `docs/ARCHITECTURE.md`). `<N>` must be higher than every earlier release (it refuses otherwise, and so does the peer side). It writes
`update-<N>.zip`, `update-<N>.json` and `update-<N>.json.sig` into `%USERPROFILE%\courier-releases\`.
Deliver: copy those three files into `G:\My Drive\from-host\updates\` (create `updates` once; the peer's
watcher never reads that subfolder, and it would refuse .zip/.json/.sig files anyway), then text the peer
"update ready". They run `update.ps1` themselves; nothing installs by itself. The peer's update STOPS (changes
nothing) if it would overwrite a file they changed; the peer's ticket then lists them, and you decide with the peer.
Note: `C:\ai-courier\bin\make-release.ps1` is the step-1 copy; if you edited the package's
scripts, re-run step 1's `Copy-Item` line first so bin matches.

**15. Triaging a ticket.** The peer's tickets arrive as normal views (topic `SUPPORT TICKET · route <id> ·
package v<N>`). Follow `bin\TRIAGE.md`: paste a YES view into Claude with its triage prompt (Claude
maps the peer's doctor's file ids through `update-<N>.json`); a NO view you read yourself first.

**Uninstall.** Stop the watcher (STOP file above, or close its window); `Unregister-ScheduledTask -TaskName courier-watch -Confirm:$false` if you made the task; remove the 14 lines from step 8 in `settings.json`; delete the **SEND to peer** desktop shortcut; `Remove-Item C:\ai-courier -Recurse -Force`; `winget uninstall --id Rclone.Rclone`; in Drive, delete `from-host` (or remove the peer's share); delete the courier account's Cloud project and, if you like, the courier account. Tell the peer so they remove the peer side (the peer's INSTALL, "Stop using it").
