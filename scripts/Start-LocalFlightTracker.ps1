[CmdletBinding()]
param(
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TrackerPaths {
    $root = Split-Path -Parent $PSScriptRoot
    $vendorRoot = Join-Path $root "vendor\Dump1090"
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    $pythonPath = $null

    if ($pythonCmd) {
        try {
            $resolvedPython = (& $pythonCmd.Source -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
            if ($resolvedPython) {
                $pythonPath = $resolvedPython.Trim()
            }
        }
        catch {
        }

        if (-not $pythonPath) {
            $pythonPath = $pythonCmd.Source
        }
    }

    return [pscustomobject]@{
        Root = $root
        VendorRoot = $vendorRoot
        Dump1090 = Join-Path $vendorRoot "dump1090.exe"
        Config = Join-Path $root "dump1090-local.cfg"
        LogDir = Join-Path $root "logs"
        LogFile = Join-Path $root "logs\dump1090.log"
        BeastBridge = Join-Path $root "scripts\Dump1090BeastBridge.py"
        BeastBridgeLog = Join-Path $root "logs\beast-bridge.log"
        BeastBridgePid = Join-Path $root "logs\beast-bridge.pid"
        Python = $pythonPath
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
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    $process = Get-ProcessSummary -ProcessId ([int]$pidText)
    if (-not $process) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }

    return $process
}

function Test-PortOwnedByProcess {
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

function Ensure-PortAvailable {
    param(
        [Parameter(Mandatory)]
        [int]$Port,
        [int]$AllowedProcessId = 0
    )

    $listener = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Listen" } |
        Select-Object -First 1

    if (-not $listener) {
        return
    }

    if ($AllowedProcessId -and $listener.OwningProcess -eq $AllowedProcessId) {
        return
    }

    $blockingProcess = Get-ProcessSummary -ProcessId $listener.OwningProcess
    throw "Port $Port is already being used by process $($blockingProcess.Name) (PID $($blockingProcess.ProcessId)). Stop that app first, then try again."
}

function Start-BeastBridge {
    param(
        [Parameter(Mandatory)]
        $Paths
    )

    if (-not $Paths.Python) {
        throw "Python was not found on PATH. Install Python 3, then try again."
    }

    $bridgeCommand = '/c start "" /min "{0}" -u "{1}" --source-host 127.0.0.1 --source-port 30002 --listen-host 127.0.0.1 --listen-port 30005 --log-file "{2}" --pid-file "{3}"' -f `
        $Paths.Python, $Paths.BeastBridge, $Paths.BeastBridgeLog, $Paths.BeastBridgePid

    Start-Process -FilePath "cmd.exe" `
        -ArgumentList $bridgeCommand `
        -WindowStyle Hidden | Out-Null
}

$paths = Get-TrackerPaths

foreach ($requiredPath in @($paths.Dump1090, $paths.Config, $paths.RtlTest, $paths.BeastBridge)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required file not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $paths.LogDir | Out-Null

$existingTracker = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1
$existingBridge = Get-BridgeProcess -PidFile $paths.BeastBridgePid | Select-Object -First 1

if ($existingTracker -and $existingBridge) {
    if ((Test-PortOwnedByProcess -ProcessId $existingTracker.ProcessId -Port 8080) -and
        (Test-PortOwnedByProcess -ProcessId $existingBridge.ProcessId -Port 30005)) {
        if (-not $NoBrowser) {
            Start-Process $paths.Url
        }

        Write-Host "Flight tracker and Beast bridge are already running." -ForegroundColor Yellow
        Write-Host "Map: $($paths.Url)"
        Write-Host "Feed outputs: AVR/raw on tcp://127.0.0.1:30002, SBS on tcp://127.0.0.1:30003, Beast on tcp://127.0.0.1:30005."
        Write-Host "The Beast bridge uses synthetic timestamps, so do not expect MLAT to work."
        return
    }
}

Ensure-PortAvailable -Port 8080 -AllowedProcessId $(if ($existingTracker) { $existingTracker.ProcessId } else { 0 })
Ensure-PortAvailable -Port 30005 -AllowedProcessId $(if ($existingBridge) { $existingBridge.ProcessId } else { 0 })

if (-not $existingTracker) {
    $sdrStatus = Test-SdrReady -RtlTestPath $paths.RtlTest
    if (-not $sdrStatus.Ready) {
        throw "$($sdrStatus.Message)`n`n$($sdrStatus.Details)"
    }

    $launchCommand = '/c cd /d "{0}" && dump1090.exe --config "{1}" --net' -f $paths.VendorRoot, $paths.Config

    Start-Process -FilePath "cmd.exe" `
        -ArgumentList $launchCommand `
        -WindowStyle Minimized | Out-Null
}

$deadline = (Get-Date).AddSeconds(30)
$trackerProcess = $existingTracker
$bridgeProcess = $existingBridge

do {
    Start-Sleep -Milliseconds 500

    $trackerProcess = Get-TrackerProcess -ExecutablePath $paths.Dump1090 | Select-Object -First 1

    if ($trackerProcess -and (Test-PortOwnedByProcess -ProcessId $trackerProcess.ProcessId -Port 8080)) {
        break
    }
}
until ((Get-Date) -ge $deadline)

if (-not $trackerProcess) {
    Throw-StartupFailure -Message "dump1090 exited before the local web server came up." -LogPath $paths.LogFile
}

if (-not (Test-PortOwnedByProcess -ProcessId $trackerProcess.ProcessId -Port 8080)) {
    Throw-StartupFailure -Message "dump1090 started but never opened port 8080." -LogPath $paths.LogFile
}

if (-not $bridgeProcess) {
    Start-BeastBridge -Paths $paths
}

$bridgeDeadline = (Get-Date).AddSeconds(20)

do {
    Start-Sleep -Milliseconds 500

    $bridgeProcess = Get-BridgeProcess -PidFile $paths.BeastBridgePid | Select-Object -First 1

    if ($bridgeProcess -and (Test-PortOwnedByProcess -ProcessId $bridgeProcess.ProcessId -Port 30005)) {
        break
    }
}
until ((Get-Date) -ge $bridgeDeadline)

if (-not $bridgeProcess) {
    Throw-StartupFailure -Message "The Beast bridge exited before opening port 30005." -LogPath $paths.BeastBridgeLog
}

if (-not (Test-PortOwnedByProcess -ProcessId $bridgeProcess.ProcessId -Port 30005)) {
    Throw-StartupFailure -Message "The Beast bridge started but never opened port 30005." -LogPath $paths.BeastBridgeLog
}

if (-not $NoBrowser) {
    Start-Process $paths.Url
}

Write-Host "Flight tracker is running at $($paths.Url)." -ForegroundColor Green
Write-Host "Feed outputs: AVR/raw on tcp://127.0.0.1:30002, SBS on tcp://127.0.0.1:30003, Beast on tcp://127.0.0.1:30005."
Write-Host "The Beast bridge uses synthetic timestamps, so it can help Beast-only feeders but should not be expected to support MLAT."

$nativeFeederScript = Join-Path $paths.Root "scripts\Manage-NativeFeeder.ps1"
if (Test-Path -LiteralPath $nativeFeederScript) {
    try {
        & powershell.exe -ExecutionPolicy Bypass -File $nativeFeederScript -Provider "airplanes-live" -Action Ensure | Out-Null
    }
    catch {
        Write-Host "Native feeder note: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
