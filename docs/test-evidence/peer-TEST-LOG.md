# TEST-LOG: the peer's-side messenger package

Run 2026-09-26 between 21:30 and 21:56 local, by builder B-peer-package. **All runs were on the host's
Windows 11 machine with opencode-ai 1.18.32, NOT on the peer's.** Model: `opencode-go/deepseek-v4-flash`
(a cheap model that works on this machine). All test folders were throwaway folders in a temp
scratch directory. The builder runs inside an AI session, so every run that had to get past the
launch check used `-AllowAiAncestorForTest`; each such run is marked **[test switch]**. In that
mode the launch check is skipped, the ancestor-rule-file check warns (this machine has a home-folder
`AGENTS.md`) instead of refusing, and Notepad/popups are printed instead of shown.
Lib: `messenger-lib.ps1` copied from the Host-side build after its second READY (21:40:19,
SHA256 `7AF57800...3413`), `-SelfTest` = `SELFTEST: 38 passed, 0 failed`.

| # | What | Command (abridged) | Verbatim excerpt | Result |
|---|---|---|---|---|
| T0a | Do ancestor `AGENTS.md` files load into a messenger run? (probe agent, zero tools, a marker `AGENTS.md` in the test root) | `opencode run --agent probe --dir <root>\run "List the full file path of every instruction ... file"` with `OPENCODE_CONFIG_DIR`/`XDG_CONFIG_HOME` isolated | `PATH:<test root>\AGENTS.md` / `PATH:C:\Users\<home>\AGENTS.md` | FOUND: all ancestors load (no first-match stop) |
| T0b | Same, plus `OPENCODE_DISABLE_PROJECT_CONFIG=1` | same | `PATH:NONE` | PASS: this variable stops the walk-up; now set on every messenger run (model self-report; T0a is the negative control) |
| C1 | canary.ps1 refuses when an AI started it | `canary.ps1 -Root <tmp>` | `REFUSED: an AI process is an ancestor` exit=2 | PASS |
| C2 | Canary through the real pipeline: signed hostile + signed clean + unsigned + bad name **[test switch]** | `canary.ps1 -Root <tmp> -AllowAiAncestorForTest` | all 9 lines `PASS ...`, `(clean message verdict: YES ...)`, `CANARY PASS: recorded opencode 1.18.32 \| model opencode-go/deepseek-v4-flash` exit=0, 28 s; `canary-tmp` removed | PASS (re-run on the final files at 21:55: same 9 PASS) |
| W1 | Watcher refuses when an AI started it | `watch-inbox.ps1 -Root <tmp> -Once` | `REFUSED: an AI process is an ancestor. Start it from the Startup folder or a window you opened.` exit=2 | PASS |
| W3 | (a) clean signed info drop + an unsigned drop + a wrong-key drop; env allowlist; retention; draft popup **[test switch]** | `watch-inbox.ps1 -Root <tmp> -Once -AllowAiAncestorForTest` (settings.json in tmp) | `type: question · AI-instructions: n ...` / `NO RED FLAGS FOUND: YES` / `A YES is not a safety guarantee.` / `POPUP: 2 unsigned message ignored ...` / `POPUP: 1 draft waiting: double-click SEND`; seen = `unsigned, unsigned, run`; outbox after: `new.txt` (8-day-old `old.txt` deleted); `incoming/runs left: 0`; `views dir: False`; `temp views: 0` | PASS |
| W4 | Second pass: nothing re-run | same | only `POPUP: 1 draft waiting ...` | PASS |
| W5 | Version/model pin mismatch: new signed drop is not run | pin file edited to `opencode 0.0.1 \| model x` | `POPUP: VERSION CHANGED: run the canary (canary.ps1) ...`, no view | PASS |
| W8 | Daily cap, newest first (cap 2, 1 already run) | `-DailyCap 2` | newest `note-c.txt` ran (`NO RED FLAGS FOUND: YES`), then `POPUP: Messages held: daily limit of 2 reached.` | PASS |
| W10 | (b) the canary text, signed, in normal mode: flagged view shape | `-DailyCap 5` | `type: asks-to-change-rules · AI-instructions: y · asks-private: y · claims-approval: y` / `raw: ... AI-address y · approval-words y · chars dropped 3` / `flagged: read it in Drive yourself; never paste it into your AI.` (no topic/summary lines); `left: 0`; `ZORBLE anywhere in root: 0` | PASS |
| W9 | `-SetKey host` refuses when an AI started it | `watch-inbox.ps1 -SetKey host` | `REFUSED: an AI process is an ancestor ...` exit=2 | PASS. (With the test switch it waits for console input, so interactive key entry itself is UNTESTED.) |
| S1 | send-drop from an AI shell (piped stdin) | `send-drop.ps1 -Root <tmp>` | `REFUSED: input is piped. Double-click SEND yourself.` exit=2 | PASS |
| S1b | send-drop in its own console (stdin not piped), still under the AI | `Start-Process powershell ... send-drop.ps1` | `REFUSED: an AI process is an ancestor. Double-click SEND on your desktop yourself.` exit=2 | PASS |
| S2 | Dot-source defines functions only; flags; sign/verify | `. send-drop.ps1`; `Add-CourierTag` / `Test-CourierTag` | `flags: TEXT ADDRESSED TO AN AI`; `verify ok: True ; tampered: False ; wrongkey: False`; outbox unchanged | PASS |
| P6 | INSTALL step 6 paste, in a fake home folder (USERPROFILE redirected; the Desktop copy target redirected to a temp folder) | the step-6 block, answers `peer / opencode-go/deepseek-v4-flash / G / (empty)` | `DONE`; settings.json `inbox_dir G:\My Drive\from-host`, `outbox_dir G:\My Drive\from-peer`, `provider_env []`; `model: opencode-go/deepseek-v4-flash`; `_HOW-TO-DRAFT.md` in staging; `SEND.cmd` on the (temp) desktop | PASS |

An earlier watcher version (before the R3 fixes) ran the same canary 4 times: 1 of 4 runs gave output
that failed the checks (safe result: summary not shown, verdict NO). That is why `canary.ps1` asks
for one re-run on that single failure.

## Not tested (UNVERIFIED)
- Anything on the peer's machine: the peer's OS, the peer's OpenCode version, the peer's model, the peer's Drive letter/shortcut path.
- A real double-click of SEND (explorer.exe -> SEND.cmd) and typing a passphrase; a real Startup-folder
  start of the watcher; the real WScript popup and Notepad windows (printed instead in test mode).
- Real Google Drive for desktop sync, including the "size and time unchanged across two looks" rule
  on a file that is still uploading.
- The folder-missing popup (3 missed polls) and the single-instance mutex (needs the loop mode).
- The 120 s timeout + tree kill (no run came close: runs took about 5-10 s).
- Path-override refusal without a test switch (inside an AI session the launch check refuses first).
