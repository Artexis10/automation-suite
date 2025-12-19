BeforeAll {
    $script:AutosuiteRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:AutosuitePath = Join-Path $script:AutosuiteRoot "autosuite.ps1"
    
    # Create test directory for mock files
    $script:TestDir = Join-Path $env:TEMP "autosuite-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:MockCliPath = Join-Path $script:TestDir "mock-cli.ps1"
    $script:MockWingetPath = Join-Path $script:TestDir "mock-winget.ps1"
    $script:CapturedArgsPath = Join-Path $script:TestDir "captured-args.json"
    $script:TestManifestPath = Join-Path $script:TestDir "test-manifest.jsonc"
    
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
    
    # Create test manifest
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
    
    Context "Delegation Message" {
        BeforeEach {
            $env:AUTOSUITE_PROVISIONING_CLI = $script:MockCliPath
            if (Test-Path $script:CapturedArgsPath) {
                Remove-Item $script:CapturedArgsPath -Force
            }
        }
        
        AfterEach {
            $env:AUTOSUITE_PROVISIONING_CLI = $null
        }
        
        It "Emits stable delegation message for report" {
            $output = & $script:AutosuitePath report 2>&1
            $output | Should -Contain "[autosuite] Delegating to provisioning subsystem..."
        }
        
        It "Emits stable delegation message for doctor" {
            $output = & $script:AutosuitePath doctor 2>&1
            $output | Should -Contain "[autosuite] Delegating to provisioning subsystem..."
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
    
    Context "DryRun Mode" {
        It "Does not invoke winget install with -DryRun" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' apply -Manifest '$($script:TestManifestPath)' -DryRun -OnlyApps" 2>&1
            $outputStr = $output -join "`n"
            
            # Should show PLAN for missing app
            $outputStr | Should -Match "\[PLAN\].*Missing\.App"
            
            # Should NOT have actually installed anything
            $installLog = Join-Path $script:TestDir "install-log.txt"
            $installLog | Should -Not -Exist
        }
        
        It "Emits stable wrapper lines" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' apply -Manifest '$($script:TestManifestPath)' -DryRun -OnlyApps" 2>&1
            $outputStr = $output -join "`n"
            
            $outputStr | Should -Match "\[autosuite\] Apply: reading manifest"
            $outputStr | Should -Match "\[autosuite\] Apply: installing apps"
            $outputStr | Should -Match "\[autosuite\] Apply: completed"
        }
    }
    
    Context "Idempotent Installs" {
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
    
    Context "Exit Codes" {
        It "Exits 0 when all apps are installed" {
            # Create manifest with only installed apps
            $allInstalledManifest = Join-Path $script:TestDir "all-installed.jsonc"
            $content = @'
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
            Set-Content -Path $allInstalledManifest -Value $content
            
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$allInstalledManifest'" 2>&1
            $exitCode = $LASTEXITCODE
            
            $exitCode | Should -Be 0
        }
        
        It "Exits 1 when apps are missing" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:TestManifestPath)'" 2>&1
            $exitCode = $LASTEXITCODE
            
            $exitCode | Should -Be 1
        }
    }
    
    Context "Summary Output" {
        It "Shows OK count and missing count" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:TestManifestPath)'" 2>&1
            $outputStr = $output -join "`n"
            
            $outputStr | Should -Match "Installed OK.*2"
            $outputStr | Should -Match "Missing.*1"
        }
        
        It "Lists missing apps" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:TestManifestPath)'" 2>&1
            $outputStr = $output -join "`n"
            
            $outputStr | Should -Match "Missing\.App"
        }
        
        It "Emits stable wrapper lines" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_WINGET_SCRIPT='$($script:MockWingetPath)'; & '$($script:AutosuitePath)' verify -Manifest '$($script:TestManifestPath)'" 2>&1
            $outputStr = $output -join "`n"
            
            $outputStr | Should -Match "\[autosuite\] Verify: checking manifest"
            $outputStr | Should -Match "\[autosuite\] Verify: (PASSED|FAILED)"
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
    
    Context "Report Command" {
        It "Forwards -Latest to provisioning" {
            & $script:AutosuitePath report -Latest 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "report"
            $captured.Latest | Should -Be $true
        }
        
        It "Forwards -Json to provisioning" {
            & $script:AutosuitePath report -Json 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "report"
            $captured.Json | Should -Be $true
        }
    }
    
    Context "Doctor Command" {
        It "Forwards doctor command to provisioning" {
            & $script:AutosuitePath doctor 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "doctor"
        }
    }
}
