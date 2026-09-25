@echo off
REM Windows one-click local environment: k3d cluster + Argo CD + app + CRUD test.
REM Needs Docker Desktop. k3d, kubectl and terraform are downloaded to .tools\ if missing.
REM The window stays open afterwards (close it with the X) so you can take screenshots.
cd /d "%~dp0"
powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command "$env:PATH = \"$PWD\.tools;$env:PATH\"; & .\scripts\bootstrap-local.ps1"
