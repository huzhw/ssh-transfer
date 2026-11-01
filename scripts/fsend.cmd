@echo off
rem fsend - stream files to/from a remote host over SFTP (ssh-transfer skill)
rem Shim: forwards to fsend.ps1. The path is absolute on purpose: a PATH-level
rem symlink or copy of this file still finds the real script (%~dp0 would
rem resolve to the link's own directory instead).
setlocal
set "SCRIPT=F:\idea-workspase-skills\ssh-transfer\scripts\fsend.ps1"
if not exist "%SCRIPT%" (
  echo [fsend] ERROR: script not found: %SCRIPT%
  echo [fsend] The ssh-transfer skill repo may have moved.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
