@echo off
setlocal

if "%~1"=="" (
  echo Usage: Create-FlightTracker-Release.cmd 1.0.0
  exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%~dp0Create-FlightTracker-Release.ps1" -Version "%~1"
