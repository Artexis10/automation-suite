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
            $output = & $script:AutosuitePath capture *>&1
            $outputStr = $output -join "`n"
            
            # Should target local/ directory
            $outputStr | Should -Match "provisioning.manifests.local"
            $outputStr | Should -Match "\.jsonc"
            $env:AUTOSUITE_PROVISIONING_CLI = $null
        }
        
        It "Uses -Out path when provided" {
            $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
            $customPath = Join-Path $script:TestDir "custom-output.jsonc"
            $output = & $script:AutosuitePath capture -Out $customPath *>&1
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
            # New format includes ExitCode
            $completedLine = $output | Where-Object { $_ -match '\[autosuite\] Apply: completed' }
            $completedLine | Should -Not -BeNullOrEmpty
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
            # New format includes VersionMismatches and ExtraCount
            $verifyLine = $output | Where-Object { $_ -match '\[autosuite\] Verify: OkCount=2 MissingCount=1' }
            $verifyLine | Should -Not -BeNullOrEmpty
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
        
        It "Emits stable summary marker with state and drift counts" {
            . $script:AutosuitePath -LoadFunctionsOnly
            $script:ProvisioningCliPath = $script:MockCliPath
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-doctor-marker"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            # Ensure no state exists
            if (Test-Path $script:AutosuiteStateDir) {
                Remove-Item $script:AutosuiteStateDir -Recurse -Force
            }
            
            $output = Invoke-DoctorCore 4>&1
            $markerLine = $output | Where-Object { $_ -match '\[autosuite\] Doctor: state=' }
            $markerLine | Should -Not -BeNullOrEmpty
            $markerLine | Should -Match 'state=absent'
            $markerLine | Should -Match 'driftMissing=\d+'
            $markerLine | Should -Match 'driftExtra=\d+'
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

#region Bundle C Tests - Driver Abstraction + Version Constraints

Describe "Bundle C: Version Constraint Parsing" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
    }
    
    Context "Parse-VersionConstraint" {
        It "Returns null for empty constraint" {
            $result = Parse-VersionConstraint -Constraint $null
            $result | Should -BeNullOrEmpty
            
            $result = Parse-VersionConstraint -Constraint ""
            $result | Should -BeNullOrEmpty
        }
        
        It "Parses exact version constraint" {
            $result = Parse-VersionConstraint -Constraint "1.2.3"
            
            $result.Type | Should -Be 'exact'
            $result.Version | Should -Be '1.2.3'
        }
        
        It "Parses minimum version constraint" {
            $result = Parse-VersionConstraint -Constraint ">=2.40.0"
            
            $result.Type | Should -Be 'minimum'
            $result.Version | Should -Be '2.40.0'
        }
        
        It "Handles whitespace in constraint" {
            $result = Parse-VersionConstraint -Constraint "  >= 1.0.0  "
            
            $result.Type | Should -Be 'minimum'
            $result.Version | Should -Be '1.0.0'
        }
    }
    
    Context "Compare-Versions" {
        It "Returns 0 for equal versions" {
            $result = Compare-Versions -Version1 "1.2.3" -Version2 "1.2.3"
            $result | Should -Be 0
        }
        
        It "Returns -1 when first version is lower" {
            $result = Compare-Versions -Version1 "1.2.3" -Version2 "1.2.4"
            $result | Should -Be -1
            
            $result = Compare-Versions -Version1 "2.0.0" -Version2 "2.43.0"
            $result | Should -Be -1
        }
        
        It "Returns 1 when first version is higher" {
            $result = Compare-Versions -Version1 "2.0.0" -Version2 "1.9.9"
            $result | Should -Be 1
            
            $result = Compare-Versions -Version1 "23.01" -Version2 "22.99"
            $result | Should -Be 1
        }
        
        It "Handles different version lengths" {
            $result = Compare-Versions -Version1 "1.2" -Version2 "1.2.0"
            $result | Should -Be 0
            
            $result = Compare-Versions -Version1 "1.2.1" -Version2 "1.2"
            $result | Should -Be 1
        }
        
        It "Returns null for null inputs" {
            $result = Compare-Versions -Version1 $null -Version2 "1.0.0"
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "Test-VersionConstraint" {
        It "Returns satisfied for no constraint" {
            $result = Test-VersionConstraint -InstalledVersion "1.0.0" -Constraint $null
            
            $result.Satisfied | Should -Be $true
            $result.Reason | Should -Be 'no constraint'
        }
        
        It "Returns not satisfied for unknown version with constraint" {
            $constraint = @{ Type = 'exact'; Version = '1.0.0' }
            $result = Test-VersionConstraint -InstalledVersion $null -Constraint $constraint
            
            $result.Satisfied | Should -Be $false
            $result.Reason | Should -Be 'version unknown'
        }
        
        It "Exact constraint satisfied when versions match" {
            $constraint = @{ Type = 'exact'; Version = '1.2.3' }
            $result = Test-VersionConstraint -InstalledVersion "1.2.3" -Constraint $constraint
            
            $result.Satisfied | Should -Be $true
        }
        
        It "Exact constraint not satisfied when versions differ" {
            $constraint = @{ Type = 'exact'; Version = '1.2.3' }
            $result = Test-VersionConstraint -InstalledVersion "1.2.4" -Constraint $constraint
            
            $result.Satisfied | Should -Be $false
            $result.Reason | Should -Match 'expected 1.2.3'
        }
        
        It "Minimum constraint satisfied when installed >= required" {
            $constraint = @{ Type = 'minimum'; Version = '2.40.0' }
            
            $result = Test-VersionConstraint -InstalledVersion "2.43.0" -Constraint $constraint
            $result.Satisfied | Should -Be $true
            
            $result = Test-VersionConstraint -InstalledVersion "2.40.0" -Constraint $constraint
            $result.Satisfied | Should -Be $true
        }
        
        It "Minimum constraint not satisfied when installed < required" {
            $constraint = @{ Type = 'minimum'; Version = '2.40.0' }
            $result = Test-VersionConstraint -InstalledVersion "2.39.0" -Constraint $constraint
            
            $result.Satisfied | Should -Be $false
            $result.Reason | Should -Match '2.39.0 < 2.40.0'
        }
    }
}

Describe "Bundle C: Driver Abstraction" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
    }
    
    Context "Get-AppDriver" {
        It "Returns winget as default driver" {
            $app = [PSCustomObject]@{ id = "test"; refs = @{ windows = "Test.App" } }
            $driver = Get-AppDriver -App $app
            
            $driver | Should -Be 'winget'
        }
        
        It "Returns specified driver" {
            $app = [PSCustomObject]@{ id = "test"; driver = "custom" }
            $driver = Get-AppDriver -App $app
            
            $driver | Should -Be 'custom'
        }
        
        It "Normalizes driver to lowercase" {
            $app = [PSCustomObject]@{ id = "test"; driver = "CUSTOM" }
            $driver = Get-AppDriver -App $app
            
            $driver | Should -Be 'custom'
        }
    }
    
    Context "Get-AppWingetId" {
        It "Returns refs.windows when present" {
            $app = [PSCustomObject]@{ id = "test"; refs = @{ windows = "Test.App" } }
            $wingetId = Get-AppWingetId -App $app
            
            $wingetId | Should -Be 'Test.App'
        }
        
        It "Returns null for custom driver without refs" {
            $app = [PSCustomObject]@{ id = "test"; driver = "custom" }
            $wingetId = Get-AppWingetId -App $app
            
            $wingetId | Should -BeNullOrEmpty
        }
    }
}

Describe "Bundle C: Custom Driver" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
        
        # Create test fixtures directory
        $script:CustomTestDir = Join-Path $script:TestDir "custom-driver-test"
        New-Item -ItemType Directory -Path $script:CustomTestDir -Force | Out-Null
        
        # Create a mock install script inside repo (tests/fixtures simulated)
        $script:MockInstallScript = Join-Path $script:CustomTestDir "mock-install.ps1"
        Set-Content -Path $script:MockInstallScript -Value @'
# Mock install script for testing
Write-Output "Mock install executed"
exit 0
'@
        
        # Create a mock detect file
        $script:MockDetectFile = Join-Path $script:CustomTestDir "detected-app.exe"
        Set-Content -Path $script:MockDetectFile -Value "mock"
    }
    
    AfterAll {
        if ($script:CustomTestDir -and (Test-Path $script:CustomTestDir)) {
            Remove-Item -Path $script:CustomTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Test-CustomScriptPathSafe" {
        It "Accepts paths under repo root" {
            $script:AutosuiteRoot = $script:AutosuiteRoot  # Ensure set
            $safePath = "provisioning/installers/test.ps1"
            
            $result = Test-CustomScriptPathSafe -ScriptPath $safePath
            $result | Should -Be $true
        }
        
        It "Rejects path traversal attempts" {
            $unsafePath = "../../../malicious.ps1"
            
            $result = Test-CustomScriptPathSafe -ScriptPath $unsafePath
            $result | Should -Be $false
        }
        
        It "Rejects absolute paths outside repo" {
            $unsafePath = "C:\Windows\System32\malicious.ps1"
            
            $result = Test-CustomScriptPathSafe -ScriptPath $unsafePath
            $result | Should -Be $false
        }
        
        It "Rejects null or empty paths" {
            $result = Test-CustomScriptPathSafe -ScriptPath $null
            $result | Should -Be $false
            
            $result = Test-CustomScriptPathSafe -ScriptPath ""
            $result | Should -Be $false
        }
    }
    
    Context "Test-CustomAppInstalled" {
        It "Detects file exists" {
            $customConfig = [PSCustomObject]@{
                detect = [PSCustomObject]@{
                    type = 'file'
                    path = $script:MockDetectFile
                }
            }
            
            $result = Test-CustomAppInstalled -CustomConfig $customConfig
            
            $result.Installed | Should -Be $true
        }
        
        It "Detects file not exists" {
            $customConfig = [PSCustomObject]@{
                detect = [PSCustomObject]@{
                    type = 'file'
                    path = "C:\NonExistent\Path\app.exe"
                }
            }
            
            $result = Test-CustomAppInstalled -CustomConfig $customConfig
            
            $result.Installed | Should -Be $false
        }
        
        It "Returns error for missing detect config" {
            $result = Test-CustomAppInstalled -CustomConfig $null
            
            $result.Installed | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
        
        It "Returns error for unknown detect type" {
            $customConfig = [PSCustomObject]@{
                detect = [PSCustomObject]@{
                    type = 'unknown'
                }
            }
            
            $result = Test-CustomAppInstalled -CustomConfig $customConfig
            
            $result.Installed | Should -Be $false
            $result.Error | Should -Match 'unknown detect type'
        }
    }
}

Describe "Bundle C: Backward Compatibility" {
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:WingetScript = $script:MockWingetPath
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "Old Manifests Without Driver Field" {
        It "Treats apps without driver field as winget" {
            # Old format manifest - no driver field
            $app = [PSCustomObject]@{
                id = "7zip-7zip"
                refs = @{ windows = "7zip.7zip" }
            }
            
            $driver = Get-AppDriver -App $app
            $driver | Should -Be 'winget'
        }
        
        It "Verify works with old manifest format" {
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-compat-test"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            # Use existing test manifest (old format)
            $result = Invoke-VerifyCore -ManifestPath $script:AllInstalledManifestPath -SkipStateWrite
            
            $result.Success | Should -Be $true
            $result.OkCount | Should -Be 2
        }
    }
}

Describe "Bundle C: Verify with Version Constraints" {
    
    BeforeAll {
        $script:VersionTestDir = Join-Path $script:TestDir "version-test"
        New-Item -ItemType Directory -Path $script:VersionTestDir -Force | Out-Null
        
        # Create manifest with version constraints
        $script:VersionConstraintManifest = Join-Path $script:VersionTestDir "version-manifest.jsonc"
        $manifestContent = @'
{
  "version": 1,
  "name": "version-test",
  "apps": [
    { "id": "7zip", "refs": { "windows": "7zip.7zip" }, "version": ">=23.00" },
    { "id": "git", "refs": { "windows": "Git.Git" }, "version": ">=2.40.0" }
  ]
}
'@
        Set-Content -Path $script:VersionConstraintManifest -Value $manifestContent
        
        # Create manifest with failing version constraint
        $script:VersionFailManifest = Join-Path $script:VersionTestDir "version-fail.jsonc"
        $failContent = @'
{
  "version": 1,
  "name": "version-fail-test",
  "apps": [
    { "id": "7zip", "refs": { "windows": "7zip.7zip" }, "version": ">=99.0.0" }
  ]
}
'@
        Set-Content -Path $script:VersionFailManifest -Value $failContent
    }
    
    AfterAll {
        if ($script:VersionTestDir -and (Test-Path $script:VersionTestDir)) {
            Remove-Item -Path $script:VersionTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:WingetScript = $script:MockWingetPath
        $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-version-test"
        $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
        if (Test-Path $script:AutosuiteStateDir) {
            Remove-Item $script:AutosuiteStateDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Version Constraint Verification" {
        It "Passes when installed versions satisfy constraints" {
            # Mock winget returns 7zip 23.01 and Git 2.43.0
            $result = Invoke-VerifyCore -ManifestPath $script:VersionConstraintManifest -SkipStateWrite
            
            $result.Success | Should -Be $true
            $result.VersionMismatches | Should -Be 0
        }
        
        It "Fails when installed version violates constraint" {
            # Constraint requires >=99.0.0, but mock returns 23.01
            $result = Invoke-VerifyCore -ManifestPath $script:VersionFailManifest -SkipStateWrite
            
            $result.Success | Should -Be $false
            $result.VersionMismatches | Should -BeGreaterThan 0
        }
        
        It "Emits version mismatch count in output" {
            $output = Invoke-VerifyCore -ManifestPath $script:VersionFailManifest -SkipStateWrite 4>&1
            
            $verifyLine = $output | Where-Object { $_ -match '\[autosuite\] Verify:.*VersionMismatches=' }
            $verifyLine | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Bundle C: Apply with Version Constraints" {
    
    BeforeAll {
        $script:ApplyVersionTestDir = Join-Path $script:TestDir "apply-version-test"
        New-Item -ItemType Directory -Path $script:ApplyVersionTestDir -Force | Out-Null
        
        # Create manifest with version constraint that triggers upgrade
        $script:UpgradeManifest = Join-Path $script:ApplyVersionTestDir "upgrade-manifest.jsonc"
        $upgradeContent = @'
{
  "version": 1,
  "name": "upgrade-test",
  "apps": [
    { "id": "7zip", "refs": { "windows": "7zip.7zip" }, "version": ">=99.0.0" }
  ]
}
'@
        Set-Content -Path $script:UpgradeManifest -Value $upgradeContent
    }
    
    AfterAll {
        if ($script:ApplyVersionTestDir -and (Test-Path $script:ApplyVersionTestDir)) {
            Remove-Item -Path $script:ApplyVersionTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:WingetScript = $script:MockWingetPath
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "Apply Decides Upgrade Path" {
        It "Attempts upgrade when version constraint not satisfied (DryRun)" {
            $result = Invoke-ApplyCore -ManifestPath $script:UpgradeManifest -IsDryRun $true -IsOnlyApps $true
            
            # Should report upgrade action in dry-run
            $result.Upgraded | Should -BeGreaterThan 0
        }
    }
}

Describe "Bundle C: Drift with Version Mismatches" {
    
    BeforeEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $script:MockWingetPath
        . $script:AutosuitePath -LoadFunctionsOnly
        $script:WingetScript = $script:MockWingetPath
    }
    
    AfterEach {
        $env:AUTOSUITE_WINGET_SCRIPT = $null
    }
    
    Context "Drift Summary Includes Version Mismatches" {
        It "Drift output includes VersionMismatches count" {
            $script:AutosuiteStateDir = Join-Path $script:TestDir ".autosuite-drift-version"
            $script:AutosuiteStatePath = Join-Path $script:AutosuiteStateDir "state.json"
            
            $output = Invoke-VerifyCore -ManifestPath $script:TestManifestPath -SkipStateWrite 4>&1
            
            $driftLine = $output | Where-Object { $_ -match '\[autosuite\] Drift:.*VersionMismatches=' }
            $driftLine | Should -Not -BeNullOrEmpty
        }
    }
}

#endregion Bundle C Tests

#region Bundle D Tests - Capture Sanitization + Examples Pipeline + Guardrails

Describe "Bundle D: Capture Default Path" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
    }
    
    Context "Default Output Path Policy" {
        It "Default capture path is under local/ directory (gitignored)" {
            # The default path should be provisioning/manifests/local/<machine>.jsonc
            $expectedLocalDir = Join-Path $script:AutosuiteRoot "provisioning\manifests\local"
            $script:LocalManifestsDir | Should -Be $expectedLocalDir
        }
        
        It "Examples directory path is correctly set" {
            $expectedExamplesDir = Join-Path $script:AutosuiteRoot "provisioning\manifests\examples"
            $script:ExamplesManifestsDir | Should -Be $expectedExamplesDir
        }
    }
}

Describe "Bundle D: Sanitization Functions" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
        
        $script:SanitizeTestDir = Join-Path $script:TestDir "sanitize-test"
        New-Item -ItemType Directory -Path $script:SanitizeTestDir -Force | Out-Null
    }
    
    AfterAll {
        if ($script:SanitizeTestDir -and (Test-Path $script:SanitizeTestDir)) {
            Remove-Item -Path $script:SanitizeTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Test-IsExamplesDirectory" {
        It "Returns true for paths under examples directory" {
            $examplesPath = Join-Path $script:ExamplesManifestsDir "test.jsonc"
            $result = Test-IsExamplesDirectory -Path $examplesPath
            $result | Should -Be $true
        }
        
        It "Returns false for paths under local directory" {
            $localPath = Join-Path $script:LocalManifestsDir "test.jsonc"
            $result = Test-IsExamplesDirectory -Path $localPath
            $result | Should -Be $false
        }
        
        It "Returns false for arbitrary paths" {
            $result = Test-IsExamplesDirectory -Path "C:\temp\test.jsonc"
            $result | Should -Be $false
        }
        
        It "Returns false for null path" {
            $result = Test-IsExamplesDirectory -Path $null
            $result | Should -Be $false
        }
    }
    
    Context "Test-PathLooksLikeSecret" {
        It "Detects password-like field names" {
            $result = Test-PathLooksLikeSecret -Value "userPassword"
            $result | Should -Be $true
        }
        
        It "Detects api key field names" {
            $result = Test-PathLooksLikeSecret -Value "api_key"
            $result | Should -Be $true
            
            $result = Test-PathLooksLikeSecret -Value "apiKey"
            $result | Should -Be $true
        }
        
        It "Detects token field names" {
            $result = Test-PathLooksLikeSecret -Value "accessToken"
            $result | Should -Be $true
        }
        
        It "Returns false for normal field names" {
            $result = Test-PathLooksLikeSecret -Value "appName"
            $result | Should -Be $false
            
            $result = Test-PathLooksLikeSecret -Value "version"
            $result | Should -Be $false
        }
    }
    
    Context "Test-PathLooksLikeLocalPath" {
        It "Detects Windows user paths" {
            $result = Test-PathLooksLikeLocalPath -Value "C:\Users\john\AppData\test.exe"
            $result | Should -Be $true
        }
        
        It "Detects Linux home paths" {
            $result = Test-PathLooksLikeLocalPath -Value "/home/john/.config/app"
            $result | Should -Be $true
        }
        
        It "Detects macOS user paths" {
            $result = Test-PathLooksLikeLocalPath -Value "/Users/john/Library/app"
            $result | Should -Be $true
        }
        
        It "Returns false for program files paths" {
            $result = Test-PathLooksLikeLocalPath -Value "C:\Program Files\App\app.exe"
            $result | Should -Be $false
        }
    }
    
    Context "Invoke-SanitizeManifest" {
        It "Removes captured timestamp" {
            $manifest = @{
                version = 1
                name = "test"
                captured = "2025-01-01T00:00:00Z"
                apps = @()
            }
            
            $result = Invoke-SanitizeManifest -Manifest $manifest
            
            $result.Keys | Should -Not -Contain 'captured'
        }
        
        It "Sets custom name when provided" {
            $manifest = @{
                version = 1
                name = "old-name"
                apps = @()
            }
            
            $result = Invoke-SanitizeManifest -Manifest $manifest -NewName "new-name"
            
            $result.name | Should -Be "new-name"
        }
        
        It "Sorts apps by id for deterministic output" {
            $manifest = @{
                version = 1
                name = "test"
                apps = @(
                    @{ id = "zebra-app"; refs = @{ windows = "Zebra.App" } }
                    @{ id = "alpha-app"; refs = @{ windows = "Alpha.App" } }
                    @{ id = "middle-app"; refs = @{ windows = "Middle.App" } }
                )
            }
            
            $result = Invoke-SanitizeManifest -Manifest $manifest
            
            $result.apps[0].id | Should -Be "alpha-app"
            $result.apps[1].id | Should -Be "middle-app"
            $result.apps[2].id | Should -Be "zebra-app"
        }
        
        It "Preserves app refs" {
            $manifest = @{
                version = 1
                name = "test"
                apps = @(
                    @{ id = "test-app"; refs = @{ windows = "Test.App"; linux = "test-app" } }
                )
            }
            
            $result = Invoke-SanitizeManifest -Manifest $manifest
            
            $result.apps[0].refs.windows | Should -Be "Test.App"
            $result.apps[0].refs.linux | Should -Be "test-app"
        }
        
        It "Initializes empty restore and verify arrays" {
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
            }
            
            $result = Invoke-SanitizeManifest -Manifest $manifest
            
            # Arrays should exist as keys in the result
            $result.Keys | Should -Contain 'restore'
            $result.Keys | Should -Contain 'verify'
            $result.restore.Count | Should -Be 0
            $result.verify.Count | Should -Be 0
        }
    }
}

Describe "Bundle D: Capture Guardrails" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
        
        $script:GuardrailTestDir = Join-Path $script:TestDir "guardrail-test"
        New-Item -ItemType Directory -Path $script:GuardrailTestDir -Force | Out-Null
        
        # Create a mock examples directory for testing
        $script:MockExamplesDir = Join-Path $script:GuardrailTestDir "examples"
        New-Item -ItemType Directory -Path $script:MockExamplesDir -Force | Out-Null
        
        # Override the examples directory for testing
        $script:ExamplesManifestsDir = $script:MockExamplesDir
    }
    
    AfterAll {
        if ($script:GuardrailTestDir -and (Test-Path $script:GuardrailTestDir)) {
            Remove-Item -Path $script:GuardrailTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Overwrite Protection" {
        It "Blocks overwrite of existing example manifest without -Force" {
            # Create existing example manifest
            $existingExample = Join-Path $script:MockExamplesDir "existing.jsonc"
            Set-Content -Path $existingExample -Value '{"version": 1, "apps": []}'
            
            # Attempt to capture to same path without -Force
            $result = Invoke-Capture -OutputPath $existingExample -IsSanitize $true -ForceOverwrite $false
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "use -Force"
        }
    }
    
    Context "Non-Sanitized Write Protection" {
        It "Blocks non-sanitized capture to examples directory" {
            $examplePath = Join-Path $script:MockExamplesDir "blocked.jsonc"
            
            # Attempt non-sanitized capture to examples dir
            $result = Invoke-Capture -OutputPath $examplePath -IsSanitize $false -ForceOverwrite $false
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "Non-sanitized write"
        }
    }
}

Describe "Bundle D: Example Manifest Structure" {
    
    BeforeAll {
        $script:ExampleManifestPath = Join-Path $script:AutosuiteRoot "provisioning\manifests\examples\example-windows-core.jsonc"
    }
    
    Context "Committed Example Manifest" {
        It "Example manifest file exists" {
            $script:ExampleManifestPath | Should -Exist
        }
        
        It "Example manifest is valid JSONC" {
            $content = Get-Content $script:ExampleManifestPath -Raw
            # Strip comments
            $jsonContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
            
            { $jsonContent | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It "Example manifest has no captured timestamp" {
            $content = Get-Content $script:ExampleManifestPath -Raw
            $content | Should -Not -Match '"captured"'
        }
        
        It "Example manifest has no machine name" {
            $content = Get-Content $script:ExampleManifestPath -Raw
            $content | Should -Not -Match $env:COMPUTERNAME
        }
        
        It "Example manifest has expected structure" {
            $content = Get-Content $script:ExampleManifestPath -Raw
            $jsonContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
            $manifest = $jsonContent | ConvertFrom-Json
            
            $manifest.version | Should -Be 1
            $manifest.name | Should -Be "example-windows-core"
            $manifest.apps | Should -Not -BeNullOrEmpty
            $manifest.apps.Count | Should -BeGreaterThan 0
        }
        
        It "Example manifest apps are sorted by id" {
            $content = Get-Content $script:ExampleManifestPath -Raw
            $jsonContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
            $manifest = $jsonContent | ConvertFrom-Json
            
            $ids = $manifest.apps | ForEach-Object { $_.id }
            $sortedIds = $ids | Sort-Object
            
            # Compare arrays
            for ($i = 0; $i -lt $ids.Count; $i++) {
                $ids[$i] | Should -Be $sortedIds[$i]
            }
        }
    }
}

Describe "Bundle D: Capture Output Markers" {
    
    BeforeAll {
        . $script:AutosuitePath -LoadFunctionsOnly
    }
    
    Context "Stable Output Lines" {
        It "Capture emits starting marker" {
            # We can't fully test capture without winget, but we can test the function signature
            # and that it emits the expected markers
            $script:ExamplesManifestsDir = Join-Path $script:TestDir "examples-marker-test"
            
            # Test with legacy -Example flag which doesn't need winget
            $examplePath = Join-Path $script:TestDir "marker-test-example.jsonc"
            $output = Invoke-Capture -OutputPath $examplePath -IsExample $true 4>&1
            
            $output | Should -Contain "[autosuite] Capture: starting..."
        }
    }
}

#endregion Bundle D Tests
