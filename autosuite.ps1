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
    [string]$Out,

    [Parameter(Mandatory = $false)]
    [switch]$Example,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$OnlyApps,

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

# Allow override of winget script for testing (path to .ps1 file)
$script:WingetScript = $env:AUTOSUITE_WINGET_SCRIPT

# Local manifests directory (gitignored)
$script:LocalManifestsDir = Join-Path $script:AutosuiteRoot "provisioning\manifests\local"

function Show-Banner {
    Write-Host ""
    Write-Host "Automation Suite - $script:Version" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Help {
    Show-Banner
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    .\autosuite.ps1 <command> [options]"
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "    capture   Capture current machine state into a manifest"
    Write-Host "    apply     Apply manifest to current machine"
    Write-Host "    verify    Verify current state matches manifest"
    Write-Host "    plan      Generate execution plan from manifest"
    Write-Host "    report    Show history of previous runs"
    Write-Host "    doctor    Diagnose environment issues"
    Write-Host ""
    Write-Host "CAPTURE OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Out <path>        Output path (default: provisioning/manifests/local/<machine>.jsonc)"
    Write-Host "    -Example           Generate sanitized example manifest (no machine/timestamps)"
    Write-Host ""
    Write-Host "APPLY OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Manifest <path>   Path to manifest file"
    Write-Host "    -Profile <name>    Profile name (resolves to manifests/<name>.jsonc)"
    Write-Host "    -DryRun            Preview changes without applying"
    Write-Host "    -OnlyApps          Install apps only (skip restore/verify)"
    Write-Host "    -EnableRestore     Enable config restoration during apply"
    Write-Host ""
    Write-Host "VERIFY OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Manifest <path>   Path to manifest file"
    Write-Host "    -Profile <name>    Profile name (resolves to manifests/<name>.jsonc)"
    Write-Host ""
    Write-Host "REPORT OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Latest            Show most recent run (default)"
    Write-Host "    -RunId <id>        Show specific run by ID"
    Write-Host "    -Last <n>          Show N most recent runs"
    Write-Host "    -Json              Output as JSON"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    .\autosuite.ps1 capture                          # Capture to local/<machine>.jsonc"
    Write-Host "    .\autosuite.ps1 capture -Out my-manifest.jsonc   # Capture to specific path"
    Write-Host "    .\autosuite.ps1 capture -Example                 # Generate example fixture"
    Write-Host "    .\autosuite.ps1 apply -Manifest manifest.jsonc   # Apply manifest"
    Write-Host "    .\autosuite.ps1 apply -Manifest manifest.jsonc -DryRun"
    Write-Host "    .\autosuite.ps1 verify -Manifest manifest.jsonc  # Verify apps installed"
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
        [bool]$IsOnlyApps,
        [bool]$IsEnableRestore
    )
    
    # Resolve manifest path
    $resolvedPath = if ($ManifestPath) {
        $ManifestPath
    } elseif ($ProfileName) {
        Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'apply' command." -ForegroundColor Red
        exit 1
    }
    
    Write-Output "[autosuite] Apply: reading manifest $resolvedPath"
    $manifest = Read-Manifest -Path $resolvedPath
    
    Write-Output "[autosuite] Apply: installing apps"
    
    $installed = 0
    $skipped = 0
    $failed = 0
    
    foreach ($app in $manifest.apps) {
        $wingetId = $app.refs.windows
        if (-not $wingetId) {
            Write-Host "  [SKIP] $($app.id) - no Windows ref" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Check if already installed
        $isInstalled = Test-AppInstalled -WingetId $wingetId
        
        if ($isInstalled) {
            Write-Host "  [SKIP] $wingetId - already installed" -ForegroundColor DarkGray
            $skipped++
            continue
        }
        
        if ($IsDryRun) {
            Write-Host "  [PLAN] $wingetId - would install" -ForegroundColor Cyan
            $installed++
        } else {
            Write-Host "  [INSTALL] $wingetId" -ForegroundColor Green
            try {
                if ($script:WingetScript) {
                    & pwsh -NoProfile -File $script:WingetScript install --id $wingetId 2>&1 | Out-Null
                } else {
                    & winget install --id $wingetId --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Null
                }
                if ($LASTEXITCODE -eq 0) {
                    $installed++
                } else {
                    Write-Host "    [WARN] Install may have issues: exit code $LASTEXITCODE" -ForegroundColor Yellow
                    $installed++
                }
            } catch {
                Write-Host "    [ERROR] Failed to install: $_" -ForegroundColor Red
                $failed++
            }
        }
    }
    
    Write-Host ""
    Write-Host "[autosuite] Apply: Summary" -ForegroundColor Cyan
    Write-Host "  Installed: $installed"
    Write-Host "  Skipped:   $skipped"
    if ($failed -gt 0) {
        Write-Host "  Failed:    $failed" -ForegroundColor Red
    }
    
    # Run verify unless -OnlyApps
    if (-not $IsOnlyApps -and -not $IsDryRun) {
        Write-Host ""
        Invoke-VerifyManifest -ManifestPath $resolvedPath
    }
    
    Write-Output "[autosuite] Apply: completed"
}

function Get-InstalledApps {
    # Get list of installed apps via winget (or mock script for testing)
    if ($script:WingetScript) {
        $wingetOutput = & pwsh -NoProfile -File $script:WingetScript list 2>$null
    } else {
        $wingetOutput = & winget list --accept-source-agreements 2>$null
    }
    return $wingetOutput
}

function Test-AppInstalled {
    param([string]$WingetId)
    
    $installedApps = Get-InstalledApps
    foreach ($line in $installedApps) {
        if ($line -match [regex]::Escape($WingetId)) {
            return $true
        }
    }
    return $false
}

function Read-Manifest {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Manifest not found: $Path" -ForegroundColor Red
        exit 1
    }
    
    $content = Get-Content -Path $Path -Raw
    # Strip JSONC comments for parsing
    $jsonContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
    
    try {
        return $jsonContent | ConvertFrom-Json
    } catch {
        Write-Host "[ERROR] Failed to parse manifest: $_" -ForegroundColor Red
        exit 1
    }
}

function Write-ExampleManifest {
    param([string]$Path)
    
    $example = @{
        version = 1
        name = "example"
        apps = @(
            @{ id = "7zip-7zip"; refs = @{ windows = "7zip.7zip" } }
            @{ id = "git-git"; refs = @{ windows = "Git.Git" } }
            @{ id = "microsoft-powershell"; refs = @{ windows = "Microsoft.PowerShell" } }
            @{ id = "microsoft-windowsterminal"; refs = @{ windows = "Microsoft.WindowsTerminal" } }
            @{ id = "videolan-vlc"; refs = @{ windows = "VideoLAN.VLC" } }
        )
        restore = @()
        verify = @()
    }
    
    $jsonContent = $example | ConvertTo-Json -Depth 10
    
    # Add header comment
    $header = @"
{
  // Deterministic example manifest
  // This file is committed and used for automated tests
  // Do NOT add machine-specific data or timestamps

"@
    
    # Convert to JSONC format with comments
    $jsoncContent = $header + ($jsonContent.TrimStart('{'))
    
    $parentDir = Split-Path -Parent $Path
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    Set-Content -Path $Path -Value $jsoncContent
    return $Path
}

function Invoke-Capture {
    param(
        [string]$OutputPath,
        [bool]$IsExample
    )
    
    Write-Output "[autosuite] Capture: starting..."
    
    if ($IsExample) {
        # Generate sanitized example manifest
        $examplePath = if ($OutputPath) { $OutputPath } else { Join-Path $script:AutosuiteRoot "provisioning\manifests\example.jsonc" }
        Write-Output "[autosuite] Capture: generating example manifest"
        Write-ExampleManifest -Path $examplePath
        Write-Host "[autosuite] Capture: example manifest written to $examplePath" -ForegroundColor Green
        return
    }
    
    # Default output path: local/<machine>.jsonc
    $outPath = if ($OutputPath) {
        $OutputPath
    } else {
        $machineName = $env:COMPUTERNAME.ToLower()
        if (-not (Test-Path $script:LocalManifestsDir)) {
            New-Item -ItemType Directory -Path $script:LocalManifestsDir -Force | Out-Null
        }
        Join-Path $script:LocalManifestsDir "$machineName.jsonc"
    }
    
    Write-Output "[autosuite] Capture: output path is $outPath"
    
    # Delegate to provisioning CLI for actual capture
    $cliArgs = @{ OutManifest = $outPath }
    Invoke-ProvisioningCli -ProvisioningCommand "capture" -Arguments $cliArgs
    
    Write-Output "[autosuite] Capture: completed"
}

function Invoke-VerifyManifest {
    param([string]$ManifestPath)
    
    Write-Output "[autosuite] Verify: checking manifest $ManifestPath"
    $manifest = Read-Manifest -Path $ManifestPath
    
    $okCount = 0
    $missingCount = 0
    $missingApps = @()
    
    foreach ($app in $manifest.apps) {
        $wingetId = $app.refs.windows
        if (-not $wingetId) {
            continue
        }
        
        $isInstalled = Test-AppInstalled -WingetId $wingetId
        
        if ($isInstalled) {
            Write-Host "  [OK] $wingetId" -ForegroundColor Green
            $okCount++
        } else {
            Write-Host "  [MISSING] $wingetId" -ForegroundColor Red
            $missingCount++
            $missingApps += $wingetId
        }
    }
    
    Write-Host ""
    Write-Host "[autosuite] Verify: Summary" -ForegroundColor Cyan
    Write-Host "  Installed OK: $okCount" -ForegroundColor Green
    Write-Host "  Missing:      $missingCount" -ForegroundColor $(if ($missingCount -gt 0) { "Red" } else { "Green" })
    
    if ($missingCount -gt 0) {
        Write-Host ""
        Write-Host "Missing apps:" -ForegroundColor Yellow
        foreach ($app in $missingApps) {
            Write-Host "  - $app"
        }
        Write-Output "[autosuite] Verify: FAILED"
        return 1
    }
    
    Write-Output "[autosuite] Verify: PASSED"
    return 0
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
    
    # Resolve manifest path
    $resolvedPath = if ($ManifestPath) {
        $ManifestPath
    } elseif ($ProfileName) {
        Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for 'verify' command." -ForegroundColor Red
        exit 1
    }
    
    Write-Output "[autosuite] Verify: checking manifest $resolvedPath"
    $manifest = Read-Manifest -Path $resolvedPath
    
    $okCount = 0
    $missingCount = 0
    $missingApps = @()
    
    foreach ($app in $manifest.apps) {
        $wingetId = $app.refs.windows
        if (-not $wingetId) {
            continue
        }
        
        $isInstalled = Test-AppInstalled -WingetId $wingetId
        
        if ($isInstalled) {
            Write-Host "  [OK] $wingetId" -ForegroundColor Green
            $okCount++
        } else {
            Write-Host "  [MISSING] $wingetId" -ForegroundColor Red
            $missingCount++
            $missingApps += $wingetId
        }
    }
    
    Write-Host ""
    Write-Host "[autosuite] Verify: Summary" -ForegroundColor Cyan
    Write-Host "  Installed OK: $okCount" -ForegroundColor Green
    Write-Host "  Missing:      $missingCount" -ForegroundColor $(if ($missingCount -gt 0) { "Red" } else { "Green" })
    
    if ($missingCount -gt 0) {
        Write-Host ""
        Write-Host "Missing apps:" -ForegroundColor Yellow
        foreach ($app in $missingApps) {
            Write-Host "  - $app"
        }
        Write-Output "[autosuite] Verify: FAILED"
        exit 1
    }
    
    Write-Output "[autosuite] Verify: PASSED"
    exit 0
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
    "capture" {
        Invoke-Capture -OutputPath $Out -IsExample $Example.IsPresent
    }
    "apply" {
        Invoke-Apply -ProfileName $Profile -ManifestPath $Manifest -IsDryRun $DryRun.IsPresent -IsOnlyApps $OnlyApps.IsPresent -IsEnableRestore $EnableRestore.IsPresent
    }
    "verify" {
        Invoke-Verify -ProfileName $Profile -ManifestPath $Manifest
    }
    "plan" {
        Invoke-Plan -ProfileName $Profile -ManifestPath $Manifest
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
