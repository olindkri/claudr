@echo off
rem claudr.cmd — cmd.exe shim that delegates to the PowerShell script.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claudr.ps1" %*
