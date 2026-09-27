# Route cards: symptom -> card id

How to use: read the symptom your person describes, find the ONE line below whose words fit it best,
then open `routes\<id>.md` in this folder and follow it. If two lines fit, take the one that names what
they SEE (a popup text, a window, an error line) over one that names a guess. If nothing fits, use NONE.
Every card ends the same way: still broken -> make a ticket (`TICKET-TEMPLATE.md`, one folder up).

| id | what the person sees or says |
|---|---|
| F1 | a popup or window that says "flagged"; "NO RED FLAGS FOUND: NO"; the summary was not shown; told to open the file on the from: line and read it myself |
| F2 | "failed validation"; "messenger timed out"; "ask for a resend"; the checker broke or took too long on one message |
| F3 | popup "the safety test failed after an update; don't read messages"; OpenCode updated itself and now messages are held |
| F4 | I ran the canary (safety test) by hand and a line says FAIL; "CANARY FAIL"; setup step 8 failed |
| F5 | forgot my passphrase; don't remember the secret words; the host changed their passphrase |
| F6 | nothing arrives any more; no messages for days; after a restart nothing comes; the minimized watcher window is gone from the taskbar; I closed the black window |
| F7 | popup "folder missing (is Google Drive running?)"; SEND says "Drive send folder was not found"; Google Drive is paused or signed out; the host says my message never reached them |
| F8 | The host says THEIR side cannot download my messages; "pull failing"; their Google token expired (the host side) |
| F9 | The host says they are away from their computer and cannot read my message yet (the host side) |
| F10 | I want to stop using the messenger; uninstall; remove everything |
| F11 | my AI saved or sent a file into Google Drive by itself; the host says they got an unsigned message from me that I did not send |
| F12 | popup "unsigned message ignored (not from the host's SEND)"; a message came without the host's signature |
| F13 | The host says my message is held because of their daily limit (the host side) |
| F14 | a red "TELL THE HOST: found ..." line during setup; watcher says "a rules file sits above its folder"; "REFUSED: found AGENTS.md above" |
| F15 | SEND says REFUSED or "Nothing sent": over 8 KB, 3 a day limit, "Not one of the topics", "passphrases differ", "input is piped", "not explorer.exe" |
| HS3 | during setup: "opencode is not recognized" after the kit setup; the setup script failed; "running scripts is disabled on this system"; cannot sign in or pick a model |
| HS5 | the from-host folder does not show up in File Explorer or in "Shared with me" |
| HS7 | saving the host's key says "Empty or different. Nothing saved." |
| HS9 | trying to START the watcher fails: I start or double-click it and its window flashes, closes or disappears at once; it prints "REFUSED" (not the rules-file one) or "Already running" |
| U1 | update.ps1 said REFUSED, STOPPED, ROLLED BACK, RESTORED or ROLLBACK MISMATCH; an update did not install or was interrupted; "files changed on this computer" list |
| NONE | none of the above fits, or it is a question about how to use it rather than something broken |
