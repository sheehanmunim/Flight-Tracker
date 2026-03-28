[CmdletBinding()]
param(
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TrackerPaths {
    $root = Split-Path -Parent $PSScriptRoot
    $vendorRoot = Join-Path $root "vendor\Dump1090"

    return [pscustomobject]@{
        Root = $root
        VendorRoot = $vendorRoot
        Dump1090 = Join-Path $vendorRoot "dump1090.exe"
        Config = Join-Path $root "dump1090-local.cfg"
        LogDir = Join-Path $root "logs"
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

function Get-ProcessSummary {
    param(
        [int]$ProcessId
    )

    if (-not $ProcessId) {
        return $null
    }

    Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

function Test-PortOwnedByTracker {
    param(
        [int]$ProcessId,
        [int]$Port
    )

    $listener = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $ProcessId -and $_.State -eq "Listen" }

    return [bool]$listener
}

function Get-BlockingPortProcess {
    param(
        [int]$Port
    )

    $listener = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Listen" } |
        Select-Object -First 1

    if (-not $listener) {
        return $null
    }

    return Get-ProcessSummary -ProcessId $listener.OwningProcess
}

function Test-SdrReady {
    param(
        [Parameter(Mandatory)]
        [string]$RtlTestPath
    )

    if (-not (Test-Path -LiteralPath $RtlTestPath)) {
        return [pscustomobject]@{
            Ready = $false
            Message = "rtl_test.exe was not found."
            Details = ""
        }
    }

    $output = (& cmd.exe /d /c ('"{0}" -t 2>&1' -f $RtlTestPath) | Out-String).Trim()

    if ($output -match "Found 0 device\(s\)" -or $output -match "No supported devices found") {
        return [pscustomobject]@{
            Ready = $false
            Message = "No RTL-SDR dongle detected."
            Details = $output
        }
    }

    if ($output -match "usb_claim_interface error" -or $output -match "Failed to open rtlsdr device") {
        return [pscustomobject]@{
            Ready = $false
            Message = "The RTL-SDR dongle is present but currently busy."
            Details = $output
        }
    }

    if ($output -match "Found [1-9]\d* device\(s\)") {
        return [pscustomobject]@{
            Ready = $true
            Message = "RTL-SDR dongle detected."
            Details = $output
        }
    }

    return [pscustomobject]@{
        Ready = $false
        Message = "Unable to confirm RTL-SDR availability."
        Details = $output
    }
}

function Get-RecentLogTail {
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        [int]$Lines = 40
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return ""
    }

    return (Get-Content -LiteralPath $LogPath -Tail $Lines | Out-String).Trim()
}

function Throw-StartupFailure {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $tail = Get-RecentLogTail -LogPath $LogPath

    if ($tail) {
        throw "$Message`n`nRecent log output:`n$tail"
    }

    throw $Message
}

$paths = Get-TrackerPaths

foreach ($requiredPath in @($paths.Dump1090, $paths.Config, $paths.RtlTest)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required file not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $paths.LogDir | Out-Null

$existingTracker = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1
if ($existingTracker) {
    if (-not $NoBrowser) {
        Start-Process $paths.Url
    }

    Write-Host "Flight tracker is already running at $($paths.Url)." -ForegroundColor Yellow
    return
}

$blockingProcess = Get-BlockingPortProcess -Port 8080
if ($blockingProcess) {
    throw "Port 8080 is already being used by process $($blockingProcess.Name) (PID $($blockingProcess.ProcessId)). Stop that app first, then try again."
}

$sdrStatus = Test-SdrReady -RtlTestPath $paths.RtlTest
if (-not $sdrStatus.Ready) {
    throw "$($sdrStatus.Message)`n`n$($sdrStatus.Details)"
}

$launchCommand = '/c cd /d "{0}" && dump1090.exe --config "{1}" --net' -f $paths.VendorRoot, $paths.Config

Start-Process -FilePath "cmd.exe" `
    -ArgumentList $launchCommand `
    -WindowStyle Minimized | Out-Null

$deadline = (Get-Date).AddSeconds(30)
$process = $null

do {
    Start-Sleep -Milliseconds 500

    $process = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1

    if ($process -and (Test-PortOwnedByTracker -ProcessId $process.ProcessId -Port 8080)) {
        break
    }
}
until ((Get-Date) -ge $deadline)

if (-not $process) {
    Throw-StartupFailure -Message "dump1090 exited before the local web server came up." -LogPath $paths.LogFile
}

if (-not (Test-PortOwnedByTracker -ProcessId $process.ProcessId -Port 8080)) {
    Throw-StartupFailure -Message "dump1090 started but never opened port 8080." -LogPath $paths.LogFile
}

if (-not $NoBrowser) {
    Start-Process $paths.Url
}

Write-Host "Flight tracker is running at $($paths.Url)." -ForegroundColor Green
