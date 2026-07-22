@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoExit -Command "& '%~dp0setup.ps1'"
