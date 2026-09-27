# messenger

Your AI and the host's AI pass short notes through Google Drive. A locked-down "messenger" AI
(no tools at all) reads each incoming note and writes a short, checked summary for **you**.
Your own AI sees it only if you paste it in.

## Files
| File | What it does |
|---|---|
| `watch-inbox.ps1` | Runs in the background. Every 60 s it looks in your `from-host` Drive folder. A new file runs only if the host signed it at their SEND. It runs the messenger, then shows you the result: Notepad if no red flags, a short "flagged" popup otherwise. It tells you when a draft is waiting. It never sends anything and never opens SEND. |
| `send-drop.ps1` + `SEND.cmd` | The only way out. Double-click SEND, read the draft, pick a topic, type your passphrase. It signs exactly the text you saw and writes it into your `from-<name>` Drive folder. It refuses unless you started it from the desktop. |
| `canary.ps1` + `canary\` | A fake hostile message pushed through the real pipeline. Run it at setup and whenever a popup says VERSION CHANGED. |
| `messenger-lib.ps1` | The checker (same file as the host's): cleans text, checks the messenger's answer, builds the summary, signs and verifies. |
| `messenger.md` | The messenger AI's settings: no tools, temperature 0, one pinned model. |
| `messenger-prompt.txt` | The messenger's instructions (same text on both sides). |
| `oc-config\` | A separate OpenCode settings folder used only for messenger runs (see below). |
| `_HOW-TO-DRAFT.md` | Rules for your AI when it writes a draft. Setup moves it into `work\outbox-staging\`. |
| `TEST-LOG.md` | What was tested, where, and the results. |

Installed in `%USERPROFILE%\ai-courier\`. It keeps: `settings.json` (folder paths, written at
setup), `keys\host.key` (the host's verify key, encrypted for your Windows user), `seen.jsonl`
(IDs of handled files, no text), `canary-pass.txt`, `sent.log` + `sent\` (your sent drafts).
`incoming\` and `runs\` hold a raw copy only for the seconds of a run, and get swept after 5 minutes
at most. Summaries are not saved anywhere.

## Why the messenger can't be talked into things
- It has **zero tools**: it cannot read other files, run commands, or go online. The message is
  attached to its prompt, and a script (not the AI) builds the summary.
- Each run is isolated: `OPENCODE_CONFIG_DIR` = `oc-config\`, `XDG_CONFIG_HOME` = `oc-config\xdg\`
  (empty), `OPENCODE_DISABLE_CLAUDE_CODE=1`, `OPENCODE_DISABLE_PROJECT_CONFIG=1`. So your normal
  OpenCode settings and rule files (`AGENTS.md`) are not loaded into it, and your normal OpenCode
  is not changed. It also gets only a short list of environment variables (plus the API-key
  variable you named at setup, if any). Your `/connect` login still works.
- **No `AGENTS.md`, `CLAUDE.md`, `.git` or `.opencode` may exist in your user folder or above it.**
  The watcher refuses to start if one does.
- Only signed files run. The signature comes from a passphrase typed at SEND and never stored, so a
  file an AI dropped into Drive by itself is ignored (you get a popup about it). The same holds the
  other way: if your AI ever copies a file into your `from-<name>` folder itself, the host's side
  refuses it and they will ask you whether you sent it.
- It refuses anything that is not a `.txt`/`.md` of 8 KB or less with a plain name, runs at most
  10 messages a day, and stops reading when your OpenCode version or the model changes until the
  canary passes again.
- The last lines say `NO RED FLAGS FOUND: YES` or `NO`. A YES is not a safety guarantee.

## Known limits (accepted)
- Your Drive shortcut keeps the raw `from-host` files on your disk. The kit's settings stop your
  normal AI's file tools from opening them, but its shell commands could.
- Your own AI runs as you, so it could read `keys\host.key` and fake a "signed" note to your own
  watcher. That fools only your own summary window, not the host.
- A well-written normal message can still persuade. You decide; a message never approves anything.
- Tested only on the host's computer (OpenCode 1.18.32). UNVERIFIED on yours until the canary passes there.
