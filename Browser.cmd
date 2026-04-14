@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROJECT=%ROOT%\apps\windows\DashboardHost\DashboardHost.csproj"
set "TRACKER_START=%ROOT%\scripts\Start-LocalFlightTracker.ps1"
set "USER_DOTNET=%USERPROFILE%\.dotnet\dotnet.exe"
set "DOTNET_EXE="
set "PORT=5099"
set "KEY_FILE=%ROOT%\logs\dashboard.key"
set "MAC_URL_FILE=%ROOT%\macOS\flight-tracker-url.txt"

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

if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

echo Starting the local tracker runtime...
powershell -ExecutionPolicy Bypass -File "%TRACKER_START%" -NoBrowser
if errorlevel 1 exit /b %errorlevel%

set "LISTENER_COUNT=0"
netstat -ano | findstr /r /c:":%PORT% .*LISTENING" >nul 2>&1
if not errorlevel 1 set "LISTENER_COUNT=1"

if "%LISTENER_COUNT%"=="0" (
  if exist "%KEY_FILE%" del "%KEY_FILE%" >nul 2>&1
  start "Flight Tracker Web" cmd /k ""%DOTNET_EXE%" run --project "%PROJECT%" -c Release -- --no-browser --urls http://0.0.0.0:%PORT%"
  powershell -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 6"
)

for /l %%I in (1,1,20) do (
  if exist "%KEY_FILE%" goto key_ready
  powershell -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 1"
)

echo Dashboard key file was not created. Check the web console window.
exit /b 1

:key_ready
set /p DASHBOARD_KEY=<"%KEY_FILE%"

for /f "usebackq delims=" %%A in (`powershell -ExecutionPolicy Bypass -Command "$ip = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp,Manual -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress; if ($ip) { Write-Output $ip } else { Write-Output 'localhost' }"`) do set "HOST_IP=%%A"

if not exist "%ROOT%\macOS" mkdir "%ROOT%\macOS"
> "%MAC_URL_FILE%" echo http://%HOST_IP%:%PORT%/?key=%DASHBOARD_KEY%

echo.
echo Flight Tracker dashboard URL:
echo http://localhost:%PORT%/?key=%DASHBOARD_KEY%
echo.
echo Share this LAN URL with a Mac or another device:
echo http://%HOST_IP%:%PORT%/?key=%DASHBOARD_KEY%

start "" "http://localhost:%PORT%/?key=%DASHBOARD_KEY%"
