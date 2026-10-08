@echo off
rem Starts OpenCode (Mammouth) in the workspace folder (the parent of this handoff folder),
rem no matter where you call it from.
cd /d "%~dp0.."
opencode.cmd %*
