[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dump1090Path = Join-Path $root "vendor\Dump1090\dump1090.exe"
$beastBridgePid = Join-Path $root "logs\beast-bridge.pid"
$nativeFeederScript = Join-Path $root "scripts\Manage-NativeFeeder.ps1"

if (Test-Path -LiteralPath $nativeFeederScript) {
    foreach ($provider in @("airplanes-live", "flightaware")) {
        try {
            & powershell.exe -ExecutionPolicy Bypass -File $nativeFeederScript -Provider $provider -Action Stop | Out-Null
        }
        catch {
        }
    }
}

$trackerTargets = Get-CimInstance Win32_Process -Filter "Name = 'dump1090.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $dump1090Path }

$bridgeTargets = @()
if (Test-Path -LiteralPath $beastBridgePid) {
    $pidText = (Get-Content -LiteralPath $beastBridgePid -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($pidText -match '^\d+$') {
        $bridgeTarget = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
        if ($bridgeTarget) {
            $bridgeTargets = @($bridgeTarget)
        }
    }
}

if (-not $trackerTargets -and -not $bridgeTargets) {
    Write-Host "Flight tracker is not running."
    return
}

foreach ($target in $bridgeTargets) {
    Stop-Process -Id $target.ProcessId -Force
}

foreach ($target in $trackerTargets) {
    Stop-Process -Id $target.ProcessId -Force
}

Remove-Item -LiteralPath $beastBridgePid -Force -ErrorAction SilentlyContinue

Write-Host "Flight tracker stopped."
