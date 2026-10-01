@echo off
rem One-command SALU release: clean -> pub get -> analyze/test -> build -> Inno Setup.
rem Usage:  tools\build-installer.cmd [-SkipClean] [-SkipTests] [-OpenOutput]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_installer.ps1" %*
exit /b %ERRORLEVEL%
