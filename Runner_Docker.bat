@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File ".\Runner_Docker.ps1"
pause
