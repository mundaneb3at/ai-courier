# HS9 - The watcher will not start

**Symptom:** starting the watcher prints `REFUSED: ...` (not the rules-file one, that is F14),
`Already running`, or the window closes right after opening.

**Checks**
1. `Already running`: fine, one watcher is already up (look in the taskbar). Nothing to do.
2. `REFUSED: an AI process is an ancestor` or `... is not a plain shell`: it was started from inside an
   AI or another program.
3. `No inbox folder set`: `settings.json` is missing; INSTALL step 6 did not finish.

**Fix:** the person pastes INSTALL step 9 into a PowerShell window they opened from the Start menu or
"Open PowerShell here", never from inside OpenCode. Missing settings: redo step 6.

**Still broken:** make a ticket with route HS9 (copy the REFUSED line into "what I tried").
