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

function Convert-WindowsPathToWslPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $rest = $resolved.Substring(2).Replace("\", "/")
    return "/mnt/$drive$rest"
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

function Get-ExistingFlightAwareFeederId {
    $path = Join-Path (Get-RepoRoot) "logs\flightaware.uuid"
    if (-not (Test-Path -LiteralPath $path)) {
        return ""
    }

    $value = (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($value -match '^[0-9a-fA-F-]{36}$') {
        return $value
    }

    return ""
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

function Test-WslSystemdAvailable {
    $script = @'
if [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ] && [ -d /run/systemd/system ]; then
  echo yes
else
  echo no
fi
'@

    $result = Invoke-WslScript -ScriptContent $script
    return $result.Output -match 'yes'
}

function Repair-WslPackageState {
    $script = @'
set -e
if getent passwd uuidd >/dev/null 2>&1 && getent group uuidd >/dev/null 2>&1 && [ -f /var/lib/dpkg/info/uuid-runtime.postinst ]; then
  sed -i 's|[[:space:]]*systemd-sysusers .*uuidd-sysusers.conf|   true|' /var/lib/dpkg/info/uuid-runtime.postinst || true
fi
if [ -f /etc/apt/sources.list.d/flightaware-apt-repository.list ]; then
  mv -f /etc/apt/sources.list.d/flightaware-apt-repository.list /etc/apt/sources.list.d/flightaware-apt-repository.list.disabled || true
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
$flightAwareFeederId = Get-ExistingFlightAwareFeederId
$repoRootWsl = Convert-WindowsPathToWslPath -Path $repoRoot
$logDirWsl = Convert-WindowsPathToWslPath -Path $logDir

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
    $wslHasSystemd = Test-WslSystemdAvailable

    switch ($Provider) {
        "flightaware" {
            Write-Host "Installing FlightAware PiAware in Debian..." -ForegroundColor Cyan
            $usesManualPiaware = $false
            if ($wslInfo.Architecture -in @("arm64", "aarch64", "armhf", "armv7l") -and $wslHasSystemd) {
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
            }
            else {
                $usesManualPiaware = $true
                $script = @'
set -e
export DEBIAN_FRONTEND=noninteractive

get_git() {
  repo="$1"
  branch="$2"
  target="$3"

  if [ -d "$target/.git" ]; then
    git -C "$target" fetch --depth 1 origin "$branch"
    git -C "$target" reset --hard FETCH_HEAD
  else
    rm -rf "$target"
    git clone --depth 1 --single-branch --branch "$branch" "$repo" "$target"
  fi
}

pkill -f '/usr/bin/piaware|/usr/lib/piaware/helpers/faup1090|/usr/lib/piaware/helpers/fa-mlat-client|/usr/local/share/piaware/venv/bin/fa-mlat-client' || true

apt-get update
apt-get install -y git autoconf build-essential net-tools iproute2 tclx8.4 tcl8.6 tcllib tcl-tls itcl3 rsyslog openssl libboost-system-dev libboost-program-options-dev libboost-regex-dev libboost-filesystem-dev python3-dev python3-venv python3-pip python3-setuptools python3-wheel python3-build ca-certificates

mkdir -p /usr/local/share/piaware/src /usr/local/share/piaware
get_git "https://github.com/flightaware/piaware.git" "v10.2" "/usr/local/share/piaware/src/piaware"
get_git "https://github.com/flightaware/tcllauncher.git" "v1.10" "/usr/local/share/piaware/src/tcllauncher"
get_git "https://github.com/flightaware/dump1090.git" "v10.2" "/usr/local/share/piaware/src/dump1090"
get_git "https://github.com/mutability/mlat-client.git" "v0.2.13" "/usr/local/share/piaware/src/mlat-client"

cd /usr/local/share/piaware/src/tcllauncher
autoconf -f
./configure --prefix=/usr --with-tcl=/usr/lib/tcl8.6
make -j2
make install

cd /usr/local/share/piaware/src/dump1090
make RTLSDR=no BLADERF=no DUMP1090_VERSION="flighttracker-wsl" faup1090
install -d /usr/lib/piaware/helpers
install -m 0755 faup1090 /usr/lib/piaware/helpers/faup1090

python3 -m venv /usr/local/share/piaware/venv
. /usr/local/share/piaware/venv/bin/activate
python -m pip install --upgrade pip setuptools wheel pyasyncore
python -m pip install /usr/local/share/piaware/src/mlat-client
cat >/usr/lib/piaware/helpers/fa-mlat-client <<'EOF'
#!/bin/sh
exec /usr/local/share/piaware/venv/bin/fa-mlat-client "$@"
EOF
chmod +x /usr/lib/piaware/helpers/fa-mlat-client

cd /usr/local/share/piaware/src/piaware
make -C package PREFIX=/usr install
make -C programs/piaware PREFIX=/usr TCLLAUNCHER=/usr/bin/tcllauncher install
make -C programs/piaware-config PREFIX=/usr TCLLAUNCHER=/usr/bin/tcllauncher install
make -C programs/piaware-status PREFIX=/usr TCLLAUNCHER=/usr/bin/tcllauncher install
make -C scripts PREFIX=/usr SYSTEMD= SYSVINIT= install

cat >/etc/piaware.conf <<'EOF'
# This file configures piaware and related software.
# You can edit it directly or use piaware-config from the command line
# to view and change settings.
#
# If /boot/piaware-config.txt also exists, then settings present in
# that file will override settings in this file.
EOF
/usr/bin/piaware-config allow-auto-updates no
/usr/bin/piaware-config allow-manual-updates no
/usr/bin/piaware-config allow-mlat yes
/usr/bin/piaware-config receiver-type other
/usr/bin/piaware-config receiver-host "__HOST_IP__"
/usr/bin/piaware-config receiver-port 30005
/usr/bin/piaware-config mlat-results-format "beast,connect,localhost:30104 basestation,listen,31003"

if [ -n "__FLIGHTAWARE_FEEDER_ID__" ]; then
  /usr/bin/piaware-config feeder-id "__FLIGHTAWARE_FEEDER_ID__"
fi

mkdir -p /usr/local/share/piaware
rm -f /usr/local/share/piaware/piaware.pid
setsid /bin/bash -lc 'exec /usr/bin/piaware -plainlog -statusfile "__PIAWARE_STATUS_FILE__" >>"__PIAWARE_LOG_FILE__" 2>&1' </dev/null &
echo $! >/usr/local/share/piaware/piaware.pid
sleep 20
pgrep -f '/usr/bin/piaware -plainlog' >/dev/null

echo
echo FlightAware install complete.
echo PiAware now points at Beast on __HOST_IP__:30005 and is running directly in WSL on this Windows PC.
if [ -n "__FLIGHTAWARE_FEEDER_ID__" ]; then
  echo Claim URL: https://flightaware.com/adsb/piaware/claim/__FLIGHTAWARE_FEEDER_ID__
else
  echo Claim URL: https://flightaware.com/adsb/piaware/claim
fi
'@
                $piawareStatusFile = ($logDirWsl + "/flightaware.wsl.status.json")
                $piawareLogFile = ($logDirWsl + "/flightaware.wsl.log")
                $script = $script.Replace("__HOST_IP__", $hostIp).Replace("__FLIGHTAWARE_FEEDER_ID__", $flightAwareFeederId).Replace("__PIAWARE_STATUS_FILE__", $piawareStatusFile).Replace("__PIAWARE_LOG_FILE__", $piawareLogFile)
            }
            Invoke-WslScript -ScriptContent $script | Out-Null

            if ($usesManualPiaware) {
                $piawareStatusPath = Join-Path $logDir "flightaware.wsl.status.json"
                $nativeStatusPath = Join-Path $logDir "flightaware.status.json"
                if (Test-Path -LiteralPath $piawareStatusPath) {
                    $piawareStatus = Get-Content -LiteralPath $piawareStatusPath -Raw | ConvertFrom-Json
                    $mlatMessage = $piawareStatus.mlat.message
                    $summary = "Official PiAware is running in WSL. FlightAware: $($piawareStatus.adept.message). MLAT: $mlatMessage."
                    $payload = [ordered]@{
                        providerId = "flightaware"
                        running = $true
                        state = "connected"
                        summary = $summary
                        source = "127.0.0.1:30005"
                        target = "piaware.flightaware.com:1200"
                        lastError = ""
                        updatedAtUtc = ([DateTime]::UtcNow.ToString("o"))
                        feederId = $flightAwareFeederId
                    }

                    $payload | ConvertTo-Json | Set-Content -LiteralPath $nativeStatusPath
                }
            }
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
            if ($wslHasSystemd) {
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
INPUT="$($hostIp):30005"
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
echo The feeder now points at Beast on $($hostIp):30005 with the official airplanes.live MLAT runtime enabled for $defaultMlatName.
"@
            }
            else {
                $script = @'
set -e
export DEBIAN_FRONTEND=noninteractive

get_git() {
  repo="$1"
  branch="$2"
  target="$3"

  if [ -d "$target/.git" ]; then
    git -C "$target" fetch --depth 1 origin "$branch"
    git -C "$target" reset --hard FETCH_HEAD
  else
    rm -rf "$target"
    git clone --depth 1 --single-branch --branch "$branch" "$repo" "$target"
  fi
}

pkill -f '/usr/local/share/airplanes/(airplanes-feed\.sh|airplanes-mlat\.sh|feed-airplanes|venv/bin/mlat-client|git/(update|setup|configure)\.sh)' || true

apt-get update
apt-get install -y git wget unzip curl build-essential python3-dev python3-venv socat ncurses-dev ncurses-bin uuid-runtime zlib1g-dev zlib1g libzstd-dev libzstd1 netcat-openbsd ca-certificates pkg-config

mkdir -p /usr/local/share/airplanes
get_git "https://github.com/airplanes-live/feed.git" "main" "/usr/local/share/airplanes/git"

cat >/etc/default/airplanes <<'EOF'
INPUT="__HOST_IP__:30005"
REDUCE_INTERVAL="0.5"
USER="__MLAT_NAME__"
LATITUDE="__LAT__"
LONGITUDE="__LON__"
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

bash /usr/local/share/airplanes/git/create-uuid.sh
cp /usr/local/share/airplanes/git/scripts/*.sh /usr/local/share/airplanes/
chmod +x /usr/local/share/airplanes/*.sh

if [ ! -x /usr/local/share/airplanes/venv/bin/mlat-client ]; then
  get_git "https://github.com/airplanes-live/mlat-client" "master" "/usr/local/share/airplanes/mlat-client-git"
  rm -rf /usr/local/share/airplanes/venv
  /usr/bin/python3 -m venv /usr/local/share/airplanes/venv
  . /usr/local/share/airplanes/venv/bin/activate
  python3 -m pip install --upgrade pip setuptools wheel pyasyncore
  pip install /usr/local/share/airplanes/mlat-client-git
fi

get_git "https://github.com/airplanes-live/readsb.git" "dev" "/usr/local/share/airplanes/readsb-git"
cd /usr/local/share/airplanes/readsb-git
make clean
make -j2 AIRCRAFT_HASH_BITS=12
cp readsb /usr/local/share/airplanes/feed-airplanes

setsid /bin/bash -lc 'exec bash /usr/local/share/airplanes/airplanes-feed.sh' >/usr/local/share/airplanes/airplanes-feed.log 2>&1 </dev/null &
echo $! >/usr/local/share/airplanes/airplanes-feed.pid
sleep 4
pgrep -f '/usr/local/share/airplanes/(airplanes-feed\.sh|feed-airplanes)' >/dev/null

setsid /bin/bash -lc 'exec bash /usr/local/share/airplanes/airplanes-mlat.sh' >/usr/local/share/airplanes/airplanes-mlat.log 2>&1 </dev/null &
echo $! >/usr/local/share/airplanes/airplanes-mlat.pid
sleep 4
pgrep -f '/usr/local/share/airplanes/(airplanes-mlat\.sh|venv/bin/mlat-client)' >/dev/null

echo
echo airplanes.live install complete.
echo The feeder now points at Beast on __HOST_IP__:30005 with the official airplanes.live runtime launched directly in WSL for __MLAT_NAME__.
'@
                $script = $script.Replace("__HOST_IP__", $hostIp).Replace("__MLAT_NAME__", $defaultMlatName).Replace("__LAT__", $homePosition.Latitude).Replace("__LON__", $homePosition.Longitude)
            }

            Invoke-WslScript -ScriptContent $script | Out-Null

            $nativeStatusPath = Join-Path $logDir "airplanes-live.status.json"
            $payload = [ordered]@{
                providerId = "airplanes-live"
                running = $true
                state = "connected"
                summary = "Official airplanes.live feeder is running in WSL against Beast on 127.0.0.1:30005. MLAT is enabled in the WSL feeder."
                source = "127.0.0.1:30005"
                target = "feed.airplanes.live:30004"
                lastError = ""
                updatedAtUtc = ([DateTime]::UtcNow.ToString("o"))
            }

            $payload | ConvertTo-Json | Set-Content -LiteralPath $nativeStatusPath
        }
    }

    Write-Host ""
    Write-Host "Feeder install finished for $Provider." -ForegroundColor Green
    Write-Host "Detailed log: $logFile"
}
finally {
    Stop-Transcript | Out-Null
}
