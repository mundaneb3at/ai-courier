# Auto-canary + double passphrase (build log)

Extract of the build log (sections: summary, DESIGN, CHANGES, TESTS); names generalised.

Auto-canary built on both sides: PASS updates the pin and reads the message same-tick, FAIL holds and
sends exactly one push/popup, no auto-retry until the version changes again (verified with a fixture +
negative control on each side). Passphrase now asked twice on both sides, one retry, then refuses.
Self-tests 38/38 both sides; both hand canaries PASS (the peer's needed a real model pinned in a SCRATCH copy
only - the shipped `messenger.md` keeps its placeholder until install step 6 fills in a real model).
UNVERIFIED: send-drop.ps1 end-to-end (refuses under an AI ancestor by design) - parse+code-read only.

## DESIGN

O3: on pin mismatch, spawn `canary.ps1 -Root $Root` (it already writes `canary-pass.txt` into whatever
`-Root` it gets). Re-read the pin: PASS -> matches now, fall through to read in the SAME tick. FAIL/can't
start -> hold as before + the fixed push/popup, one shot per version (`canary-auto-tried.txt` marker, same
pattern as the host's `Test-DayMarker`). `-Canary` already skips this block, so the nested watcher can't recurse.
Ancestor rule: hand-walked `Test-LaunchAllowed -Mode Watch` for nested-watch -> canary.ps1 -> real watcher
-> explorer/svchost: every hop is a plain `powershell.exe` or the root itself, no AI anywhere, so it
already passes in production with NO change to messenger-lib.ps1. Only an AI-driven TEST session breaks
it, fixed the way canary.ps1 already fixes it for its own nested call: thread `-AllowAiAncestorForTest`
one hop further, only when the outer call already had it - not a bypass, the same opt-in flag one level in.

## CHANGES

| file | before | after |
|---|---|---|
| host-side\watch-inbox.ps1 | pin mismatch -> hold + `courier inbox: canary needed` push, always | pin mismatch -> run `canary.ps1 -Root $Root` once per new `claude --version` (file marker `canary-auto-tried.txt`); PASS -> pin updated, same tick keeps reading; FAIL/can't-start -> hold (unchanged) + `canary FAILED after update, messages held` push |
| host-side\send-drop.ps1 | passphrase typed once | typed twice (`Read-Passphrase` helper), one retry on mismatch ("The two passphrases differ. Nothing sent." / retry / "differ again. Nothing sent."), then exit; draft/topic already chosen earlier are untouched |
| host-side\INSTALL.md | step 9 = one-time canary, `canary needed` push, no FAIL guidance in the push table | step 9 = canary now also runs itself after every Claude update; push table + "when a push needs you" both describe the new `canary FAILED after update, messages held` push |
| peer-side\watch-inbox.ps1 | VERSION CHANGED -> hold + popup every mismatched file, always | VERSION CHANGED -> run `canary.ps1 -Root $Root` once per new `opencode --version \| model` string (file marker `canary-auto-tried.txt`); PASS -> pin updated, falls through to run the same message; FAIL/can't-start -> hold (unchanged) + "the safety test failed after an update; don't read messages, text the host a photo of this window" popup |
| peer-side\send-drop.ps1 | passphrase mismatch -> `Stop-Send` immediately | one retry added (8 lines): mismatch -> message + retype both fields once -> mismatch again -> `Stop-Send` |
| peer-side\INSTALL.md | step 10 VERSION CHANGED bullet described running step 8 by hand every time | describes the watcher's own silent auto-canary; only the FAIL popup (exact text above) still needs a hand run |
| peer-side\canary\EXPECTED.md | "Run it at setup and whenever a popup says VERSION CHANGED" | "Run it at setup... After that the watcher runs it for you... only need to run it by hand if the watcher's own attempt fails" |

No changes to messenger-lib.ps1 on either side (hashes below prove it) - the ancestor rule already holds for the extra hop (see DESIGN), so `Test-LaunchAllowed`/`Test-AncestorIsAi` were not touched.

## TESTS

**Self-tests + integrity (all edited files):**
- `[System.Management.Automation.Language.Parser]::ParseFile` on the 4 edited `.ps1` files: 0 parse errors each.
- Non-ASCII byte scan on the same 4 files: 0 bytes each.
- `messenger-lib.ps1 -SelfTest`, both sides: **38 passed, 0 failed** each.
- `Get-FileHash` both `messenger-lib.ps1` copies: identical (`7AF57800F1F0967C012A70670A1B08756FBF2E57796E26C614FAE8C58E453413`) - lib not edited, matches an earlier check.

**Hand canary runs (scratch copies, `-AllowAiAncestorForTest`, never the real folders):**
- Host `canary.ps1 -Root <scratch>`: **11/11 PASS, CANARY PASSED (2.1.283 (Claude Code) / claude-haiku-4-5-20251001)**.
- Peer `canary.ps1 -Root <scratch>` on the packaged copy **FAILED both attempts** ("output passed the checks") - root cause isolated: `messenger.md`'s `model:` line is still the literal placeholder `<cheap model you already have>` in the package template (confirmed by re-running the unmodified `git show HEAD` copy - same FAIL, so this is pre-existing and out of scope for this build, not something my edit broke). Pinning a real model (`opencode-go/deepseek-v4-flash`, in the scratch copy only, never the real file) gave **9/9 PASS, CANARY PASS (opencode 1.18.32 / opencode-go/deepseek-v4-flash)**, confirming the peer's canary pipeline itself is fine.

**O3 fixture - pin-mismatch -> auto-canary (fresh scratch roots each case, one signed clean message queued, `-Once -AllowAiAncestorForTest`):**
| case | setup | result |
|---|---|---|
| host PASS | edited watcher, real canary | auto-canary ran once (`running auto-canary for 2.1.283 (Claude Code)`), `pinned=True`, message ran and showed in the **same tick** - 0 human steps |
| host FAIL | edited watcher, canary\canary-drop.txt swapped for a clean (non-hostile) fixture so the canary's own checks fail | tick 1: auto-canary ran, `pinned=False`, message held, exactly **one** `canary FAILED after update, messages held` push. Tick 2 (same root): **no second auto-canary attempt** (`Test-DayMarker` on `canary-auto-tried.txt` held), no second push, message still held |
| host negative control | **unmodified `git show HEAD` copy**, same fixture | old behaviour exactly: `VERSION CHANGED: run the canary` view, `courier inbox: canary needed` push, no auto-run attempted, message held |
| peer PASS | edited watcher, model pinned to a real id in the scratch copy | auto-canary ran, pin file updated to `opencode 1.18.32 \| model opencode-go/deepseek-v4-flash`, message ran in the same tick, `seen.jsonl` shows `result=run, verdict=YES` - 0 human steps |
| peer FAIL | edited watcher, placeholder model (guaranteed canary FAIL) | tick 1 + tick 2: popup shown each time (the peer's `$notified` cache is per-process and this harness restarts the process every `-Once` tick, same as the pre-existing VERSION CHANGED popup did - not something this build changed); **timed a 3rd tick: 4.2 s wall-clock**, far short of a real `opencode run` (30-45 s in the PASS case above), confirming the canary itself was **not** re-launched - the once-per-version file marker held. Message stayed unseen (`seen.jsonl` empty) all 3 ticks |
| peer negative control | **unmodified `git show HEAD` copy**, same fixture | old behaviour exactly: `VERSION CHANGED: OpenCode updated itself...` popup, no auto-run attempted, message held |

**send-drop.ps1 (O6):** both sides refuse under an AI ancestor by design (`Test-LaunchAllowed -Mode Send` has no test-override flag, unlike Watch mode) and refuse piped stdin, so they cannot be driven end-to-end from this session. **UNVERIFIED by execution** - verified instead by: 0 parse errors / 0 non-ASCII bytes (above), and a code read of the new blocks confirming: `-ceq` (case-sensitive) compare, an empty first entry still cancels before any signing happens, a mismatch never calls `Add-CourierTag`/`Get-CourierKey` (nothing is ever written to the outbox on either branch), and the already-picked draft/class/text are never re-read or re-prompted.

