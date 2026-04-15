[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("flightaware", "flightradar24", "airplanes-live")]
    [string]$Provider
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Get-LanHost {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp,Manual -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -ExpandProperty IPAddress

    $first = $addresses | Select-Object -First 1
    if ($first) {
        return $first
    }

    return "127.0.0.1"
}

function Invoke-Wsl {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $escapedArguments = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        }
        else {
            $_
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = ($escapedArguments -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $output = (($stdout, $stderr) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd() }) -join [Environment]::NewLine
    $exitCode = $process.ExitCode

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw ($output.Trim())
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output.Trim()
    }
}

function Ensure-WslReady {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw "WSL is not installed on this Windows receiver PC."
    }

    $status = Invoke-Wsl -Arguments @("--status") -IgnoreExitCode
    if ($status.Output -match "kernel file is not found") {
        Write-Host "WSL kernel is missing. Attempting to update it..." -ForegroundColor Yellow
        $update = Invoke-Wsl -Arguments @("--update") -IgnoreExitCode
        if ($update.ExitCode -ne 0) {
            throw ("WSL could not update the kernel automatically.`n`n{0}" -f $update.Output)
        }
    }

    $list = Invoke-Wsl -Arguments @("-l", "-q") -IgnoreExitCode
    $distro = $list.Output -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    if ($distro -notcontains "Debian") {
        Write-Host "Debian is not installed in WSL. Starting automatic Debian installation..." -ForegroundColor Yellow
        $install = Invoke-Wsl -Arguments @("--install", "-d", "Debian") -IgnoreExitCode
        if ($install.ExitCode -ne 0) {
            throw ("WSL could not install Debian automatically.`n`n{0}" -f $install.Output)
        }

        throw "Debian installation has been started. Windows may need to finish the first Debian setup before feeder installation can continue. Run the install button again after Debian is available in WSL."
    }
}

function Ensure-WslSystemd {
    $script = @'
set -e
mkdir -p /etc
if [ ! -f /etc/wsl.conf ] || ! grep -q "systemd=true" /etc/wsl.conf; then
  cat >/etc/wsl.conf <<'EOF'
[boot]
systemd=true
EOF
  echo CHANGED
else
  echo OK
fi
'@

    $temp = Join-Path $env:TEMP "flight-tracker-systemd.sh"
    [System.IO.File]::WriteAllText($temp, ($script -replace "`r`n?", "`n"), [System.Text.Encoding]::ASCII)
    try {
        $linuxTemp = "/mnt/" + $temp.Substring(0, 1).ToLower() + $temp.Substring(2).Replace("\", "/")
        $result = Invoke-Wsl -Arguments @("-d", "Debian", "-u", "root", "--", "bash", $linuxTemp)
        if ($result.Output -match "CHANGED") {
            Invoke-Wsl -Arguments @("--terminate", "Debian") -IgnoreExitCode | Out-Null
            Start-Sleep -Seconds 2
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WslScript {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptContent
    )

    $temp = Join-Path $env:TEMP ("flight-tracker-{0}.sh" -f ([guid]::NewGuid().ToString("N")))
    [System.IO.File]::WriteAllText($temp, ($ScriptContent -replace "`r`n?", "`n"), [System.Text.Encoding]::ASCII)

    try {
        $linuxTemp = "/mnt/" + $temp.Substring(0, 1).ToLower() + $temp.Substring(2).Replace("\", "/")
        return Invoke-Wsl -Arguments @("-d", "Debian", "-u", "root", "--", "bash", $linuxTemp)
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-TrackerRunning {
    $startScript = Join-Path (Get-RepoRoot) "scripts\Start-LocalFlightTracker.ps1"
    & powershell.exe -ExecutionPolicy Bypass -File $startScript -NoBrowser | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The local tracker could not be started, so feeder installation cannot continue."
    }
}

function Get-HomePosition {
    $configPath = Join-Path (Get-RepoRoot) "dump1090-local.cfg"
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ($line -match '^\s*homepos\s*=\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*$') {
            return [pscustomobject]@{
                Latitude = $matches[1]
                Longitude = $matches[2]
            }
        }
    }

    return $null
}

function Get-DefaultMlatName {
    $raw = ("{0}-{1}" -f $env:USERNAME, $env:COMPUTERNAME).ToLowerInvariant()
    return (($raw -replace '[^a-z0-9_-]', '-') -replace '-{2,}', '-').Trim('-')
}

function Get-WslDebianInfo {
    $script = @'
source /etc/os-release
printf "VERSION_ID=%s\n" "$VERSION_ID"
printf "VERSION_CODENAME=%s\n" "$VERSION_CODENAME"
printf "ARCH=%s\n" "$(uname -m)"
'@

    $result = Invoke-WslScript -ScriptContent $script
    $map = @{}
    foreach ($line in ($result.Output -split "[`r`n]+")) {
        if ($line -match '^([^=]+)=(.*)$') {
            $map[$matches[1]] = $matches[2]
        }
    }

    return [pscustomobject]@{
        VersionId = $map["VERSION_ID"]
        VersionCodeName = $map["VERSION_CODENAME"]
        Architecture = $map["ARCH"]
    }
}

function Repair-WslPackageState {
    $script = @'
set -e
if getent passwd uuidd >/dev/null 2>&1 && getent group uuidd >/dev/null 2>&1 && [ -f /var/lib/dpkg/info/uuid-runtime.postinst ]; then
  sed -i 's|[[:space:]]*systemd-sysusers .*uuidd-sysusers.conf|   true|' /var/lib/dpkg/info/uuid-runtime.postinst || true
fi
dpkg --configure -a || true
'@

    Invoke-WslScript -ScriptContent $script | Out-Null
}

function Stop-NativeConnectorIfPresent {
    param(
        [Parameter(Mandatory)]
        [string]$Provider
    )

    if ($Provider -notin @("flightaware", "airplanes-live")) {
        return
    }

    $nativeScript = Join-Path (Get-RepoRoot) "scripts\Manage-NativeFeeder.ps1"
    if (-not (Test-Path -LiteralPath $nativeScript)) {
        return
    }

    try {
        Write-Host "Stopping the lightweight Windows feeder for $Provider before the official install takes over..." -ForegroundColor Cyan
        & powershell.exe -ExecutionPolicy Bypass -File $nativeScript -Provider $Provider -Action Disconnect | Out-Null
    }
    catch {
        Write-Host "The lightweight Windows feeder for $Provider could not be stopped cleanly. Continuing with the official install..." -ForegroundColor Yellow
    }
}

$repoRoot = Get-RepoRoot
$logDir = Join-Path $repoRoot "logs"
$logFile = Join-Path $logDir ("feeder-install-{0}.log" -f $Provider)
$hostIp = Get-LanHost
$homePosition = Get-HomePosition
$defaultMlatName = Get-DefaultMlatName

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Start-Transcript -Path $logFile -Append | Out-Null
try {
    Write-Host "Preparing the Windows tracker feed..." -ForegroundColor Cyan
    Ensure-TrackerRunning

    Write-Host "Checking WSL and Debian..." -ForegroundColor Cyan
    Ensure-WslReady
    Ensure-WslSystemd
    Repair-WslPackageState
    Stop-NativeConnectorIfPresent -Provider $Provider

    $wslInfo = Get-WslDebianInfo

    switch ($Provider) {
        "flightaware" {
            if ($wslInfo.Architecture -notin @("arm64", "aarch64", "armhf", "armv7l")) {
                throw ("FlightAware's official PiAware packages are ARM-only, and this WSL Debian install is {0} on {1}. " +
                    "Quick Connect still works for ADS-B uploads on Windows, but full FlightAware MLAT needs a supported ARM Linux environment.") -f $wslInfo.VersionCodeName, $wslInfo.Architecture
            }

            Write-Host "Installing FlightAware PiAware in Debian..." -ForegroundColor Cyan
            $script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
cd /tmp
apt-get update
apt-get install -y wget ca-certificates
wget -q https://www.flightaware.com/adsb/piaware/files/packages/pool/piaware/f/flightaware-apt-repository/flightaware-apt-repository_1.2_all.deb
dpkg -i flightaware-apt-repository_1.2_all.deb
apt-get update
apt-get install -y piaware
piaware-config receiver-type relay
piaware-config receiver-host $hostIp
piaware-config receiver-port 30005
piaware-config allow-mlat yes
piaware-config allow-auto-updates yes
piaware-config allow-manual-updates yes
systemctl enable piaware
systemctl restart piaware
piaware-status || true
echo
echo FlightAware install complete.
echo PiAware now points at Beast on $hostIp:30005 with MLAT enabled.
"@
            Invoke-WslScript -ScriptContent $script | Out-Null
        }

        "flightradar24" {
            Write-Host "Installing Flightradar24 feeder in Debian..." -ForegroundColor Cyan
            $script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
cd /tmp
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL https://fr24.com/install.sh -o fr24-install.sh
bash fr24-install.sh -a -s ADSB
cat >/etc/fr24feed.ini <<'EOF'
receiver="avr-tcp"
host="$hostIp:30002"
raw="no"
bs="no"
mlat="no"
mlat-without-gps="no"
fr24key=""
EOF
systemctl disable --now fr24feed || true
echo
echo Flightradar24 package install complete.
echo The receiver source is prefilled as avr-tcp on $hostIp:30002.
echo A real FR24 sharing key is still required before the feeder can start.
"@
            Invoke-WslScript -ScriptContent $script | Out-Null
        }

        "airplanes-live" {
            if (-not $homePosition) {
                throw "No receiver home position was found in dump1090-local.cfg, so the airplanes.live MLAT install cannot be completed automatically yet."
            }

            Write-Host "Installing airplanes.live feeder in Debian..." -ForegroundColor Cyan
            $script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
pkill -f '/usr/local/share/airplanes/git/(update|setup|configure)\.sh' || true
apt-get update
apt-get install -y git curl ca-certificates
mkdir -p /usr/local/share/airplanes
rm -rf /usr/local/share/airplanes/git
git clone --depth 1 https://github.com/airplanes-live/feed.git /usr/local/share/airplanes/git
cat >/etc/default/airplanes <<'EOF'
INPUT="${hostIp}:30005"
REDUCE_INTERVAL="0.5"
USER="$defaultMlatName"
LATITUDE="$($homePosition.Latitude)"
LONGITUDE="$($homePosition.Longitude)"
ALTITUDE="0"
UAT_INPUT="127.0.0.1:30978"
RESULTS="--results beast,connect,127.0.0.1:30104"
RESULTS2="--results basestation,listen,31015"
RESULTS3="--results beast,listen,30157"
RESULTS4="--results beast,connect,127.0.0.1:30187"
PRIVACY=""
INPUT_TYPE="dump1090"
MLATSERVER="feed.airplanes.live:31090"
TARGET="--net-connector feed.airplanes.live,30004,beast_reduce_plus_out,feed.airplanes.live,64004"
NET_OPTIONS="--net-heartbeat 60 --net-ro-size 1280 --net-ro-interval 0.2 --net-ro-port 0 --net-sbs-port 0 --net-bi-port 30187 --net-bo-port 0 --net-ri-port 0 --write-json-every 1 --uuid-file /usr/local/share/airplanes/airplanes-uuid"
JSON_OPTIONS="--max-range 450 --json-location-accuracy 2 --range-outline-hours 24"
EOF
bash /usr/local/share/airplanes/git/update.sh
echo
echo airplanes.live install complete.
echo The feeder now points at Beast on ${hostIp}:30005 with the official airplanes.live MLAT runtime enabled for $defaultMlatName.
"@
            Invoke-WslScript -ScriptContent $script | Out-Null
        }
    }

    Write-Host ""
    Write-Host "Feeder install finished for $Provider." -ForegroundColor Green
    Write-Host "Detailed log: $logFile"
}
finally {
    Stop-Transcript | Out-Null
}
