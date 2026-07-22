@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoExit -Command "& '%~dp0run.ps1'"
