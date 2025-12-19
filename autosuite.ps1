<#
.SYNOPSIS
    Automation Suite - Root orchestrator CLI.

.DESCRIPTION
    Primary entrypoint for the automation-suite project.
    Delegates commands to appropriate subsystems (currently provisioning).

.PARAMETER Command
    The command to execute: apply, capture, plan, verify, report, doctor

.PARAMETER Profile
    Profile name (maps to provisioning -Profile).

.PARAMETER Manifest
    Path to manifest file (bypasses profile mapping, passed directly to provisioning).

.PARAMETER DryRun
    Preview changes without applying them.

.PARAMETER EnableRestore
    Enable restore operations during apply (opt-in for safety).

.PARAMETER Latest
    Show most recent run for report command.

.PARAMETER RunId
    Specific run ID to retrieve for report command.

.PARAMETER Last
    Show N most recent runs for report command.

.PARAMETER Json
    Output report as JSON.

.EXAMPLE
    .\autosuite.ps1 apply -Profile hugo-win11
    Apply the hugo-win11 profile manifest.

.EXAMPLE
    .\autosuite.ps1 apply -Profile hugo-win11 -DryRun
    Preview what would be applied.

.EXAMPLE
    .\autosuite.ps1 capture -Profile hugo-win11
    Capture current machine state to hugo-win11 profile.

.EXAMPLE
    .\autosuite.ps1 report -Latest
    Show most recent provisioning run.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet("apply", "capture", "plan", "verify", "report", "doctor")]
    [string]$Command,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [string]$Manifest,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$EnableRestore,

    [Parameter(Mandatory = $false)]
    [switch]$Latest,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [int]$Last = 0,

    [Parameter(Mandatory = $false)]
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$script:AutosuiteRoot = $PSScriptRoot
$script:Version = "v0"

# Allow override of provisioning CLI path for testing
$script:ProvisioningCliPath = if ($env:AUTOSUITE_PROVISIONING_CLI) {
    $env:AUTOSUITE_PROVISIONING_CLI
} else {
    Join-Path $script:AutosuiteRoot "provisioning\cli.ps1"
}

function Show-Banner {
    Write-Host ""
    Write-Host "Automation Suite - $script:Version" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Help {
    Show-Banner
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    .\autosuite.ps1 <command> [-Profile <name>] [-Manifest <path>] [options]"
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "    apply     Apply manifest to current machine"
    Write-Host "    capture   Capture current machine state into a manifest"
    Write-Host "    plan      Generate execution plan from manifest"
    Write-Host "    verify    Verify current state matches manifest"
    Write-Host "    report    Show history of previous runs"
    Write-Host "    doctor    Diagnose environment issues"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Profile <name>    Profile name (resolves to manifests/<name>.jsonc)"
    Write-Host "    -Manifest <path>   Direct path to manifest (bypasses profile)"
    Write-Host "    -DryRun            Preview changes without applying"
    Write-Host "    -EnableRestore     Enable config restoration during apply"
    Write-Host ""
    Write-Host "REPORT OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Latest            Show most recent run (default)"
    Write-Host "    -RunId <id>        Show specific run by ID"
    Write-Host "    -Last <n>          Show N most recent runs"
    Write-Host "    -Json              Output as JSON"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    .\autosuite.ps1 apply -Profile hugo-win11"
    Write-Host "    .\autosuite.ps1 apply -Profile hugo-win11 -DryRun"
    Write-Host "    .\autosuite.ps1 capture -Profile hugo-win11"
    Write-Host "    .\autosuite.ps1 plan -Profile hugo-win11"
    Write-Host "    .\autosuite.ps1 verify -Profile hugo-win11"
    Write-Host "    .\autosuite.ps1 report -Latest"
    Write-Host "    .\autosuite.ps1 doctor"
    Write-Host ""
}

function Resolve-ManifestPath {
    param([string]$ProfileName)
    
    $manifestPath = Join-Path $script:AutosuiteRoot "provisioning\manifests\$ProfileName.jsonc"
    return $manifestPath
}

function Invoke-ProvisioningCli {
    param(
        [string]$ProvisioningCommand,
        [hashtable]$Arguments
    )
    
    $cliPath = $script:ProvisioningCliPath
    
    if (-not (Test-Path $cliPath)) {
        Write-Host "[ERROR] Provisioning CLI not found: $cliPath" -ForegroundColor Red
        exit 1
    }
    
    # Emit stable wrapper line via Write-Output for testability (also Write-Host for console)
    $delegationMsg = "[autosuite] Delegating to provisioning subsystem..."
    Write-Output $delegationMsg
    Write-Host ""
    
    $params = @{ Command = $ProvisioningCommand }
    
    foreach ($key in $Arguments.Keys) {
        if ($null -ne $Arguments[$key]) {
            $params[$key] = $Arguments[$key]
        }
    }
    
    & $cliPath @params
    
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Invoke-Apply {
    param(
        [string]$ProfileName,
        [string]$ManifestPath,
        [bool]$IsDryRun,
        [bool]$IsEnableRestore
    )
    
    $cliArgs = @{}
    
    if ($ManifestPath) {
        $cliArgs.Manifest = $ManifestPath
    } elseif ($ProfileName) {
        $cliArgs.Manifest = Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'apply' command." -ForegroundColor Red
        exit 1
    }
    
    if ($IsDryRun) { $cliArgs.DryRun = $true }
    if ($IsEnableRestore) { $cliArgs.EnableRestore = $true }
    
    Invoke-ProvisioningCli -ProvisioningCommand "apply" -Arguments $cliArgs
}

function Invoke-Capture {
    param(
        [string]$ProfileName,
        [string]$ManifestPath
    )
    
    $cliArgs = @{}
    
    if ($ManifestPath) {
        $cliArgs.OutManifest = $ManifestPath
    } elseif ($ProfileName) {
        $cliArgs.Profile = $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'capture' command." -ForegroundColor Red
        exit 1
    }
    
    Invoke-ProvisioningCli -ProvisioningCommand "capture" -Arguments $cliArgs
}

function Invoke-Plan {
    param(
        [string]$ProfileName,
        [string]$ManifestPath
    )
    
    $cliArgs = @{}
    
    if ($ManifestPath) {
        $cliArgs.Manifest = $ManifestPath
    } elseif ($ProfileName) {
        $cliArgs.Manifest = Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'plan' command." -ForegroundColor Red
        exit 1
    }
    
    Invoke-ProvisioningCli -ProvisioningCommand "plan" -Arguments $cliArgs
}

function Invoke-Verify {
    param(
        [string]$ProfileName,
        [string]$ManifestPath
    )
    
    $cliArgs = @{}
    
    if ($ManifestPath) {
        $cliArgs.Manifest = $ManifestPath
    } elseif ($ProfileName) {
        $cliArgs.Manifest = Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'verify' command." -ForegroundColor Red
        exit 1
    }
    
    Invoke-ProvisioningCli -ProvisioningCommand "verify" -Arguments $cliArgs
}

function Invoke-Report {
    param(
        [bool]$IsLatest,
        [string]$ReportRunId,
        [int]$LastN,
        [bool]$OutputJson
    )
    
    $cliArgs = @{}
    
    if ($ReportRunId) { $cliArgs.RunId = $ReportRunId }
    if ($IsLatest) { $cliArgs.Latest = $true }
    if ($LastN -gt 0) { $cliArgs.Last = $LastN }
    if ($OutputJson) { $cliArgs.Json = $true }
    
    Invoke-ProvisioningCli -ProvisioningCommand "report" -Arguments $cliArgs
}

function Invoke-Doctor {
    Invoke-ProvisioningCli -ProvisioningCommand "doctor" -Arguments @{}
}

# Main execution
Show-Banner

if (-not $Command) {
    Show-Help
    exit 0
}

switch ($Command) {
    "apply" {
        Invoke-Apply -ProfileName $Profile -ManifestPath $Manifest -IsDryRun $DryRun.IsPresent -IsEnableRestore $EnableRestore.IsPresent
    }
    "capture" {
        Invoke-Capture -ProfileName $Profile -ManifestPath $Manifest
    }
    "plan" {
        Invoke-Plan -ProfileName $Profile -ManifestPath $Manifest
    }
    "verify" {
        Invoke-Verify -ProfileName $Profile -ManifestPath $Manifest
    }
    "report" {
        Invoke-Report -IsLatest $Latest.IsPresent -ReportRunId $RunId -LastN $Last -OutputJson $Json.IsPresent
    }
    "doctor" {
        Invoke-Doctor
    }
    default {
        Show-Help
        exit 1
    }
}
