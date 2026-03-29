[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TrackerPaths {
    $root = Split-Path -Parent $PSScriptRoot
    return [pscustomobject]@{
        Root = $root
        Dump1090 = Join-Path $root "vendor\Dump1090\dump1090.exe"
        LogFile = Join-Path $root "logs\dump1090.log"
        BeastBridgeLog = Join-Path $root "logs\beast-bridge.log"
        BeastBridgePid = Join-Path $root "logs\beast-bridge.pid"
        RtlTest = Join-Path $root "vendor\rtl-sdr-tools\rtl-sdr-64bit-20260322\rtl_test.exe"
        Url = "http://localhost:8080"
    }
}

function Get-TrackerProcess {
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath
    )

    Get-CimInstance Win32_Process -Filter "Name = 'dump1090.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -eq $ExecutablePath }
}

function Get-BridgeProcess {
    param(
        [Parameter(Mandatory)]
        [string]$PidFile
    )

    if (-not (Test-Path -LiteralPath $PidFile)) {
        return $null
    }

    $pidText = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if (-not $pidText -or $pidText -notmatch '^\d+$') {
        return $null
    }

    return Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
}

function Get-PortListener {
    param(
        [int]$Port
    )

    Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Listen" } |
        Select-Object -First 1
}

function Get-RecentLogTail {
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        [int]$Lines = 25
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return ""
    }

    return (Get-Content -LiteralPath $LogPath -Tail $Lines | Out-String).Trim()
}

function Write-PortStatus {
    param(
        [Parameter(Mandatory)]
        [int]$Port,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $listener = Get-PortListener -Port $Port
    if ($listener) {
        Write-Host ("{0,-15}: listening on tcp://127.0.0.1:{1}" -f $Label, $Port) -ForegroundColor Green
    } else {
        Write-Host ("{0,-15}: not listening on port {1}" -f $Label, $Port) -ForegroundColor Yellow
    }
}

$paths = Get-TrackerPaths
$tracker = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1
$bridge = Get-BridgeProcess -PidFile $paths.BeastBridgePid | Select-Object -First 1
$listener = Get-PortListener -Port 8080

if ($tracker) {
    Write-Host "Tracker process : running (PID $($tracker.ProcessId))" -ForegroundColor Green
} else {
    Write-Host "Tracker process : not running" -ForegroundColor Yellow
}

if ($bridge) {
    Write-Host "Beast bridge    : running (PID $($bridge.ProcessId))" -ForegroundColor Green
} else {
    Write-Host "Beast bridge    : not running" -ForegroundColor Yellow
}

if ($listener) {
    Write-Host "Web server      : listening on http://localhost:8080" -ForegroundColor Green
} else {
    Write-Host "Web server      : not listening on port 8080" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Feed outputs:"
Write-PortStatus -Port 30002 -Label "AVR/raw"
Write-PortStatus -Port 30003 -Label "SBS"
Write-PortStatus -Port 30005 -Label "Beast"
Write-Host "FR24           : can use AVR on tcp://127.0.0.1:30002"
Write-Host "FlightAware    : native host uploader can use SBS on tcp://127.0.0.1:30003; external/manual setups can use Beast on tcp://127.0.0.1:30005 with MLAT off"
Write-Host "airplanes.live : can use Beast on tcp://127.0.0.1:30005, but synthetic timestamps mean MLAT should stay off"

if ($tracker) {
    Write-Host "USB device      : skipped because the tracker already has the SDR open"
} elseif (Test-Path -LiteralPath $paths.RtlTest) {
    $rtlOutput = (& cmd.exe /d /c ('"{0}" -t 2>&1' -f $paths.RtlTest) | Out-String).Trim()

    if ($rtlOutput -match "Found [1-9]\d* device\(s\)") {
        Write-Host "USB device      : detected" -ForegroundColor Green
    } elseif ($rtlOutput -match "Found 0 device\(s\)" -or $rtlOutput -match "No supported devices found") {
        Write-Host "USB device      : not detected" -ForegroundColor Red
    } else {
        Write-Host "USB device      : unclear, see details below" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "rtl_test output:"
    Write-Host $rtlOutput
} else {
    Write-Host "USB device      : rtl_test.exe not found" -ForegroundColor Red
}

$logTail = Get-RecentLogTail -LogPath $paths.LogFile
if ($logTail) {
    Write-Host ""
    Write-Host "Recent log output:"
    Write-Host $logTail
}

$bridgeLogTail = Get-RecentLogTail -LogPath $paths.BeastBridgeLog
if ($bridgeLogTail) {
    Write-Host ""
    Write-Host "Recent Beast bridge log output:"
    Write-Host $bridgeLogTail
}

$nativeStatusScript = Join-Path $paths.Root "scripts\Manage-NativeFeeder.ps1"
if (Test-Path -LiteralPath $nativeStatusScript) {
    Write-Host ""
    Write-Host "Native feeder status:"
    foreach ($provider in @("flightaware", "airplanes-live")) {
        & powershell.exe -ExecutionPolicy Bypass -File $nativeStatusScript -Provider $provider -Action Status
        Write-Host ""
    }

    foreach ($provider in @("flightaware", "airplanes-live")) {
        $providerLog = Join-Path $paths.Root "logs\$provider.log"
        $providerTail = Get-RecentLogTail -LogPath $providerLog
        if ($providerTail) {
            Write-Host "Recent $provider feeder log output:"
            Write-Host $providerTail
            Write-Host ""
        }
    }
}
