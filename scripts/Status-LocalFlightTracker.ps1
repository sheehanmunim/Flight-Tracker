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

$paths = Get-TrackerPaths
$tracker = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1
$listener = Get-PortListener -Port 8080

if ($tracker) {
    Write-Host "Tracker process : running (PID $($tracker.ProcessId))" -ForegroundColor Green
} else {
    Write-Host "Tracker process : not running" -ForegroundColor Yellow
}

if ($listener) {
    Write-Host "Web server      : listening on http://localhost:8080" -ForegroundColor Green
} else {
    Write-Host "Web server      : not listening on port 8080" -ForegroundColor Yellow
}

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
