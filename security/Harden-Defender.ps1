#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies an idempotent, reversible hardened Microsoft Defender configuration on Windows 11.

.DESCRIPTION
    Harden-Defender is the source of truth for this host's Microsoft Defender posture when
    Defender is the sole, resident antivirus. It is safe to run repeatedly: every control
    converges to the declared desired state (set-semantics), so re-running never accretes
    duplicate configuration.

    The script applies four classes of change to Defender configuration only (unless the
    optional -EnableLSAProtection switch is passed, which additionally writes the LSA
    RunAsPPL registry value):

      1. Cloud / baseline preferences (Set-MpPreference) - always applied, low risk.
      2. Attack Surface Reduction (ASR) rules - staged audit -> enforce.
      3. Controlled Folder Access (CFA) - audit-first, blocks only on explicit opt-in.
      4. Exclusions (Add-MpPreference) - opt-in dev build paths / process names.

    It also reports (without changing) Tamper Protection, LSA Protection, HVCI / Memory
    Integrity, Credential Guard, and system Exploit Protection state, and warns when Tamper
    Protection is off (changes may otherwise silently fail) or when an applied setting does
    not read back as expected (managed by Group Policy / Intune).

    A timestamped backup of the prior state is written before any change, enabling -Rollback.

    Pure ASR logic (rule catalog, desired-state, promotion resolution) lives in the dot-sourced
    Defender-Hardening.Helpers.ps1 and is unit-tested in tests/unit/Harden-Defender.Tests.ps1.

.PARAMETER Mode
    Audit   : every stageable control is observe-only. ASR (all phases) = audit, CFA = audit.
              The baseline cloud preferences are still applied (they are not disruptive).
    Enforce : Phase 1 ASR rules block; Phase 2 (reviewed set) and Phase 3 (extended coverage)
              ASR rules stay in audit unless promoted with -PromoteRules; CFA stays in audit
              unless -EnableControlledFolderAccess is set.
    Default is Audit.

.PARAMETER PromoteRules
    One or more Phase 2/3 ASR rules to promote from audit to block (only honoured in -Mode
    Enforce). Each entry may be the rule's GUID, its canonical name, or its short key.
    Phase 2: BlockOfficeChildProcesses, BlockObfuscatedScripts,
             BlockEmailExecutableContent, BlockPsexecWmiProcessCreation
    Phase 3: BlockAdobeReaderChildProcesses, BlockJsVbsLaunchingExecutables,
             BlockOfficeExecutableContent, BlockOfficeCodeInjection,
             BlockOfficeCommsChildProcesses, BlockSafeModeReboot,
             BlockUntrustedUsbProcesses, BlockImpersonatedSystemTools,
             BlockOfficeMacroWin32Api, AdvancedRansomwareProtection
    Caution: promote AdvancedRansomwareProtection only after -ExclusionPath covers self-built
    binary output directories (it blocks unknown-reputation files).

.PARAMETER EnableControlledFolderAccess
    In -Mode Enforce, set Controlled Folder Access to Enabled (block). Ignored in Audit mode
    (CFA stays in audit). CFA has the highest dev-workflow friction; whitelist legitimate
    writers before enabling.

.PARAMETER MinimizeTelemetry
    Drop MAPSReporting from Advanced to Basic (less cloud telemetry, slightly weaker cloud
    classification). SubmitSamplesConsent is NeverSend regardless.

.PARAMETER EnableLSAProtection
    Enable LSA Protection (RunAsPPL) via the registry. Complements the Phase 1 LSASS ASR
    rule. Takes effect after a reboot. Off by default because it can break custom smartcard
    drivers / LSA plugins - opt in deliberately.

.PARAMETER LSAProtectionUefiLock
    With -EnableLSAProtection, write RunAsPPL = 1 (UEFI-locked, tamper-resistant, harder to
    undo) instead of the default RunAsPPL = 2 (enabled, no UEFI lock, reversible).

.PARAMETER ExclusionPath
    Defender exclusion paths to add (dev build-output directories). Default empty. Reduces
    protection - add only trusted, frequently-rebuilt locations.

.PARAMETER ExclusionProcess
    Defender exclusion process names to add (e.g. self-built binaries). Default empty.

.PARAMETER Rollback
    Path to a backup JSON produced by a prior run. Restores Defender configuration to the
    state captured in that file and exits. Mutually exclusive with the apply parameters.

.PARAMETER OutputDirectory
    Where logs and backups are written. Default: %ProgramData%\DefenderHardening
    (off the repo, on the host).

.PARAMETER Transcript
    Also wrap the run in Start-Transcript / Stop-Transcript.

.EXAMPLE
    .\Harden-Defender.ps1
    Audit run: baseline applied, all ASR rules + CFA in audit, full backup + posture report.

.EXAMPLE
    .\Harden-Defender.ps1 -Mode Enforce
    Block Phase 1 ASR rules; Phase 2 rules and CFA remain in audit.

.EXAMPLE
    .\Harden-Defender.ps1 -Mode Enforce -PromoteRules BlockObfuscatedScripts,BlockPsexecWmiProcessCreation
    Enforce Phase 1, and promote two reviewed Phase 2 rules to block.

.EXAMPLE
    .\Harden-Defender.ps1 -Mode Enforce -EnableControlledFolderAccess -EnableLSAProtection
    Full enforce, CFA blocking, and LSA Protection enabled (reboot required for LSA).

.EXAMPLE
    .\Harden-Defender.ps1 -WhatIf -Mode Enforce
    Show every change the enforce run would make, without touching the host.

.EXAMPLE
    .\Harden-Defender.ps1 -Rollback "C:\ProgramData\DefenderHardening\backups\Defender-Backup_20260607-101500.json"
    Restore the configuration captured in that backup.

.NOTES
    Requires: Windows 11, elevation, the built-in Defender PowerShell module. No network
    calls, no external module dependencies.

    ASR rule GUIDs are sourced from the Microsoft Learn "Attack surface reduction rules
    reference". Tamper Protection cannot be set by script (reported only). HVCI / Memory
    Integrity and WDAC / Smart App Control are deliberately out of scope.

    Rationale / full comparison: Knowledge Base/Notes/Research/Personal/
    windows-defender-hardening-av-posture-and-config-surface.md
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [ValidateSet('Audit', 'Enforce')]
    [string]$Mode = 'Audit',

    [Parameter(ParameterSetName = 'Apply')]
    [string[]]$PromoteRules = @(),

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$EnableControlledFolderAccess,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$MinimizeTelemetry,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$EnableLSAProtection,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$LSAProtectionUefiLock,

    [Parameter(ParameterSetName = 'Apply')]
    [string[]]$ExclusionPath = @(),

    [Parameter(ParameterSetName = 'Apply')]
    [string[]]$ExclusionProcess = @(),

    [Parameter(ParameterSetName = 'Rollback', Mandatory = $true)]
    [string]$Rollback,

    [string]$OutputDirectory = (Join-Path $env:ProgramData 'DefenderHardening'),

    [switch]$Transcript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pure ASR logic (catalog, desired-state, promotion resolution, action formatting).
$script:HelpersPath = Join-Path $PSScriptRoot 'Defender-Hardening.Helpers.ps1'
if (-not (Test-Path -LiteralPath $script:HelpersPath)) {
    throw "Required helpers file not found: $($script:HelpersPath)"
}
. $script:HelpersPath

# ---------------------------------------------------------------------------
# Constants / script state
# ---------------------------------------------------------------------------

$script:LsaKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$script:LogFile = $null
$script:Stats = @{ Changed = 0; Warn = 0; Error = 0 }

# ---------------------------------------------------------------------------
# Logging / utility
# ---------------------------------------------------------------------------

function Initialize-Output {
    <#
    .SYNOPSIS
        Resolves the output directory tree and the script-scoped log file path. With -NoFiles
        (used under -WhatIf) it resolves paths only and creates nothing, leaving logging
        console-only so a preview never touches the filesystem.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir,
        [switch]$NoFiles
    )

    $logsDir = Join-Path $BaseDir 'logs'
    $backupsDir = Join-Path $BaseDir 'backups'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    if ($NoFiles) {
        $script:LogFile = $null
    }
    else {
        foreach ($d in @($BaseDir, $logsDir, $backupsDir)) {
            if (-not (Test-Path -LiteralPath $d)) {
                New-Item -ItemType Directory -Path $d -Force | Out-Null
            }
        }
        $script:LogFile = Join-Path $logsDir "Harden-Defender_$stamp.log"
    }

    return [pscustomobject]@{ LogsDir = $logsDir; BackupsDir = $backupsDir; Stamp = $stamp }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a structured, levelled line to both the console (coloured) and the log file.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Change', 'Warn', 'Error', 'Success', 'Header', 'Detail')]
        [string]$Level = 'Info'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value "[$ts] [$($Level.ToUpper())] $Message"
    }

    switch ($Level) {
        'Header'  { Write-Host ''; Write-Host "== $Message ==" -ForegroundColor Cyan }
        'Change'  { Write-Host "  ~ $Message" -ForegroundColor Cyan;   $script:Stats.Changed++ }
        'Warn'    { Write-Host "  ! $Message" -ForegroundColor Yellow; $script:Stats.Warn++ }
        'Error'   { Write-Host "  x $Message" -ForegroundColor Red;    $script:Stats.Error++ }
        'Success' { Write-Host "  + $Message" -ForegroundColor Green }
        'Detail'  { Write-Host "    $Message" -ForegroundColor DarkGray }
        default   { Write-Host "  - $Message" -ForegroundColor Gray }
    }
}

function Test-IsElevated {
    <#
    .SYNOPSIS
        Returns $true when the current session is elevated (Administrator).
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentAsrMap {
    <#
    .SYNOPSIS
        Returns the currently configured ASR rules as an ordered map of lowercase GUID -> action code.
    #>
    $prefs = Get-MpPreference
    $ids = @($prefs.AttackSurfaceReductionRules_Ids)
    $actions = @($prefs.AttackSurfaceReductionRules_Actions)
    $map = [ordered]@{}
    for ($i = 0; $i -lt $ids.Count; $i++) {
        if ($ids[$i]) {
            $map[([string]$ids[$i]).ToLower()] = [int]$actions[$i]
        }
    }
    return $map
}

function Test-JsonProperty {
    <#
    .SYNOPSIS
        StrictMode-safe test for whether a (ConvertFrom-Json) object has a named property.
    #>
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name])
}

# ---------------------------------------------------------------------------
# Apply helpers (host-mutating)
# ---------------------------------------------------------------------------

function Set-MpScalar {
    <#
    .SYNOPSIS
        Idempotently sets one Set-MpPreference scalar with before -> after logging and read-back
        verification. Logs a warning if the value does not stick (Tamper Protection / managed policy).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ParamName,
        [Parameter(Mandatory = $true)]$Desired,
        [Parameter(Mandatory = $true)][string]$Display,
        [Parameter(Mandatory = $true)]$Prefs
    )

    $before = "$($Prefs.$ParamName)"
    $desiredStr = "$Desired"

    if ($before -ieq $desiredStr) {
        Write-Log "$Display already '$desiredStr'" Detail
        return
    }
    if ($WhatIfPreference) {
        Write-Log "$Display: would change '$before' -> '$desiredStr' (WhatIf)" Change
        return
    }

    try {
        $splat = @{ $ParamName = $Desired }
        Set-MpPreference @splat -ErrorAction Stop
        $after = "$((Get-MpPreference).$ParamName)"
        if ($after -ieq $desiredStr) {
            Write-Log "$Display: '$before' -> '$after'" Change
        }
        else {
            Write-Log "$Display: attempted '$before' -> '$desiredStr' but reads '$after' (possibly blocked by Tamper Protection or managed policy)" Warn
        }
    }
    catch {
        Write-Log "$Display: failed ($($_.Exception.Message))" Error
    }
}

function Invoke-BaselineHardening {
    <#
    .SYNOPSIS
        Applies the cloud / baseline Set-MpPreference settings. Applied in both Audit and
        Enforce mode (these are not disruptive).
    #>
    param([bool]$Minimize)

    Write-Log 'Cloud / baseline preferences' Header
    $maps = if ($Minimize) { 'Basic' } else { 'Advanced' }
    if ($Minimize) { Write-Log 'MinimizeTelemetry: MAPSReporting will be set to Basic' Detail }

    $prefs = Get-MpPreference
    $settings = @(
        [pscustomobject]@{ Param = 'PUAProtection';           Display = 'PUA Protection';                Desired = 'Enabled' }
        [pscustomobject]@{ Param = 'MAPSReporting';           Display = 'MAPS Reporting (cloud)';        Desired = $maps }
        [pscustomobject]@{ Param = 'CloudBlockLevel';         Display = 'Cloud Block Level';             Desired = 'High' }
        [pscustomobject]@{ Param = 'CloudExtendedTimeout';    Display = 'Cloud Extended Timeout (s)';    Desired = 50 }
        [pscustomobject]@{ Param = 'SubmitSamplesConsent';    Display = 'Submit Samples Consent';        Desired = 'NeverSend' }
        [pscustomobject]@{ Param = 'EnableNetworkProtection'; Display = 'Network Protection';            Desired = 'Enabled' }
    )
    foreach ($s in $settings) {
        Set-MpScalar -ParamName $s.Param -Desired $s.Desired -Display $s.Display -Prefs $prefs
    }
    Write-Log 'SubmitSamplesConsent=NeverSend also disables Block-at-First-Sight for never-before-seen files.' Detail
}

function Invoke-AsrHardening {
    <#
    .SYNOPSIS
        Computes the desired ASR rule set for the mode and applies it with Set-MpPreference
        (set-semantics: the declared set replaces the configured set). Logs per-rule before ->
        after and verifies the result.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string[]]$Promote
    )

    Write-Log "Attack Surface Reduction (ASR) rules - mode: $Mode" Header
    $catalog = Get-AsrRuleCatalog

    $promotedGuids = @()
    if ($Mode -eq 'Enforce') {
        $resolved = Resolve-PromotedGuids -Promote $Promote -Catalog $catalog
        foreach ($w in $resolved.Warnings) { Write-Log $w Warn }
        $promotedGuids = $resolved.Guids
    }
    elseif ($Promote -and $Promote.Count -gt 0) {
        Write-Log 'PromoteRules ignored in Audit mode (Audit keeps every rule in audit)' Warn
    }

    $before = Get-CurrentAsrMap
    $desired = Get-DesiredAsrState -Mode $Mode -PromotedGuids $promotedGuids -Catalog $catalog

    # Log the plan per rule.
    foreach ($rule in $catalog) {
        $g = $rule.Guid.ToLower()
        $b = if ($before.Contains($g)) { Format-AsrAction $before[$g] } else { 'NotConfigured' }
        $d = Format-AsrAction $desired[$g]
        if ($b -ieq $d) {
            Write-Log ("[P{0}] {1}: {2} (unchanged)" -f $rule.Phase, $rule.Name, $d) Detail
        }
        else {
            Write-Log ("[P{0}] {1}: {2} -> {3}" -f $rule.Phase, $rule.Name, $b, $d) Change
        }
    }

    if ($WhatIfPreference) {
        Write-Log 'ASR: WhatIf - no changes applied' Info
        return
    }

    $ids = @($desired.Keys)
    $actions = @($desired.Keys | ForEach-Object { $desired[$_] })
    try {
        Set-MpPreference -AttackSurfaceReductionRules_Ids $ids -AttackSurfaceReductionRules_Actions $actions -ErrorAction Stop
    }
    catch {
        Write-Log "ASR: failed to apply rule set ($($_.Exception.Message))" Error
        return
    }

    # Verify read-back.
    $after = Get-CurrentAsrMap
    foreach ($rule in $catalog) {
        $g = $rule.Guid.ToLower()
        $want = $desired[$g]
        $got = if ($after.Contains($g)) { $after[$g] } else { 0 }
        if ($got -ne $want) {
            Write-Log ("ASR verify: '{0}' expected {1} but reads {2} (possibly Tamper Protection / managed policy)" -f $rule.Name, (Format-AsrAction $want), (Format-AsrAction $got)) Warn
        }
    }
}

function Invoke-CfaHardening {
    <#
    .SYNOPSIS
        Sets Controlled Folder Access. Audit by default; blocks only in Enforce mode with
        -EnableControlledFolderAccess.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [bool]$Enable
    )

    Write-Log 'Controlled Folder Access (CFA)' Header
    $desired = 'AuditMode'
    if ($Mode -eq 'Enforce' -and $Enable) {
        $desired = 'Enabled'
    }
    elseif ($Enable) {
        Write-Log 'EnableControlledFolderAccess ignored in Audit mode (CFA stays in audit)' Warn
    }

    $prefs = Get-MpPreference
    Set-MpScalar -ParamName 'EnableControlledFolderAccess' -Desired $desired -Display 'Controlled Folder Access' -Prefs $prefs
}

function Invoke-ExclusionConfiguration {
    <#
    .SYNOPSIS
        Adds exclusion paths / process names (non-destructive Add-MpPreference; already-present
        entries are skipped). Default empty -> nothing added.
    #>
    param([string[]]$Paths, [string[]]$Processes)

    $paths = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $procs = @($Processes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($paths.Count -eq 0 -and $procs.Count -eq 0) {
        Write-Log 'Exclusions: none specified (none added)' Detail
        return
    }

    Write-Log 'Exclusions' Header
    $prefs = Get-MpPreference
    $curPaths = @($prefs.ExclusionPath)
    $curProcs = @($prefs.ExclusionProcess)

    foreach ($p in $paths) {
        if ($curPaths -contains $p) { Write-Log "Exclusion path already present: $p" Detail; continue }
        if ($WhatIfPreference) { Write-Log "Would add exclusion path: $p" Change; continue }
        try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Log "Added exclusion path: $p" Change }
        catch { Write-Log "Failed to add exclusion path '$p' ($($_.Exception.Message))" Error }
    }
    foreach ($pr in $procs) {
        if ($curProcs -contains $pr) { Write-Log "Exclusion process already present: $pr" Detail; continue }
        if ($WhatIfPreference) { Write-Log "Would add exclusion process: $pr" Change; continue }
        try { Add-MpPreference -ExclusionProcess $pr -ErrorAction Stop; Write-Log "Added exclusion process: $pr" Change }
        catch { Write-Log "Failed to add exclusion process '$pr' ($($_.Exception.Message))" Error }
    }
}

function Invoke-LsaProtection {
    <#
    .SYNOPSIS
        Enables LSA Protection (RunAsPPL). Default value 2 (no UEFI lock, reversible);
        -LSAProtectionUefiLock writes 1 (UEFI-locked). Takes effect after a reboot.
    #>
    param([bool]$UefiLock)

    Write-Log 'LSA Protection (RunAsPPL)' Header
    $desired = if ($UefiLock) { 1 } else { 2 }
    $current = (Get-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -ErrorAction SilentlyContinue).RunAsPPL
    $curStr = if ($null -eq $current) { '<not set>' } else { "$current" }

    if ($current -eq $desired) {
        Write-Log "RunAsPPL already = $desired" Detail
        return
    }
    if ($WhatIfPreference) {
        Write-Log "Would set RunAsPPL '$curStr' -> $desired (1=UEFI lock, 2=no UEFI lock)" Change
        return
    }

    try {
        New-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -Value $desired -PropertyType DWord -Force | Out-Null
        Write-Log "RunAsPPL: '$curStr' -> $desired (1=UEFI lock, 2=no UEFI lock)" Change
        Write-Log 'LSA Protection takes effect after a reboot.' Warn
    }
    catch {
        Write-Log "Failed to set RunAsPPL ($($_.Exception.Message))" Error
    }
}

# ---------------------------------------------------------------------------
# Report-only posture
# ---------------------------------------------------------------------------

function Write-PostureReport {
    <#
    .SYNOPSIS
        Reports (without changing) Tamper Protection, LSA Protection, HVCI / Memory Integrity,
        Credential Guard, and system Exploit Protection.
    #>
    Write-Log 'Security posture (report-only - not modified by this script)' Header

    try {
        $status = Get-MpComputerStatus
        if ($status.IsTamperProtected) {
            Write-Log 'Tamper Protection: ON' Success
        }
        else {
            Write-Log 'Tamper Protection: OFF - enable in Windows Security > Virus & threat protection settings (cannot be set by script). Some changes below may not persist while it is managed elsewhere.' Warn
        }
        Write-Log ("Real-time protection: {0} | Antivirus enabled: {1}" -f $status.RealTimeProtectionEnabled, $status.AntivirusEnabled) Detail
    }
    catch {
        Write-Log "Could not query Defender status ($($_.Exception.Message))" Warn
    }

    $lsa = (Get-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -ErrorAction SilentlyContinue).RunAsPPL
    if ($null -eq $lsa) { Write-Log 'LSA Protection (RunAsPPL): not configured' Info }
    elseif ($lsa -eq 1) { Write-Log 'LSA Protection (RunAsPPL): enabled (UEFI lock)' Success }
    elseif ($lsa -eq 2) { Write-Log 'LSA Protection (RunAsPPL): enabled (no UEFI lock)' Success }
    else { Write-Log "LSA Protection (RunAsPPL): value $lsa" Info }

    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
        $running = @($dg.SecurityServicesRunning)
        $hvci = if ($running -contains 2) { 'running' } else { 'not running' }
        $credGuard = if ($running -contains 1) { 'running' } else { 'not running' }
        Write-Log "HVCI / Memory Integrity: $hvci (report-only; out of scope to change - driver-compat risk)" Info
        Write-Log "Credential Guard: $credGuard" Detail
    }
    catch {
        Write-Log "Could not query Device Guard / HVCI state ($($_.Exception.Message))" Detail
    }

    try {
        $mit = Get-ProcessMitigation -System -ErrorAction Stop
        Write-Log ("Exploit Protection (system): DEP={0} ASLR(ForceRelocate)={1} CFG={2} - defaults left as-is" -f $mit.Dep.Enable, $mit.Aslr.ForceRelocateImages, $mit.Cfg.Enable) Info
    }
    catch {
        Write-Log "Could not query system Exploit Protection ($($_.Exception.Message))" Detail
    }
}

# ---------------------------------------------------------------------------
# Backup / rollback
# ---------------------------------------------------------------------------

function New-DefenderBackup {
    <#
    .SYNOPSIS
        Captures the current Defender state (baseline prefs, ASR rules, CFA, exclusions, LSA)
        to a timestamped JSON used by -Rollback, plus a full Get-MpPreference Clixml snapshot.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BackupDir,
        [Parameter(Mandatory = $true)][string]$Stamp,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    Write-Log 'Backing up current Defender state' Header
    $prefs = Get-MpPreference
    $lsa = (Get-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -ErrorAction SilentlyContinue).RunAsPPL

    $backup = [ordered]@{
        SchemaVersion = 1
        Timestamp     = $Stamp
        Host          = $env:COMPUTERNAME
        Mode          = $Mode
        Baseline      = [ordered]@{
            PUAProtection           = "$($prefs.PUAProtection)"
            MAPSReporting           = "$($prefs.MAPSReporting)"
            CloudBlockLevel         = "$($prefs.CloudBlockLevel)"
            CloudExtendedTimeout    = [int]$prefs.CloudExtendedTimeout
            SubmitSamplesConsent    = "$($prefs.SubmitSamplesConsent)"
            EnableNetworkProtection = "$($prefs.EnableNetworkProtection)"
        }
        ControlledFolderAccess = "$($prefs.EnableControlledFolderAccess)"
        Asr                    = (Get-CurrentAsrMap)
        ExclusionPath          = @($prefs.ExclusionPath)
        ExclusionProcess       = @($prefs.ExclusionProcess)
        LsaRunAsPPL            = $(if ($null -eq $lsa) { $null } else { [int]$lsa })
    }

    $jsonPath = Join-Path $BackupDir "Defender-Backup_$Stamp.json"
    if ($WhatIfPreference) {
        Write-Log "Would write backup: $jsonPath" Change
        return $jsonPath
    }

    $backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $cliPath = Join-Path $BackupDir "MpPreference_$Stamp.clixml"
    try { $prefs | Export-Clixml -LiteralPath $cliPath } catch { }

    Write-Log "Backup written: $jsonPath" Success
    return $jsonPath
}

function Restore-BaselineField {
    <#
    .SYNOPSIS
        Restores one captured Set-MpPreference value during rollback, skipping (with a warning)
        when the backup is missing the field or it is blank.
    #>
    param(
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$ParamName,
        [Parameter(Mandatory = $true)][string]$Display,
        [Parameter(Mandatory = $true)]$Prefs,
        [switch]$AsInt
    )

    if (-not (Test-JsonProperty $Source $Property)) {
        Write-Log "Rollback: backup has no '$Property' - skipped" Warn
        return
    }
    $value = $Source.$Property
    if ([string]::IsNullOrWhiteSpace("$value")) {
        Write-Log "Rollback: backup '$Property' is blank - skipped" Warn
        return
    }

    $desired = if ($AsInt) { [int]$value } else { "$value" }
    Set-MpScalar -ParamName $ParamName -Desired $desired -Display $Display -Prefs $Prefs
}

function Invoke-DefenderRollback {
    <#
    .SYNOPSIS
        Restores Defender configuration from a backup JSON produced by New-DefenderBackup.
    #>
    param([Parameter(Mandatory = $true)][string]$BackupFile)

    Write-Log 'Rolling back Defender configuration' Header
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        throw "Backup file not found: $BackupFile"
    }
    try {
        $b = Get-Content -LiteralPath $BackupFile -Raw | ConvertFrom-Json
    }
    catch {
        throw "Backup file is not valid JSON: $BackupFile ($($_.Exception.Message))"
    }
    if (-not (Test-JsonProperty $b 'Baseline') -or -not (Test-JsonProperty $b 'Asr')) {
        throw "Backup file is not a recognised Harden-Defender backup (missing 'Baseline'/'Asr'): $BackupFile"
    }

    $stamp = if (Test-JsonProperty $b 'Timestamp') { $b.Timestamp } else { 'unknown' }
    $hostName = if (Test-JsonProperty $b 'Host') { $b.Host } else { 'unknown' }
    $bMode = if (Test-JsonProperty $b 'Mode') { $b.Mode } else { 'unknown' }
    Write-Log "Restoring state captured $stamp on $hostName (mode: $bMode)" Detail

    # Baseline + CFA (each field skipped with a warning if the backup lacks it).
    $prefs = Get-MpPreference
    Restore-BaselineField -Source $b.Baseline -Property 'PUAProtection'           -ParamName 'PUAProtection'           -Display 'PUA Protection'         -Prefs $prefs
    Restore-BaselineField -Source $b.Baseline -Property 'MAPSReporting'           -ParamName 'MAPSReporting'           -Display 'MAPS Reporting'         -Prefs $prefs
    Restore-BaselineField -Source $b.Baseline -Property 'CloudBlockLevel'         -ParamName 'CloudBlockLevel'         -Display 'Cloud Block Level'      -Prefs $prefs
    Restore-BaselineField -Source $b.Baseline -Property 'CloudExtendedTimeout'    -ParamName 'CloudExtendedTimeout'    -Display 'Cloud Extended Timeout' -Prefs $prefs -AsInt
    Restore-BaselineField -Source $b.Baseline -Property 'SubmitSamplesConsent'    -ParamName 'SubmitSamplesConsent'    -Display 'Submit Samples Consent' -Prefs $prefs
    Restore-BaselineField -Source $b.Baseline -Property 'EnableNetworkProtection' -ParamName 'EnableNetworkProtection' -Display 'Network Protection'     -Prefs $prefs
    Restore-BaselineField -Source $b           -Property 'ControlledFolderAccess'  -ParamName 'EnableControlledFolderAccess' -Display 'Controlled Folder Access' -Prefs $prefs

    # ASR: restore prior actions; disable (0) managed rules that were not present before.
    $priorAsr = @{}
    if ($b.Asr) {
        foreach ($prop in $b.Asr.PSObject.Properties) { $priorAsr[$prop.Name.ToLower()] = [int]$prop.Value }
    }
    $guids = New-Object 'System.Collections.Generic.List[string]'
    $acts = New-Object 'System.Collections.Generic.List[int]'
    $seen = @{}
    foreach ($k in $priorAsr.Keys) { $guids.Add($k); $acts.Add($priorAsr[$k]); $seen[$k] = $true }
    foreach ($rule in (Get-AsrRuleCatalog)) {
        $g = $rule.Guid.ToLower()
        if (-not $seen.ContainsKey($g)) { $guids.Add($g); $acts.Add(0); $seen[$g] = $true }
    }
    if ($guids.Count -gt 0) {
        if ($WhatIfPreference) {
            Write-Log "ASR: would restore $($priorAsr.Count) prior rule(s) and disable $($guids.Count - $priorAsr.Count) added rule(s)" Change
        }
        else {
            try {
                Set-MpPreference -AttackSurfaceReductionRules_Ids $guids.ToArray() -AttackSurfaceReductionRules_Actions $acts.ToArray() -ErrorAction Stop
                Write-Log "ASR: restored $($priorAsr.Count) prior rule(s), disabled $($guids.Count - $priorAsr.Count) added rule(s)" Change
            }
            catch {
                Write-Log "ASR: failed to restore ($($_.Exception.Message))" Error
            }
        }
    }

    # Exclusions: remove only what was added after the backup (current minus prior).
    $priorPaths = @()
    if (Test-JsonProperty $b 'ExclusionPath') {
        $priorPaths = @($b.ExclusionPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $priorProcs = @()
    if (Test-JsonProperty $b 'ExclusionProcess') {
        $priorProcs = @($b.ExclusionProcess | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $curPrefs = Get-MpPreference
    foreach ($p in @($curPrefs.ExclusionPath | Where-Object { $priorPaths -notcontains $_ })) {
        if ($WhatIfPreference) { Write-Log "Would remove exclusion path: $p" Change; continue }
        try { Remove-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Log "Removed exclusion path: $p" Change } catch { Write-Log "Failed to remove exclusion path '$p'" Error }
    }
    foreach ($pr in @($curPrefs.ExclusionProcess | Where-Object { $priorProcs -notcontains $_ })) {
        if ($WhatIfPreference) { Write-Log "Would remove exclusion process: $pr" Change; continue }
        try { Remove-MpPreference -ExclusionProcess $pr -ErrorAction Stop; Write-Log "Removed exclusion process: $pr" Change } catch { Write-Log "Failed to remove exclusion process '$pr'" Error }
    }

    # LSA Protection.
    $curLsa = (Get-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -ErrorAction SilentlyContinue).RunAsPPL
    $priorLsa = if (Test-JsonProperty $b 'LsaRunAsPPL') { $b.LsaRunAsPPL } else { $null }
    if ($null -eq $priorLsa) {
        if ($null -ne $curLsa) {
            if ($WhatIfPreference) { Write-Log "Would remove RunAsPPL (currently $curLsa)" Change }
            else {
                try { Remove-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -ErrorAction Stop; Write-Log "Removed RunAsPPL (was $curLsa); reboot to apply" Change } catch { Write-Log "Failed to remove RunAsPPL ($($_.Exception.Message))" Error }
            }
        }
    }
    elseif ([int]$priorLsa -ne [int]$curLsa) {
        if ($WhatIfPreference) { Write-Log "Would restore RunAsPPL -> $([int]$priorLsa)" Change }
        else {
            try { New-ItemProperty -Path $script:LsaKey -Name 'RunAsPPL' -Value ([int]$priorLsa) -PropertyType DWord -Force | Out-Null; Write-Log "Restored RunAsPPL -> $([int]$priorLsa); reboot to apply" Change } catch { Write-Log "Failed to restore RunAsPPL ($($_.Exception.Message))" Error }
        }
    }

    Write-Log 'Rollback complete. LSA Protection changes (if any) require a reboot.' Success
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    $useTranscript = $false
    if (-not (Test-IsElevated)) {
        Write-Host 'ERROR: Harden-Defender.ps1 must be run from an elevated (Administrator) PowerShell session.' -ForegroundColor Red
        exit 1
    }
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Host 'ERROR: The Defender PowerShell module (Get-MpPreference) is not available on this host.' -ForegroundColor Red
        exit 1
    }

    $io = Initialize-Output -BaseDir $OutputDirectory -NoFiles:$WhatIfPreference
    $useTranscript = $Transcript -and -not $WhatIfPreference
    if ($useTranscript) {
        try { Start-Transcript -Path (Join-Path $io.LogsDir "Transcript_$($io.Stamp).log") -Force | Out-Null } catch { }
    }

    Write-Log 'Harden-Defender' Header
    Write-Log "Host: $env:COMPUTERNAME | User: $env:USERNAME | $(Get-Date)" Detail
    if ($script:LogFile) { Write-Log "Log file: $($script:LogFile)" Detail }
    else { Write-Log 'Log file: (console only - WhatIf)' Detail }

    if ($PSCmdlet.ParameterSetName -eq 'Rollback') {
        Invoke-DefenderRollback -BackupFile $Rollback
    }
    else {
        Write-Log "Mode: $Mode" Info
        if ($WhatIfPreference) { Write-Log 'WhatIf enabled - no changes will be made' Warn }

        Write-PostureReport
        $backupPath = New-DefenderBackup -BackupDir $io.BackupsDir -Stamp $io.Stamp -Mode $Mode

        Invoke-BaselineHardening -Minimize:$MinimizeTelemetry.IsPresent
        Invoke-AsrHardening -Mode $Mode -Promote $PromoteRules
        Invoke-CfaHardening -Mode $Mode -Enable:$EnableControlledFolderAccess.IsPresent
        Invoke-ExclusionConfiguration -Paths $ExclusionPath -Processes $ExclusionProcess

        if ($EnableLSAProtection) {
            Invoke-LsaProtection -UefiLock:$LSAProtectionUefiLock.IsPresent
        }
        else {
            Write-Log 'LSA Protection not requested (use -EnableLSAProtection to enable RunAsPPL)' Detail
        }

        Write-Log 'Post-change posture' Header
        Write-PostureReport

        Write-Log ("Done. Changes: {0}  Warnings: {1}  Errors: {2}" -f $script:Stats.Changed, $script:Stats.Warn, $script:Stats.Error) Success
        Write-Log "Backup for rollback: $backupPath" Info
        Write-Log "Rollback with: .\Harden-Defender.ps1 -Rollback `"$backupPath`"" Info
        if ($Mode -eq 'Audit') {
            Write-Log 'Next: review ASR events (Event Viewer > Microsoft-Windows-Windows Defender/Operational; ID 1122 = audited, 1121 = blocked) and DeviceEvents, then run -Mode Enforce.' Info
        }
    }

    if ($useTranscript) { try { Stop-Transcript | Out-Null } catch { } }
}
catch {
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    if ($useTranscript) { try { Stop-Transcript | Out-Null } catch { } }
    exit 1
}
