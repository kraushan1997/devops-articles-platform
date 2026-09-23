@echo off
REM Windows one-click local environment: k3d cluster + Argo CD + app + CRUD test.
REM Needs Docker Desktop. k3d, kubectl and terraform are downloaded to .tools\ if missing.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\bootstrap-local.ps1"
echo.
pause
