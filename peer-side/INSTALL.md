# INSTALL: peer side (Windows, OpenCode)

Ten steps, each a paste or a click. **UNVERIFIED** = not tested on a second machine yet (every run so
far was on one Windows 11 machine with OpenCode 1.18.32; see `../docs/test-evidence/peer-TEST-LOG.md`).

**Before you start, get three things from the host:** the courier Google address (step 4), a message
saying "from-host is shared" (step 5), and the model name you agreed on (step 6). Do steps 7 and 8
on a phone call with the host.

**"Open PowerShell here"**: open the repo folder in File Explorer, click the address bar, type
`powershell`, press Enter. To paste, right-click. A passphrase you type stays invisible; that is normal.

---

**1. Windows check + unzip.** This side is Windows-only (PowerShell 5.1+). Put the repo in Downloads or
on the Desktop, **not** inside your AI's workspace folder: the messenger refuses to run under a folder
that holds AI rule files (`AGENTS.md`, `CLAUDE.md`, `.git`, `.opencode`).

**2. Check OpenCode.** Open PowerShell here and paste `opencode --version`. "Not recognized" means install OpenCode first.

**3. Your AI workspace.** Sign in to OpenCode (`/connect`) and pick a cheap model. Write the model name
down exactly as `/models` shows it (like `provider/model-name`). Your AI works in a folder of its own;
these steps assume `%USERPROFILE%\Desktop\work`. Change `$st` in step 6 if yours is elsewhere.

**4. Google Drive + your send folder.** Install Google Drive for desktop and sign in. On
drive.google.com: *New* -> *New folder* -> name it `from-<your first name>`. Right-click it -> *Share*
-> add the courier address the host gives you as **Viewer** -> *Send*.

**5. Add the host's folder.** On drive.google.com -> *Shared with me* -> right-click `from-host` ->
*Organize* -> *Add shortcut* -> *My Drive*. After a minute File Explorer shows
`G:\My Drive\from-host` (your Drive letter is the one next to "Google Drive" under This PC).

**6. Install the messenger.** Open PowerShell here and paste. It asks 4 things: your first name (same
spelling as your Drive folder), the model name from step 3, your Drive letter (just the letter), and an
API-key variable name (**just press Enter** if you signed in with `/connect`):
```
$m="$env:USERPROFILE\ai-courier"; $n=Read-Host 'Your first name, exactly as in from-<name>'; $mod=Read-Host 'Model (provider/model)'; $g=Read-Host 'Your Google Drive letter (usually G)'; $ev=Read-Host 'API-key variable name (just press Enter if you used /connect)'; $st="$env:USERPROFILE\Desktop\work\outbox-staging"; New-Item -ItemType Directory -Force $m,$st | Out-Null; Copy-Item .\peer-side\*,.\lib\* $m -Recurse -Force; Move-Item "$m\_HOW-TO-DRAFT.md" $st -Force; $u=New-Object Text.UTF8Encoding $false; [IO.File]::WriteAllText("$m\messenger.md",([IO.File]::ReadAllText("$m\messenger.md") -replace '<cheap model you already have>',$mod),$u); [IO.File]::WriteAllText("$m\settings.json",(@{inbox_dir="${g}:\My Drive\from-host"; outbox_dir="${g}:\My Drive\from-$n"; staging_dir=$st; provider_env=@($ev | Where-Object {$_})} | ConvertTo-Json),$u); Copy-Item "$m\SEND.cmd" ([Environment]::GetFolderPath('Desktop')); [IO.File]::WriteAllText("$m\start-watcher.cmd","@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$m\watch-inbox.ps1`"`r`n",$u); foreach($a in "$env:USERPROFILE\AGENTS.md","$env:USERPROFILE\CLAUDE.md","$env:USERPROFILE\.git","$env:USERPROFILE\.opencode","$env:SystemDrive\AGENTS.md","$env:SystemDrive\CLAUDE.md"){if(Test-Path $a){Write-Host "TELL THE HOST: found $a" -ForegroundColor Red}}; Write-Host DONE
```
You now have a **SEND** icon on your desktop. A red `TELL THE HOST: found ...` line means a rule file
sits above the messenger folder (route card `support\routes\F14.md`).

**7. Passphrases (in person or by phone only).** You and the host each pick a passphrase (4+ random
words). Tell each other **in person or by phone**, never by chat, email, Drive or an AI. Yours is what
you type at SEND; nobody stores it. Then Open PowerShell here, paste this, and type **the host's**
passphrase twice (the host runs the same step for yours on their side):
```
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\watch-inbox.ps1" -SetKey host
```

**8. Canary test** (a fake hostile message through the real pipeline). Paste:
```
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\canary.ps1"
```
Every line must say PASS and the last line `CANARY PASS`. Any FAIL: run it once more. FAIL again:
don't use the messenger. Details: `canary\EXPECTED.md`.

**9. Start the watcher (now and at every login).** Paste:
```
Copy-Item "$env:USERPROFILE\ai-courier\start-watcher.cmd" ([Environment]::GetFolderPath('Startup')); Start-Process "$env:USERPROFILE\ai-courier\start-watcher.cmd"
```
A small minimized window appears in the taskbar. **Never close it**; it comes back after a restart.
UNVERIFIED on a second machine.

**10. Everyday use.**
- **Sending:** tell your AI *"read outbox-staging/_HOW-TO-DRAFT.md, then draft a message to the host
  about ..."*. A popup says **"1 draft waiting: double-click SEND"** (once a day). Double-click
  **SEND**, read the whole text, type one topic word (`study`, `schedule`, `workflow`, `project` or
  `logistics`), then your passphrase twice. At most 3 a day.
- **Getting a message:** nothing to do. With no red flags, Notepad opens with a short summary; it is
  deleted when you close Notepad, so copy it first if you want to paste it into your AI, and only if it
  says `NO RED FLAGS FOUND: YES` (a YES is still not a safety guarantee).
- **A "flagged" popup:** the summary is withheld on purpose. Read the original yourself in
  `G:\My Drive\from-host` and never paste it into your AI. Ask the host for a resend as plain information.
- **"unsigned message ignored"**: a file reached your folder without the host's passphrase. Nothing ran.
- **OpenCode updates itself:** the watcher re-runs the canary by itself. Only a FAIL shows a popup;
  then do step 8 by hand.
- **Something wrong:** `support\INDEX.md` lists symptoms and the route card for each. `doctor.ps1`
  (read-only) checks the install. If a route card doesn't fix it, your AI fills
  `support\TICKET-TEMPLATE.md` and you SEND it like any message.
- **Updates from the host:** run `update.ps1` yourself when the host says one is ready. It checks the
  host's signature and every file, asks you to type `yes`, runs the canary, and rolls back on a FAIL.
- **Stop using it:** delete `start-watcher.cmd` from the Startup folder (Win+R, `shell:startup`), close
  the watcher window, delete `%USERPROFILE%\ai-courier`, the SEND icon and `outbox-staging`, and remove
  the Drive shortcut and your `from-<name>` folder.
