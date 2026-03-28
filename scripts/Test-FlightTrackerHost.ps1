[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
}

function Test-CommandAvailable {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-CommandPath {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return $null
    }

    return $cmd.Source
}

function Get-RtlDevices {
    $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
        ($_.FriendlyName -match "RTL|2832|Bulk-In|DVB") -or
        ($_.InstanceId -match "VID_0BDA&PID_2838")
    }

    return $devices | Sort-Object FriendlyName -Unique
}

$os = Get-CimInstance Win32_OperatingSystem
$wslInstalled = Test-CommandAvailable -Name "wsl.exe"
$usbipdInstalled = Test-CommandAvailable -Name "usbipd.exe"
$rtlTestInstalled = Test-CommandAvailable -Name "rtl_test.exe"
$rtlDevices = Get-RtlDevices

Write-Section "Flight Tracker Host Check"
Write-Host ("Computer      : {0}" -f $env:COMPUTERNAME)
Write-Host ("OS            : {0}" -f $os.Caption)
Write-Host ("Version       : {0}" -f $os.Version)

Write-Section "Tooling"
Write-Host ("WSL installed : {0}" -f $(if ($wslInstalled) { "Yes" } else { "No" }))
if ($wslInstalled) {
    Write-Host ("WSL path      : {0}" -f (Get-CommandPath -Name "wsl.exe"))
}

Write-Host ("usbipd        : {0}" -f $(if ($usbipdInstalled) { "Yes" } else { "No" }))
if ($usbipdInstalled) {
    Write-Host ("usbipd path   : {0}" -f (Get-CommandPath -Name "usbipd.exe"))
}

Write-Host ("rtl_test      : {0}" -f $(if ($rtlTestInstalled) { "Yes" } else { "No" }))
if ($rtlTestInstalled) {
    Write-Host ("rtl_test path : {0}" -f (Get-CommandPath -Name "rtl_test.exe"))
}

Write-Section "Detected SDR Hardware"
if ($rtlDevices.Count -gt 0) {
    foreach ($device in $rtlDevices) {
        Write-Host ("Name          : {0}" -f $device.FriendlyName)
        Write-Host ("Status        : {0}" -f $device.Status)
        Write-Host ("InstanceId    : {0}" -f $device.InstanceId)
        Write-Host ""
    }
}
else {
    Write-Host "No obvious RTL-SDR device was detected in Plug and Play."
    Write-Host "That can still be okay if the dongle is unplugged or using a less obvious device name."
}

Write-Section "Recommendation"
if ($rtlDevices.Count -gt 0 -and $rtlTestInstalled) {
    Write-Host "Your Windows PC looks good for SDR testing."
}
else {
    Write-Host "Use this Windows PC mainly to confirm the dongle and driver are working."
}

Write-Host "For a reliable always-on feeder to FlightAware + Flightradar24 + airplanes.live,"
Write-Host "move the SDR to a Raspberry Pi or Debian Linux box and run the Linux feeder stack."

if (-not $wslInstalled) {
    Write-Host ""
    Write-Host "WSL is not installed. That is fine, but it is another sign this PC is better suited"
    Write-Host "as a test machine than as the final feeder host."
}
