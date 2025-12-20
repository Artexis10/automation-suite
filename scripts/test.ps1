<#
.SYNOPSIS
    Deterministic local test runner for automation-suite.

.DESCRIPTION
    Verifies Pester >= 5 is available, imports it, and runs all tests from the repo root.
    Uses vendored Pester from tools/pester if available, otherwise checks for installed module.

.EXAMPLE
    .\scripts\test.ps1

.NOTES
    If Pester 5 is not available, run:
    Install-Module Pester -Scope CurrentUser -Force
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:MinimumVersion = [Version]'5.0.0'
$script:VendorPath = Join-Path $script:RepoRoot 'tools\pester'

function Test-PesterAvailable {
    # Check vendored Pester first
    if (Test-Path $script:VendorPath) {
        $manifests = Get-ChildItem -Path $script:VendorPath -Filter 'Pester.psd1' -Recurse -ErrorAction SilentlyContinue
        foreach ($manifest in $manifests) {
            try {
                $data = Import-PowerShellDataFile -Path $manifest.FullName
                $version = [Version]$data.ModuleVersion
                if ($version -ge $script:MinimumVersion) {
                    return @{ Path = $manifest.FullName; Version = $version; Vendored = $true }
                }
            } catch {
                # Skip invalid manifests
            }
        }
    }

    # Check installed modules
    $installed = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge $script:MinimumVersion } | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed) {
        return @{ Path = $installed.Path; Version = $installed.Version; Vendored = $false }
    }

    return $null
}

# Check for Pester >= 5
Write-Host '[test] Checking for Pester >= 5.0.0...' -ForegroundColor Cyan
$pesterInfo = Test-PesterAvailable

if (-not $pesterInfo) {
    Write-Host ''
    Write-Host '[test] ERROR: Pester >= 5.0.0 is not available.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'To install Pester 5, run:' -ForegroundColor Yellow
    Write-Host '  Install-Module Pester -Scope CurrentUser -Force' -ForegroundColor White
    Write-Host ''
    exit 1
}

# Prepend vendor path to PSModulePath if using vendored Pester
if ($pesterInfo.Vendored -and $env:PSModulePath -notlike "*$script:VendorPath*") {
    $env:PSModulePath = "$script:VendorPath$([IO.Path]::PathSeparator)$env:PSModulePath"
}

# Import Pester
Write-Host "[test] Using Pester $($pesterInfo.Version) $(if ($pesterInfo.Vendored) { '(vendored)' } else { '(installed)' })" -ForegroundColor Green
Import-Module Pester -MinimumVersion $script:MinimumVersion -Force

# Build Pester configuration
$testsPath = Join-Path $script:RepoRoot 'tests'
$config = New-PesterConfiguration

$config.Run.Path = $testsPath
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.Filter.ExcludeTag = @('Integration', 'OptionalTooling')

# Run tests
Write-Host "[test] Running tests from: $testsPath" -ForegroundColor Cyan
Write-Host ''

Invoke-Pester -Configuration $config
