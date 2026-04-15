[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("airplanes-live", "flightaware", "flightradar24")]
    [string]$Provider,

    [ValidateSet("Connect", "Disconnect", "Ensure", "Stop", "Status")]
    [string]$Action = "Status"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NativeFeederPaths {
    $root = Split-Path -Parent $PSScriptRoot
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
        LogDir = Join-Path $root "logs"
        Runtime = Join-Path $root "scripts\NativeFeederRuntime.py"
        StartScript = Join-Path $root "scripts\Start-LocalFlightTracker.ps1"
        Python = $pythonPath
    }
}

function Get-ProviderSpec {
    param(
        [Parameter(Mandatory)]
        [string]$Provider
    )

    switch ($Provider.ToLowerInvariant()) {
        "airplanes-live" {
            return [pscustomobject]@{
                Provider = $Provider
                Supported = $true
                DisplayName = "airplanes.live"
                SourceHost = "127.0.0.1"
                SourcePort = 30005
                TargetHost = "feed.airplanes.live"
                TargetPort = 30004
            }
        }
        "flightaware" {
            return [pscustomobject]@{
                Provider = $Provider
                Supported = $true
                DisplayName = "FlightAware"
                SourceHost = "127.0.0.1"
                SourcePort = 30003
                TargetHost = "piaware.flightaware.com"
                TargetPort = 1200
            }
        }
        "flightradar24" {
            return [pscustomobject]@{
                Provider = $Provider
                Supported = $false
                DisplayName = "Flightradar24"
                Message = "A native Flightradar24 host connector is not implemented in this repo yet."
            }
        }
        default {
            throw "Unknown provider: $Provider"
        }
    }
}

function Get-ProviderPaths {
    param(
        [Parameter(Mandatory)]
        $Paths,
        [Parameter(Mandatory)]
        $Spec
    )

    return [pscustomobject]@{
        EnabledMarker = Join-Path $Paths.LogDir "$($Spec.Provider).enabled"
        PidFile = Join-Path $Paths.LogDir "$($Spec.Provider).pid"
        LogFile = Join-Path $Paths.LogDir "$($Spec.Provider).log"
        StatusFile = Join-Path $Paths.LogDir "$($Spec.Provider).status.json"
        UuidFile = Join-Path $Paths.LogDir "$($Spec.Provider).uuid"
    }
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

function Get-RunningProcess {
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
        return $null
    }

    return $process
}

function Write-StatusFile {
    param(
        [Parameter(Mandatory)]
        [string]$StatusFile,
        [Parameter(Mandatory)]
        [string]$Provider,
        [Parameter(Mandatory)]
        [string]$State,
        [Parameter(Mandatory)]
        [string]$Summary,
        [bool]$Running = $false,
        [string]$LastError = "",
        [string]$Source = "",
        [string]$Target = ""
    )

    $payload = [ordered]@{
        providerId = $Provider
        running = $Running
        state = $State
        summary = $Summary
        source = $Source
        target = $Target
        lastError = $LastError
        updatedAtUtc = ([DateTime]::UtcNow.ToString("o"))
    }

    $payload | ConvertTo-Json | Set-Content -LiteralPath $StatusFile
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

function Ensure-UuidFile {
    param(
        [Parameter(Mandatory)]
        [string]$UuidFile
    )

    if (-not (Test-Path -LiteralPath $UuidFile)) {
        [guid]::NewGuid().ToString() | Set-Content -LiteralPath $UuidFile
    }
}

function Initialize-ProviderState {
    param(
        [Parameter(Mandatory)]
        $Spec,
        [Parameter(Mandatory)]
        $ProviderPaths
    )

    if ($Spec.Provider -eq "airplanes-live") {
        Ensure-UuidFile -UuidFile $ProviderPaths.UuidFile
    }
}

function Start-ProviderProcess {
    param(
        [Parameter(Mandatory)]
        $Paths,
        [Parameter(Mandatory)]
        $Spec,
        [Parameter(Mandatory)]
        $ProviderPaths
    )

    if (-not $Paths.Python) {
        throw "Python 3 was not found on PATH, so the native feeder runtime cannot start."
    }

    if (-not (Test-Path -LiteralPath $Paths.Runtime)) {
        throw "Native feeder runtime not found: $($Paths.Runtime)"
    }

    $existing = Get-RunningProcess -PidFile $ProviderPaths.PidFile
    if ($existing) {
        return $existing
    }

    Initialize-ProviderState -Spec $Spec -ProviderPaths $ProviderPaths

    $arguments = @(
        "-u"
        $Paths.Runtime
        "--provider"
        $Spec.Provider
        "--source-host"
        $Spec.SourceHost
        "--source-port"
        "$($Spec.SourcePort)"
        "--target-host"
        $Spec.TargetHost
        "--target-port"
        "$($Spec.TargetPort)"
        "--uuid-file"
        $ProviderPaths.UuidFile
        "--log-file"
        $ProviderPaths.LogFile
        "--status-file"
        $ProviderPaths.StatusFile
    )

    $argumentString = ($arguments | ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') {
            '"' + ($value -replace '"', '\"') + '"'
        }
        else {
            $value
        }
    }) -join ' '

    $process = Start-Process -FilePath $Paths.Python -ArgumentList $argumentString -WorkingDirectory $Paths.Root -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $ProviderPaths.PidFile -Value $process.Id

    Start-Sleep -Seconds 2
    $confirmed = Get-RunningProcess -PidFile $ProviderPaths.PidFile
    if (-not $confirmed) {
        $tail = Get-RecentLogTail -LogPath $ProviderPaths.LogFile
        if ($tail) {
            throw "The native feeder runtime exited during startup.`n`nRecent log output:`n$tail"
        }

        throw "The native feeder runtime exited during startup."
    }

    return $confirmed
}

function Connect-Provider {
    param(
        [Parameter(Mandatory)]
        $Paths,
        [Parameter(Mandatory)]
        $Spec,
        [Parameter(Mandatory)]
        $ProviderPaths
    )

    New-Item -ItemType Directory -Force -Path $Paths.LogDir | Out-Null
    Set-Content -LiteralPath $ProviderPaths.EnabledMarker -Value "enabled"

    $existingProcess = Get-RunningProcess -PidFile $ProviderPaths.PidFile

    if (-not $existingProcess) {
        Write-StatusFile `
            -StatusFile $ProviderPaths.StatusFile `
            -Provider $Spec.Provider `
            -State "starting" `
            -Summary "$($Spec.DisplayName) is starting on this host." `
            -Source "$($Spec.SourceHost):$($Spec.SourcePort)" `
            -Target "$($Spec.TargetHost):$($Spec.TargetPort)"
    }

    $trackerRunning = Get-NetTCPConnection -LocalPort $Spec.SourcePort -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Listen" } |
        Select-Object -First 1

    if (-not $trackerRunning) {
        Write-Host "Starting the local tracker first so the Beast source is available..." -ForegroundColor Yellow
        & powershell.exe -ExecutionPolicy Bypass -File $Paths.StartScript -NoBrowser | Out-Null
    }

    $process = if ($existingProcess) {
        $existingProcess
    }
    else {
        Start-ProviderProcess -Paths $Paths -Spec $Spec -ProviderPaths $ProviderPaths
    }

    $processId = $process.ProcessId
    if (-not $processId) {
        $processId = $process.Id
    }

    Write-Host "$($Spec.DisplayName) native feeder enabled on this host." -ForegroundColor Green
    Write-Host "Process ID: $processId"
    Write-Host "Source: tcp://$($Spec.SourceHost):$($Spec.SourcePort)"
    Write-Host "Target: $($Spec.TargetHost):$($Spec.TargetPort)"
    Write-Host "Log: $($ProviderPaths.LogFile)"
}

function Stop-Provider {
    param(
        [Parameter(Mandatory)]
        $Spec,
        [Parameter(Mandatory)]
        $ProviderPaths,
        [switch]$KeepEnabled
    )

    $process = Get-RunningProcess -PidFile $ProviderPaths.PidFile
    if ($process) {
        Stop-Process -Id $process.ProcessId -Force
    }

    Remove-Item -LiteralPath $ProviderPaths.PidFile -Force -ErrorAction SilentlyContinue

    if (-not $KeepEnabled) {
        Remove-Item -LiteralPath $ProviderPaths.EnabledMarker -Force -ErrorAction SilentlyContinue
    }

    Write-StatusFile `
        -StatusFile $ProviderPaths.StatusFile `
        -Provider $Spec.Provider `
        -State "stopped" `
        -Summary "$($Spec.DisplayName) is disconnected on this host." `
        -Source "$($Spec.SourceHost):$($Spec.SourcePort)" `
        -Target "$($Spec.TargetHost):$($Spec.TargetPort)"

    Write-Host "$($Spec.DisplayName) native feeder stopped."
}

function Show-ProviderStatus {
    param(
        [Parameter(Mandatory)]
        $Spec,
        [Parameter(Mandatory)]
        $ProviderPaths
    )

    $enabled = Test-Path -LiteralPath $ProviderPaths.EnabledMarker
    $process = Get-RunningProcess -PidFile $ProviderPaths.PidFile
    $statusPayload = $null

    if (Test-Path -LiteralPath $ProviderPaths.StatusFile) {
        try {
            $statusPayload = Get-Content -LiteralPath $ProviderPaths.StatusFile -Raw | ConvertFrom-Json
        }
        catch {
            $statusPayload = $null
        }
    }

    if ($process) {
        Write-Host "$($Spec.DisplayName): connected on host (PID $($process.ProcessId))" -ForegroundColor Green
    } elseif ($statusPayload -and $statusPayload.running) {
        Write-Host "$($Spec.DisplayName): official feeder active" -ForegroundColor Green
    } elseif ($enabled) {
        Write-Host "$($Spec.DisplayName): enabled, waiting for host connector" -ForegroundColor Yellow
    } else {
        Write-Host "$($Spec.DisplayName): not connected" -ForegroundColor Yellow
    }

    Write-Host "Source: tcp://$($Spec.SourceHost):$($Spec.SourcePort)"
    Write-Host "Target: $($Spec.TargetHost):$($Spec.TargetPort)"

    if ($statusPayload) {
        Write-Host ""
        Write-Host "Runtime status:"
        $statusPayload | ConvertTo-Json
    }
}

$paths = Get-NativeFeederPaths
$spec = Get-ProviderSpec -Provider $Provider

if (-not $spec.Supported) {
    if ($Action -eq "Status") {
        Write-Host $spec.Message -ForegroundColor Yellow
        return
    }

    throw $spec.Message
}

$providerPaths = Get-ProviderPaths -Paths $paths -Spec $spec
New-Item -ItemType Directory -Force -Path $paths.LogDir | Out-Null

switch ($Action) {
    "Connect" {
        Connect-Provider -Paths $paths -Spec $spec -ProviderPaths $providerPaths
    }
    "Disconnect" {
        Stop-Provider -Spec $spec -ProviderPaths $providerPaths
    }
    "Ensure" {
        if (Test-Path -LiteralPath $providerPaths.EnabledMarker) {
            Connect-Provider -Paths $paths -Spec $spec -ProviderPaths $providerPaths
        } else {
            Write-Host "$($spec.DisplayName) is not enabled on this host."
        }
    }
    "Stop" {
        Stop-Provider -Spec $spec -ProviderPaths $providerPaths -KeepEnabled
    }
    "Status" {
        Show-ProviderStatus -Spec $spec -ProviderPaths $providerPaths
    }
}
