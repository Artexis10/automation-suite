BeforeAll {
    $script:AutosuiteRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:AutosuitePath = Join-Path $script:AutosuiteRoot "autosuite.ps1"
    
    # Create mock provisioning CLI for testing argument forwarding
    $script:MockCliDir = Join-Path $env:TEMP "autosuite-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:MockCliPath = Join-Path $script:MockCliDir "mock-cli.ps1"
    $script:CapturedArgsPath = Join-Path $script:MockCliDir "captured-args.json"
    
    New-Item -ItemType Directory -Path $script:MockCliDir -Force | Out-Null
    
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
}

AfterAll {
    # Cleanup mock CLI directory
    if ($script:MockCliDir -and (Test-Path $script:MockCliDir)) {
        Remove-Item -Path $script:MockCliDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Clear env var
    $env:AUTOSUITE_PROVISIONING_CLI = $null
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
            $outputStr | Should -Match "apply"
            $outputStr | Should -Match "capture"
            $outputStr | Should -Match "plan"
            $outputStr | Should -Match "verify"
            $outputStr | Should -Match "report"
            $outputStr | Should -Match "doctor"
        }
    }
    
    Context "Command Validation" {
        It "Requires -Profile or -Manifest for apply" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)' apply" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "Either -Profile or -Manifest is required"
        }
        
        It "Requires -Profile or -Manifest for capture" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)' capture" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "Either -Profile or -Manifest is required"
        }
        
        It "Requires -Profile or -Manifest for plan" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)' plan" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "Either -Profile or -Manifest is required"
        }
        
        It "Requires -Profile or -Manifest for verify" {
            $output = pwsh -NoProfile -Command "& '$($script:AutosuitePath)' verify" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "Either -Profile or -Manifest is required"
        }
    }
    
    Context "Delegation Message" {
        BeforeEach {
            if (Test-Path $script:CapturedArgsPath) {
                Remove-Item $script:CapturedArgsPath -Force
            }
        }
        
        It "Prints delegation message for apply" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_PROVISIONING_CLI='$($script:MockCliPath)'; & '$($script:AutosuitePath)' apply -Manifest 'c:\test.jsonc'" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "\[autosuite\] Delegating to provisioning subsystem"
        }
        
        It "Prints delegation message for capture" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_PROVISIONING_CLI='$($script:MockCliPath)'; & '$($script:AutosuitePath)' capture -Profile 'test'" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "\[autosuite\] Delegating to provisioning subsystem"
        }
        
        It "Prints delegation message for report" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_PROVISIONING_CLI='$($script:MockCliPath)'; & '$($script:AutosuitePath)' report" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "\[autosuite\] Delegating to provisioning subsystem"
        }
        
        It "Prints delegation message for doctor" {
            $output = pwsh -NoProfile -Command "`$env:AUTOSUITE_PROVISIONING_CLI='$($script:MockCliPath)'; & '$($script:AutosuitePath)' doctor" 2>&1
            $outputStr = $output -join "`n"
            $outputStr | Should -Match "\[autosuite\] Delegating to provisioning subsystem"
        }
    }
}

Describe "Autosuite Argument Forwarding" {
    
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
    
    Context "Apply Command" {
        It "Forwards -Manifest to provisioning" {
            & $script:AutosuitePath apply -Manifest "c:\test\manifest.jsonc" 2>&1 | Out-Null
            
            $script:CapturedArgsPath | Should -Exist
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "apply"
            $captured.Manifest | Should -Be "c:\test\manifest.jsonc"
        }
        
        It "Forwards -DryRun to provisioning" {
            & $script:AutosuitePath apply -Manifest "c:\test\manifest.jsonc" -DryRun 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "apply"
            $captured.DryRun | Should -Be $true
        }
        
        It "Forwards -EnableRestore to provisioning" {
            & $script:AutosuitePath apply -Manifest "c:\test\manifest.jsonc" -EnableRestore 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "apply"
            $captured.EnableRestore | Should -Be $true
        }
        
        It "Resolves -Profile to manifest path" {
            & $script:AutosuitePath apply -Profile "my-profile" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "apply"
            $captured.Manifest | Should -Match "my-profile\.jsonc$"
        }
    }
    
    Context "Capture Command" {
        It "Forwards -Profile to provisioning" {
            & $script:AutosuitePath capture -Profile "my-profile" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "capture"
            $captured.Profile | Should -Be "my-profile"
        }
        
        It "Forwards -Manifest as -OutManifest" {
            & $script:AutosuitePath capture -Manifest "c:\test\output.jsonc" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "capture"
            $captured.OutManifest | Should -Be "c:\test\output.jsonc"
        }
    }
    
    Context "Plan Command" {
        It "Forwards -Manifest to provisioning" {
            & $script:AutosuitePath plan -Manifest "c:\test\manifest.jsonc" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "plan"
            $captured.Manifest | Should -Be "c:\test\manifest.jsonc"
        }
    }
    
    Context "Verify Command" {
        It "Forwards -Manifest to provisioning" {
            & $script:AutosuitePath verify -Manifest "c:\test\manifest.jsonc" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "verify"
            $captured.Manifest | Should -Be "c:\test\manifest.jsonc"
        }
    }
    
    Context "Report Command" {
        It "Forwards -Latest to provisioning" {
            & $script:AutosuitePath report -Latest 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "report"
            $captured.Latest | Should -Be $true
        }
        
        It "Forwards -RunId to provisioning" {
            & $script:AutosuitePath report -RunId "20251219-010000" 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "report"
            $captured.RunId | Should -Be "20251219-010000"
        }
        
        It "Forwards -Last to provisioning" {
            & $script:AutosuitePath report -Last 5 2>&1 | Out-Null
            
            $captured = Get-Content $script:CapturedArgsPath | ConvertFrom-Json
            $captured.Command | Should -Be "report"
            $captured.Last | Should -Be 5
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
