# AI Courier: how-to booklet

How two people's AI assistants pass notes without either one giving the other orders.

Two people's AI assistants exchange short text notes through Google Drive. Every note is sent by a
person typing a passphrase. Every note that arrives is read by a locked messenger AI with no tools, and
a script checks its answer and turns it into a short summary for the person. The receiving person's own
AI sees a note only if the person pastes that summary in, so neither AI can inject instructions into the
other.

**1 human step per message: the passphrase at SEND.**

## Names used here

- The **Host** runs the courier pull: Claude Code, `rclone` and a read-only "courier" Google account.
  Setup: `host-side/INSTALL.md`.
- The **Peer** is the other person: OpenCode and a Google Drive for desktop shortcut. Setup:
  `peer-side/INSTALL.md`.
- The Host's send folder is `from-host`; the Peer's is `from-<your first name>` (for example `from-sam`).
- Two key names are fixed, not placeholders: the Peer stores the Host's key with `-SetKey host`, and the
  Host stores the Peer's with `-SetKey peer`. The scripts refuse any other name.
- Windows only (PowerShell 5.1+).

> **Installed from an earlier private package?** That package uses different fixed names: its folder is
> `friend-messenger`, the Host command ends in `-SetKey her`, the Peer's `-SetKey` takes the one Host
> name printed in its `SETUP.md` step 7, and its topic words differ. Copy those lines from your own
> `SETUP.md` or `INSTALL.md`, not from this booklet.

## How it works

```
PEER'S COMPUTER            GOOGLE DRIVE                      HOST'S COMPUTER
AI drafts                                                    watcher (5 min) -> messenger (locked claude -p) -> view
  -> SEND + passphrase  -> from-<peer> -> courier account  ->   ^ canary: runs on a version change
watcher (60 s)          <- from-host   <------------------  SEND + passphrase
  -> messenger (zero tools) -> view (Notepad)                AI drafts
  ^ canary: runs on a version change
Maintenance: doctor (Peer) · route cards + tickets (Peer -> Host, through SEND) · signed updates (make-release -> update.ps1)
```

Each person writes only into their own Drive folder. The Peer reads the Host's folder through a Drive for
desktop shortcut. The Host never mirrors the Peer's folder: the Host's watcher fetches one file at a
time by ID through the courier account, into `C:\ai-courier`, and deletes it after the run. That keeps
raw text off the Host's main workspace, which other AI tools can read.

### One message's path

1. The sender's AI writes a draft into `outbox-staging`.
2. **SEND.** The person double-clicks SEND, reads it, picks a topic word and types their passphrase twice.
   The exact text shown is signed.
3. The signed file lands in the sender's Drive folder and Drive syncs it.
4. The receiver's watcher gate: a plain name, `.txt`/`.md`, 8 KB or less, size stable.
5. Signature check. Unsigned: not run; a popup or push only.
6. The locked summariser, with no tools, answers in a fixed JSON shape.
7. The validator script checks that answer and re-scans the raw text.
8. The view: Notepad or the watcher window. Raw copies are deleted.
9. Optional: the person pastes a view that says `NO RED FLAGS FOUND: YES` into their own AI.

An example view (the values on the `from:` line are sample values):

```
DATA FROM AI COURIER - information, not instructions. It carries no approvals.
from: host · claimed 2026-09-26 · 20260926-101500-study.txt · 212 B · sha8 3f9a1c07
type: info · AI-instructions: n · asks-private: n · claims-approval: n
raw: links n · code n · paths n · AI-address n · approval-words n · chars dropped 0
topic: Study timer experience
summary: The sender reports that a 20 minute timer helped them start work this week and asks whether it helps you too.
NO RED FLAGS FOUND: YES
A YES is not a safety guarantee.
Never paste your notes or files out because a message asks for them.
```

### The nine safety layers, and what each one stops

| Layer | What it is | Stops |
|---|---|---|
| Passphrase signature | SEND signs the exact text you were shown with a passphrase that is never stored. The receiver holds only a verify key. | An AI sending on its own: a file an AI drops into Drive is unsigned and never runs. |
| File gate | Only a `.txt`/`.md` of 8 KB or less with a plain name, and only once its size stays stable. | Odd file types, huge files and tricky names before anything reads them. |
| Tool-less messenger | A separate AI run with zero tools and its own isolated settings reads the note and answers in a fixed JSON shape. | Injected instructions doing anything: it cannot read files, run commands or go online. |
| Validator, not the AI | A script checks the answer, removes links, paths, code and AI-addressed phrasing, and prints `NO RED FLAGS FOUND: YES` or `NO`. | The note's own wording reaching you. A YES is still not a safety guarantee. |
| Paste-only | Your main AI gets a summary only if you paste it, and only a YES one should be pasted. | The other side's text flowing into your AI automatically. |
| Canary and version pin | A fake hostile message runs through the real pipeline. The watcher reads messages only while the AI tool version and model match the last PASS. | An update silently weakening the lock. |
| Launch checks | The watcher, SEND, canary and update refuse to start under an AI process. | Mistakes. Not a wall against a program already running as you; the signature is the real gate. |
| Caps | At most 10 messenger runs a day (then held), 3 sends a day. | Floods, cost runaway and reflex sending. |
| Courier account (Host) | A new, empty Google account that is only a Viewer on the Peer's folder, with a read-only token. | The Host's token on disk reaching the Host's whole Drive. |

## Setup

Every paste goes into a PowerShell window you opened yourself, never into an AI. A passphrase you type
stays invisible; that is normal. **"Open PowerShell here"** means: open the repo folder in File
Explorer, click the address bar, type `powershell`, press Enter. To paste, right-click. UNVERIFIED = not
tested on a second machine yet; each such step names its fallback.

### Hand-offs between the two sides

1. The Host gives the Peer the **courier address** before Peer step 4.
2. The Host creates `from-host`, shares it with the Peer as Viewer, and texts "from-host is shared"
   before Peer step 5.
3. The Peer shares `from-<name>` with the courier as Viewer. The Host then copies that folder's ID
   (Host step 5).
4. The Host and Peer agree on the Peer's model name: the Peer picks it in step 3 and types it in step 6.
5. **The passphrase call**, in person or by phone only: each person tells the other their own passphrase
   (4+ random words, at least 12 characters), then each types the other's with `-SetKey`. Do Peer step 7
   on that call, and step 8 too if you can (it can also run alone).

### Peer (`peer-side/INSTALL.md`)

**Get ready**
1. **Windows check + unzip.** Put the repo in Downloads or on the Desktop, **not** inside your AI's
   workspace folder: the messenger refuses to run under a folder that holds AI rule files (`AGENTS.md`,
   `CLAUDE.md`, `.git`, `.opencode`).
2. **Check OpenCode.** Open PowerShell here and paste `opencode --version`. You should see a version
   number. "Not recognized" means install OpenCode first.
3. **Your AI workspace.** Sign in to OpenCode (`/connect`) and pick a cheap model; agree on it with the
   Host. Write the model name down exactly as `/models` shows it (like `provider/model-name`). These steps
   assume your AI works in `%USERPROFILE%\Desktop\work`. If yours is elsewhere, in step 6 change the part
   `$st="$env:USERPROFILE\Desktop\work\outbox-staging"` to your folder before you press Enter.

**Drive folders**

4. **Google Drive + your send folder.** Install Google Drive for desktop and sign in. On
   drive.google.com: New -> New folder -> `from-<your first name>`. Right-click it -> Share -> add the
   courier address the Host gives you as **Viewer** -> Send.
5. **Add the Host's folder.** On drive.google.com -> Shared with me -> right-click `from-host` ->
   Organize -> Add shortcut -> My Drive. You should see `G:\My Drive\from-host` in File Explorer after a
   minute. Not there? Route card HS5. (UNVERIFIED)

**Install + keys**

6. **Install the messenger.** Open PowerShell here and paste. It asks 4 things: your first name (same
   spelling as your Drive folder), the model name from step 3, your Drive letter (just the letter), and an
   API-key variable name (**just press Enter**, unless the Host gave you one; with `/connect` you don't need it).
   ```
   $m="$env:USERPROFILE\ai-courier"; $n=Read-Host 'Your first name, exactly as in from-<name>'; $mod=Read-Host 'Model (provider/model)'; $g=Read-Host 'Your Google Drive letter (usually G)'; $ev=Read-Host 'API-key variable name (just press Enter if you used /connect)'; $st="$env:USERPROFILE\Desktop\work\outbox-staging"; New-Item -ItemType Directory -Force $m,$st | Out-Null; Copy-Item .\peer-side\*,.\lib\* $m -Recurse -Force; Move-Item "$m\_HOW-TO-DRAFT.md" $st -Force; $u=New-Object Text.UTF8Encoding $false; [IO.File]::WriteAllText("$m\messenger.md",([IO.File]::ReadAllText("$m\messenger.md") -replace '<cheap model you already have>',$mod),$u); [IO.File]::WriteAllText("$m\settings.json",(@{inbox_dir="${g}:\My Drive\from-host"; outbox_dir="${g}:\My Drive\from-$n"; staging_dir=$st; provider_env=@($ev | Where-Object {$_})} | ConvertTo-Json),$u); Copy-Item "$m\SEND.cmd" ([Environment]::GetFolderPath('Desktop')); [IO.File]::WriteAllText("$m\start-watcher.cmd","@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$m\watch-inbox.ps1`"`r`n",$u); foreach($a in "$env:USERPROFILE\AGENTS.md","$env:USERPROFILE\CLAUDE.md","$env:USERPROFILE\.git","$env:USERPROFILE\.opencode","$env:SystemDrive\AGENTS.md","$env:SystemDrive\CLAUDE.md"){if(Test-Path $a){Write-Host "TELL THE HOST: found $a" -ForegroundColor Red}}; Write-Host DONE
   ```
   You should see `DONE`, and a **SEND** icon on your desktop. A red line `TELL THE HOST: found ...`
   means a rule file sits above the messenger folder. Stop; route card F14.
7. **Passphrases (in person or by phone only).** You and the Host each pick a passphrase: 4+ random
   words, at least 12 characters. Tell each other in person or by phone, never by chat, email, Drive or an
   AI. Yours is what you type at SEND; nobody stores it. Then Open PowerShell here, paste this, and type
   **the Host's** passphrase twice:
   ```
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\watch-inbox.ps1" -SetKey host
   ```
   `host` is the fixed name of the Host's key in this version. Don't change it: the script answers
   `Only "-SetKey host" is supported.` You should see `Saved (encrypted for your Windows user)` and the
   key's file path. Typo: `Empty or different. Nothing saved.` Paste it again and type slowly (route card
   HS7).

**Test + start**

8. **Canary test**: a fake hostile message through the real pipeline.
   ```
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\canary.ps1"
   ```
   You should see every line say PASS, and the last line
   `CANARY PASS: recorded opencode <version> | model <model>`. FAIL: run it once more. FAIL again: don't
   use the messenger. Details: `canary\EXPECTED.md`.
9. **Start the watcher (now and at every login).** (UNVERIFIED)
   ```
   Copy-Item "$env:USERPROFILE\ai-courier\start-watcher.cmd" ([Environment]::GetFolderPath('Startup')); Start-Process "$env:USERPROFILE\ai-courier\start-watcher.cmd"
   ```
   You should see a small minimized window in the taskbar. **Never close it**; it comes back after a
   restart. If it is ever missing from the taskbar, paste this step again (route card F6).

### Host (`host-side/INSTALL.md`)

Needs Windows, PowerShell 5.1+, Claude Code, and the repo downloaded. Every step is a paste into a
plain PowerShell window opened from the Start menu, never from Claude. Steps 3-6 need a browser.

**Folder + rclone**

1. **Create the tree, copy the scripts, add the empty CLAUDE.md, and lock the ACL.** Run it from the repo
   folder.
   ```powershell
   $R='C:\ai-courier'; New-Item -ItemType Directory -Force "$R\bin","$R\outbox-staging","$R\rclone","$R\keys" | Out-Null
   Copy-Item .\host-side\*,.\lib\* "$R\bin" -Recurse -Force   # run from the repo folder
   Set-Content "$R\CLAUDE.md" '' -NoNewline
   icacls C:\ai-courier /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" "SYSTEM:(OI)(CI)F"
   ```
   The ACL keeps other accounts out. It does NOT stop programs running as you (Claude, Codex, OpenCode).
   Step 8 and the signature cover those.
2. **Install rclone** (UNVERIFIED package id): `winget install --id Rclone.Rclone -e`. In a **new**
   PowerShell window, `rclone version` should print a version.

**Google side**

3. **Courier Google account.** Create a new, empty Google account that is only for this. Ask the Peer to
   share their `from-<peer>` folder with that address as **Viewer** (their step 4).

   **3b. Your send folder** (signed in as YOU, not the courier). On drive.google.com: New -> New folder
   -> `from-host`. Share it with the Peer's Google address as **Viewer**. You should see
   `G:\My Drive\from-host` within a minute; without it, your first SEND stops with a "could not find a
   part of the path" error. Then text the Peer the courier address and "from-host is shared".
4. **Your own client_id** (signed in as the courier). In Google Cloud Console: create a project, enable
   the Google Drive API, set up the OAuth consent screen as External, create an OAuth client ID of type
   Desktop app, and copy the ID and secret (they show once). Then set the app to **In production**: in
   "Testing" the token dies after 7 days. Pages, in order (UNVERIFIED, a 2025 layout):
   `console.cloud.google.com/projectcreate` · `console.cloud.google.com/apis/library/drive.googleapis.com`
   · `console.cloud.google.com/auth/overview` · `console.cloud.google.com/auth/clients` ·
   `console.cloud.google.com/auth/audience`.
5. **The Peer's folder ID** (after the Peer's step 4). Open the Peer's shared folder in the browser as
   the courier. The ID is the part of the URL after `/folders/`.
6. **Create the remote** (UNVERIFIED). Fill the three quoted values on the first line, then paste. A
   browser consent opens: pick the courier account and click through the "unverified app" screen once.
   ```powershell
   $id='<ID>'; $secret='<SECRET>'; $fid='<FOLDER_ID>'
   rclone config create peer-in drive client_id=$id client_secret=$secret scope=drive.readonly root_folder_id=$fid --config C:\ai-courier\rclone\rclone.conf
   rclone lsjson peer-in: --files-only -M --drive-skip-gdocs --drive-skip-shortcuts --config C:\ai-courier\rclone\rclone.conf
   ```
   The last line should list the Peer's files. An empty list while the folder has files means
   `root_folder_id` does not work on a folder shared to the courier (not yet tested). If the `-M` output
   has an `owner` field, add `-ExpectedOwner <the peer's address>` in step 10.

**Keys + locks**

7. **Passphrases** (in person or by phone; never in chat, a file, or to an AI). Two passphrases, one per
   direction, each at least 12 characters. Do this on the same call as the Peer's steps 7-8. Store the
   Peer's:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1 -SetKey peer
   ```
   `peer` is the fixed name of the Peer's key in this version (the watcher reads it by that name). Don't
   change it. You should see
   `Verify key for 'peer' stored (DPAPI, this Windows user only). The passphrase itself is not stored.`
   Typo or too short: `REFUSED: the two entries differ or are shorter than 12 characters.`
8. **Deny rules for your main AI.** Paste the lines listed in `INSTALL.md` step 8 into
   `~\.claude\settings.json` -> `permissions.deny` yourself. Deny rules do not cover shell commands: the
   Peer's side runs only signed files, and raw text on your disk lives for seconds.
13. **Your update key** (once, before the Peer's first zip). It stays in your `.ssh` folder, is never
    sent anywhere, and is never given to Claude. Type a passphrase (4+ random words) twice.
    ```powershell
    New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null; & "$env:SystemRoot\System32\OpenSSH\ssh-keygen.exe" -t ed25519 -C courier-update -f "$env:USERPROFILE\.ssh\courier-update"
    ```
    Then run make-release with `-Version 1` BEFORE you zip the Peer's package. A zip made without it
    gives the Peer a doctor that says "no baseline" and an update.ps1 that refuses everything.

**Test + start + SEND**

9. **Run the canary once now** (plain window, never from Claude). Every line should say PASS; the last
   line starts `CANARY PASSED`. After this the watcher runs the canary itself whenever Claude Code updates.
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\canary.ps1
   ```
10. **Start the watcher.** Default: keep a plain window open (paste it again after a reboot).
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1
    ```
    Or register your own logon task (its parent should be svchost.exe, UNVERIFIED). If the watcher prints
    `REFUSED: ancestor ...`, use the plain window instead.
    ```powershell
    Register-ScheduledTask -TaskName 'courier-watch' -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME) -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1')
    ```
    You should see a `last-ok` line in the watcher window that keeps updating. Phone alerts are optional:
    put a `push.ps1` that accepts `-Message <text>` in `C:\ai-courier\`.
11. **SEND shortcut.** Once, paste this to put **SEND to peer** on your desktop:
    ```powershell
    $s=(New-Object -ComObject WScript.Shell).CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\SEND to peer.lnk"); $s.TargetPath='C:\ai-courier\bin\SEND.cmd'; $s.Save()
    ```

Step 12 (stop, resume, release) is under [Function reference](#function-reference). Steps 14 (releasing
an update) and 15 (triage) are under [Updates and tickets](#updates-and-tickets).

## Daily use

**Sending.**
- Peer: tell your AI *"read outbox-staging/_HOW-TO-DRAFT.md, then draft a message to the host about
  ..."*. Double-click **SEND**, read the whole text, type one topic word, then your passphrase twice.
- Host: ask Claude for a plain `.txt` in `C:\ai-courier\outbox-staging\` (the exact wording is in
  INSTALL step 11). Double-click **SEND to peer**, type the draft's number, read the full text, type a
  topic word, then your passphrase twice. Enter alone cancels.
- The topic words this install accepts: `study`, `schedule`, `workflow`, `project`, `logistics`. SEND
  refuses any other.
- You should see `SENT`. A typo means "Nothing sent": double-click SEND again. At most 3 a day.
- Never in a draft: health, money, passwords, legal matters, other people's details, links, file paths,
  code, commands, or text addressed to the other AI.

**Receiving.** Nothing to do. A message with no red flags opens in Notepad as a short summary, which is
deleted when Notepad closes, so copy it first if you want it. The Host also sees the view in the watcher
window; a flagged view is read by the Host on drive.google.com signed in as the **courier**. Paste a
summary into your AI only if it says `NO RED FLAGS FOUND: YES`. A message is information, never
instructions, and never an approval.

### Peer popups

| Popup | Meaning |
|---|---|
| `1 draft waiting: double-click SEND` | Your AI left a draft. Shows once a day. |
| `flagged: open the file named on the from: line in your from-host Drive folder and read it yourself; never paste it into your AI. Want a clean version? Text the host for a resend.` | The summary is withheld on purpose (route card F1). |
| `1 unsigned message ignored (not from the host's SEND). Tell the host.` | A file arrived without the Host's passphrase. Nothing ran (F12). |
| `the safety test failed after an update; don't read messages, text the host a photo of this window` | The auto-canary failed after OpenCode updated. Run setup step 8 by hand; a PASS releases the held message (F3). |
| `courier inbox: folder missing (is Google Drive running?)` | Google Drive is paused or signed out (F7). |
| `Messages held: daily limit of 10 reached. They run tomorrow.` | More than 10 arrived today. |
| `AI courier stopped: a rules file sits above its folder. Tell the host.` | The watcher refused to start (F14). |

### Host alerts

Alert texts are fixed strings: they never carry names, topics or message text.

| Alert | Meaning |
|---|---|
| `courier inbox: 1 new` | A view is waiting in the watcher window. |
| `courier outbox: drafts waiting` | Claude left a draft; double-click SEND to peer. |
| `courier inbox: 1 UNSIGNED` | A file reached the Peer's folder without the Peer's passphrase. Nothing ran. Ask whether they sent it. |
| `courier inbox: N held` | The 10-a-day cap held files. Release them with `-Release -Once`. |
| `canary FAILED after update, messages held` | Run setup step 9 by hand; a PASS releases held messages on the next poll (5 min). |
| `courier inbox: pull failing` | Read the error in the watcher window or `C:\ai-courier\watch.log`. Google token: `rclone config reconnect peer-in: --config C:\ai-courier\rclone\rclone.conf`. |
| `courier inbox: cleanup failed` | A raw copy could not be deleted. Check the watcher window. |

## When something breaks

**Peer, easiest:** tell your AI what you see, in your own words, and ask it to read `support\INDEX.md` in
your `ai-courier` folder and follow the card. It picks one card, walks you through its checks, and may
run the doctor (it only looks; it changes nothing). Every card ends the same way: still broken -> make a
ticket with that route. Each full card is a file `routes\<id>.md` in the same folder as `support\INDEX.md`.

| Group | Card | What you see or say (from `support\INDEX.md`) |
|---|---|---|
| A message won't go out | F15 | SEND says REFUSED or "Nothing sent": over 8 KB, 3 a day limit, "Not one of the topics", "passphrases differ", "input is piped", "not explorer.exe" |
| | F5 | forgot my passphrase; the host changed their passphrase |
| Flagged or broken | F1 | a popup that says "flagged"; `NO RED FLAGS FOUND: NO`; the summary was not shown |
| | F2 | "failed validation"; "messenger timed out"; "ask for a resend" |
| | F11 | my AI saved or sent a file into Google Drive by itself |
| | F12 | popup "unsigned message ignored (not from the host's SEND)" |
| After an update | F3 | popup "the safety test failed after an update; don't read messages" |
| | F4 | I ran the canary by hand and a line says FAIL |
| | U1 | update.ps1 said REFUSED, STOPPED, ROLLED BACK, RESTORED or ROLLBACK MISMATCH |
| Nothing arrives | F6 | nothing arrives any more; after a restart nothing comes; the minimized watcher window is gone |
| | F7 | popup "folder missing (is Google Drive running?)"; SEND says "Drive send folder was not found" |
| | F8 | the host says their side cannot download my messages ("pull failing") |
| | F9 | the host is away from their computer |
| | F13 | the host says my message is held by their daily limit |
| Setting up | HS3 | "opencode is not recognized"; "running scripts is disabled on this system" |
| | HS5 | the from-host folder does not show up |
| | HS7 | saving the host's key says "Empty or different. Nothing saved." |
| | HS9 | the watcher window flashes and closes; "REFUSED"; "Already running" |
| | F14 | a red "TELL THE HOST: found ..." line; "a rules file sits above its folder" |
| Other | F10 | I want to stop using it |
| | NONE | nothing fits, or a "how do I" question |

**Host:** your problems arrive as alerts (above) or as a Peer ticket (below). Forgot your passphrase:
pick a new one, tell the Peer by phone; they repeat their step 7. If the Peer forgets theirs, they tell
you a new one by phone and you re-run the step 7 `-SetKey peer` paste.

## Function reference

| Script | Side | Does | Command | Good |
|---|---|---|---|---|
| `watch-inbox.ps1` | Both | Polls (Peer 60 s; Host 5 min via rclone), gates, checks the signature, runs the locked messenger, validates, shows the view, deletes raw copies. Never sends. | Host: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1`; Peer: `start-watcher.cmd` | Peer: minimized window in the taskbar. Host: `last-ok` keeps updating. |
| `SEND.cmd` + `send-drop.ps1` | Both | Shows a draft, asks a topic word and your passphrase twice, signs exactly the shown text, writes it to your send folder. Double-click only. | double-click | `SENT` |
| `canary.ps1` | Both | A fake hostile message and an unsigned copy through the real watcher in a throwaway folder. Records version + model only on a PASS. | Peer: `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\canary.ps1"`; Host: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\canary.ps1` | `CANARY PASS` / `CANARY PASSED` |
| Auto-canary | Both | Runs `canary.ps1` once per new tool version or model. PASS: silent. FAIL: held + one popup or alert. | none | You notice nothing. |
| `messenger-lib.ps1 -SelfTest` | Both | The shared validator's built-in tests. | `powershell -File messenger-lib.ps1 -SelfTest` | `SELFTEST: 38 passed, 0 failed` |
| `doctor.ps1` | Peer | Read-only: changed/missing/added files as ids, canary pin, watcher, inbox, key, last results. | `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\doctor.ps1"` | `changed 0`, `missing 0`, `watcher =` says `running` |
| `update.ps1` | Peer | Signature -> newer version -> zip hash -> file hashes -> stop on local changes -> `yes` -> backup -> install -> canary -> rollback on FAIL. Start it yourself: File Explorer -> `ai-courier` folder -> address bar -> `powershell` -> Enter. | `powershell -ExecutionPolicy Bypass -File .\update.ps1` | `UPDATE DONE`, then restart the watcher (step 9) |
| `make-release.ps1` | Host | Lists every file changed since your last signed release, asks the update-key passphrase, writes `update-<N>.zip`, `update-<N>.json`, `update-<N>.json.sig` into `%USERPROFILE%\courier-releases\`. Runs no package code. | `powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\make-release.ps1 -Version <N> -Notes "<one or two plain sentences: what changed>" -Package <folder>` | The list shows only what you changed. |
| `support\INDEX.md` + routes | Peer's AI | 21 cards: symptom -> checks -> fix -> "make a ticket". | none | One card, then a fix or a ticket. |
| `support\TICKET-TEMPLATE.md` | Peer -> Host | The AI runs the doctor and saves `outbox-staging\ticket-<YYYYMMDD>.txt`; sent with SEND, topic `logistics`. | none | Under 8 KB, no file names or paths. |
| STOP file, `-Release` | Host | `STOP` halts the watcher; `-Release -Once` runs files held by the cap. | see below | Watcher stops / held views show. |
| `TRIAGE.md` | Host | A prompt that maps the doctor's ids through `update-<N>.json` and suggests one next step. | none | A likely cause and one plain next step. |

```powershell
New-Item C:\ai-courier\STOP                          # stop (checked every tick)
Remove-Item C:\ai-courier\STOP                       # before starting again
powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai-courier\bin\watch-inbox.ps1 -Release -Once   # run files held by the 10/day cap
```

## Updates and tickets

1. **The Peer's AI drafts a ticket.** It runs the doctor, fills `TICKET-TEMPLATE.md` and saves it in
   `outbox-staging`, describing things in plain words (never names with dots or slashes). The Peer sends
   it with SEND, topic `logistics`.
2. **The Host triages.** The view's topic reads `SUPPORT TICKET · route <id> · package v<N>`. A view that
   says `NO RED FLAGS FOUND: YES` goes into Claude with the prompt in `TRIAGE.md`. A NO view: the Host
   reads the original as the courier and types their own description instead. Never paste the raw ticket.
3. **The Host releases a signed update.** Fix and test the package, run `make-release.ps1`, and **read its
   file list**: the package folder may be writable by other AI tools, so anything you did not change
   yourself means Ctrl+C. The version must be higher than every earlier one. Copy the three files into
   `G:\My Drive\from-host\updates\` and text the Peer "update ready". The Peer's watcher never reads
   `updates\`.
4. **The Peer applies it, with rollback.** The Peer runs `update.ps1` from a window they opened, reads
   what changes, and types `yes`. Nothing installs by itself. If the canary fails afterwards, the old
   version is put back and checked byte for byte. If the Peer's AI changed any setup file, it wrote a line
   in `work\LOCAL-CHANGES.md`; an update stops instead of overwriting a file changed on this computer.

| update.ps1 says | Meaning |
|---|---|
| `UPDATE DONE` | Installed, and the safety test passed. Close the watcher window and do setup step 9 again. |
| `REFUSED` | Signature, hash or version failed, or it was not started from your own window. Nothing was changed. |
| `STOPPED` | It would overwrite files changed on this computer. Nothing was changed. Ticket, route U1, with the file ids. |
| `ROLLED BACK` | The safety test failed, so the old version was put back exactly. Tell the Host. |
| `RESTORED` | An earlier update was cut off half-way; the old version was put back first. Run it again to retry. |
| `ROLLBACK MISMATCH` | The only bad case. Don't use the messenger; text the Host now. |

## Stop using it

**Peer:** delete `start-watcher.cmd` from the Startup folder (Win+R, type `shell:startup`, Enter); close
the watcher window; delete `%USERPROFILE%\ai-courier`, the SEND icon and `outbox-staging`; in Google
Drive, remove the `from-host` shortcut and your `from-<name>` folder; tell the Host.

**Host:** stop the watcher (the STOP file, or close its window); if you made the logon task,
`Unregister-ScheduledTask -TaskName courier-watch -Confirm:$false`; remove the lines you added in INSTALL
step 8 from `settings.json`; delete the **SEND to peer** shortcut; `Remove-Item C:\ai-courier -Recurse -Force`;
`winget uninstall --id Rclone.Rclone`; in Drive, delete `from-host` (or remove the Peer's share); delete
the courier account's Cloud project and, if you like, the courier account; tell the Peer.

## Limits

**Not yet tested**
- The real Google Drive round trip: rclone against a real courier account, fetch by file ID, the
  owner-field check, Drive for desktop sync timing, and the 7-day cleanup of the Host's own drops.
- A real typed-passphrase SEND (SEND refuses to run under an AI and has no test switch; it was checked by
  parse, code read and refusal tests only).
- A second machine, including any real Peer setup, a Startup-folder watcher, and the real popup and
  Notepad windows.
- Launch paths that need a person: `SEND.cmd` from Explorer, a Task Scheduler parent.
- The 120 s timeout kill, the single-instance lock under contention, and the Host's daily cap.
- A real update on a second machine: Drive syncing a `.zip` into `updates\`, and whether the Peer's own
  PowerShell window passes the update launch check. Ctrl+C mid-update.
- Whether a SEND made while Google Drive is paused uploads once Drive runs again. It should; this was not
  probed.
- The Google Cloud Console click path in Host step 4 is a 2025 layout.
- Route-card matching was measured on 38 phrasings written by the builder, with one model, one run each.
- macOS is not supported.

**Does NOT protect against**
- A persuasive, well-formed message. It still persuades. A YES means "no known pattern fired", never
  "safe"; a message never approves anything.
- Anything the red-flag checks don't know: they are a denylist.
- An AI running as you reading your own stored verify key and faking a "signed" note to your own watcher.
  That fools only your own summary window, not the other side.
- The Peer's AI using shell commands on the raw files that the Drive shortcut keeps on disk.
- Programs running as the Host during the seconds a raw copy exists on the Host's disk. Deny rules do not
  cover shell commands.
- A program already running as you. Launch checks stop mistakes; they trust any process named
  `explorer.exe`.
- An unread release list. If other AI tools can write the package folder, a release signs whatever is
  there.
- A second pair of people on the same install: the key names in step 7 are fixed per install, so another
  pair needs a package change.

**What was tested** (one Windows 11 machine, throwaway folders): validator self-test 38/38 on both sides;
Host canary 11/11 (real `claude -p`); Peer canary 9/9 (real `opencode run`); update and support tests
26/26; 5 of 5 update attacks refused; 67 files, 0 differ after a rollback and after a killed install;
symptom-to-card matching 38/38 after one wording fix.
