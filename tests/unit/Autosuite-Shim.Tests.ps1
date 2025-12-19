<#
.SYNOPSIS
    Unit tests for autosuite CLI shim behavior.

.DESCRIPTION
    Tests that the installed shim correctly:
    - Resolves repo root from env var or repo-root.txt
    - Fails with clear message when repo root not configured
    - Delegates to repo entrypoint with all arguments preserved
    - Does not attempt to load modules from %LOCALAPPDATA%
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ShimTemplatePath = Join-Path $script:RepoRoot "provisioning\engine\shim-template.ps1"
    
    # Ensure shim template exists
    if (-not (Test-Path $script:ShimTemplatePath)) {
        throw "Shim template not found: $script:ShimTemplatePath"
    }
}

Describe "Shim Template" {
    It "Should exist at expected path" {
        Test-Path $script:ShimTemplatePath | Should -Be $true
    }
    
    It "Should be a valid PowerShell script" {
        { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script:ShimTemplatePath -Raw), [ref]$null) } | Should -Not -Throw
    }
    
    It "Should contain Get-RepoRootPath function" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        $content | Should -Match 'function Get-RepoRootPath'
    }
    
    It "Should check AUTOSUITE_ROOT environment variable" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        $content | Should -Match '\$env:AUTOSUITE_ROOT'
    }
    
    It "Should check repo-root.txt file" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        $content | Should -Match 'repo-root\.txt'
    }
    
    It "Should delegate to repo entrypoint with @args" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        $content | Should -Match '& \$repoEntrypoint @args'
    }
    
    It "Should preserve exit code using LASTEXITCODE" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        $content | Should -Match '\$LASTEXITCODE'
        $content | Should -Match 'exit \$exitCode'
    }
}

Describe "Shim Behavior - Repo Root Resolution" {
    BeforeAll {
        # Create temp directory for testing
        $script:TestDir = Join-Path $env:TEMP "autosuite-shim-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        
        # Create a mock repo structure
        $script:MockRepoRoot = Join-Path $script:TestDir "mock-repo"
        New-Item -ItemType Directory -Path $script:MockRepoRoot -Force | Out-Null
        
        # Create mock autosuite.ps1 in mock repo
        $mockEntrypoint = Join-Path $script:MockRepoRoot "autosuite.ps1"
        $mockScript = @'
param()
Write-Output "MOCK_ENTRYPOINT_CALLED"
Write-Output "Args: $args"
exit 42
'@
        Set-Content -Path $mockEntrypoint -Value $mockScript -Encoding UTF8
        
        # Create test shim
        $script:TestShimPath = Join-Path $script:TestDir "test-shim.ps1"
        Copy-Item -Path $script:ShimTemplatePath -Destination $script:TestShimPath -Force
    }
    
    AfterAll {
        # Cleanup
        if (Test-Path $script:TestDir) {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "When AUTOSUITE_ROOT is set" {
        It "Should use AUTOSUITE_ROOT and delegate to repo entrypoint" {
            $env:AUTOSUITE_ROOT = $script:MockRepoRoot
            
            try {
                $output = & pwsh -NoProfile -File $script:TestShimPath "apply" "-Profile" "test" 2>&1
                $LASTEXITCODE | Should -Be 42
                $output -join "`n" | Should -Match "MOCK_ENTRYPOINT_CALLED"
            } finally {
                $env:AUTOSUITE_ROOT = $null
            }
        }
        
        It "Should forward all arguments correctly" {
            $env:AUTOSUITE_ROOT = $script:MockRepoRoot
            
            try {
                $output = & pwsh -NoProfile -File $script:TestShimPath "apply" "-Profile" "hugo-desktop" "-Parallel" "-Throttle" "3" 2>&1
                $outputStr = $output -join "`n"
                $outputStr | Should -Match "MOCK_ENTRYPOINT_CALLED"
                $outputStr | Should -Match "apply"
                $outputStr | Should -Match "hugo-desktop"
                $outputStr | Should -Match "Parallel"
            } finally {
                $env:AUTOSUITE_ROOT = $null
            }
        }
    }
    
    Context "When repo-root.txt exists" {
        It "Should use repo-root.txt if AUTOSUITE_ROOT not set" {
            # Create mock LOCALAPPDATA structure
            $mockLocalAppData = Join-Path $script:TestDir "LocalAppData"
            $autosuiteDir = Join-Path $mockLocalAppData "Autosuite"
            New-Item -ItemType Directory -Path $autosuiteDir -Force | Out-Null
            
            $repoRootFile = Join-Path $autosuiteDir "repo-root.txt"
            Set-Content -Path $repoRootFile -Value $script:MockRepoRoot -Encoding UTF8
            
            # Temporarily override LOCALAPPDATA
            $originalLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = $mockLocalAppData
            $env:AUTOSUITE_ROOT = $null
            
            try {
                $output = & pwsh -NoProfile -File $script:TestShimPath "verify" 2>&1
                $LASTEXITCODE | Should -Be 42
                $output -join "`n" | Should -Match "MOCK_ENTRYPOINT_CALLED"
            } finally {
                $env:LOCALAPPDATA = $originalLocalAppData
                $env:AUTOSUITE_ROOT = $null
            }
        }
    }
    
    Context "When repo root not configured" {
        It "Should fail with clear error message" {
            # Ensure no repo root configured
            $mockLocalAppData = Join-Path $script:TestDir "LocalAppData-Empty"
            New-Item -ItemType Directory -Path $mockLocalAppData -Force | Out-Null
            
            $originalLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = $mockLocalAppData
            $env:AUTOSUITE_ROOT = $null
            
            try {
                $output = & pwsh -NoProfile -File $script:TestShimPath "apply" 2>&1
                $LASTEXITCODE | Should -Be 1
                $outputStr = $output -join "`n"
                $outputStr | Should -Match "repo root not configured"
                $outputStr | Should -Match "bootstrap"
            } finally {
                $env:LOCALAPPDATA = $originalLocalAppData
                $env:AUTOSUITE_ROOT = $null
            }
        }
    }
}

Describe "Bootstrap Integration" {
    BeforeAll {
        # Dot-source autosuite.ps1 to load functions
        . (Join-Path $script:RepoRoot "autosuite.ps1") -LoadFunctionsOnly
    }
    
    It "Should have Install-AutosuiteToPath function available" {
        Get-Command Install-AutosuiteToPath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Install-AutosuiteToPath should reference shim-template.ps1" {
        $functionDef = (Get-Command Install-AutosuiteToPath).Definition
        $functionDef | Should -Match 'shim-template\.ps1'
    }
    
    It "Should not copy full autosuite.ps1 to bin directory" {
        $functionDef = (Get-Command Install-AutosuiteToPath).Definition
        # Should NOT use $PSCommandPath as source
        $functionDef | Should -Not -Match '\$sourceScript = \$PSCommandPath'
    }
}

Describe "Shim Does Not Load Provisioning Modules" {
    It "Shim template should not contain provisioning engine imports" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        
        # Should NOT import or dot-source provisioning modules
        $content | Should -Not -Match 'provisioning\\engine\\parallel\.ps1'
        $content | Should -Not -Match 'provisioning\\engine\\progress\.ps1'
        $content | Should -Not -Match '\. .+provisioning'
    }
    
    It "Shim template should not reference LOCALAPPDATA for module paths" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        
        # Should NOT try to load modules from LOCALAPPDATA
        $content | Should -Not -Match 'LOCALAPPDATA.+provisioning.+\.ps1'
    }
    
    It "Shim should only resolve repo root and delegate" {
        $content = Get-Content $script:ShimTemplatePath -Raw
        
        # Count function definitions - should only have Get-RepoRootPath
        $functionMatches = [regex]::Matches($content, 'function\s+[\w-]+')
        $functionMatches.Count | Should -Be 1
        $functionMatches[0].Value | Should -Match 'Get-RepoRootPath'
    }
}
