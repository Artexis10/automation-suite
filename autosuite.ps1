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
    [ValidateSet("apply", "capture", "plan", "verify", "report", "doctor", "state", "")]
    [string]$Command,
    
    # Internal flag for dot-sourcing to load functions without running main logic
    [Parameter(Mandatory = $false)]
    [switch]$LoadFunctionsOnly,

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
    [switch]$Json,

    # State subcommand (e.g., "reset")
    [Parameter(Position = 1, Mandatory = $false)]
    [string]$SubCommand
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

# State directory (repo-local, gitignored)
$script:AutosuiteStateDir = Join-Path $script:AutosuiteRoot ".autosuite"
$script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"

#region State Store Helpers

function Get-AutosuiteStatePath {
    return $script:AutosuiteStatePath
}

function Get-AutosuiteStateDir {
    return $script:AutosuiteStateDir
}

function Read-AutosuiteState {
    $statePath = Get-AutosuiteStatePath
    if (-not (Test-Path $statePath)) {
        return $null
    }
    try {
        $content = Get-Content -Path $statePath -Raw -ErrorAction Stop
        return $content | ConvertFrom-Json
    } catch {
        Write-Host "[WARN] Failed to read state file: $_" -ForegroundColor Yellow
        return $null
    }
}

function Write-AutosuiteStateAtomic {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )
    
    $stateDir = Get-AutosuiteStateDir
    $statePath = Get-AutosuiteStatePath
    
    # Ensure state directory exists
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    
    # Write to temp file first, then move (atomic on same filesystem)
    $tempPath = Join-Path $stateDir "state.tmp.$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
    
    try {
        $jsonContent = $State | ConvertTo-Json -Depth 10
        Set-Content -Path $tempPath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
        
        # Move temp to final (atomic replace)
        Move-Item -Path $tempPath -Destination $statePath -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "[ERROR] Failed to write state file: $_" -ForegroundColor Red
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function New-AutosuiteState {
    return @{
        schemaVersion = 1
        lastApplied = $null
        lastVerify = $null
        appsObserved = @{}
    }
}

function Get-ManifestHash {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    # Read as bytes and normalize line endings for deterministic hash
    $content = Get-Content -Path $Path -Raw
    # Normalize CRLF to LF for consistent hashing across platforms
    $normalized = $content -replace "`r`n", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
    
    return $hashString.ToLower()
}

function Get-InstalledAppsMap {
    # Returns a hashtable of winget ID -> version (or $true if version unknown)
    $installedApps = Get-InstalledApps
    $map = @{}
    
    $headerPassed = $false
    foreach ($line in $installedApps) {
        if (-not $line) { continue }
        
        # Skip header lines (look for separator line with dashes)
        if ($line -match '^-+$') {
            $headerPassed = $true
            continue
        }
        if (-not $headerPassed) { continue }
        
        # Parse line: Name, Id, Version (tab or multi-space separated)
        # Winget output is column-aligned, so we look for the ID pattern
        if ($line -match '\s+([A-Za-z0-9._-]+\.[A-Za-z0-9._-]+)\s+([\d.]+)') {
            $id = $Matches[1]
            $version = $Matches[2]
            $map[$id] = $version
        } elseif ($line -match '\s+([A-Za-z0-9._-]+\.[A-Za-z0-9._-]+)') {
            $id = $Matches[1]
            $map[$id] = $true
        }
    }
    
    return $map
}

function Compute-Drift {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $false)]
        [hashtable]$InstalledAppsMap = $null
    )
    
    $manifest = Read-Manifest -Path $ManifestPath
    if (-not $manifest) {
        return @{
            Success = $false
            Error = "Failed to read manifest"
            Missing = @()
            Extra = @()
            VersionMismatches = @()
        }
    }
    
    if (-not $InstalledAppsMap) {
        $InstalledAppsMap = Get-InstalledAppsMap
    }
    
    # Get required app IDs from manifest
    $requiredIds = @()
    foreach ($app in $manifest.apps) {
        $wingetId = $app.refs.windows
        if ($wingetId) {
            $requiredIds += $wingetId
        }
    }
    
    # Missing: required but not installed
    $missing = @()
    foreach ($id in $requiredIds) {
        $found = $false
        foreach ($installedId in $InstalledAppsMap.Keys) {
            if ($installedId -eq $id) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $missing += $id
        }
    }
    
    # Extra: installed but not in manifest (observed extras)
    $extra = @()
    foreach ($installedId in $InstalledAppsMap.Keys) {
        if ($installedId -notin $requiredIds) {
            $extra += $installedId
        }
    }
    
    return @{
        Success = $true
        Missing = $missing
        Extra = $extra
        VersionMismatches = @()  # MVP: not comparing versions yet
        MissingCount = $missing.Count
        ExtraCount = $extra.Count
    }
}

#endregion State Store Helpers

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
    Write-Host "    report    Show state summary and drift"
    Write-Host "    doctor    Diagnose environment issues"
    Write-Host "    state     Manage autosuite state (subcommands: reset)"
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
    Write-Host "    -Manifest <path>   Include current drift against manifest"
    Write-Host "    -Json              Output as JSON"
    Write-Host ""
    Write-Host "STATE SUBCOMMANDS:" -ForegroundColor Yellow
    Write-Host "    reset              Delete .autosuite/state.json (non-destructive)"
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
        return @{ Success = $false; ExitCode = 1; Error = "Provisioning CLI not found" }
    }
    
    # Emit stable wrapper line via Write-Output for testability
    Write-Output "[autosuite] Delegating to provisioning subsystem..."
    Write-Host ""
    
    $params = @{ Command = $ProvisioningCommand }
    
    foreach ($key in $Arguments.Keys) {
        if ($null -ne $Arguments[$key]) {
            $params[$key] = $Arguments[$key]
        }
    }
    
    & $cliPath @params
    
    $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    return @{ Success = ($exitCode -eq 0); ExitCode = $exitCode }
}

function Invoke-ApplyCore {
    param(
        [string]$ManifestPath,
        [bool]$IsDryRun,
        [bool]$IsOnlyApps,
        [switch]$SkipStateWrite
    )
    
    Write-Output "[autosuite] Apply: reading manifest $ManifestPath"
    $manifest = Read-Manifest -Path $ManifestPath
    
    if (-not $manifest) {
        return @{ Success = $false; ExitCode = 1; Error = "Failed to read manifest" }
    }
    
    Write-Output "[autosuite] Apply: installing apps"
    
    $installed = 0
    $skipped = 0
    $failed = 0
    $timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    
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
    
    # Write state for apply (unless dry-run or skipped)
    if (-not $IsDryRun -and -not $SkipStateWrite) {
        $manifestHash = Get-ManifestHash -Path $ManifestPath
        $state = Read-AutosuiteState
        if (-not $state) {
            $state = New-AutosuiteState
        }
        
        # Convert PSCustomObject to hashtable if needed
        if ($state -is [PSCustomObject]) {
            $stateHash = @{}
            $state.PSObject.Properties | ForEach-Object { $stateHash[$_.Name] = $_.Value }
            $state = $stateHash
        }
        
        $state.lastApplied = @{
            manifestPath = $ManifestPath
            manifestHash = $manifestHash
            timestampUtc = $timestampUtc
        }
        
        Write-AutosuiteStateAtomic -State $state | Out-Null
    }
    
    # Run verify unless -OnlyApps or -DryRun
    $verifyResult = $null
    if (-not $IsOnlyApps -and -not $IsDryRun) {
        Write-Host ""
        $verifyResult = Invoke-VerifyCore -ManifestPath $ManifestPath -SkipStateWrite:$SkipStateWrite
    }
    
    Write-Output "[autosuite] Apply: completed"
    
    # DryRun always succeeds; otherwise propagate verify result if run
    if ($IsDryRun) {
        return @{ Success = $true; ExitCode = 0; Installed = $installed; Skipped = $skipped; Failed = $failed }
    }
    
    if ($verifyResult) {
        return @{ 
            Success = $verifyResult.Success
            ExitCode = $verifyResult.ExitCode
            Installed = $installed
            Skipped = $skipped
            Failed = $failed
            VerifyResult = $verifyResult
        }
    }
    
    return @{ Success = ($failed -eq 0); ExitCode = (if ($failed -gt 0) { 1 } else { 0 }); Installed = $installed; Skipped = $skipped; Failed = $failed }
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
        return $null
    }
    
    $content = Get-Content -Path $Path -Raw
    # Strip JSONC comments for parsing
    $jsonContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
    
    try {
        return $jsonContent | ConvertFrom-Json
    } catch {
        Write-Host "[ERROR] Failed to parse manifest: $_" -ForegroundColor Red
        return $null
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

function Invoke-VerifyCore {
    param(
        [string]$ManifestPath,
        [switch]$SkipStateWrite
    )
    
    Write-Output "[autosuite] Verify: checking manifest $ManifestPath"
    $manifest = Read-Manifest -Path $ManifestPath
    
    if (-not $manifest) {
        return @{ Success = $false; ExitCode = 1; Error = "Failed to read manifest"; OkCount = 0; MissingCount = 0; MissingApps = @() }
    }
    
    $okCount = 0
    $missingCount = 0
    $missingApps = @()
    $appsObserved = @{}
    $timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    
    # Get installed apps map for drift detection
    $installedAppsMap = Get-InstalledAppsMap
    
    foreach ($app in $manifest.apps) {
        $wingetId = $app.refs.windows
        if (-not $wingetId) {
            continue
        }
        
        $isInstalled = Test-AppInstalled -WingetId $wingetId
        
        if ($isInstalled) {
            Write-Host "  [OK] $wingetId" -ForegroundColor Green
            $okCount++
            # Record observed app
            $version = $installedAppsMap[$wingetId]
            $appsObserved[$wingetId] = @{
                installed = $true
                version = if ($version -and $version -ne $true) { $version } else { $null }
                lastSeenUtc = $timestampUtc
            }
        } else {
            Write-Host "  [MISSING] $wingetId" -ForegroundColor Red
            $missingCount++
            $missingApps += $wingetId
            $appsObserved[$wingetId] = @{
                installed = $false
                version = $null
                lastSeenUtc = $timestampUtc
            }
        }
    }
    
    # Compute drift (extras)
    $drift = Compute-Drift -ManifestPath $ManifestPath -InstalledAppsMap $installedAppsMap
    $extraCount = $drift.ExtraCount
    
    Write-Host ""
    Write-Host "[autosuite] Verify: Summary" -ForegroundColor Cyan
    Write-Host "  Installed OK: $okCount" -ForegroundColor Green
    Write-Host "  Missing:      $missingCount" -ForegroundColor $(if ($missingCount -gt 0) { "Red" } else { "Green" })
    
    # Output summary via Write-Output for test capture
    Write-Output "[autosuite] Verify: OkCount=$okCount MissingCount=$missingCount"
    
    # Emit drift summary
    Write-Output "[autosuite] Drift: Missing=$missingCount Extra=$extraCount VersionMismatches=0"
    
    # Update state (unless skipped, e.g., during tests with no state dir)
    if (-not $SkipStateWrite) {
        $manifestHash = Get-ManifestHash -Path $ManifestPath
        $state = Read-AutosuiteState
        if (-not $state) {
            $state = New-AutosuiteState
        }
        
        # Convert PSCustomObject to hashtable if needed
        if ($state -is [PSCustomObject]) {
            $stateHash = @{}
            $state.PSObject.Properties | ForEach-Object { $stateHash[$_.Name] = $_.Value }
            $state = $stateHash
        }
        
        $state.lastVerify = @{
            manifestPath = $ManifestPath
            manifestHash = $manifestHash
            timestampUtc = $timestampUtc
            okCount = $okCount
            missingCount = $missingCount
            missingApps = $missingApps
            success = ($missingCount -eq 0)
        }
        
        # Merge appsObserved
        if (-not $state.appsObserved -or $state.appsObserved -is [PSCustomObject]) {
            $state.appsObserved = @{}
        }
        foreach ($key in $appsObserved.Keys) {
            $state.appsObserved[$key] = $appsObserved[$key]
        }
        
        Write-AutosuiteStateAtomic -State $state | Out-Null
    }
    
    if ($missingCount -gt 0) {
        Write-Host ""
        Write-Host "Missing apps:" -ForegroundColor Yellow
        foreach ($app in $missingApps) {
            Write-Host "  - $app"
        }
        Write-Output "[autosuite] Verify: FAILED"
        return @{ Success = $false; ExitCode = 1; OkCount = $okCount; MissingCount = $missingCount; MissingApps = $missingApps; ExtraCount = $extraCount }
    }
    
    Write-Output "[autosuite] Verify: PASSED"
    return @{ Success = $true; ExitCode = 0; OkCount = $okCount; MissingCount = $missingCount; MissingApps = @(); ExtraCount = $extraCount }
}

function Invoke-PlanCore {
    param(
        [string]$ManifestPath
    )
    
    $cliArgs = @{ Manifest = $ManifestPath }
    return Invoke-ProvisioningCli -ProvisioningCommand "plan" -Arguments $cliArgs
}

function Invoke-ReportCore {
    param(
        [string]$ManifestPath,
        [bool]$OutputJson
    )
    
    Write-Output "[autosuite] Report: reading state..."
    
    $state = Read-AutosuiteState
    
    if (-not $state) {
        Write-Output "[autosuite] Report: no state found"
        Write-Host "No autosuite state found. Run 'apply' or 'verify' to create state." -ForegroundColor Yellow
        return @{ Success = $true; ExitCode = 0; HasState = $false }
    }
    
    if ($OutputJson) {
        # JSON output mode
        $output = @{
            schemaVersion = $state.schemaVersion
            lastApplied = $state.lastApplied
            lastVerify = $state.lastVerify
        }
        
        if ($ManifestPath) {
            $drift = Compute-Drift -ManifestPath $ManifestPath
            $output.drift = @{
                manifestPath = $ManifestPath
                missing = $drift.Missing
                extra = $drift.Extra
                missingCount = $drift.MissingCount
                extraCount = $drift.ExtraCount
            }
        }
        
        $output | ConvertTo-Json -Depth 10
        return @{ Success = $true; ExitCode = 0; HasState = $true }
    }
    
    # Human-readable output
    Write-Host ""
    Write-Host "=== Autosuite State Report ===" -ForegroundColor Cyan
    Write-Host ""
    
    if ($state.lastApplied) {
        Write-Host "Last Applied:" -ForegroundColor Yellow
        Write-Host "  Manifest: $($state.lastApplied.manifestPath)"
        Write-Host "  Hash:     $($state.lastApplied.manifestHash)"
        Write-Host "  Time:     $($state.lastApplied.timestampUtc)"
        Write-Host ""
    } else {
        Write-Host "Last Applied: (none)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    if ($state.lastVerify) {
        Write-Host "Last Verify:" -ForegroundColor Yellow
        Write-Host "  Manifest: $($state.lastVerify.manifestPath)"
        Write-Host "  Hash:     $($state.lastVerify.manifestHash)"
        Write-Host "  Time:     $($state.lastVerify.timestampUtc)"
        Write-Host "  Result:   $(if ($state.lastVerify.success) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($state.lastVerify.success) { 'Green' } else { 'Red' })
        Write-Host "  OK:       $($state.lastVerify.okCount)  Missing: $($state.lastVerify.missingCount)"
        Write-Host ""
    } else {
        Write-Host "Last Verify: (none)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # If manifest provided, show current drift
    if ($ManifestPath) {
        Write-Host "Current Drift (vs $ManifestPath):" -ForegroundColor Yellow
        $drift = Compute-Drift -ManifestPath $ManifestPath
        if ($drift.Success) {
            Write-Host "  Missing: $($drift.MissingCount)"
            Write-Host "  Extra:   $($drift.ExtraCount)"
            Write-Output "[autosuite] Drift: Missing=$($drift.MissingCount) Extra=$($drift.ExtraCount) VersionMismatches=0"
        } else {
            Write-Host "  Error computing drift: $($drift.Error)" -ForegroundColor Red
        }
    }
    
    Write-Output "[autosuite] Report: completed"
    return @{ Success = $true; ExitCode = 0; HasState = $true }
}

function Invoke-DoctorCore {
    param(
        [string]$ManifestPath
    )
    
    Write-Output "[autosuite] Doctor: checking environment..."
    Write-Host ""
    Write-Host "=== Autosuite Doctor ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check state
    $state = Read-AutosuiteState
    $hasState = $null -ne $state
    
    Write-Host "State:" -ForegroundColor Yellow
    if ($hasState) {
        Write-Host "  [OK] State file exists" -ForegroundColor Green
        
        if ($state.lastApplied) {
            Write-Host "  Last applied: $($state.lastApplied.timestampUtc)" -ForegroundColor DarkGray
            Write-Host "    Manifest hash: $($state.lastApplied.manifestHash.Substring(0, 16))..." -ForegroundColor DarkGray
        }
        
        if ($state.lastVerify) {
            $verifyStatus = if ($state.lastVerify.success) { "PASSED" } else { "FAILED" }
            Write-Host "  Last verify: $($state.lastVerify.timestampUtc) ($verifyStatus)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [INFO] No state file (run apply or verify to create)" -ForegroundColor DarkGray
    }
    Write-Host ""
    
    # Check manifest hash drift if manifest provided
    if ($ManifestPath -and $hasState -and $state.lastApplied) {
        Write-Host "Manifest Drift:" -ForegroundColor Yellow
        $currentHash = Get-ManifestHash -Path $ManifestPath
        $lastHash = $state.lastApplied.manifestHash
        
        if ($currentHash -eq $lastHash) {
            Write-Host "  [OK] Manifest unchanged since last apply" -ForegroundColor Green
        } else {
            Write-Host "  [DRIFT] Manifest has changed since last apply" -ForegroundColor Yellow
            Write-Host "    Last applied: $($lastHash.Substring(0, 16))..." -ForegroundColor DarkGray
            Write-Host "    Current:      $($currentHash.Substring(0, 16))..." -ForegroundColor DarkGray
            Write-Host "    Suggestion: Run 'apply' to converge" -ForegroundColor Cyan
        }
        Write-Host ""
        
        # Show drift summary
        Write-Host "App Drift:" -ForegroundColor Yellow
        $drift = Compute-Drift -ManifestPath $ManifestPath
        if ($drift.Success) {
            if ($drift.MissingCount -eq 0 -and $drift.ExtraCount -eq 0) {
                Write-Host "  [OK] No drift detected" -ForegroundColor Green
            } else {
                if ($drift.MissingCount -gt 0) {
                    Write-Host "  [MISSING] $($drift.MissingCount) app(s) required but not installed" -ForegroundColor Red
                    Write-Host "    Suggestion: Run 'apply -Manifest $ManifestPath' to install" -ForegroundColor Cyan
                }
                if ($drift.ExtraCount -gt 0) {
                    Write-Host "  [EXTRA] $($drift.ExtraCount) app(s) installed but not in manifest" -ForegroundColor Yellow
                    Write-Host "    Suggestion: Update manifest to include observed extras" -ForegroundColor Cyan
                }
            }
            Write-Output "[autosuite] Drift: Missing=$($drift.MissingCount) Extra=$($drift.ExtraCount) VersionMismatches=0"
        } else {
            Write-Host "  [ERROR] Could not compute drift: $($drift.Error)" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Delegate to provisioning doctor for additional checks
    Write-Host "Provisioning Subsystem:" -ForegroundColor Yellow
    $provResult = Invoke-ProvisioningCli -ProvisioningCommand "doctor" -Arguments @{}
    
    Write-Output "[autosuite] Doctor: completed"
    return @{ Success = $true; ExitCode = 0; HasState = $hasState }
}

function Invoke-StateResetCore {
    Write-Output "[autosuite] State: resetting..."
    
    $statePath = Get-AutosuiteStatePath
    
    if (-not (Test-Path $statePath)) {
        Write-Output "[autosuite] State: no state file to reset"
        Write-Host "No state file found at $statePath" -ForegroundColor Yellow
        return @{ Success = $true; ExitCode = 0; WasReset = $false }
    }
    
    try {
        Remove-Item -Path $statePath -Force -ErrorAction Stop
        Write-Output "[autosuite] State: reset completed"
        Write-Host "State file deleted: $statePath" -ForegroundColor Green
        return @{ Success = $true; ExitCode = 0; WasReset = $true }
    } catch {
        Write-Host "[ERROR] Failed to delete state file: $_" -ForegroundColor Red
        return @{ Success = $false; ExitCode = 1; Error = $_.ToString() }
    }
}

# Helper to resolve manifest path with validation
function Resolve-ManifestPathWithValidation {
    param(
        [string]$ProfileName,
        [string]$ManifestPath,
        [string]$CommandName
    )
    
    if ($ManifestPath) {
        return $ManifestPath
    } elseif ($ProfileName) {
        return Resolve-ManifestPath -ProfileName $ProfileName
    } else {
        Write-Host "[ERROR] Either -Profile or -Manifest is required for '$CommandName' command." -ForegroundColor Red
        return $null
    }
}

# Main execution - skip if loading functions only (for testing)
if ($LoadFunctionsOnly) {
    return
}

Show-Banner

if (-not $Command) {
    Show-Help
    exit 0
}

$exitCode = 0

switch ($Command) {
    "capture" {
        Invoke-Capture -OutputPath $Out -IsExample $Example.IsPresent
    }
    "apply" {
        $resolvedPath = Resolve-ManifestPathWithValidation -ProfileName $Profile -ManifestPath $Manifest -CommandName "apply"
        if (-not $resolvedPath) {
            exit 1
        }
        $result = Invoke-ApplyCore -ManifestPath $resolvedPath -IsDryRun $DryRun.IsPresent -IsOnlyApps $OnlyApps.IsPresent
        $exitCode = $result.ExitCode
    }
    "verify" {
        $resolvedPath = Resolve-ManifestPathWithValidation -ProfileName $Profile -ManifestPath $Manifest -CommandName "verify"
        if (-not $resolvedPath) {
            exit 1
        }
        $result = Invoke-VerifyCore -ManifestPath $resolvedPath
        $exitCode = $result.ExitCode
    }
    "plan" {
        $resolvedPath = Resolve-ManifestPathWithValidation -ProfileName $Profile -ManifestPath $Manifest -CommandName "plan"
        if (-not $resolvedPath) {
            exit 1
        }
        $result = Invoke-PlanCore -ManifestPath $resolvedPath
        $exitCode = $result.ExitCode
    }
    "report" {
        $result = Invoke-ReportCore -ManifestPath $Manifest -OutputJson $Json.IsPresent
        $exitCode = $result.ExitCode
    }
    "doctor" {
        $result = Invoke-DoctorCore -ManifestPath $Manifest
        $exitCode = $result.ExitCode
    }
    "state" {
        switch ($SubCommand) {
            "reset" {
                $result = Invoke-StateResetCore
                $exitCode = $result.ExitCode
            }
            default {
                if ($SubCommand) {
                    Write-Host "[ERROR] Unknown state subcommand: $SubCommand" -ForegroundColor Red
                } else {
                    Write-Host "[ERROR] State command requires a subcommand (e.g., 'reset')" -ForegroundColor Red
                }
                Write-Host "Usage: .\autosuite.ps1 state reset" -ForegroundColor Yellow
                $exitCode = 1
            }
        }
    }
    default {
        Show-Help
        exit 1
    }
}

exit $exitCode
