@echo off
rem Double-click this to send ONE draft. Keep the file name SEND.cmd (the script checks it).
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\ai-courier\send-drop.ps1"
