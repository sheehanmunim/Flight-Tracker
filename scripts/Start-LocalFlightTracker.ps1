[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$root = Split-Path -Parent $PSScriptRoot
$vendorRoot = Join-Path $root "vendor\Dump1090"
$configPath = Join-Path $root "dump1090-local.cfg"
$logDir = Join-Path $root "logs"
$url = "http://localhost:8080"
$dump1090Path = Join-Path $vendorRoot "dump1090.exe"
$startupDeadline = (Get-Date).AddSeconds(90)

if (-not (Test-Path -LiteralPath $vendorRoot)) {
    throw "Bundled decoder not found at '$vendorRoot'."
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found at '$configPath'."
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-IsAdministrator)) {
    Write-Host "Requesting Administrator access so Windows will allow SDR device access..." -ForegroundColor Yellow
    $arguments = @(
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath)
    )
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments
    return
}

$existing = Get-CimInstance Win32_Process -Filter "Name = 'dump1090.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $dump1090Path }

if ($existing) {
    Write-Host "dump1090 is already running. Opening the local map..." -ForegroundColor Yellow
    Start-Process $url
    return
}

$process = Start-Process -FilePath $dump1090Path `
    -ArgumentList @("--config", $configPath, "--net") `
    -WorkingDirectory $vendorRoot `
    -PassThru

do {
    Start-Sleep -Seconds 2

    if ($process.HasExited) {
        throw "dump1090 exited early. Check logs\\dump1090.log for details."
    }

    $listener = Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -eq 8080 -and $_.OwningProcess -eq $process.Id }
}
until ($listener -or (Get-Date) -ge $startupDeadline)

if (-not $listener) {
    throw "dump1090 started but port 8080 did not come up within 90 seconds."
}

Start-Process $url
Write-Host "Local flight tracker started. Open $url if your browser did not launch automatically." -ForegroundColor Green
