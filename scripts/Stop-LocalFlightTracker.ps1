[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$vendorExe = Join-Path $root "vendor\Dump1090\dump1090.exe"

$targets = Get-CimInstance Win32_Process -Filter "Name = 'dump1090.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $vendorExe }

if (-not $targets) {
    Write-Host "No local dump1090 process is running from this workspace."
    return
}

foreach ($target in $targets) {
    Stop-Process -Id $target.ProcessId -Force
}

Write-Host "Local flight tracker stopped."
