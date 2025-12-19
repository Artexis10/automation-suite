BeforeAll {
    $script:AutosuiteRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:AutosuitePath = Join-Path $script:AutosuiteRoot "autosuite.ps1"
    
    # Create test directory for mock files
    $script:TestDir = Join-Path $env:TEMP "autosuite-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:MockCliPath = Join-Path $script:TestDir "mock-cli.ps1"
    $script:MockWingetPath = Join-Path $script:TestDir "mock-winget.ps1"
    $script:CapturedArgsPath = Join-Path $script:TestDir "captured-args.json"
    $script:TestManifestPath = Join-Path $script:TestDir "test-manifest.jsonc"
    $script:AllInstalledManifestPath = Join-Path $script:TestDir "all-installed.jsonc"
    
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
    
    # Mock provisioning CLI
    $mockCliContent = @'
param(
    [string]$Command,
    [string]$Manifest,
    [string]$OutManifest,
    [string]$Profile,
    [switch]$DryRun,
    [switch]$EnableRestore,
    [switch]$Latest,
    [string]$RunId,
    [int]$Last,
    [switch]$Json
)

$captured = @{
    Command = $Command
    Manifest = $Manifest
    OutManifest = $OutManifest
    Profile = $Profile
    DryRun = $DryRun.IsPresent
    EnableRestore = $EnableRestore.IsPresent
    Latest = $Latest.IsPresent
    RunId = $RunId
    Last = $Last
    Json = $Json.IsPresent
}

$argsPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "captured-args.json"
$captured | ConvertTo-Json | Set-Content -Path $argsPath

Write-Host "[mock-cli] Command: $Command"
'@
    Set-Content -Path $script:MockCliPath -Value $mockCliContent
    
    # Mock winget command - simulates installed apps
    $mockWingetContent = @'
param(
    [Parameter(Position=0)]
    [string]$Action,
    [string]$id,
    [switch]$AcceptSourceAgreements,
    [switch]$AcceptPackageAgreements,
    [switch]$e
)

# Simulate installed apps list
$installedApps = @"
Name                                   Id                                   Version
------------------------------------------------------------------------------------
7-Zip                                  7zip.7zip                            23.01
Git                                    Git.Git                              2.43.0
"@

if ($Action -eq "list") {
    Write-Output $installedApps
    exit 0
}

if ($Action -eq "install") {
    # Record install attempt
    $installLog = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "install-log.txt"
    Add-Content -Path $installLog -Value "install:$id"
    Write-Host "Installing $id..."
    exit 0
}

exit 0
'@
    Set-Content -Path $script:MockWingetPath -Value $mockWingetContent
    
    # Create test manifest with mixed installed/missing apps
    $testManifest = @'
{
  "version": 1,
  "name": "test-manifest",
  "apps": [
    { "id": "7zip-7zip", "refs": { "windows": "7zip.7zip" } },
    { "id": "git-git", "refs": { "windows": "Git.Git" } },
    { "id": "missing-app", "refs": { "windows": "Missing.App" } }
  ],
  "restore": [],
  "verify": []
}
'@
    Set-Content -Path $script:TestManifestPath -Value $testManifest
    
    # Create manifest with only installed apps
    $allInstalledManifest = @'
{
  "version": 1,
  "name": "all-installed",
  "apps": [
    { "id": "7zip", "refs": { "windows": "7zip.7zip" } },
    { "id": "git", "refs": { "windows": "Git.Git" } }
  ],
  "restore": [],
  "verify": []
}
'@
    Set-Content -Path $script:AllInstalledManifestPath -Value $allInstalledManifest
}

AfterAll {
    # Cleanup test directory
    if ($script:TestDir -and (Test-Path $script:TestDir)) {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Clear env vars
    $env:AUTOSUITE_PROVISIONING_CLI = $null
    $env:AUTOSUITE_WINGET_SCRIPT = $null
}

Describe "Autosuite Root Orchestrator" {
    
    Context "Banner and Help" {
        It "Shows banner with version" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)'" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "Automation Suite"
            $outputStr | Should -Match "v0"
        }
        
        It "Shows help when no command provided" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)'" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "USAGE:"
            $outputStr | Should -Match "COMMANDS:"
            $outputStr | Should -Match "capture"
            $outputStr | Should -Match "apply"
            $outputStr | Should -Match "verify"
        }
    }
    
    Context "Delegation Message (in-process)" {
        BeforeEach {
            $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
            if (Test-Path $script:CapturedArgsPath) {
                Remove-Item $script:CapturedArgsPath -Force
            }
        }
        
        AfterEach {
            $env:AUTOSUITE_PROVISIONING_CLI = $null
        }
        
        It "Emits stable wrapper message for report" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:ProvisioningCliPath = $script:MockCliPath
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-delegation-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            $output = Invoke-ReportCore -OutputJson $false 4>&1
            $output | Should -Contain "[autosuite] Report: reading state..."
        }
        
        It "Emits stable wrapper message for doctor" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:ProvisioningCliPath = $script:MockCliPath
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-delegation-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            $output = Invoke-DoctorCore 4>&1
            $output | Should -Contain "[autosuite] Doctor: checking environment..."
        }
    }
}

Describe "Autosuite Capture Command" {
    
    Context "Default Output Path" {
        It "Defaults to local/<machine>.jsonc when no -Out provided" {
            $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
            $output = & $script:AutosuitePath capture 2>&1
            $outputStr = $output -join "`n"
            
            # Should target local/ directory
            $outputStr | Should -Match "provisioning.manifests.local"
            $outputStr | Should -Match "\.jsonc"
            $env:AUTOSUITE_PROVISIONING_CLI = $null
        }
        
        It "Uses -Out path when provided" {
            $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
            $customPath = Join-Path $script:TestDir "custom-output.jsonc"
            $output = & $script:AutosuitePath capture -Out $customPath 2>&1
            $outputStr = $output -join "`n"
            
            $outputStr | Should -Match "custom-output\.jsonc"
            $env:AUTOSUITE_PROVISIONING_CLI = $null
        }
    }
    
    Context "Example Flag" {
        It "Generates deterministic example manifest with -Example" {
            $examplePath = Join-Path $script:TestDir "example-output.jsonc"
            $output = & $script:AutosuitePath capture -Example -Out $examplePath 2>&1
            
            $examplePath | Should -Exist
            $content = Get-Content $examplePath -Raw
            
            # Should contain expected apps
            $content | Should -Match "7zip\.7zip"
            $content | Should -Match "Git\.Git"
            $content | Should -Match "Microsoft\.PowerShell"
            
            # Should NOT contain machine-specific data
            $content | Should -Not -Match "captured"
            $content | Should -Not -Match $env:COMPUTERNAME
        }
        
        It "Example manifest has no timestamps" {
            $examplePath = Join-Path $script:TestDir "example-notimestamp.jsonc"
            & $script:AutosuitePath capture -Example -Out $examplePath 2>&1 | Out-Null
            
            $content = Get-Content $examplePath -Raw
            # Should not have ISO timestamp pattern
            $content | Should -Not -Match "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        }
    }
}

Describe "Autosuite Apply Command" {
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        $installLog = Join-Path $script:TestDir "install-log.txt"
        if (Test-Path $installLog) {
            Remove-Item $installLog -Force
        }
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "DryRun Mode (in-process)" {
        It "Returns success and does not install with -DryRun" {
            # Dot-source to get access to functions
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $result = Invoke-ApplyCore -ManifestPath $script:TestManifestPath -IsDryRun $true -IsOnlyApps $true
            
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
            
            # Should NOT have actually installed anything
            $installLog = Join-Path $script:TestDir "install-log.txt"
            $installLog | Should -Not -Exist
        }
        
        It "Emits stable wrapper lines via Write-Output" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $output = Invoke-ApplyCore -ManifestPath $script:TestManifestPath -IsDryRun $true -IsOnlyApps $true 4>&1
            
            $output | Should -Contain "[autosuite] Apply: reading manifest $($script:TestManifestPath)"
            $output | Should -Contain "[autosuite] Apply: installing apps"
            $output | Should -Contain "[autosuite] Apply: completed"
        }
    }
    
    Context "Idempotent Installs (subprocess for Write-Host)" {
        It "Skips already installed apps" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' apply -Manifest '$($script:TestManifestPath)' -DryRun -OnlyApps" 2>&1
            $outputStr = $output -join "`n"
            
            # 7zip and Git are in mock installed list
            $outputStr | Should -Match "\[SKIP\].*7zip\.7zip.*already installed"
            $outputStr | Should -Match "\[SKIP\].*Git\.Git.*already installed"
        }
    }
}

Describe "Autosuite Verify Command" {
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "Structured Results (in-process)" {
        It "Returns success when all apps are installed" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $result = Invoke-VerifyCore -ManifestPath $script:AllInstalledManifestPath
            
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
            $result.OkCount | Should -Be 2
            $result.MissingCount | Should -Be 0
            $result.MissingApps.Count | Should -Be 0
        }
        
        It "Returns failure with missing apps details" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $result = Invoke-VerifyCore -ManifestPath $script:TestManifestPath
            
            $result.Success | Should -Be $false
            $result.ExitCode | Should -Be 1
            $result.OkCount | Should -Be 2
            $result.MissingCount | Should -Be 1
            $result.MissingApps | Should -Contain "Missing.App"
        }
        
        It "Emits stable wrapper lines via Write-Output" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $output = Invoke-VerifyCore -ManifestPath $script:TestManifestPath 4>&1
            
            $output | Should -Contain "[autosuite] Verify: checking manifest $($script:TestManifestPath)"
            $output | Should -Contain "[autosuite] Verify: OkCount=2 MissingCount=1"
            $output | Should -Contain "[autosuite] Verify: FAILED"
        }
        
        It "Emits PASSED for successful verify" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:WingetScript = $script:MockWingetPath
            
            $output = Invoke-VerifyCore -ManifestPath $script:AllInstalledManifestPath 4>&1
            
            $output | Should -Contain "[autosuite] Verify: PASSED"
        }
    }
    
    Context "Process Exit Codes (subprocess)" {
        It "Exits 0 when all apps are installed" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:AllInstalledManifestPath)'" 2>&1
            $exitCode = $LASTEXITCODE
            
            $exitCode | Should -Be 0
        }
        
        It "Exits 1 when apps are missing" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:TestManifestPath)'" 2>&1
            $exitCode = $LASTEXITCODE
            
            $exitCode | Should -Be 1
        }
    }
}

Describe "Autosuite Report and Doctor Commands" {
    
    BeforeAll {
        $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
    }
    
    AfterAll {
        $env:AUTOSUITE_PROVISIONING_CLI = $null
    }
    
    BeforeEach {
        if (Test-Path $script:CapturedArgsPath) {
            Remove-Item $script:CapturedArgsPath -Force
        }
    }
    
    Context "Report Command (in-process)" {
        It "Returns no state found when state file does not exist" {
            . $script:AutosuitePath -LoadFunctionsOnly
            # Override state path to temp location
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            # Ensure no state file exists
            if (Test-Path $script:AutosuiteStatePath) {
                Remove-Item $script:AutosuiteStatePath -Force
            }
            
            $output = Invoke-ReportCore -OutputJson $false 4>&1
            $output | Should -Contain "[autosuite] Report: no state found"
        }
        
        It "Emits stable wrapper lines" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            $output = Invoke-ReportCore -OutputJson $false 4>&1
            $output | Should -Contain "[autosuite] Report: reading state..."
        }
    }
    
    Context "Doctor Command (in-process)" {
        It "Emits stable wrapper lines" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:ProvisioningCliPath = $script:MockCliPath
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            $output = Invoke-DoctorCore 4>&1
            $output | Should -Contain "[autosuite] Doctor: checking environment..."
            $output | Should -Contain "[autosuite] Doctor: completed"
        }
    }
}

Describe "Autosuite State Store (Bundle B)" {
    
    BeforeAll {
        $script:TestStateDir = Join-Path $script:TestDir ".autosuite-state-test"
    }
    
    BeforeEach {
        # Clean up test state directory before each test
        if (Test-Path $script:TestStateDir) {
            Remove-Item $script:TestStateDir -Recurse -Force
        }
        
        # Load functions and override state paths
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:AutosuiteStateDir = $script:TestStateDir
        $script:AutosuiteStatePath = Join-Path $script:TestStateDir "state.json"
    }
    
    AfterEach {
        if (Test-Path $script:TestStateDir) {
            Remove-Item $script:TestStateDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "State File Creation" {
        It "Creates state directory if it does not exist" {
            $state = New-AutosuiteState
            $result = Write-AutosuiteStateAtomic -State $state
            
            $result | Should -Be $true
            $script:TestStateDir | Should -Exist
        }
        
        It "Creates state file with correct schema version" {
            $state = New-AutosuiteState
            Write-AutosuiteStateAtomic -State $state | Out-Null
            
            $script:AutosuiteStatePath | Should -Exist
            $content = Get-Content $script:AutosuiteStatePath -Raw | ConvertFrom-Json
            $content.schemaVersion | Should -Be 1
        }
        
        It "Atomic write uses temp file then moves" {
            $state = New-AutosuiteState
            $state.lastApplied = @{ manifestPath = "test.jsonc"; manifestHash = "abc123"; timestampUtc = "2025-01-01T00:00:00Z" }
            
            $result = Write-AutosuiteStateAtomic -State $state
            
            $result | Should -Be $true
            # Temp files should be cleaned up
            $tempFiles = Get-ChildItem -Path $script:TestStateDir -Filter "state.tmp.*.json" -ErrorAction SilentlyContinue
            $tempFiles.Count | Should -Be 0
        }
    }
    
    Context "State Read/Write" {
        It "Read returns null when no state file exists" {
            $state = Read-AutosuiteState
            $state | Should -BeNullOrEmpty
        }
        
        It "Read returns state after write" {
            $state = New-AutosuiteState
            $state.lastApplied = @{ manifestPath = "test.jsonc"; manifestHash = "abc123"; timestampUtc = "2025-01-01T00:00:00Z" }
            Write-AutosuiteStateAtomic -State $state | Out-Null
            
            $readState = Read-AutosuiteState
            $readState | Should -Not -BeNullOrEmpty
            $readState.lastApplied.manifestPath | Should -Be "test.jsonc"
            $readState.lastApplied.manifestHash | Should -Be "abc123"
        }
    }
}

Describe "Autosuite Manifest Hashing (Bundle B)" {
    
    BeforeAll {
        $script:HashTestDir = Join-Path $script:TestDir "hash-test"
        New-Item -ItemType Directory -Path $script:HashTestDir -Force | Out-Null
    }
    
    BeforeEach {
        . $script:AutosuitePath -LoadFunctionsOnly
    }
    
    Context "Deterministic Hashing" {
        It "Same content produces same hash" {
            $manifest1 = Join-Path $script:HashTestDir "manifest1.jsonc"
            $manifest2 = Join-Path $script:HashTestDir "manifest2.jsonc"
            
            $content = '{"version": 1, "apps": []}'
            Set-Content -Path $manifest1 -Value $content
            Set-Content -Path $manifest2 -Value $content
            
            $hash1 = Get-ManifestHash -Path $manifest1
            $hash2 = Get-ManifestHash -Path $manifest2
            
            $hash1 | Should -Be $hash2
        }
        
        It "Different content produces different hash" {
            $manifest1 = Join-Path $script:HashTestDir "diff1.jsonc"
            $manifest2 = Join-Path $script:HashTestDir "diff2.jsonc"
            
            Set-Content -Path $manifest1 -Value '{"version": 1}'
            Set-Content -Path $manifest2 -Value '{"version": 2}'
            
            $hash1 = Get-ManifestHash -Path $manifest1
            $hash2 = Get-ManifestHash -Path $manifest2
            
            $hash1 | Should -Not -Be $hash2
        }
        
        It "CRLF and LF produce same hash" {
            $manifestCRLF = Join-Path $script:HashTestDir "crlf.jsonc"
            $manifestLF = Join-Path $script:HashTestDir "lf.jsonc"
            
            $contentCRLF = "{`"version`": 1,`r`n`"apps`": []`r`n}"
            $contentLF = "{`"version`": 1,`n`"apps`": []`n}"
            
            [System.IO.File]::WriteAllText($manifestCRLF, $contentCRLF)
            [System.IO.File]::WriteAllText($manifestLF, $contentLF)
            
            $hashCRLF = Get-ManifestHash -Path $manifestCRLF
            $hashLF = Get-ManifestHash -Path $manifestLF
            
            $hashCRLF | Should -Be $hashLF
        }
        
        It "Returns null for non-existent file" {
            $hash = Get-ManifestHash -Path "C:\nonexistent\file.jsonc"
            $hash | Should -BeNullOrEmpty
        }
        
        It "Hash is lowercase hex string" {
            $manifest = Join-Path $script:HashTestDir "hex.jsonc"
            Set-Content -Path $manifest -Value '{"test": true}'
            
            $hash = Get-ManifestHash -Path $manifest
            
            $hash | Should -Match '^[a-f0-9]{64}$'
        }
    }
}

Describe "Autosuite Drift Detection (Bundle B)" {
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:WingetScript = $script:MockWingetPath
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "Compute-Drift Function" {
        It "Detects missing apps" {
            $drift = Compute-Drift -ManifestPath $script:TestManifestPath
            
            $drift.Success | Should -Be $true
            $drift.MissingCount | Should -BeGreaterThan 0
            $drift.Missing | Should -Contain "Missing.App"
        }
        
        It "Reports zero missing when all installed" {
            $drift = Compute-Drift -ManifestPath $script:AllInstalledManifestPath
            
            $drift.Success | Should -Be $true
            $drift.MissingCount | Should -Be 0
        }
        
        It "Detects extra apps (installed but not in manifest)" {
            # Create a minimal manifest with only one app
            $minimalManifest = Join-Path $script:TestDir "minimal.jsonc"
            $content = @'
{
  "version": 1,
  "apps": [
    { "id": "7zip", "refs": { "windows": "7zip.7zip" } }
  ]
}
'@
            Set-Content -Path $minimalManifest -Value $content
            
            $drift = Compute-Drift -ManifestPath $minimalManifest
            
            $drift.Success | Should -Be $true
            # Git.Git is installed but not in manifest
            $drift.ExtraCount | Should -BeGreaterThan 0
        }
        
        It "Returns error for invalid manifest" {
            $drift = Compute-Drift -ManifestPath "C:\nonexistent\manifest.jsonc"
            
            $drift.Success | Should -Be $false
            $drift.Error | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Verify Updates State" {
        BeforeEach {
            $script:TestStateDir = Join-Path $script:TestDir ".autosuite-verify-test"
            if (Test-Path $script:TestStateDir) {
                Remove-Item $script:TestStateDir -Recurse -Force
            }
            $script:AutosuiteStateDir = $script:TestStateDir
            $script:AutosuiteStatePath = Join-Path $script:TestStateDir "state.json"
        }
        
        AfterEach {
            if (Test-Path $script:TestStateDir) {
                Remove-Item $script:TestStateDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Verify creates state file with lastVerify" {
            $result = Invoke-VerifyCore -ManifestPath $script:AllInstalledManifestPath
            
            $script:AutosuiteStatePath | Should -Exist
            $state = Get-Content $script:AutosuiteStatePath -Raw | ConvertFrom-Json
            $state.lastVerify | Should -Not -BeNullOrEmpty
            $state.lastVerify.manifestPath | Should -Be $script:AllInstalledManifestPath
            $state.lastVerify.success | Should -Be $true
        }
        
        It "Verify records okCount and missingCount" {
            Invoke-VerifyCore -ManifestPath $script:TestManifestPath | Out-Null
            
            $state = Get-Content $script:AutosuiteStatePath -Raw | ConvertFrom-Json
            $state.lastVerify.okCount | Should -Be 2
            $state.lastVerify.missingCount | Should -Be 1
        }
        
        It "Verify emits drift summary line" {
            $output = Invoke-VerifyCore -ManifestPath $script:TestManifestPath 4>&1
            
            $driftLine = $output | Where-Object { $_ -match '\[autosuite\] Drift:' }
            $driftLine | Should -Not -BeNullOrEmpty
            $driftLine | Should -Match 'Missing=1'
        }
    }
}

Describe "Autosuite State Reset (Bundle B)" {
    
    BeforeEach {
        $script:TestStateDir = Join-Path $script:TestDir ".autosuite-reset-test"
        if (Test-Path $script:TestStateDir) {
            Remove-Item $script:TestStateDir -Recurse -Force
        }
        
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:AutosuiteStateDir = $script:TestStateDir
        $script:AutosuiteStatePath = Join-Path $script:TestStateDir "state.json"
    }
    
    AfterEach {
        if (Test-Path $script:TestStateDir) {
            Remove-Item $script:TestStateDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "State Reset Command" {
        It "Reset succeeds when no state file exists" {
            $result = Invoke-StateResetCore
            
            $result.Success | Should -Be $true
            $result.WasReset | Should -Be $false
        }
        
        It "Reset deletes existing state file" {
            # Create state file first
            New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
            Set-Content -Path $script:AutosuiteStatePath -Value '{"schemaVersion": 1}'
            
            $result = Invoke-StateResetCore
            
            $result.Success | Should -Be $true
            $result.WasReset | Should -Be $true
            $script:AutosuiteStatePath | Should -Not -Exist
        }
        
        It "Reset emits stable wrapper lines" {
            New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
            Set-Content -Path $script:AutosuiteStatePath -Value '{"schemaVersion": 1}'
            
            $output = Invoke-StateResetCore 4>&1
            
            $output | Should -Contain "[autosuite] State: resetting..."
            $output | Should -Contain "[autosuite] State: reset completed"
        }
    }
}
