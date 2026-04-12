@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROJECT=%ROOT%\apps\windows\FlightTracker\FlightTracker.csproj"
set "EXE=%ROOT%\apps\windows\FlightTracker\bin\Release\net8.0-windows\FlightTracker.exe"
set "USER_DOTNET=%USERPROFILE%\.dotnet\dotnet.exe"
set "DOTNET_EXE="

if exist "%USER_DOTNET%" (
  set "DOTNET_EXE=%USER_DOTNET%"
) else (
  set "DOTNET_EXE=dotnet"
)

"%DOTNET_EXE%" --list-sdks >nul 2>&1
if errorlevel 1 (
  echo Installing the .NET 8 SDK to %USERPROFILE%\.dotnet ...
  powershell -ExecutionPolicy Bypass -Command ^
    "$script = Join-Path $env:TEMP 'dotnet-install.ps1';" ^
    "Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1' -OutFile $script;" ^
    "& powershell -ExecutionPolicy Bypass -File $script -Channel 8.0 -InstallDir (Join-Path $env:USERPROFILE '.dotnet') -NoPath"
  if errorlevel 1 exit /b %errorlevel%
  set "DOTNET_EXE=%USER_DOTNET%"
)

"%DOTNET_EXE%" build "%PROJECT%" -c Release -nologo
if errorlevel 1 exit /b %errorlevel%

start "" "%EXE%"
