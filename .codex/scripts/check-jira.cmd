@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0check-jira.ps1" %*
exit /b %ERRORLEVEL%
