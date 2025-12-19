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
    [Alias("v")]
    [switch]$Version,

    [Parameter(Mandatory = $false)]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [string]$Manifest,

    [Parameter(Mandatory = $false)]
    [string]$Out,

    [Parameter(Mandatory = $false)]
    [switch]$Example,

    [Parameter(Mandatory = $false)]
    [switch]$Sanitize,

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$ExamplesDir,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

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

function Get-AutosuiteVersion {
    <#
    .SYNOPSIS
        Returns the current version of Automation Suite.
    .DESCRIPTION
        If provisioning/VERSION.txt exists (release build), returns its content.
        Otherwise returns dev version: 0.0.0-dev+<short git sha>
    #>
    $versionFile = Join-Path $script:AutosuiteRoot "provisioning\VERSION.txt"
    
    if (Test-Path $versionFile) {
        $version = (Get-Content -Path $versionFile -Raw).Trim()
        return $version
    }
    
    # Dev version: try to get git sha
    try {
        $gitSha = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitSha) {
            return "0.0.0-dev+$gitSha"
        }
    } catch {
        # Git not available
    }
    
    return "0.0.0-dev"
}

function Get-GitSha {
    <#
    .SYNOPSIS
        Returns the current git commit SHA (short form), or $null if unavailable.
    #>
    try {
        $gitSha = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitSha) {
            return $gitSha.Trim()
        }
    } catch {
        # Git not available
    }
    return $null
}

$script:VersionString = Get-AutosuiteVersion

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

# Examples directory (committed, shareable)
$script:ExamplesManifestsDir = Join-Path $script:AutosuiteRoot "provisioning\manifests\examples"

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
    Write-Host "Automation Suite - $script:VersionString" -ForegroundColor Cyan
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
    Write-Host "    -Out <path>        Output path (overrides all defaults)"
    Write-Host "    -Sanitize          Remove machine-specific fields, secrets, local paths; stable sort"
    Write-Host "    -Name <string>     Manifest name (used for filename when -Sanitize)"
    Write-Host "    -ExamplesDir <p>   Examples directory (default: provisioning/manifests/examples/)"
    Write-Host "    -Force             Overwrite existing example manifests without prompting"
    Write-Host "    -Example           (Legacy) Generate sanitized example manifest"
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
    Write-Host "    .\autosuite.ps1 capture                                    # Capture to local/<machine>.jsonc"
    Write-Host "    .\autosuite.ps1 capture -Out my-manifest.jsonc             # Capture to specific path"
    Write-Host "    .\autosuite.ps1 capture -Sanitize -Name example-win-core   # Sanitized to examples/"
    Write-Host "    .\autosuite.ps1 capture -Example                           # (Legacy) Generate example fixture"
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
    $upgraded = 0
    $timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    
    foreach ($app in $manifest.apps) {
        $driver = Get-AppDriver -App $app
        $appDisplayId = if ($driver -eq 'winget') { Get-AppWingetId -App $app } else { $app.id }
        
        if (-not $appDisplayId) {
            Write-Host "  [SKIP] $($app.id) - no installable ref for driver '$driver'" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Check if already installed using driver abstraction
        $installStatus = Test-AppInstalledWithDriver -App $app
        
        if ($installStatus.Installed) {
            # Check version constraint if present
            $versionConstraint = Parse-VersionConstraint -Constraint $app.version
            
            if ($versionConstraint) {
                $versionCheck = Test-VersionConstraint -InstalledVersion $installStatus.Version -Constraint $versionConstraint
                
                if (-not $versionCheck.Satisfied) {
                    # Version mismatch - attempt upgrade for winget, report for custom
                    if ($driver -eq 'winget') {
                        if ($IsDryRun) {
                            Write-Host "  [PLAN] $appDisplayId - would upgrade ($($versionCheck.Reason))" -ForegroundColor Cyan
                            $upgraded++
                        } else {
                            Write-Host "  [UPGRADE] $appDisplayId ($($versionCheck.Reason))" -ForegroundColor Yellow
                            $result = Install-AppWithDriver -App $app -DryRun $false -IsUpgrade $true
                            if ($result.Success) {
                                $upgraded++
                            } else {
                                Write-Host "    [WARN] Upgrade may have issues: $($result.Error)" -ForegroundColor Yellow
                                $upgraded++
                            }
                        }
                    } else {
                        Write-Host "  [MANUAL] $appDisplayId - version mismatch, manual intervention needed ($($versionCheck.Reason))" -ForegroundColor Yellow
                        $failed++
                    }
                    continue
                }
            }
            
            Write-Host "  [SKIP] $appDisplayId - already installed" -ForegroundColor DarkGray
            $skipped++
            continue
        }
        
        # Not installed - install it
        if ($IsDryRun) {
            Write-Host "  [PLAN] $appDisplayId - would install (driver: $driver)" -ForegroundColor Cyan
            $installed++
        } else {
            Write-Host "  [INSTALL] $appDisplayId (driver: $driver)" -ForegroundColor Green
            $result = Install-AppWithDriver -App $app -DryRun $false -IsUpgrade $false
            
            if ($result.Success) {
                $installed++
            } else {
                Write-Host "    [ERROR] Failed to install: $($result.Error)" -ForegroundColor Red
                $failed++
            }
        }
    }
    
    Write-Host ""
    Write-Host "[autosuite] Apply: Summary" -ForegroundColor Cyan
    Write-Host "  Installed: $installed"
    Write-Host "  Upgraded:  $upgraded"
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
    
    Write-Output "[autosuite] Apply: completed ExitCode=$(if ($failed -gt 0) { 1 } else { 0 })"
    
    # DryRun always succeeds; otherwise propagate verify result if run
    if ($IsDryRun) {
        return @{ Success = $true; ExitCode = 0; Installed = $installed; Upgraded = $upgraded; Skipped = $skipped; Failed = $failed }
    }
    
    if ($verifyResult) {
        return @{ 
            Success = $verifyResult.Success
            ExitCode = $verifyResult.ExitCode
            Installed = $installed
            Upgraded = $upgraded
            Skipped = $skipped
            Failed = $failed
            VerifyResult = $verifyResult
        }
    }
    
    return @{ Success = ($failed -eq 0); ExitCode = (if ($failed -gt 0) { 1 } else { 0 }); Installed = $installed; Upgraded = $upgraded; Skipped = $skipped; Failed = $failed }
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

#region Driver Abstraction (Bundle C)

<#
.SYNOPSIS
    Parse version constraint string.
.DESCRIPTION
    Supports:
    - Exact match: "1.2.3"
    - Minimum: ">=1.2.3"
    Returns hashtable with Type (exact|minimum) and Version.
#>
function Parse-VersionConstraint {
    param([string]$Constraint)
    
    if (-not $Constraint) {
        return $null
    }
    
    $Constraint = $Constraint.Trim()
    
    if ($Constraint -match '^>=(.+)$') {
        return @{
            Type = 'minimum'
            Version = $Matches[1].Trim()
        }
    } else {
        return @{
            Type = 'exact'
            Version = $Constraint
        }
    }
}

<#
.SYNOPSIS
    Compare two version strings.
.DESCRIPTION
    Returns:
    - -1 if $Version1 < $Version2
    - 0 if $Version1 == $Version2
    - 1 if $Version1 > $Version2
    Handles dotted version strings (e.g., 1.2.3, 2.43.0).
#>
function Compare-Versions {
    param(
        [string]$Version1,
        [string]$Version2
    )
    
    if (-not $Version1 -or -not $Version2) {
        return $null
    }
    
    # Split into parts and compare numerically
    $parts1 = $Version1 -split '\.'
    $parts2 = $Version2 -split '\.'
    
    $maxParts = [Math]::Max($parts1.Count, $parts2.Count)
    
    for ($i = 0; $i -lt $maxParts; $i++) {
        $p1 = if ($i -lt $parts1.Count) { 
            $num = 0
            if ([int]::TryParse($parts1[$i], [ref]$num)) { $num } else { 0 }
        } else { 0 }
        
        $p2 = if ($i -lt $parts2.Count) { 
            $num = 0
            if ([int]::TryParse($parts2[$i], [ref]$num)) { $num } else { 0 }
        } else { 0 }
        
        if ($p1 -lt $p2) { return -1 }
        if ($p1 -gt $p2) { return 1 }
    }
    
    return 0
}

<#
.SYNOPSIS
    Test if installed version satisfies constraint.
.DESCRIPTION
    Returns hashtable with:
    - Satisfied: $true/$false
    - Reason: explanation string
#>
function Test-VersionConstraint {
    param(
        [string]$InstalledVersion,
        [hashtable]$Constraint
    )
    
    if (-not $Constraint) {
        return @{ Satisfied = $true; Reason = 'no constraint' }
    }
    
    if (-not $InstalledVersion -or $InstalledVersion -eq $true) {
        # Unknown version - fail by default (CI-safe)
        return @{ Satisfied = $false; Reason = 'version unknown' }
    }
    
    $cmp = Compare-Versions -Version1 $InstalledVersion -Version2 $Constraint.Version
    
    if ($null -eq $cmp) {
        return @{ Satisfied = $false; Reason = 'version comparison failed' }
    }
    
    switch ($Constraint.Type) {
        'exact' {
            if ($cmp -eq 0) {
                return @{ Satisfied = $true; Reason = "exact match $InstalledVersion" }
            } else {
                return @{ Satisfied = $false; Reason = "expected $($Constraint.Version), got $InstalledVersion" }
            }
        }
        'minimum' {
            if ($cmp -ge 0) {
                return @{ Satisfied = $true; Reason = "$InstalledVersion >= $($Constraint.Version)" }
            } else {
                return @{ Satisfied = $false; Reason = "$InstalledVersion < $($Constraint.Version)" }
            }
        }
        default {
            return @{ Satisfied = $false; Reason = "unknown constraint type: $($Constraint.Type)" }
        }
    }
}

<#
.SYNOPSIS
    Get driver for an app entry.
.DESCRIPTION
    Returns driver name: 'winget' (default) or 'custom'.
#>
function Get-AppDriver {
    param([PSObject]$App)
    
    if ($App.driver) {
        return $App.driver.ToLower()
    }
    return 'winget'
}

<#
.SYNOPSIS
    Get winget ID for an app.
.DESCRIPTION
    Supports both old format (refs.windows) and new format (id with driver=winget).
#>
function Get-AppWingetId {
    param([PSObject]$App)
    
    # Prefer refs.windows for backward compatibility
    if ($App.refs -and $App.refs.windows) {
        return $App.refs.windows
    }
    
    # Fallback: if driver is winget and no refs, use id as winget id
    $driver = Get-AppDriver -App $App
    if ($driver -eq 'winget' -and $App.id) {
        return $App.id
    }
    
    return $null
}

<#
.SYNOPSIS
    Validate custom driver install script path.
.DESCRIPTION
    Security: Only allow scripts under repo root.
    Returns $true if path is safe, $false otherwise.
#>
function Test-CustomScriptPathSafe {
    param([string]$ScriptPath)
    
    if (-not $ScriptPath) {
        return $false
    }
    
    # Resolve to absolute path
    $absolutePath = if ([System.IO.Path]::IsPathRooted($ScriptPath)) {
        $ScriptPath
    } else {
        Join-Path $script:AutosuiteRoot $ScriptPath
    }
    
    try {
        $resolvedPath = [System.IO.Path]::GetFullPath($absolutePath)
        $repoRoot = [System.IO.Path]::GetFullPath($script:AutosuiteRoot)
        
        # Check if resolved path starts with repo root (prevent path traversal)
        return $resolvedPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Test if custom app is installed using detect configuration.
.DESCRIPTION
    Supports detect types:
    - file: check if file exists at path
    - registry: check if registry key/value exists (optional)
    Returns hashtable with Installed and Version (if detectable).
#>
function Test-CustomAppInstalled {
    param([PSObject]$CustomConfig)
    
    if (-not $CustomConfig -or -not $CustomConfig.detect) {
        return @{ Installed = $false; Version = $null; Error = 'no detect config' }
    }
    
    $detect = $CustomConfig.detect
    
    switch ($detect.type) {
        'file' {
            if (-not $detect.path) {
                return @{ Installed = $false; Version = $null; Error = 'file detect missing path' }
            }
            
            # Expand environment variables in path
            $expandedPath = [Environment]::ExpandEnvironmentVariables($detect.path)
            $exists = Test-Path $expandedPath
            
            return @{ 
                Installed = $exists
                Version = $null  # File detection doesn't provide version
                DetectPath = $expandedPath
            }
        }
        'registry' {
            if (-not $detect.key) {
                return @{ Installed = $false; Version = $null; Error = 'registry detect missing key' }
            }
            
            try {
                $regValue = Get-ItemProperty -Path $detect.key -Name $detect.value -ErrorAction SilentlyContinue
                if ($regValue) {
                    $version = if ($detect.value) { $regValue.$($detect.value) } else { $null }
                    return @{ Installed = $true; Version = $version }
                }
                return @{ Installed = $false; Version = $null }
            } catch {
                return @{ Installed = $false; Version = $null; Error = $_.ToString() }
            }
        }
        default {
            return @{ Installed = $false; Version = $null; Error = "unknown detect type: $($detect.type)" }
        }
    }
}

<#
.SYNOPSIS
    Install custom app by running install script.
.DESCRIPTION
    Runs the installScript from custom config.
    Returns hashtable with Success, ExitCode, Output.
#>
function Install-CustomApp {
    param(
        [PSObject]$App,
        [bool]$DryRun = $false
    )
    
    $customConfig = $App.custom
    if (-not $customConfig -or -not $customConfig.installScript) {
        return @{ Success = $false; ExitCode = 1; Error = 'no installScript defined' }
    }
    
    $scriptPath = $customConfig.installScript
    
    # Security check: script must be under repo root
    if (-not (Test-CustomScriptPathSafe -ScriptPath $scriptPath)) {
        Write-Host "    [SECURITY] Install script path rejected (must be under repo root): $scriptPath" -ForegroundColor Red
        return @{ Success = $false; ExitCode = 1; Error = 'script path outside repo root' }
    }
    
    # Resolve to absolute path
    $absoluteScript = if ([System.IO.Path]::IsPathRooted($scriptPath)) {
        $scriptPath
    } else {
        Join-Path $script:AutosuiteRoot $scriptPath
    }
    
    if (-not (Test-Path $absoluteScript)) {
        return @{ Success = $false; ExitCode = 1; Error = "install script not found: $absoluteScript" }
    }
    
    if ($DryRun) {
        Write-Output "[autosuite] CustomDriver: would run $absoluteScript"
        return @{ Success = $true; ExitCode = 0; DryRun = $true }
    }
    
    Write-Output "[autosuite] CustomDriver: running $absoluteScript"
    
    try {
        $output = & pwsh -NoProfile -File $absoluteScript 2>&1
        $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        
        return @{ 
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $output
        }
    } catch {
        return @{ Success = $false; ExitCode = 1; Error = $_.ToString() }
    }
}

<#
.SYNOPSIS
    Driver interface: Test if app is installed.
.DESCRIPTION
    Dispatches to appropriate driver based on app config.
    Returns hashtable with Installed, Version, Driver.
#>
function Test-AppInstalledWithDriver {
    param([PSObject]$App)
    
    $driver = Get-AppDriver -App $App
    
    switch ($driver) {
        'winget' {
            $wingetId = Get-AppWingetId -App $App
            if (-not $wingetId) {
                return @{ Installed = $false; Version = $null; Driver = 'winget'; Error = 'no winget id' }
            }
            
            $installedMap = Get-InstalledAppsMap
            $isInstalled = $installedMap.ContainsKey($wingetId)
            $version = if ($isInstalled) { $installedMap[$wingetId] } else { $null }
            
            # Handle version being $true (installed but version unknown)
            if ($version -eq $true) { $version = $null }
            
            return @{ 
                Installed = $isInstalled
                Version = $version
                Driver = 'winget'
                WingetId = $wingetId
            }
        }
        'custom' {
            $result = Test-CustomAppInstalled -CustomConfig $App.custom
            $result.Driver = 'custom'
            return $result
        }
        default {
            return @{ Installed = $false; Version = $null; Driver = $driver; Error = "unknown driver: $driver" }
        }
    }
}

<#
.SYNOPSIS
    Driver interface: Install app.
.DESCRIPTION
    Dispatches to appropriate driver based on app config.
    Returns hashtable with Success, ExitCode, Action.
#>
function Install-AppWithDriver {
    param(
        [PSObject]$App,
        [bool]$DryRun = $false,
        [bool]$IsUpgrade = $false
    )
    
    $driver = Get-AppDriver -App $App
    
    switch ($driver) {
        'winget' {
            $wingetId = Get-AppWingetId -App $App
            if (-not $wingetId) {
                return @{ Success = $false; ExitCode = 1; Error = 'no winget id'; Action = 'none' }
            }
            
            if ($DryRun) {
                $action = if ($IsUpgrade) { 'would upgrade' } else { 'would install' }
                return @{ Success = $true; ExitCode = 0; Action = $action; DryRun = $true }
            }
            
            try {
                $action = if ($IsUpgrade) { 'upgrade' } else { 'install' }
                
                if ($script:WingetScript) {
                    & pwsh -NoProfile -File $script:WingetScript $action --id $wingetId 2>&1 | Out-Null
                } else {
                    if ($IsUpgrade) {
                        & winget upgrade --id $wingetId --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Null
                    } else {
                        & winget install --id $wingetId --accept-source-agreements --accept-package-agreements -e 2>&1 | Out-Null
                    }
                }
                
                $exitCode = if ($LASTEXITCODE) { $LASTEXITCODE } else { 0 }
                return @{ Success = ($exitCode -eq 0); ExitCode = $exitCode; Action = $action }
            } catch {
                return @{ Success = $false; ExitCode = 1; Error = $_.ToString(); Action = 'failed' }
            }
        }
        'custom' {
            if ($IsUpgrade) {
                # Custom driver doesn't support upgrade - report manual intervention needed
                return @{ Success = $false; ExitCode = 1; Action = 'manual_upgrade_needed'; Error = 'custom driver does not support upgrade' }
            }
            return Install-CustomApp -App $App -DryRun $DryRun
        }
        default {
            return @{ Success = $false; ExitCode = 1; Error = "unknown driver: $driver"; Action = 'none' }
        }
    }
}

#endregion Driver Abstraction (Bundle C)

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

#region Bundle D - Sanitization Helpers

<#
.SYNOPSIS
    Patterns for fields that look like secrets or local paths.
#>
$script:SensitiveFieldPatterns = @(
    'password', 'secret', 'token', 'apikey', 'api_key', 'api-key',
    'credential', 'auth', 'private', 'key'
)

$script:LocalPathPatterns = @(
    '^[A-Za-z]:\\Users\\',
    '^C:\\Users\\',
    '^/home/',
    '^/Users/',
    '\$env:USERPROFILE',
    '\$env:LOCALAPPDATA',
    '\$env:APPDATA'
)

function Test-IsExamplesDirectory {
    param([string]$Path)
    
    if (-not $Path) { return $false }
    
    try {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
        $examplesDir = [System.IO.Path]::GetFullPath($script:ExamplesManifestsDir)
        return $resolvedPath.StartsWith($examplesDir, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Test-PathLooksLikeSecret {
    param([string]$Value)
    
    if (-not $Value) { return $false }
    
    $lowerValue = $Value.ToLower()
    foreach ($pattern in $script:SensitiveFieldPatterns) {
        if ($lowerValue -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-PathLooksLikeLocalPath {
    param([string]$Value)
    
    if (-not $Value) { return $false }
    
    foreach ($pattern in $script:LocalPathPatterns) {
        if ($Value -match $pattern) {
            return $true
        }
    }
    return $false
}

function Invoke-SanitizeManifest {
    <#
    .SYNOPSIS
        Sanitize a manifest by removing machine-specific fields, secrets, and local paths.
    .DESCRIPTION
        - Removes 'captured' timestamp
        - Removes 'machine' field if present
        - Removes fields that look like secrets or local paths (best-effort)
        - Sorts apps array by id for deterministic output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        
        [Parameter(Mandatory = $false)]
        [string]$NewName
    )
    
    $sanitized = @{}
    
    # Copy version
    if ($Manifest.version) {
        $sanitized.version = $Manifest.version
    } else {
        $sanitized.version = 1
    }
    
    # Set name (use provided or strip machine-specific parts)
    if ($NewName) {
        $sanitized.name = $NewName
    } elseif ($Manifest.name) {
        # Remove machine name from existing name if present
        $name = $Manifest.name -replace $env:COMPUTERNAME, '' -replace '--', '-' -replace '^-|-$', ''
        $sanitized.name = if ($name) { $name.ToLower() } else { 'sanitized' }
    } else {
        $sanitized.name = 'sanitized'
    }
    
    # DO NOT copy 'captured' timestamp - this is machine-specific
    # DO NOT copy 'machine' field if present
    
    # Copy includes if present (but not machine-specific ones)
    if ($Manifest.includes) {
        $sanitized.includes = @($Manifest.includes | Where-Object { 
            $_ -notmatch 'local/' -and $_ -notmatch $env:COMPUTERNAME
        })
        if ($sanitized.includes.Count -eq 0) {
            $sanitized.Remove('includes')
        }
    }
    
    # Sanitize and sort apps
    $sanitizedApps = @()
    if ($Manifest.apps) {
        foreach ($app in $Manifest.apps) {
            $sanitizedApp = @{}
            
            # Copy safe fields
            if ($app.id) { $sanitizedApp.id = $app.id }
            if ($app.refs) { $sanitizedApp.refs = $app.refs }
            if ($app.driver) { $sanitizedApp.driver = $app.driver }
            if ($app.version) { $sanitizedApp.version = $app.version }
            
            # Copy custom config but sanitize paths
            if ($app.custom) {
                $sanitizedCustom = @{}
                if ($app.custom.installScript -and -not (Test-PathLooksLikeLocalPath -Value $app.custom.installScript)) {
                    $sanitizedCustom.installScript = $app.custom.installScript
                }
                if ($app.custom.detect) {
                    $sanitizedDetect = @{}
                    if ($app.custom.detect.type) { $sanitizedDetect.type = $app.custom.detect.type }
                    # Only include path if it's not a user-specific path
                    if ($app.custom.detect.path -and -not (Test-PathLooksLikeLocalPath -Value $app.custom.detect.path)) {
                        $sanitizedDetect.path = $app.custom.detect.path
                    }
                    if ($app.custom.detect.key) { $sanitizedDetect.key = $app.custom.detect.key }
                    if ($app.custom.detect.value) { $sanitizedDetect.value = $app.custom.detect.value }
                    if ($sanitizedDetect.Count -gt 0) {
                        $sanitizedCustom.detect = $sanitizedDetect
                    }
                }
                if ($sanitizedCustom.Count -gt 0) {
                    $sanitizedApp.custom = $sanitizedCustom
                }
            }
            
            # Skip apps that look like they contain secrets
            $skipApp = $false
            foreach ($key in $app.Keys) {
                if (Test-PathLooksLikeSecret -Value $key) {
                    $skipApp = $true
                    break
                }
            }
            
            if (-not $skipApp -and $sanitizedApp.Count -gt 0) {
                $sanitizedApps += $sanitizedApp
            }
        }
        
        # Sort apps by id for deterministic output
        $sanitized.apps = @($sanitizedApps | Sort-Object -Property { $_.id })
    } else {
        $sanitized.apps = @()
    }
    
    # Copy restore and verify arrays (empty by default for examples)
    # Use explicit array creation to ensure non-null even when empty
    $sanitized.restore = [System.Collections.ArrayList]::new()
    $sanitized.verify = [System.Collections.ArrayList]::new()
    
    return $sanitized
}

#endregion Bundle D - Sanitization Helpers

function Invoke-CaptureCore {
    <#
    .SYNOPSIS
        Core capture logic. Returns structured result only - no stream output.
    #>
    param(
        [string]$OutputPath,
        [bool]$IsExample,
        [bool]$IsSanitize,
        [string]$ManifestName,
        [string]$CustomExamplesDir,
        [bool]$ForceOverwrite
    )
    
    # Determine effective examples directory
    $effectiveExamplesDir = if ($CustomExamplesDir) {
        $CustomExamplesDir
    } else {
        $script:ExamplesManifestsDir
    }
    
    # Legacy -Example flag: generate static example manifest
    if ($IsExample -and -not $IsSanitize) {
        $examplePath = if ($OutputPath) { $OutputPath } else { Join-Path $script:AutosuiteRoot "provisioning\manifests\example.jsonc" }
        $null = Write-ExampleManifest -Path $examplePath
        Write-Host "[autosuite] Capture: example manifest written to $examplePath" -ForegroundColor Green
        return @{ Success = $true; OutputPath = $examplePath; Sanitized = $false; IsExample = $true }
    }
    
    # Determine output path based on flags
    $outPath = $null
    $isExamplesTarget = $false
    
    if ($OutputPath) {
        # Explicit -Out overrides everything
        $outPath = $OutputPath
        $isExamplesTarget = Test-IsExamplesDirectory -Path $outPath
    } elseif ($IsSanitize) {
        # -Sanitize: output to examples directory
        $fileName = if ($ManifestName) { 
            "$($ManifestName.ToLower() -replace '\s+', '-').jsonc" 
        } else { 
            "sanitized.jsonc" 
        }
        
        if (-not (Test-Path $effectiveExamplesDir)) {
            New-Item -ItemType Directory -Path $effectiveExamplesDir -Force | Out-Null
        }
        $outPath = Join-Path $effectiveExamplesDir $fileName
        $isExamplesTarget = $true
    } else {
        # Default: local/<machine>.jsonc (gitignored)
        $machineName = $env:COMPUTERNAME.ToLower()
        if (-not (Test-Path $script:LocalManifestsDir)) {
            New-Item -ItemType Directory -Path $script:LocalManifestsDir -Force | Out-Null
        }
        $outPath = Join-Path $script:LocalManifestsDir "$machineName.jsonc"
    }
    
    # GUARDRAIL: Block non-sanitized writes to examples directory
    if ($isExamplesTarget -and -not $IsSanitize) {
        Write-Host "[ERROR] Cannot write non-sanitized capture to examples directory." -ForegroundColor Red
        Write-Host "        Use -Sanitize flag or choose a different output path." -ForegroundColor Yellow
        return @{ Success = $false; Error = "Non-sanitized write to examples directory blocked"; Blocked = $true }
    }
    
    # GUARDRAIL: Prevent overwrite of existing example manifests without -Force
    if ($isExamplesTarget -and (Test-Path $outPath) -and -not $ForceOverwrite) {
        Write-Host "[ERROR] Example manifest already exists: $outPath" -ForegroundColor Red
        Write-Host "        Use -Force to overwrite existing example manifests." -ForegroundColor Yellow
        return @{ Success = $false; Error = "Example manifest exists, use -Force to overwrite"; ExitCode = 1; Blocked = $true }
    }
    
    if ($IsSanitize) {
        Write-Host "[autosuite] Capture: sanitization enabled" -ForegroundColor Cyan
        
        # First capture to a temp location
        $tempDir = Join-Path $env:TEMP "autosuite-capture-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempPath = Join-Path $tempDir "raw-capture.jsonc"
        
        # Delegate to provisioning CLI for raw capture
        $cliArgs = @{ OutManifest = $tempPath }
        $captureResult = Invoke-ProvisioningCli -ProvisioningCommand "capture" -Arguments $cliArgs
        
        if (-not (Test-Path $tempPath)) {
            Write-Host "[ERROR] Raw capture failed - no output file generated" -ForegroundColor Red
            return @{ Success = $false; Error = "Raw capture failed" }
        }
        
        # Read and sanitize the manifest
        $rawContent = Get-Content -Path $tempPath -Raw
        $jsonContent = $rawContent -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
        $rawManifest = $jsonContent | ConvertFrom-Json
        
        # Convert PSCustomObject to hashtable for sanitization
        $manifestHash = @{}
        $rawManifest.PSObject.Properties | ForEach-Object { 
            $manifestHash[$_.Name] = $_.Value 
        }
        
        # Sanitize
        $sanitizedManifest = Invoke-SanitizeManifest -Manifest $manifestHash -NewName $ManifestName
        
        # Write sanitized manifest
        $parentDir = Split-Path -Parent $outPath
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        
        # Add header comment for sanitized manifests
        $header = @"
{
  // Sanitized example manifest
  // Generated via: autosuite capture -Sanitize
  // This file is safe to commit - no machine-specific data or timestamps

"@
        $jsonBody = ($sanitizedManifest | ConvertTo-Json -Depth 10).TrimStart('{')
        $jsoncContent = $header + $jsonBody
        
        Set-Content -Path $outPath -Value $jsoncContent -Encoding UTF8
        
        # Cleanup temp
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "[autosuite] Capture: sanitized manifest written to $outPath" -ForegroundColor Green
        
        return @{ 
            Success = $true
            OutputPath = $outPath
            Sanitized = $true
            AppCount = $sanitizedManifest.apps.Count
        }
    }
    
    # Non-sanitized capture: delegate to provisioning CLI
    $cliArgs = @{ OutManifest = $outPath }
    $null = Invoke-ProvisioningCli -ProvisioningCommand "capture" -Arguments $cliArgs
    
    return @{ Success = $true; OutputPath = $outPath; Sanitized = $false }
}

function Invoke-VerifyCore {
    <#
    .SYNOPSIS
        Core verify logic. Returns structured result only - no stream output.
    #>
    param(
        [string]$ManifestPath,
        [switch]$SkipStateWrite
    )
    
    $manifest = Read-Manifest -Path $ManifestPath
    
    if (-not $manifest) {
        return @{ Success = $false; ExitCode = 1; Error = "Failed to read manifest"; OkCount = 0; MissingCount = 0; MissingApps = @(); VersionMismatches = 0 }
    }
    
    $okCount = 0
    $missingCount = 0
    $versionMismatchCount = 0
    $missingApps = @()
    $versionMismatchApps = @()
    $appsObserved = @{}
    $timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    
    # Get installed apps map for drift detection (winget only)
    $installedAppsMap = Get-InstalledAppsMap
    
    foreach ($app in $manifest.apps) {
        $driver = Get-AppDriver -App $app
        $appDisplayId = if ($driver -eq 'winget') { Get-AppWingetId -App $app } else { $app.id }
        
        if (-not $appDisplayId) {
            continue
        }
        
        # Use driver abstraction to check installation
        $installStatus = Test-AppInstalledWithDriver -App $app
        
        if ($installStatus.Installed) {
            # Check version constraint if present
            $versionConstraint = Parse-VersionConstraint -Constraint $app.version
            $versionSatisfied = $true
            $versionCheckResult = $null
            
            if ($versionConstraint) {
                $versionCheckResult = Test-VersionConstraint -InstalledVersion $installStatus.Version -Constraint $versionConstraint
                $versionSatisfied = $versionCheckResult.Satisfied
            }
            
            if ($versionSatisfied) {
                Write-Host "  [OK] $appDisplayId (driver: $driver)" -ForegroundColor Green
                $okCount++
            } else {
                Write-Host "  [VERSION] $appDisplayId - $($versionCheckResult.Reason)" -ForegroundColor Yellow
                $versionMismatchCount++
                $versionMismatchApps += @{
                    id = $appDisplayId
                    reason = $versionCheckResult.Reason
                    installedVersion = $installStatus.Version
                    constraint = $app.version
                }
            }
            
            # Record observed app
            $appsObserved[$appDisplayId] = @{
                installed = $true
                driver = $driver
                version = $installStatus.Version
                versionConstraint = $app.version
                versionSatisfied = $versionSatisfied
                lastSeenUtc = $timestampUtc
            }
        } else {
            Write-Host "  [MISSING] $appDisplayId (driver: $driver)" -ForegroundColor Red
            $missingCount++
            $missingApps += $appDisplayId
            $appsObserved[$appDisplayId] = @{
                installed = $false
                driver = $driver
                version = $null
                versionConstraint = $app.version
                versionSatisfied = $false
                lastSeenUtc = $timestampUtc
            }
        }
    }
    
    # Compute drift (extras) - only for winget apps currently
    $drift = Compute-Drift -ManifestPath $ManifestPath -InstalledAppsMap $installedAppsMap
    $extraCount = $drift.ExtraCount
    
    Write-Host ""
    Write-Host "[autosuite] Verify: Summary" -ForegroundColor Cyan
    Write-Host "  Installed OK:       $okCount" -ForegroundColor Green
    Write-Host "  Missing:            $missingCount" -ForegroundColor $(if ($missingCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Version Mismatches: $versionMismatchCount" -ForegroundColor $(if ($versionMismatchCount -gt 0) { "Yellow" } else { "Green" })
    
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
            versionMismatchCount = $versionMismatchCount
            missingApps = $missingApps
            versionMismatchApps = $versionMismatchApps
            success = ($missingCount -eq 0 -and $versionMismatchCount -eq 0)
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
    
    # Determine overall success: missing OR version mismatch = failure
    $overallSuccess = ($missingCount -eq 0 -and $versionMismatchCount -eq 0)
    
    if ($missingCount -gt 0) {
        Write-Host ""
        Write-Host "Missing apps:" -ForegroundColor Yellow
        foreach ($app in $missingApps) {
            Write-Host "  - $app"
        }
    }
    
    if ($versionMismatchCount -gt 0) {
        Write-Host ""
        Write-Host "Version mismatches:" -ForegroundColor Yellow
        foreach ($mismatch in $versionMismatchApps) {
            Write-Host "  - $($mismatch.id): $($mismatch.reason)"
        }
    }
    
    if (-not $overallSuccess) {
        return @{ 
            Success = $false
            ExitCode = 1
            OkCount = $okCount
            MissingCount = $missingCount
            VersionMismatches = $versionMismatchCount
            MissingApps = $missingApps
            VersionMismatchApps = $versionMismatchApps
            ExtraCount = $extraCount
        }
    }
    
    return @{ 
        Success = $true
        ExitCode = 0
        OkCount = $okCount
        MissingCount = $missingCount
        VersionMismatches = $versionMismatchCount
        MissingApps = @()
        VersionMismatchApps = @()
        ExtraCount = $extraCount
    }
}

function Invoke-PlanCore {
    param(
        [string]$ManifestPath
    )
    
    $cliArgs = @{ Manifest = $ManifestPath }
    return Invoke-ProvisioningCli -ProvisioningCommand "plan" -Arguments $cliArgs
}

function Invoke-ReportCore {
    <#
    .SYNOPSIS
        Core report logic. Returns structured result only - no stream output.
    #>
    param(
        [string]$ManifestPath,
        [bool]$OutputJson
    )
    
    $state = Read-AutosuiteState
    
    if (-not $state) {
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
        } else {
            Write-Host "  Error computing drift: $($drift.Error)" -ForegroundColor Red
        }
    }
    
    return @{ Success = $true; ExitCode = 0; HasState = $true }
}

function Invoke-DoctorCore {
    <#
    .SYNOPSIS
        Core doctor logic. Returns structured result only - no stream output.
    #>
    param(
        [string]$ManifestPath
    )
    
    Write-Host ""
    Write-Host "=== Autosuite Doctor ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check state
    $state = Read-AutosuiteState
    $hasState = $null -ne $state
    $stateStatus = if ($hasState) { "present" } else { "absent" }
    
    # Compute drift counts for stable marker (default 0 if no manifest)
    $driftMissing = 0
    $driftExtra = 0
    
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
            $driftMissing = $drift.MissingCount
            $driftExtra = $drift.ExtraCount
        } else {
            Write-Host "  [ERROR] Could not compute drift: $($drift.Error)" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Delegate to provisioning doctor for additional checks
    Write-Host "Provisioning Subsystem:" -ForegroundColor Yellow
    $provResult = Invoke-ProvisioningCli -ProvisioningCommand "doctor" -Arguments @{}
    
    return @{ Success = $true; ExitCode = 0; HasState = $hasState; StateStatus = $stateStatus; DriftMissing = $driftMissing; DriftExtra = $driftExtra }
}

function Invoke-StateResetCore {
    <#
    .SYNOPSIS
        Core state reset logic. Returns structured result only - no stream output.
    #>
    $statePath = Get-AutosuiteStatePath
    
    if (-not (Test-Path $statePath)) {
        Write-Host "No state file found at $statePath" -ForegroundColor Yellow
        return @{ Success = $true; ExitCode = 0; WasReset = $false }
    }
    
    try {
        Remove-Item -Path $statePath -Force -ErrorAction Stop
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

# Handle --version flag before anything else
if ($Version.IsPresent) {
    Write-Host $script:VersionString
    exit 0
}

Show-Banner

if (-not $Command) {
    Show-Help
    exit 0
}

$exitCode = 0

switch ($Command) {
    "capture" {
        Write-Information "[autosuite] Capture: starting..." -InformationAction Continue
        $captureResult = Invoke-CaptureCore -OutputPath $Out -IsExample $Example.IsPresent -IsSanitize $Sanitize.IsPresent -ManifestName $Name -CustomExamplesDir $ExamplesDir -ForceOverwrite $Force.IsPresent
        if ($captureResult.OutputPath) {
            Write-Information "[autosuite] Capture: output path is $($captureResult.OutputPath)" -InformationAction Continue
        }
        if ($captureResult.Blocked) {
            Write-Information "[autosuite] Capture: BLOCKED - $($captureResult.Error)" -InformationAction Continue
        }
        if ($captureResult.Success) {
            $completedMsg = if ($captureResult.Sanitized) { "completed (sanitized, $($captureResult.AppCount) apps)" } else { "completed" }
            Write-Information "[autosuite] Capture: $completedMsg" -InformationAction Continue
        }
        if ($captureResult -and $captureResult.ExitCode) {
            $exitCode = $captureResult.ExitCode
        } elseif ($captureResult -and -not $captureResult.Success) {
            $exitCode = 1
        }
    }
    "apply" {
        $resolvedPath = Resolve-ManifestPathWithValidation -ProfileName $Profile -ManifestPath $Manifest -CommandName "apply"
        if (-not $resolvedPath) {
            exit 1
        }
        Write-Information "[autosuite] Apply: starting with manifest $resolvedPath" -InformationAction Continue
        $result = Invoke-ApplyCore -ManifestPath $resolvedPath -IsDryRun $DryRun.IsPresent -IsOnlyApps $OnlyApps.IsPresent
        Write-Information "[autosuite] Apply: completed ExitCode=$($result.ExitCode)" -InformationAction Continue
        $exitCode = $result.ExitCode
    }
    "verify" {
        $resolvedPath = Resolve-ManifestPathWithValidation -ProfileName $Profile -ManifestPath $Manifest -CommandName "verify"
        if (-not $resolvedPath) {
            exit 1
        }
        Write-Information "[autosuite] Verify: checking manifest $resolvedPath" -InformationAction Continue
        $result = Invoke-VerifyCore -ManifestPath $resolvedPath
        Write-Information "[autosuite] Verify: OkCount=$($result.OkCount) MissingCount=$($result.MissingCount) VersionMismatches=$($result.VersionMismatches) ExtraCount=$($result.ExtraCount)" -InformationAction Continue
        Write-Information "[autosuite] Drift: Missing=$($result.MissingCount) Extra=$($result.ExtraCount) VersionMismatches=$($result.VersionMismatches)" -InformationAction Continue
        $passedFailed = if ($result.Success) { "PASSED" } else { "FAILED" }
        Write-Information "[autosuite] Verify: $passedFailed" -InformationAction Continue
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
        Write-Information "[autosuite] Report: reading state..." -InformationAction Continue
        $result = Invoke-ReportCore -ManifestPath $Manifest -OutputJson $Json.IsPresent
        if ($result.HasState) {
            Write-Information "[autosuite] Report: completed" -InformationAction Continue
        } else {
            Write-Information "[autosuite] Report: no state found" -InformationAction Continue
        }
        $exitCode = $result.ExitCode
    }
    "doctor" {
        Write-Information "[autosuite] Doctor: checking environment..." -InformationAction Continue
        $result = Invoke-DoctorCore -ManifestPath $Manifest
        Write-Information "[autosuite] Doctor: state=$($result.StateStatus) driftMissing=$($result.DriftMissing) driftExtra=$($result.DriftExtra)" -InformationAction Continue
        Write-Information "[autosuite] Doctor: completed" -InformationAction Continue
        $exitCode = $result.ExitCode
    }
    "state" {
        switch ($SubCommand) {
            "reset" {
                Write-Information "[autosuite] State: resetting..." -InformationAction Continue
                $result = Invoke-StateResetCore
                if ($result.WasReset) {
                    Write-Information "[autosuite] State: reset completed" -InformationAction Continue
                } else {
                    Write-Information "[autosuite] State: no state file to reset" -InformationAction Continue
                }
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
