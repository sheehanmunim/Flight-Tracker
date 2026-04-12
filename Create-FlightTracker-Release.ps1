[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Remote = "origin",

    [switch]$SkipBranchPush,

    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$markerPath = Join-Path $repoRoot "flight-tracker-root.marker"

if (-not (Test-Path -LiteralPath $markerPath)) {
    throw "This script must be run from the Flight Tracker repo root."
}

Push-Location $repoRoot
try {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        throw "Git is required to create a release tag."
    }

    $normalizedVersion = $Version.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        throw "Version cannot be empty."
    }

    if ($normalizedVersion.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedVersion = $normalizedVersion.Substring(1)
    }

    $tagName = "v$normalizedVersion"

    $dirtyStatus = git status --short
    if (($LASTEXITCODE -ne 0) -or ($null -eq $dirtyStatus)) {
        throw "Unable to read git status."
    }

    if ((-not $AllowDirty.IsPresent) -and -not [string]::IsNullOrWhiteSpace(($dirtyStatus | Out-String).Trim())) {
        throw "Working tree is not clean. Commit or stash changes first, or rerun with -AllowDirty."
    }

    $existingTag = git tag --list $tagName
    if (($LASTEXITCODE -ne 0) -or ($null -eq $existingTag)) {
        throw "Unable to query existing git tags."
    }

    if (-not [string]::IsNullOrWhiteSpace(($existingTag | Out-String).Trim())) {
        throw "Tag '$tagName' already exists."
    }

    $branchName = git rev-parse --abbrev-ref HEAD
    $branchNameText = ($branchName | Out-String).Trim()
    if (($LASTEXITCODE -ne 0) -or [string]::IsNullOrWhiteSpace($branchNameText)) {
        throw "Unable to determine current branch."
    }

    Invoke-Git tag -a $tagName -m "Release $tagName"

    if (-not $SkipBranchPush.IsPresent) {
        Invoke-Git push $Remote HEAD
    }

    Invoke-Git push $Remote "refs/tags/$tagName"

    Write-Host ""
    Write-Host "Release tag pushed:"
    Write-Host "  $tagName"
    Write-Host ""
    Write-Host "GitHub Actions will now build and publish:"
    Write-Host "  FlightTracker-Setup.exe"
    Write-Host "  FlightTracker-Windows.zip"
    Write-Host "  FlightTracker.dmg (Apple Silicon compatible)"
    Write-Host ""
    Write-Host "Branch pushed:"
    Write-Host "  $branchNameText"
}
finally {
    Pop-Location
}
