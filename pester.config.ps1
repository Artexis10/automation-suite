<#
.SYNOPSIS
    Pester v5 configuration for automation-suite tests.

.DESCRIPTION
    Returns a PesterConfiguration object for running tests.
    Compatible with Windows PowerShell 5.1.

.PARAMETER IncludeIntegration
    Include Integration-tagged tests (excluded by default).

.PARAMETER IncludeOptionalTooling
    Include OptionalTooling-tagged tests (excluded by default).
    These tests require external tools like ffmpeg/ffprobe.

.EXAMPLE
    # Run unit tests only (default)
    Invoke-Pester -Configuration (& .\pester.config.ps1)

.EXAMPLE
    # Include integration tests
    Invoke-Pester -Configuration (& .\pester.config.ps1 -IncludeIntegration)

.EXAMPLE
    # Include optional tooling tests (requires ffmpeg/ffprobe)
    Invoke-Pester -Configuration (& .\pester.config.ps1 -IncludeOptionalTooling)
#>
[CmdletBinding()]
param(
    [switch]$IncludeIntegration,
    [switch]$IncludeOptionalTooling
)

$repoRoot = $PSScriptRoot
$testsPath = Join-Path $repoRoot "tests"

# Ensure vendored Pester is loaded
$vendorPesterPath = Join-Path $repoRoot "tools\pester"
if (Test-Path $vendorPesterPath) {
    if ($env:PSModulePath -notlike "*$vendorPesterPath*") {
        $env:PSModulePath = "$vendorPesterPath$([IO.Path]::PathSeparator)$env:PSModulePath"
    }
}

# Import Pester if not already loaded
if (-not (Get-Module -Name Pester)) {
    Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop
}

# Build exclusion tags
$excludeTags = @()
if (-not $IncludeIntegration) {
    $excludeTags += 'Integration'
}
if (-not $IncludeOptionalTooling) {
    $excludeTags += 'OptionalTooling'
}

# Create configuration
$config = New-PesterConfiguration

# Run configuration
$config.Run.Path = $testsPath
$config.Run.Exit = $true
$config.Run.PassThru = $true

# Filter configuration
if ($excludeTags.Count -gt 0) {
    $config.Filter.ExcludeTag = $excludeTags
}

# Output configuration
$config.Output.Verbosity = 'Detailed'
$config.Output.StackTraceVerbosity = 'Filtered'
$config.Output.CIFormat = 'Auto'

# Test result configuration
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $repoRoot "tests\test-results.xml"
$config.TestResult.OutputFormat = 'NUnitXml'

# Should configuration
$config.Should.ErrorAction = 'Continue'

# Return the configuration
$config
