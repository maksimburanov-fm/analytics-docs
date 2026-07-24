@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0check-fmedia-gp.ps1" %*
exit /b %ERRORLEVEL%
