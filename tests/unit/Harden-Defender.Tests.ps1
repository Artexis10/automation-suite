<#
.SYNOPSIS
    Unit tests for the Harden-Defender pure helper functions.

.DESCRIPTION
    Tests the host-independent logic in security/Defender-Hardening.Helpers.ps1 (ASR catalog,
    desired-state computation, promotion resolution, action formatting). These tests require no
    elevation, no Defender module, and make no host changes - they never dot-source the main
    Harden-Defender.ps1 (which carries #Requires -RunAsAdministrator).
#>

BeforeAll {
    # Load test helpers
    . (Join-Path $PSScriptRoot "..\TestHelpers.ps1")

    # Load the pure helpers under test
    $helpersPath = Join-Path (Get-RepoRoot) "security\Defender-Hardening.Helpers.ps1"
    . $helpersPath

    # Known-good GUIDs (resolved from the MS Learn ASR rules reference). Used to detect drift.
    $script:ExpectedGuids = @{
        BlockLsassCredentialTheft      = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'
        BlockVulnerableSignedDrivers   = '56a863a9-875e-4185-98a7-b882c64b5ce5'
        BlockWmiPersistence            = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'
        BlockOfficeChildProcesses      = 'd4f940ab-401b-4efc-aadc-ad5f3c50688a'
        BlockObfuscatedScripts         = '5beb7efe-fd9a-4556-801d-275e5ffc04cc'
        BlockEmailExecutableContent    = 'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550'
        BlockPsexecWmiProcessCreation  = 'd1e49aac-8f56-4280-b9ba-993a6d77406c'
        BlockAdobeReaderChildProcesses = '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c'
        BlockJsVbsLaunchingExecutables = 'd3e037e1-3eb8-44c8-a917-57927947596d'
        BlockOfficeExecutableContent   = '3b576869-a4ec-4529-8536-b80a7769e899'
        BlockOfficeCodeInjection       = '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84'
        BlockOfficeCommsChildProcesses = '26190899-1602-49e8-8b27-eb1d0a1ce869'
        BlockSafeModeReboot            = '33ddedf1-c6e0-47cb-833e-de6133960387'
        BlockUntrustedUsbProcesses     = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'
        BlockImpersonatedSystemTools   = 'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb'
        BlockOfficeMacroWin32Api       = '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b'
        AdvancedRansomwareProtection   = 'c1db55ab-c21a-4637-bb3f-a12568109d35'
    }
}

Describe "Get-AsrRuleCatalog" {
    BeforeAll {
        $script:catalog = Get-AsrRuleCatalog
    }

    It "returns exactly 17 rules" {
        @($catalog).Count | Should -Be 17
    }

    It "has 3 Phase 1, 4 Phase 2, and 10 Phase 3 rules" {
        @($catalog | Where-Object { $_.Phase -eq 1 }).Count | Should -Be 3
        @($catalog | Where-Object { $_.Phase -eq 2 }).Count | Should -Be 4
        @($catalog | Where-Object { $_.Phase -eq 3 }).Count | Should -Be 10
    }

    It "uses only phases 1, 2, and 3" {
        foreach ($rule in $catalog) {
            $rule.Phase | Should -BeIn @(1, 2, 3)
        }
    }

    It "has unique keys" {
        $keys = @($catalog | ForEach-Object { $_.Key })
        ($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }

    It "has unique GUIDs" {
        $guids = @($catalog | ForEach-Object { $_.Guid })
        ($guids | Sort-Object -Unique).Count | Should -Be $guids.Count
    }

    It "has a non-empty name for every rule" {
        foreach ($rule in $catalog) {
            [string]::IsNullOrWhiteSpace($rule.Name) | Should -BeFalse
        }
    }

    It "has GUIDs that parse as [guid]" {
        foreach ($rule in $catalog) {
            { [guid]$rule.Guid } | Should -Not -Throw
        }
    }

    It "matches the known-good GUIDs from the MS Learn reference (drift guard)" {
        foreach ($rule in $catalog) {
            $rule.Guid | Should -Be $script:ExpectedGuids[$rule.Key]
        }
    }
}

Describe "Format-AsrAction" {
    It "maps 0 to NotConfigured" { Format-AsrAction -Action 0 | Should -Be 'NotConfigured' }
    It "maps 1 to Block"         { Format-AsrAction -Action 1 | Should -Be 'Block' }
    It "maps 2 to Audit"         { Format-AsrAction -Action 2 | Should -Be 'Audit' }
    It "maps 6 to Warn"          { Format-AsrAction -Action 6 | Should -Be 'Warn' }
    It "maps unknown codes to Unknown(n)" { Format-AsrAction -Action 99 | Should -Be 'Unknown(99)' }
}

Describe "Get-DesiredAsrState" {
    BeforeAll {
        $script:catalog = Get-AsrRuleCatalog
        $script:phase1 = @($catalog | Where-Object { $_.Phase -eq 1 } | ForEach-Object { $_.Guid.ToLower() })
        $script:phase2 = @($catalog | Where-Object { $_.Phase -eq 2 } | ForEach-Object { $_.Guid.ToLower() })
        $script:phase3 = @($catalog | Where-Object { $_.Phase -eq 3 } | ForEach-Object { $_.Guid.ToLower() })
    }

    Context "Audit mode" {
        It "sets every rule to Audit (2)" {
            $desired = Get-DesiredAsrState -Mode Audit -PromotedGuids @() -Catalog $catalog
            foreach ($rule in $catalog) {
                $desired[$rule.Guid.ToLower()] | Should -Be 2
            }
        }

        It "ignores PromotedGuids (still all Audit)" {
            $desired = Get-DesiredAsrState -Mode Audit -PromotedGuids $script:phase2 -Catalog $catalog
            foreach ($rule in $catalog) {
                $desired[$rule.Guid.ToLower()] | Should -Be 2
            }
        }
    }

    Context "Enforce mode without promotions" {
        It "blocks Phase 1 (1) and audits Phase 2 and Phase 3 (2)" {
            $desired = Get-DesiredAsrState -Mode Enforce -PromotedGuids @() -Catalog $catalog
            foreach ($g in $script:phase1) { $desired[$g] | Should -Be 1 }
            foreach ($g in $script:phase2) { $desired[$g] | Should -Be 2 }
            foreach ($g in $script:phase3) { $desired[$g] | Should -Be 2 }
        }
    }

    Context "Enforce mode with one promoted Phase 2 rule" {
        It "blocks the promoted rule and leaves other Phase 2 in audit" {
            $promote = @($script:phase2[0])
            $desired = Get-DesiredAsrState -Mode Enforce -PromotedGuids $promote -Catalog $catalog

            $desired[$script:phase2[0]] | Should -Be 1
            foreach ($g in $script:phase2[1..($script:phase2.Count - 1)]) { $desired[$g] | Should -Be 2 }
            foreach ($g in $script:phase1) { $desired[$g] | Should -Be 1 }
        }

        It "is case-insensitive on the promoted GUID" {
            $promote = @($script:phase2[0].ToUpper())
            $desired = Get-DesiredAsrState -Mode Enforce -PromotedGuids $promote -Catalog $catalog
            $desired[$script:phase2[0]] | Should -Be 1
        }
    }

    Context "Enforce mode with one promoted Phase 3 rule" {
        It "blocks the promoted rule and leaves other Phase 3 in audit" {
            $promote = @($script:phase3[0])
            $desired = Get-DesiredAsrState -Mode Enforce -PromotedGuids $promote -Catalog $catalog

            $desired[$script:phase3[0]] | Should -Be 1
            foreach ($g in $script:phase3[1..($script:phase3.Count - 1)]) { $desired[$g] | Should -Be 2 }
            foreach ($g in $script:phase2) { $desired[$g] | Should -Be 2 }
            foreach ($g in $script:phase1) { $desired[$g] | Should -Be 1 }
        }
    }

    It "preserves catalog order in the returned map" {
        $desired = Get-DesiredAsrState -Mode Audit -PromotedGuids @() -Catalog $catalog
        $orderedKeys = @($desired.Keys) -join ','
        $catalogGuids = @($catalog | ForEach-Object { $_.Guid.ToLower() }) -join ','
        $orderedKeys | Should -Be $catalogGuids
    }
}

Describe "Resolve-PromotedGuids" {
    BeforeAll {
        $script:catalog = Get-AsrRuleCatalog
    }

    Context "Valid Phase 2/3 entries" {
        It "resolves by short key" {
            $r = Resolve-PromotedGuids -Promote @('BlockObfuscatedScripts') -Catalog $catalog
            $r.Guids | Should -Contain '5beb7efe-fd9a-4556-801d-275e5ffc04cc'
            $r.Warnings.Count | Should -Be 0
        }

        It "resolves a Phase 3 rule by short key" {
            $r = Resolve-PromotedGuids -Promote @('BlockSafeModeReboot') -Catalog $catalog
            $r.Guids | Should -Contain '33ddedf1-c6e0-47cb-833e-de6133960387'
            $r.Warnings.Count | Should -Be 0
        }

        It "resolves by canonical name" {
            $r = Resolve-PromotedGuids -Promote @('Block execution of potentially obfuscated scripts') -Catalog $catalog
            $r.Guids | Should -Contain '5beb7efe-fd9a-4556-801d-275e5ffc04cc'
        }

        It "resolves by GUID (case-insensitive)" {
            $r = Resolve-PromotedGuids -Promote @('5BEB7EFE-FD9A-4556-801D-275E5FFC04CC') -Catalog $catalog
            $r.Guids | Should -Contain '5beb7efe-fd9a-4556-801d-275e5ffc04cc'
        }

        It "de-duplicates entries that resolve to the same rule" {
            $r = Resolve-PromotedGuids -Promote @('BlockObfuscatedScripts', '5beb7efe-fd9a-4556-801d-275e5ffc04cc') -Catalog $catalog
            @($r.Guids).Count | Should -Be 1
        }
    }

    Context "Invalid entries" {
        It "warns and excludes an unknown entry" {
            $r = Resolve-PromotedGuids -Promote @('NotARealRule') -Catalog $catalog
            @($r.Guids).Count | Should -Be 0
            $r.Warnings.Count | Should -Be 1
            $r.Warnings[0] | Should -BeLike "*matched no known ASR rule*"
        }

        It "warns and excludes a Phase 1 rule" {
            $r = Resolve-PromotedGuids -Promote @('BlockLsassCredentialTheft') -Catalog $catalog
            @($r.Guids).Count | Should -Be 0
            $r.Warnings.Count | Should -Be 1
            $r.Warnings[0] | Should -BeLike "*Phase 1 rule*"
        }
    }

    Context "Edge cases" {
        It "returns no guids and no warnings for an empty list" {
            $r = Resolve-PromotedGuids -Promote @() -Catalog $catalog
            @($r.Guids).Count | Should -Be 0
            @($r.Warnings).Count | Should -Be 0
        }

        It "skips blank / whitespace entries" {
            $r = Resolve-PromotedGuids -Promote @('', '   ') -Catalog $catalog
            @($r.Guids).Count | Should -Be 0
            @($r.Warnings).Count | Should -Be 0
        }

        It "handles a null promote list" {
            $r = Resolve-PromotedGuids -Promote $null -Catalog $catalog
            @($r.Guids).Count | Should -Be 0
        }
    }
}

Describe "Script file syntax" {
    # The main script is never dot-sourced by tests (#Requires -RunAsAdministrator), so without
    # this check a parse error in it would reach the host unseen. Parsing does not execute.
    It "all security/*.ps1 files parse without errors" {
        $files = @(Get-ChildItem -Path (Join-Path (Get-RepoRoot) "security") -Filter "*.ps1")
        $files.Count | Should -BeGreaterThan 0

        foreach ($f in $files) {
            $parseTokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$parseTokens, [ref]$parseErrors)
            $msgs = (@($parseErrors) | ForEach-Object { "L$($_.Extent.StartLineNumber) $($_.Message)" }) -join '; '
            @($parseErrors).Count | Should -Be 0 -Because "$($f.Name) should parse cleanly ($msgs)"
        }
    }
}
