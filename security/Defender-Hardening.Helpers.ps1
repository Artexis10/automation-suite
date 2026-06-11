<#
.SYNOPSIS
    Pure helper functions for Harden-Defender.ps1.

.DESCRIPTION
    Host-independent logic extracted for testability: the Attack Surface Reduction (ASR) rule
    catalog, action formatting, promotion resolution, and desired-state computation. These
    functions contain no side effects, make no Defender / registry calls, and require no
    elevation, so they can be dot-sourced and unit-tested in CI.

    Dot-sourced by Harden-Defender.ps1 (which owns all host-mutating logic) and by
    tests/unit/Harden-Defender.Tests.ps1.
#>

function Get-AsrRuleCatalog {
    <#
    .SYNOPSIS
        Returns the catalog of ASR rules managed by Harden-Defender.

    .DESCRIPTION
        GUIDs are sourced from the Microsoft Learn "Attack surface reduction rules reference".
        Phase 1 rules block in Enforce mode (low disruption). Phase 2 rules (the originally
        reviewed set) and Phase 3 rules (extended coverage) stay in audit by default and are
        promoted to block per-rule after review - Phase 2 typically after the first audit
        cycle, Phase 3 opportunistically as audit data accumulates.

        Two client rules are deliberately NOT in this catalog (see README): "Block executable
        files from running unless they meet a prevalence, age, or trusted list criterion"
        (allowlisting - blocks self-built binaries by design) and "Block Webshell creation for
        Servers" (Exchange servers only).

    .OUTPUTS
        An array of [pscustomobject] with: Key, Phase (1|2|3), Guid, Name.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    return @(
        [pscustomobject]@{ Key = 'BlockLsassCredentialTheft';      Phase = 1; Guid = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'; Name = 'Block credential stealing from the Windows local security authority subsystem (LSASS)' }
        [pscustomobject]@{ Key = 'BlockVulnerableSignedDrivers';   Phase = 1; Guid = '56a863a9-875e-4185-98a7-b882c64b5ce5'; Name = 'Block abuse of exploited vulnerable signed drivers' }
        [pscustomobject]@{ Key = 'BlockWmiPersistence';            Phase = 1; Guid = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'; Name = 'Block persistence through WMI event subscription' }
        [pscustomobject]@{ Key = 'BlockOfficeChildProcesses';      Phase = 2; Guid = 'd4f940ab-401b-4efc-aadc-ad5f3c50688a'; Name = 'Block all Office applications from creating child processes' }
        [pscustomobject]@{ Key = 'BlockObfuscatedScripts';         Phase = 2; Guid = '5beb7efe-fd9a-4556-801d-275e5ffc04cc'; Name = 'Block execution of potentially obfuscated scripts' }
        [pscustomobject]@{ Key = 'BlockEmailExecutableContent';    Phase = 2; Guid = 'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550'; Name = 'Block executable content from email client and webmail' }
        [pscustomobject]@{ Key = 'BlockPsexecWmiProcessCreation';  Phase = 2; Guid = 'd1e49aac-8f56-4280-b9ba-993a6d77406c'; Name = 'Block process creations originating from PSExec and WMI commands' }
        [pscustomobject]@{ Key = 'BlockAdobeReaderChildProcesses'; Phase = 3; Guid = '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c'; Name = 'Block Adobe Reader from creating child processes' }
        [pscustomobject]@{ Key = 'BlockJsVbsLaunchingExecutables'; Phase = 3; Guid = 'd3e037e1-3eb8-44c8-a917-57927947596d'; Name = 'Block JavaScript or VBScript from launching downloaded executable content' }
        [pscustomobject]@{ Key = 'BlockOfficeExecutableContent';   Phase = 3; Guid = '3b576869-a4ec-4529-8536-b80a7769e899'; Name = 'Block Office applications from creating executable content' }
        [pscustomobject]@{ Key = 'BlockOfficeCodeInjection';       Phase = 3; Guid = '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84'; Name = 'Block Office applications from injecting code into other processes' }
        [pscustomobject]@{ Key = 'BlockOfficeCommsChildProcesses'; Phase = 3; Guid = '26190899-1602-49e8-8b27-eb1d0a1ce869'; Name = 'Block Office communication application from creating child processes' }
        [pscustomobject]@{ Key = 'BlockSafeModeReboot';            Phase = 3; Guid = '33ddedf1-c6e0-47cb-833e-de6133960387'; Name = 'Block rebooting machine in Safe Mode' }
        [pscustomobject]@{ Key = 'BlockUntrustedUsbProcesses';     Phase = 3; Guid = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'; Name = 'Block untrusted and unsigned processes that run from USB' }
        [pscustomobject]@{ Key = 'BlockImpersonatedSystemTools';   Phase = 3; Guid = 'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb'; Name = 'Block use of copied or impersonated system tools' }
        [pscustomobject]@{ Key = 'BlockOfficeMacroWin32Api';       Phase = 3; Guid = '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b'; Name = 'Block Win32 API calls from Office macros' }
        [pscustomobject]@{ Key = 'AdvancedRansomwareProtection';   Phase = 3; Guid = 'c1db55ab-c21a-4637-bb3f-a12568109d35'; Name = 'Use advanced protection against ransomware' }
    )
}

function Format-AsrAction {
    <#
    .SYNOPSIS
        Maps an ASR action code to a human-readable label.

    .PARAMETER Action
        ASR action code: 0 = Disabled/NotConfigured, 1 = Block (Enabled), 2 = AuditMode, 6 = Warn.

    .OUTPUTS
        String label.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][int]$Action)

    switch ($Action) {
        0 { 'NotConfigured' }
        1 { 'Block' }
        2 { 'Audit' }
        6 { 'Warn' }
        default { "Unknown($Action)" }
    }
}

function Resolve-PromotedGuids {
    <#
    .SYNOPSIS
        Resolves -PromoteRules entries to a set of Phase 2/3 rule GUIDs (pure; no logging side effects).

    .DESCRIPTION
        Each entry may be a rule's GUID, canonical Name, or short Key (case-insensitive). Entries
        that match no rule, or that match a Phase 1 rule (already blocked in Enforce), are excluded
        and reported as warnings for the caller to surface.

    .PARAMETER Promote
        Raw -PromoteRules values (may be empty or contain blanks).

    .PARAMETER Catalog
        The ASR catalog (from Get-AsrRuleCatalog).

    .OUTPUTS
        Hashtable with:
        - Guids:    string[] of resolved, lowercased, de-duplicated Phase 2 GUIDs.
        - Warnings: string[] describing ignored entries.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$Promote,
        [Parameter(Mandatory = $true)]$Catalog
    )

    $guids = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'

    foreach ($entry in @($Promote)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $match = @($Catalog | Where-Object { $_.Guid -ieq $entry -or $_.Name -ieq $entry -or $_.Key -ieq $entry })
        if ($match.Count -eq 0) {
            $warnings.Add("PromoteRules: '$entry' matched no known ASR rule - ignored")
            continue
        }
        $rule = $match[0]
        if ($rule.Phase -eq 1) {
            $warnings.Add("PromoteRules: '$($rule.Name)' is a Phase 1 rule (already blocks in Enforce) - ignored")
            continue
        }
        $g = $rule.Guid.ToLower()
        if (-not $guids.Contains($g)) { $guids.Add($g) }
    }

    return @{ Guids = $guids.ToArray(); Warnings = $warnings.ToArray() }
}

function Get-DesiredAsrState {
    <#
    .SYNOPSIS
        Computes the desired ASR rule actions for a mode (pure).

    .DESCRIPTION
        Audit   : every rule -> 2 (Audit).
        Enforce : Phase 1 -> 1 (Block); Phase 2/3 -> 1 if its GUID is in PromotedGuids, else 2 (Audit).

    .PARAMETER Mode
        Audit or Enforce.

    .PARAMETER PromotedGuids
        Lowercased Phase 2/3 GUIDs to promote to block (from Resolve-PromotedGuids). Honoured only in
        Enforce mode; ignored in Audit (kept here so callers need no extra branching).

    .PARAMETER Catalog
        The ASR catalog (from Get-AsrRuleCatalog).

    .OUTPUTS
        Ordered dictionary of lowercase GUID -> action code (int), in catalog order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Audit', 'Enforce')][string]$Mode,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$PromotedGuids,
        [Parameter(Mandatory = $true)]$Catalog
    )

    $promoted = @{}
    foreach ($g in @($PromotedGuids)) {
        if (-not [string]::IsNullOrWhiteSpace($g)) { $promoted[$g.ToLower()] = $true }
    }

    $desired = [ordered]@{}
    foreach ($rule in $Catalog) {
        $g = $rule.Guid.ToLower()
        if ($Mode -eq 'Audit') { $desired[$g] = 2 }
        elseif ($rule.Phase -eq 1) { $desired[$g] = 1 }
        elseif ($promoted.ContainsKey($g)) { $desired[$g] = 1 }
        else { $desired[$g] = 2 }
    }
    return $desired
}
