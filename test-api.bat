@echo off
REM Re-runs the CRUD test. Output is also saved to docs\screenshots\api-test-output.txt
REM The window stays open afterwards (close it with the X).
cd /d "%~dp0"
powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command "$env:PATH = \"$PWD\.tools;$env:PATH\"; & .\scripts\test-api.ps1 %*"
