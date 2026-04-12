@echo off
setlocal

powershell -ExecutionPolicy Bypass -File "%~dp0Windows\Build-FlightTracker-Windows.ps1" %*
