<#
.SYNOPSIS
    Canonical entrypoint for running Pester v5 tests in automation-suite.

.DESCRIPTION
    Runs tests using the vendored Pester v5.7.1 under Windows PowerShell 5.1.
    By default, runs unit tests only. Use switches to include integration or optional tooling tests.

.PARAMETER Integration
    Include integration tests (tagged 'Integration').

.PARAMETER OptionalTooling
    Include tests requiring external tools like ffmpeg/ffprobe (tagged 'OptionalTooling').

.PARAMETER All
    Include all tests (unit, integration, and optional tooling).

.EXAMPLE
    # Run unit tests only (default)
    .\tests\run-tests.ps1

.EXAMPLE
    # Run unit and integration tests
    .\tests\run-tests.ps1 -Integration

.EXAMPLE
    # Run all tests including those requiring external tools
    .\tests\run-tests.ps1 -All

.NOTES
    Compatible with Windows PowerShell 5.1 (powershell.exe).
    Uses pester.config.ps1 for configuration.
#>
[CmdletBinding()]
param(
    [switch]$Integration,
    [switch]$OptionalTooling,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

# Resolve repo root (parent of tests/)
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$configScript = Join-Path $repoRoot "pester.config.ps1"

if (-not (Test-Path $configScript)) {
    Write-Error "pester.config.ps1 not found at: $configScript"
    exit 1
}

# Build arguments for pester.config.ps1
$configArgs = @{}

if ($All) {
    $configArgs['IncludeIntegration'] = $true
    $configArgs['IncludeOptionalTooling'] = $true
} else {
    if ($Integration) {
        $configArgs['IncludeIntegration'] = $true
    }
    if ($OptionalTooling) {
        $configArgs['IncludeOptionalTooling'] = $true
    }
}

# Get Pester configuration
$config = & $configScript @configArgs

# Run tests
Invoke-Pester -Configuration $config
