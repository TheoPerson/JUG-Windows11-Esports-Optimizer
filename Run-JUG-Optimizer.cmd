@echo off
setlocal
cd /d "%~dp0"

:: Relaunch the optimizer from an elevated Windows PowerShell 5.1+ session.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0JUG_Windows11_EsportsOptimizer.ps1'"

endlocal
