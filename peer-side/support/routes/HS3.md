# HS3 - Setup of the kit or OpenCode failed

**Symptom:** during INSTALL steps 2-3: `opencode is not recognized` after the kit setup ran, `running
scripts is disabled on this system`, the setup script stopped with red text, or signing in / picking a
model does not work.

**Checks**
1. Close the PowerShell window, open a NEW one ("Open PowerShell here"), and run `opencode --version`.
2. Did the paste start with `powershell -ExecutionPolicy Bypass -File`? (That avoids "scripts disabled".)

**Fix:** a new window usually fixes "not recognized". "Scripts disabled": paste INSTALL step 3 exactly as
written. Sign-in: `kit\tools\opencode\README.md`, "Install and sign in", with the host on the phone.

**Still broken:** text the host a photo of the red text, or make a ticket with route HS3.
