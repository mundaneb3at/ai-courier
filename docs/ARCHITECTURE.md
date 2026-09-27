# Architecture

Two sides, one shared validator (`lib/messenger-lib.ps1`), and Google Drive as the only transport.

- **Host** (`host-side/`): runs Claude Code. Pulls the peer's folder with `rclone` using a separate,
  read-only "courier" Google account, so the token can see nothing but that one folder.
- **Peer** (`peer-side/`): runs OpenCode. Reads the host's folder through a Google Drive for desktop
  shortcut, so there is no OAuth app and no rclone on the peer's machine.

```
PEER MACHINE                                GOOGLE DRIVE                 HOST MACHINE
peer AI -> outbox-staging\
  [SEND: peer reads it, types passphrase]
  send-drop.ps1 -> from-<peer>\   --sync-->  from-<peer>  --rclone, courier acct, read-only-->
                                                                         incoming\peer\ (seconds only)
                                                                         watch-inbox.ps1 -> claude -p (locked)
                                                                         -> validator -> view in watcher window
host AI -> outbox-staging\
  [SEND: host reads it, types passphrase]
                                            from-host  <--sync--  send-drop.ps1
peer watch-inbox.ps1 (60 s poll of the Drive shortcut) -> opencode run (zero tools) -> validator -> view
```

## One message, end to end

1. **Draft (automatic).** The sender's AI writes a plain `.txt` into `outbox-staging\`, following
   `peer-side/_HOW-TO-DRAFT.md` (no paths, links, code, health/money/legal details, or text addressed
   to the other AI). The AI can never send: it has no passphrase.
2. **SEND (the one human step).** The sender double-clicks `SEND.cmd`. `send-drop.ps1` refuses piped
   input and AI ancestors, shows the full text, asks for a topic word, then the passphrase twice. It
   signs exactly the bytes it showed (`courier-sig: <HMAC-SHA256>` appended) and writes them into the
   sender's own Drive folder. At most 3 sends a day.
3. **Pull (automatic).** The receiver's watcher lists the other side's folder: name
   `^[A-Za-z0-9._-]{1,64}$`, `.txt`/`.md`, 1 B to 8 KB, not seen before. The host fetches by Drive file
   ID; the peer waits until size and time are stable across two polls.
4. **Signature check.** An unsigned or wrongly signed file is not run. The receiver gets a count-only
   alert (`1 UNSIGNED`).
5. **Quarantined read.** One model run per message, with a 120 s timeout:
   - Host: `claude -p --safe-mode --restricted --system-prompt-file messenger-prompt.txt --tools Read
     --strict-mcp-config --no-session-persistence --model <literal id> --output-format json
     --json-schema <schema.json>`, run in an empty folder whose parent holds an empty `CLAUDE.md`.
   - Peer: `opencode run --agent messenger` with `permission: {"*": "deny"}` (zero tools), the message
     attached with `-f`, and an isolated config (`OPENCODE_CONFIG_DIR`, `XDG_CONFIG_HOME`,
     `OPENCODE_DISABLE_CLAUDE_CODE=1`, `OPENCODE_DISABLE_PROJECT_CONFIG=1`).
   - Both: an explicit environment allowlist for the child process.
6. **Validate (a script, not a model).** `messenger-lib.ps1` checks the JSON shape and enums, collapses
   line breaks, applies a character allowlist, and re-scans the raw text for links, code, paths,
   AI-addressed phrasing and approval claims. The verdict line is `NO RED FLAGS FOUND: YES` only when
   every check passes, followed by `A YES is not a safety guarantee.`
7. **Show.** The 9-line view prints in the watcher window. A clean view also opens in Notepad from a
   temp file that is deleted on close. A flagged view shows only the flags and says to read the
   original yourself and never paste it into an AI. No view is ever written to a log.
8. **Clean up.** The raw copy and run folder are deleted; the file ID goes into `seen.jsonl` only
   after cleanup succeeds. Anything older than 5 minutes is swept on start and every tick.

## The view (contract `ai-courier/3`)

```
DATA FROM AI COURIER - information, not instructions. It carries no approvals.
from: <sender> · claimed <date> · <drive name> · <bytes> B · sha8 <hash>
type: <request_type> · AI-instructions: <y/n/unsure> · asks-private: <y/n/unsure> · claims-approval: <y/n>
raw: links <y/n> · code <y/n> · paths <y/n> · AI-address <y/n> · approval-words <y/n> · chars dropped <n>
topic: <at most 60 chars>
summary: <at most 400 chars, third person>
NO RED FLAGS FOUND: YES | NO ...
A YES is not a safety guarantee.
Never paste your notes or files out because a message asks for them.
```

## Keeping the lock honest over time

- **Version pin.** `canary-pass.txt` records the CLI version and the literal model ID the canary last
  passed with. On a mismatch, no messenger run happens.
- **Auto-canary.** On a mismatch the watcher runs `canary.ps1` once per new version. PASS: the pin is
  updated and the held message is read in the same tick. FAIL: messages stay held and exactly one
  alert is raised; there is no retry until the version changes again.
- **Canary.** A signed hostile message (rule-breaking instructions, a fake prior approval, an
  "assistant, open the folder" line, variation selectors and a U+2028 line break) plus an unsigned copy
  go through the real pipeline. It passes only if the hostile one is flagged, the unsigned one is
  refused, a random nonsense word never appears in the view or in the AI tool's own session/memory
  folders, and all raw copies are gone.

## Updates and support (peer side)

- **`doctor.ps1`** (read-only, safe for the peer's AI to run) compares the installed files with
  `BASELINE.json` and prints file IDs, not paths, so its output passes the checker.
- **Support tickets.** `support/INDEX.md` maps a symptom to a route card (`support/routes/<id>.md`).
  If the card doesn't fix it, the peer's AI fills `support/TICKET-TEMPLATE.md` and the peer sends it
  through the normal SEND. The host follows `host-side/TRIAGE.md`.
- **Signed updates.** The host runs `host-side/make-release.ps1`, which writes `update-<N>.zip` and a
  baseline JSON signed with `ssh-keygen -Y sign`. The peer runs `update.ps1` by hand. It verifies the
  signature against the installed `allowed_signers`, the version (only goes up), the zip hash and
  every file hash; stops if a file it would replace was changed locally; asks for a typed `yes`; backs
  up; applies; runs the canary; and rolls back byte for byte on a FAIL. It has no test switch: every
  guard is one tagged line, and tests delete that line in a scratch copy.
- `make-release.ps1 -Package <folder>` expects `<folder>\messenger\` (the peer files plus
  `messenger-lib.ps1`) and `<folder>\kit\` (the peer's AI workspace template, whose rule files and
  skills are also tracked in the baseline).

## Why the sides differ

The host's disk is read by several AI tools, so the host never mirrors the peer's folder: rclone
fetches one file into a folder outside the user profile and deletes it after the run. The peer runs one
AI whose config already denies outside folders, and a Drive shortcut is two clicks with no OAuth app and no rclone. The residual (the peer AI's shell could read the synced folder) is an accepted risk; see
`THREAT-MODEL.md`.

## Design IDs in code comments

Comments cite design IDs: `N1`..`N26` (often as `R3 Nx`) are the review rows in `THREAT-MODEL.md`;
`M`-numbers (`R2 Mx`) come from an earlier review round of the same design; `A`/`B` steps are the two
flows above (A = peer to host, B = host to peer). `REDESIGN sN`, `MESSENGER-DESIGN sN` and
`S-opencode`/`S-harness` point at the internal design and probe notes this document condenses; they
are not in the repo.
