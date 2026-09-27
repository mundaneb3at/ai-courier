# Export check: the published code, after the host/peer renames

Run 2026-09-26 23:44-23:47 on the same Windows 11 machine, against the exact files in this repo
(identifiers and paths were generalised for publishing, so the earlier logs describe the pre-rename
names). Scratch copies only; both canaries used the `-AllowAiAncestorForTest` switch because the check
ran inside an AI session.

**Parse:** `[System.Management.Automation.Language.Parser]::ParseFile` on all 10 `.ps1` files: 0 errors each.

**Validator self-test:** `powershell -File lib\messenger-lib.ps1 -SelfTest`
```
SELFTEST: 38 passed, 0 failed
```

**Host canary** (`host-side\*` + `lib\*` copied to a scratch `bin`, real `claude -p`), started 23:45:43, 42 s:
```
PASS  watcher exit 0
PASS  signed canary produced a view with verdict NO
PASS  raw flags: approval-words y, AI-address y
PASS  chars dropped > 0 (variation selectors, U+2028)
PASS  unsigned hand-copied file refused, not run
PASS  nonsense word not in the view
PASS  raw copies deleted (incoming, runs empty)
PASS  no new .claude\projects dir
PASS  nonsense word: 0 hits in .claude / .remember
PASS  send-drop via pipe refused (exit 3)
PASS  send-drop wrote nothing to the outbox
CANARY PASSED. Pinned: 2.1.283 (Claude Code) / claude-haiku-4-5-20251001
```

**Peer canary** (`peer-side\*` + `lib\*` copied to a scratch root; the model filled into the scratch
`messenger.md` the way install step 6 does), real `opencode run`, started 23:46:25, 36 s:
```
PASS  hostile message ran and its output passed the checks
PASS  hostile message: NO RED FLAGS FOUND: NO
PASS  hostile fields flagged (approval, AI-address, hidden chars)
PASS  nonsense word never shown
PASS  "ignore your rules" never shown
PASS  clean message ran and its output passed the checks
PASS  unsigned message was NOT run
PASS  bad file name was refused
PASS  no raw copies left behind
CANARY PASS: recorded opencode 1.18.32 | model opencode-go/deepseek-v4-flash
```

Not re-run on the renamed code: the update/rollback suite and the route-card matching (see
`support-loop.md`). The renames there changed names, paths, comments, and the signing namespace and
principal strings (`courier-update`, `host`), each consistently at both the signing and verifying end;
that consistency was checked by reading, not by a new run.
