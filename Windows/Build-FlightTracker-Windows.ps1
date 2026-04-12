[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",

    [string]$OutputRoot = "",

    [switch]$PreferExistingBuild,

    [string]$AppVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

function Get-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $normalizedPath = (Get-AbsolutePath -Path $Path).TrimEnd('\')
    $normalizedRoot = (Get-AbsolutePath -Path $Root).TrimEnd('\')

    return $normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Reset-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $resolvedPath = Get-AbsolutePath -Path $Path
    $resolvedRoot = Get-AbsolutePath -Path $AllowedRoot

    if (-not (Test-PathWithin -Path $resolvedPath -Root $resolvedRoot)) {
        throw "Refusing to clear '$resolvedPath' because it is outside '$resolvedRoot'."
    }

    if (Test-Path -LiteralPath $resolvedPath) {
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $resolvedPath | Out-Null
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Missing directory '$Source'."
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Test-DotNetSdkAvailable {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        return $false
    }

    $sdkList = & $dotnet.Source --list-sdks 2>$null
    return ($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace(($sdkList | Out-String)))
}

function Find-InnoSetupCompiler {
    $candidates = @(
        "ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }

        if (Test-Path -LiteralPath $candidate) {
            return (Get-AbsolutePath -Path $candidate)
        }
    }

    return $null
}

function Build-WindowsInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompilerPath,

        [Parameter(Mandatory = $true)]
        [string]$InstallerScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$OutputBaseFilename
    )

    $arguments = @(
        "/Qp",
        "/DAppVersion=$Version",
        "/DSourceDir=$SourceDirectory",
        "/DOutputDir=$OutputDirectory",
        "/DOutputBaseFilename=$OutputBaseFilename",
        $InstallerScriptPath
    )

    & $CompilerPath @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed."
    }
}

function Publish-OrCopyBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $true)]
        [string]$Framework,

        [Parameter(Mandatory = $true)]
        [string]$FallbackBuildPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [bool]$CanPublish
    )

    Reset-Directory -Path $DestinationPath -AllowedRoot $packageRoot

    if ($CanPublish) {
        $publishArgs = @(
            "publish",
            $ProjectPath,
            "-c", $Configuration,
            "-f", $Framework,
            "-r", "win-x64",
            "--self-contained", "true",
            "/p:PublishSingleFile=true",
            "/p:IncludeNativeLibrariesForSelfExtract=true",
            "/p:DebugType=None",
            "/p:DebugSymbols=false",
            "-o", $DestinationPath
        )

        & dotnet @publishArgs | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed for '$ProjectPath'."
        }

        return "self-contained publish"
    }

    if (-not (Test-Path -LiteralPath $FallbackBuildPath)) {
        throw "No .NET SDK was found and the existing build output is missing: '$FallbackBuildPath'."
    }

    Copy-DirectoryContents -Source $FallbackBuildPath -Destination $DestinationPath
    return "existing framework-dependent build"
}

$repoRoot = Get-AbsolutePath -Path (Join-Path $PSScriptRoot "..")
$distRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    Join-Path $repoRoot "dist\windows"
} else {
    Get-AbsolutePath -Path $OutputRoot
}

$packageRoot = Join-Path $distRoot "FlightTracker"
$desktopRoot = Join-Path $packageRoot "Desktop"
$dashboardRoot = Join-Path $packageRoot "DashboardHost"
$logsRoot = Join-Path $packageRoot "logs"
$zipPath = Join-Path $distRoot "FlightTracker-Windows.zip"
$setupPath = Join-Path $distRoot "FlightTracker-Setup.exe"
$installerScriptPath = Join-Path $PSScriptRoot "FlightTracker-Installer.iss"

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
Reset-Directory -Path $packageRoot -AllowedRoot $distRoot

$dotnetSdkAvailable = (Test-DotNetSdkAvailable) -and (-not $PreferExistingBuild.IsPresent)

$desktopMode = Publish-OrCopyBuild `
    -ProjectPath (Join-Path $repoRoot "apps\windows\FlightTracker\FlightTracker.csproj") `
    -Framework "net8.0-windows" `
    -FallbackBuildPath (Join-Path $repoRoot "apps\windows\FlightTracker\bin\$Configuration\net8.0-windows") `
    -DestinationPath $desktopRoot `
    -CanPublish $dotnetSdkAvailable

$dashboardMode = Publish-OrCopyBuild `
    -ProjectPath (Join-Path $repoRoot "apps\windows\DashboardHost\DashboardHost.csproj") `
    -Framework "net8.0" `
    -FallbackBuildPath (Join-Path $repoRoot "apps\windows\DashboardHost\bin\$Configuration\net8.0") `
    -DestinationPath $dashboardRoot `
    -CanPublish $dotnetSdkAvailable

Copy-DirectoryContents -Source (Join-Path $repoRoot "scripts") -Destination (Join-Path $packageRoot "scripts")
Copy-DirectoryContents -Source (Join-Path $repoRoot "vendor") -Destination (Join-Path $packageRoot "vendor")
Copy-DirectoryContents -Source (Join-Path $repoRoot "feeders") -Destination (Join-Path $packageRoot "feeders")
Copy-DirectoryContents -Source (Join-Path $repoRoot "docs") -Destination (Join-Path $packageRoot "docs")
Copy-DirectoryContents -Source (Join-Path $repoRoot "macOS") -Destination (Join-Path $packageRoot "macOS")

New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination (Join-Path $packageRoot "README.md") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "dump1090-local.cfg") -Destination (Join-Path $packageRoot "dump1090-local.cfg") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "flight-tracker-root.marker") -Destination (Join-Path $packageRoot "flight-tracker-root.marker") -Force

$windowsLauncher = @"
@echo off
setlocal
start "" "%~dp0Desktop\FlightTracker.exe"
"@

$browserLauncher = @"
@echo off
setlocal
start "" "%~dp0DashboardHost\FlightTrackerDashboard.exe"
"@

Set-Content -LiteralPath (Join-Path $packageRoot "Run-FlightTracker-Windows.cmd") -Value $windowsLauncher
Set-Content -LiteralPath (Join-Path $packageRoot "Run-FlightTracker-Browser.cmd") -Value $browserLauncher

$packageReadme = @"
Flight Tracker Windows package
==============================

Simple launchers:
  Run-FlightTracker-Windows.cmd
  Run-FlightTracker-Browser.cmd

Desktop launcher:
  Desktop\FlightTracker.exe

Browser dashboard host:
  DashboardHost\FlightTrackerDashboard.exe

Package mode:
  Desktop app: $desktopMode
  Dashboard host: $dashboardMode

Notes:
  - If package mode says 'existing framework-dependent build', install the .NET 8 Desktop Runtime
    and ASP.NET Core Runtime on the target Windows machine before launching the EXEs.
  - All supporting scripts, feeder configs, and SDR binaries are bundled beside the EXEs in this folder.
  - Friendly docs are included in the docs folder.
  - The Mac launcher URL template is available in macOS\flight-tracker-url.txt.
"@

Set-Content -LiteralPath (Join-Path $packageRoot "PACKAGE-README.txt") -Value $packageReadme

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal

$innoCompiler = Find-InnoSetupCompiler
$installerMode = "not built (Inno Setup not found)"

if ($innoCompiler) {
    if (Test-Path -LiteralPath $setupPath) {
        Remove-Item -LiteralPath $setupPath -Force
    }

    Build-WindowsInstaller `
        -CompilerPath $innoCompiler `
        -InstallerScriptPath $installerScriptPath `
        -SourceDirectory $packageRoot `
        -OutputDirectory $distRoot `
        -Version $AppVersion `
        -OutputBaseFilename "FlightTracker-Setup"

    if (-not (Test-Path -LiteralPath $setupPath)) {
        throw "Expected installer output was not created: '$setupPath'."
    }

    $installerMode = "Inno Setup installer"
}

Write-Host ""
Write-Host "Flight Tracker package created:"
Write-Host "  $packageRoot"
Write-Host ""
Write-Host "Desktop EXE:"
Write-Host "  $(Join-Path $desktopRoot 'FlightTracker.exe')"
Write-Host ""
Write-Host "Dashboard host EXE:"
Write-Host "  $(Join-Path $dashboardRoot 'FlightTrackerDashboard.exe')"
Write-Host ""
Write-Host "Download ZIP:"
Write-Host "  $zipPath"
Write-Host ""
Write-Host "Installer EXE:"
Write-Host "  $setupPath"
Write-Host ""
Write-Host "Desktop build mode: $desktopMode"
Write-Host "Dashboard build mode: $dashboardMode"
Write-Host "Installer mode: $installerMode"
