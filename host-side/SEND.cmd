@echo off
rem Double-click this yourself. It runs send-drop.ps1 in THIS window (no "start": send-drop checks
rem that its parent is this cmd.exe, whose parent is explorer.exe).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0send-drop.ps1"
pause
