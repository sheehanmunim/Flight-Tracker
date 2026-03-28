[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dump1090Path = Join-Path $root "vendor\Dump1090\dump1090.exe"

$targets = Get-CimInstance Win32_Process -Filter "Name = 'dump1090.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $dump1090Path }

if (-not $targets) {
    Write-Host "Flight tracker is not running."
    return
}

foreach ($target in $targets) {
    Stop-Process -Id $target.ProcessId -Force
}

Write-Host "Flight tracker stopped."

