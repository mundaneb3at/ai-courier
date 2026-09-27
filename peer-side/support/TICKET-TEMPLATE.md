# For your AI: how to draft a support ticket to the host

Use this when a route card (`routes\<id>.md`) ends in "make a ticket", or your person asks for one.
A ticket is an ordinary draft: write it into `outbox-staging` like any message (read
`outbox-staging\_HOW-TO-DRAFT.md` first). You NEVER send it: your person double-clicks SEND and types
their passphrase. Never ask for, store or type a passphrase, and never put one in a ticket.

Steps:
1. Run the doctor (it only reads, it changes nothing) and keep its whole output:
   `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-courier\doctor.ps1"`
2. Fill the template below. Paste the doctor output as-is (it already lists the local changes log and
   the last watcher results, with no file paths).
3. Save it as `outbox-staging\ticket-<YYYYMMDD>.txt` and tell your person: "the ticket is ready,
   double-click SEND and pick the topic `logistics`".

Keep it under 8 KB (SEND refuses bigger ones; the doctor output is about 1-2 KB). The host's side shows
them a checked summary, and the checker holds back anything with links, file paths or file names,
commands or code, text addressed to an AI, or words like "already", "approved", "agreed", "permission",
"plan", "as discussed", "you said". So in the parts you write: describe things in plain words ("the
watcher window", "the doctor", "the settings file"), not names with dots or slashes.

--- template (copy from the next line) ---
FROM <name>'s AI · asked by: <name> · <YYYY-MM-DD>
Facts I used: <what your person told you this session, and the doctor output below>
SUPPORT TICKET · route <card id, e.g. F6, or NONE> · package v<number from the doctor's package line>
What happened, in my person's words: <1-3 sentences>
What we tried from the route card, and what each check showed: <short list>
Doctor output:
<paste the whole doctor output here>
Question for the host: what should we try next?
