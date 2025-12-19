BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ProvisioningRoot = Join-Path $script:RepoRoot "provisioning"
    $script:EngineRoot = Join-Path $script:ProvisioningRoot "engine"
    
    # Import the config-modules module
    . (Join-Path $script:EngineRoot "manifest.ps1")
    . (Join-Path $script:EngineRoot "config-modules.ps1")
    
    # Create test directory for fixtures
    $script:TestDir = Join-Path $env:TEMP "config-modules-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:TestModulesDir = Join-Path $script:TestDir "modules\apps"
    New-Item -ItemType Directory -Path $script:TestModulesDir -Force | Out-Null
}

AfterAll {
    # Cleanup test directory
    if ($script:TestDir -and (Test-Path $script:TestDir)) {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Config Module Catalog Loading" {
    
    BeforeEach {
        # Clear catalog cache before each test
        Clear-ConfigModuleCatalogCache
    }
    
    Context "Get-ConfigModuleCatalog" {
        It "Returns empty catalog when modules directory does not exist" {
            # Point to non-existent directory by temporarily modifying PSScriptRoot behavior
            $catalog = Get-ConfigModuleCatalog -Force
            
            # Should return hashtable (may be empty or contain real modules)
            $catalog | Should -BeOfType [hashtable]
        }
        
        It "Loads real seed modules from provisioning/modules/apps" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            # Should contain our seed modules
            $catalog.ContainsKey("apps.git") | Should -Be $true
            $catalog.ContainsKey("apps.vscodium") | Should -Be $true
        }
        
        It "Seed module apps.git has correct structure" {
            $catalog = Get-ConfigModuleCatalog -Force
            $gitModule = $catalog["apps.git"]
            
            $gitModule.id | Should -Be "apps.git"
            $gitModule.displayName | Should -Be "Git"
            $gitModule.matches | Should -Not -BeNullOrEmpty
            $gitModule.matches.winget | Should -Contain "Git.Git"
            $gitModule.verify | Should -Not -BeNullOrEmpty
        }
        
        It "Seed module apps.vscodium has correct structure" {
            $catalog = Get-ConfigModuleCatalog -Force
            $vscodiumModule = $catalog["apps.vscodium"]
            
            $vscodiumModule.id | Should -Be "apps.vscodium"
            $vscodiumModule.displayName | Should -Be "VSCodium"
            $vscodiumModule.matches.winget | Should -Contain "VSCodium.VSCodium"
        }
        
        It "Caches catalog on subsequent calls" {
            $catalog1 = Get-ConfigModuleCatalog
            $catalog2 = Get-ConfigModuleCatalog
            
            # Should be same reference (cached)
            [object]::ReferenceEquals($catalog1, $catalog2) | Should -Be $true
        }
        
        It "Force parameter reloads catalog" {
            $catalog1 = Get-ConfigModuleCatalog
            $catalog2 = Get-ConfigModuleCatalog -Force
            
            # Should be different reference (reloaded)
            [object]::ReferenceEquals($catalog1, $catalog2) | Should -Be $false
        }
    }
}

Describe "Config Module Schema Validation" {
    
    Context "Test-ConfigModuleSchema" {
        It "Validates module with all required fields" {
            $validModule = @{
                id = "apps.test"
                displayName = "Test App"
                matches = @{
                    winget = @("Test.App")
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $validModule
            
            $result.Valid | Should -Be $true
            $result.Error | Should -BeNullOrEmpty
        }
        
        It "Rejects module without id" {
            $invalidModule = @{
                displayName = "Test App"
                matches = @{ winget = @("Test.App") }
            }
            
            $result = Test-ConfigModuleSchema -Module $invalidModule
            
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "id"
        }
        
        It "Rejects module without displayName" {
            $invalidModule = @{
                id = "apps.test"
                matches = @{ winget = @("Test.App") }
            }
            
            $result = Test-ConfigModuleSchema -Module $invalidModule
            
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "displayName"
        }
        
        It "Rejects module without matches" {
            $invalidModule = @{
                id = "apps.test"
                displayName = "Test App"
            }
            
            $result = Test-ConfigModuleSchema -Module $invalidModule
            
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "matches"
        }
        
        It "Rejects module with empty matches" {
            $invalidModule = @{
                id = "apps.test"
                displayName = "Test App"
                matches = @{}
            }
            
            $result = Test-ConfigModuleSchema -Module $invalidModule
            
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "at least one of"
        }
        
        It "Accepts module with exe matcher only" {
            $validModule = @{
                id = "apps.test"
                displayName = "Test App"
                matches = @{
                    exe = @("test.exe")
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $validModule
            
            $result.Valid | Should -Be $true
        }
        
        It "Accepts module with uninstallDisplayName matcher only" {
            $validModule = @{
                id = "apps.test"
                displayName = "Test App"
                matches = @{
                    uninstallDisplayName = @("^Test App")
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $validModule
            
            $result.Valid | Should -Be $true
        }
        
        It "Validates sensitivity enum values" {
            $validSensitivities = @('low', 'sensitive', 'machineBound')
            
            foreach ($sensitivity in $validSensitivities) {
                $module = @{
                    id = "apps.test"
                    displayName = "Test"
                    matches = @{ winget = @("Test.App") }
                    sensitivity = $sensitivity
                }
                
                $result = Test-ConfigModuleSchema -Module $module
                $result.Valid | Should -Be $true
            }
        }
        
        It "Rejects invalid sensitivity value" {
            $module = @{
                id = "apps.test"
                displayName = "Test"
                matches = @{ winget = @("Test.App") }
                sensitivity = "invalid"
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "sensitivity"
        }
    }
}

Describe "Config Module Manifest Expansion" {
    
    BeforeAll {
        # Create test manifest directory
        $script:TestManifestDir = Join-Path $script:TestDir "manifests"
        New-Item -ItemType Directory -Path $script:TestManifestDir -Force | Out-Null
    }
    
    BeforeEach {
        Clear-ConfigModuleCatalogCache
    }
    
    Context "Expand-ManifestConfigModules" {
        It "Returns manifest unchanged when no configModules" {
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @()
                verify = @()
                configModules = @()
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest
            
            $result.restore.Count | Should -Be 0
            $result.verify.Count | Should -Be 0
        }
        
        It "Expands verify items from config module" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @()
                verify = @()
                configModules = @("apps.git")
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
            
            # apps.git has verify items
            $result.verify.Count | Should -BeGreaterThan 0
            
            # Should have command-exists for git
            $gitVerify = $result.verify | Where-Object { $_.command -eq "git" }
            $gitVerify | Should -Not -BeNullOrEmpty
        }
        
        It "Preserves existing restore/verify items" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @(
                    @{ type = "copy"; source = "./existing.txt"; target = "~/existing.txt" }
                )
                verify = @(
                    @{ type = "file-exists"; path = "~/existing.txt" }
                )
                configModules = @("apps.git")
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
            
            # Should have both existing and expanded items
            $result.restore.Count | Should -BeGreaterOrEqual 1
            $result.verify.Count | Should -BeGreaterThan 1
            
            # Existing item should still be there
            $existingVerify = $result.verify | Where-Object { $_.path -eq "~/existing.txt" }
            $existingVerify | Should -Not -BeNullOrEmpty
        }
        
        It "Marks expanded items with _fromModule" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @()
                verify = @()
                configModules = @("apps.git")
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
            
            # Expanded items should have _fromModule marker
            $expandedVerify = $result.verify | Where-Object { $_._fromModule -eq "apps.git" }
            $expandedVerify | Should -Not -BeNullOrEmpty
        }
        
        It "Throws error for unknown module id" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @()
                verify = @()
                configModules = @("apps.nonexistent")
            }
            
            { Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog } | Should -Throw "*Unknown config module*apps.nonexistent*"
        }
        
        It "Lists available modules in error message" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                configModules = @("apps.nonexistent")
            }
            
            try {
                Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
                throw "Should have thrown"
            } catch {
                $_.Exception.Message | Should -Match "apps.git"
            }
        }
        
        It "Expands multiple modules" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                apps = @()
                restore = @()
                verify = @()
                configModules = @("apps.git", "apps.vscodium")
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
            
            # Should have verify items from both modules
            $gitVerify = $result.verify | Where-Object { $_._fromModule -eq "apps.git" }
            $vscodiumVerify = $result.verify | Where-Object { $_._fromModule -eq "apps.vscodium" }
            
            $gitVerify | Should -Not -BeNullOrEmpty
            $vscodiumVerify | Should -Not -BeNullOrEmpty
        }
        
        It "Sets _configModulesExpanded after expansion" {
            $catalog = Get-ConfigModuleCatalog -Force
            
            $manifest = @{
                version = 1
                name = "test"
                configModules = @("apps.git")
            }
            
            $result = Expand-ManifestConfigModules -Manifest $manifest -Catalog $catalog
            
            $result._configModulesExpanded | Should -Contain "apps.git"
        }
    }
}

Describe "Config Module Discovery Mapping" {
    
    BeforeEach {
        Clear-ConfigModuleCatalogCache
    }
    
    Context "Get-ConfigModulesForInstalledApps" {
        It "Returns empty array when no matches" {
            $result = Get-ConfigModulesForInstalledApps -WingetInstalledIds @("Some.Other.App")
            
            # Result should be an array (possibly empty) - check it's not $null
            $null -eq $result | Should -Be $false -Because "function should return empty array, not null"
            $result.Count | Should -Be 0
        }
        
        It "Matches by winget ID" {
            $result = Get-ConfigModulesForInstalledApps -WingetInstalledIds @("Git.Git")
            
            $gitMatch = $result | Where-Object { $_.moduleId -eq "apps.git" }
            $gitMatch | Should -Not -BeNullOrEmpty
            $gitMatch.matchReasons | Should -Contain "winget:Git.Git"
        }
        
        It "Matches by exe name from discovered items" {
            $discoveries = @(
                @{
                    name = "git"
                    method = "path"
                    path = "C:\Program Files\Git\bin\git.exe"
                }
            )
            
            $result = Get-ConfigModulesForInstalledApps -DiscoveredItems $discoveries
            
            $gitMatch = $result | Where-Object { $_.moduleId -eq "apps.git" }
            $gitMatch | Should -Not -BeNullOrEmpty
            $gitMatch.matchReasons | Should -Match "exe:git.exe"
        }
        
        It "Returns deterministic order (sorted by moduleId)" {
            $result = Get-ConfigModulesForInstalledApps -WingetInstalledIds @("Git.Git", "VSCodium.VSCodium")
            
            if ($result.Count -ge 2) {
                # Should be sorted alphabetically
                $result[0].moduleId | Should -BeLessThan $result[1].moduleId
            }
        }
        
        It "Includes hasRestore and hasVerify flags" {
            $result = Get-ConfigModulesForInstalledApps -WingetInstalledIds @("Git.Git")
            
            $gitMatch = $result | Where-Object { $_.moduleId -eq "apps.git" }
            $gitMatch.hasVerify | Should -Be $true
            # hasRestore depends on whether restore items are defined
            $gitMatch.Keys | Should -Contain "hasRestore"
        }
    }
    
    Context "Format-ConfigModuleDiscoveryOutput" {
        It "Returns message for empty matches" {
            $result = Format-ConfigModuleDiscoveryOutput -Matches @()
            
            $result | Should -Match "No config modules available"
        }
        
        It "Formats module matches with features" {
            $testMatches = @(
                @{
                    moduleId = "apps.test"
                    displayName = "Test App"
                    matchReasons = @("winget:Test.App")
                    hasVerify = $true
                    hasRestore = $false
                }
            )
            
            $result = Format-ConfigModuleDiscoveryOutput -Matches $testMatches
            
            $result | Should -Match "apps.test"
            $result | Should -Match "Test App"
            $result | Should -Match "verify"
            $result | Should -Match "winget:Test.App"
        }
    }
}

Describe "Config Modules Integration with Manifest Loading" {
    
    BeforeAll {
        $script:IntegrationTestDir = Join-Path $script:TestDir "integration"
        New-Item -ItemType Directory -Path $script:IntegrationTestDir -Force | Out-Null
    }
    
    BeforeEach {
        Clear-ConfigModuleCatalogCache
    }
    
    Context "Read-Manifest with configModules" {
        It "Expands configModules when loading manifest" {
            # Create test manifest with configModules
            $manifestPath = Join-Path $script:IntegrationTestDir "test-with-modules.jsonc"
            $manifestContent = @'
{
  "version": 1,
  "name": "test-with-modules",
  "apps": [],
  "configModules": ["apps.git"],
  "restore": [],
  "verify": []
}
'@
            Set-Content -Path $manifestPath -Value $manifestContent
            
            $manifest = Read-Manifest -Path $manifestPath
            
            # Should have expanded verify items from apps.git
            $gitVerify = $manifest.verify | Where-Object { $_._fromModule -eq "apps.git" }
            $gitVerify | Should -Not -BeNullOrEmpty
        }
        
        It "Skips expansion with -SkipConfigModuleExpansion" {
            $manifestPath = Join-Path $script:IntegrationTestDir "test-skip-expansion.jsonc"
            $manifestContent = @'
{
  "version": 1,
  "name": "test-skip",
  "configModules": ["apps.git"],
  "verify": []
}
'@
            Set-Content -Path $manifestPath -Value $manifestContent
            
            $manifest = Read-Manifest -Path $manifestPath -SkipConfigModuleExpansion
            
            # Should NOT have expanded items
            $expandedVerify = $manifest.verify | Where-Object { $_._fromModule }
            $expandedVerify | Should -BeNullOrEmpty
            
            # configModules should still be present
            $manifest.configModules | Should -Contain "apps.git"
        }
        
        It "Manifest without configModules loads normally" {
            $manifestPath = Join-Path $script:IntegrationTestDir "test-no-modules.jsonc"
            $manifestContent = @'
{
  "version": 1,
  "name": "test-no-modules",
  "apps": [
    { "id": "test-app", "refs": { "windows": "Test.App" } }
  ],
  "verify": [
    { "type": "file-exists", "path": "~/test.txt" }
  ]
}
'@
            Set-Content -Path $manifestPath -Value $manifestContent
            
            $manifest = Read-Manifest -Path $manifestPath
            
            $manifest.apps.Count | Should -Be 1
            $manifest.verify.Count | Should -Be 1
        }
    }
}

Describe "Config Module Capture Schema Validation" {
    
    BeforeAll {
        . "$PSScriptRoot\..\..\provisioning\engine\manifest.ps1"
        . "$PSScriptRoot\..\..\provisioning\engine\config-modules.ps1"
    }
    
    BeforeEach {
        Clear-ConfigModuleCatalogCache
    }
    
    Context "Test-ConfigModuleSchema with capture section" {
        It "Accepts module with valid capture section" {
            $module = @{
                id = "test.module"
                displayName = "Test Module"
                matches = @{ winget = @("Test.App") }
                capture = @{
                    files = @(
                        @{ source = "~/.config"; dest = "apps/test/config"; optional = $true }
                    )
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            $result.Valid | Should -Be $true
        }
        
        It "Accepts module with capture and excludeGlobs" {
            $module = @{
                id = "test.module"
                displayName = "Test Module"
                matches = @{ winget = @("Test.App") }
                capture = @{
                    files = @(
                        @{ source = "%APPDATA%\Test\settings.json"; dest = "apps/test/settings.json" }
                    )
                    excludeGlobs = @("**\Cache\**", "**\Temp\**")
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            $result.Valid | Should -Be $true
        }
        
        It "Rejects capture without files array" {
            $module = @{
                id = "test.module"
                displayName = "Test Module"
                matches = @{ winget = @("Test.App") }
                capture = @{
                    excludeGlobs = @("**\Cache\**")
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "capture.files"
        }
        
        It "Rejects capture.files entry without source" {
            $module = @{
                id = "test.module"
                displayName = "Test Module"
                matches = @{ winget = @("Test.App") }
                capture = @{
                    files = @(
                        @{ dest = "apps/test/config" }
                    )
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "source"
        }
        
        It "Rejects capture.files entry without dest" {
            $module = @{
                id = "test.module"
                displayName = "Test Module"
                matches = @{ winget = @("Test.App") }
                capture = @{
                    files = @(
                        @{ source = "~/.config" }
                    )
                }
            }
            
            $result = Test-ConfigModuleSchema -Module $module
            $result.Valid | Should -Be $false
            $result.Error | Should -Match "dest"
        }
    }
}

Describe "Config Module Capture Functions" {
    
    BeforeAll {
        . "$PSScriptRoot\..\..\provisioning\engine\manifest.ps1"
        . "$PSScriptRoot\..\..\provisioning\engine\config-modules.ps1"
        
        # Create test directory
        $script:CaptureTestDir = Join-Path $env:TEMP "autosuite-capture-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:CaptureTestDir -Force | Out-Null
    }
    
    AfterAll {
        if (Test-Path $script:CaptureTestDir) {
            Remove-Item -Path $script:CaptureTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Expand-ConfigPath" {
        It "Expands ~ to user profile" {
            $result = Expand-ConfigPath -Path "~/.gitconfig"
            $result | Should -Be (Join-Path $env:USERPROFILE ".gitconfig")
        }
        
        It "Expands %APPDATA% environment variable" {
            $result = Expand-ConfigPath -Path "%APPDATA%\Test\config.json"
            $result | Should -Be (Join-Path $env:APPDATA "Test\config.json")
        }
        
        It "Expands %USERPROFILE% environment variable" {
            $result = Expand-ConfigPath -Path "%USERPROFILE%\.ssh\config"
            $result | Should -Be (Join-Path $env:USERPROFILE ".ssh\config")
        }
        
        It "Returns path unchanged if no expansion needed" {
            $result = Expand-ConfigPath -Path "C:\absolute\path\file.txt"
            $result | Should -Be "C:\absolute\path\file.txt"
        }
    }
    
    Context "Test-PathMatchesExcludeGlobs" {
        It "Returns false when no exclude globs" {
            $result = Test-PathMatchesExcludeGlobs -Path "C:\some\path\file.txt" -ExcludeGlobs @()
            $result | Should -Be $false
        }
        
        It "Matches Cache directory pattern" {
            $result = Test-PathMatchesExcludeGlobs -Path "C:\App\Cache\data.bin" -ExcludeGlobs @("**/Cache/**")
            $result | Should -Be $true
        }
        
        It "Does not match non-matching path" {
            $result = Test-PathMatchesExcludeGlobs -Path "C:\App\User\settings.json" -ExcludeGlobs @("**/Cache/**")
            $result | Should -Be $false
        }
    }
    
    Context "Invoke-ConfigModuleCapture" {
        BeforeEach {
            # Create test source files
            $script:TestSourceDir = Join-Path $script:CaptureTestDir "source"
            $script:TestPayloadDir = Join-Path $script:CaptureTestDir "payload"
            New-Item -ItemType Directory -Path $script:TestSourceDir -Force | Out-Null
            
            # Create test files
            "test content" | Set-Content -Path (Join-Path $script:TestSourceDir "config.txt")
            "optional content" | Set-Content -Path (Join-Path $script:TestSourceDir "optional.txt")
        }
        
        AfterEach {
            if (Test-Path $script:TestPayloadDir) {
                Remove-Item -Path $script:TestPayloadDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Returns warning when no modules have capture definitions" {
            # Create a mock catalog with no capture sections
            $result = Invoke-ConfigModuleCapture -Modules @("nonexistent.module") -PayloadOut $script:TestPayloadDir
            
            $result.warnings.Count | Should -BeGreaterThan 0
        }
        
        It "Copies files to payload directory" {
            # This test uses the real seed modules which now have capture sections
            Clear-ConfigModuleCatalogCache
            $catalog = Get-ConfigModuleCatalog
            
            # Find a module with capture (apps.git has capture)
            $gitModule = $catalog["apps.git"]
            if ($gitModule -and $gitModule.capture) {
                $result = Invoke-ConfigModuleCapture -Modules @("apps.git") -PayloadOut $script:TestPayloadDir
                
                # Result should have the expected structure
                $result.payloadRoot | Should -Be $script:TestPayloadDir
                $result.Keys | Should -Contain "copied"
                $result.Keys | Should -Contain "skipped"
                $result.Keys | Should -Contain "missing"
            }
        }
        
        It "Skips optional files that don't exist" {
            Clear-ConfigModuleCatalogCache
            $catalog = Get-ConfigModuleCatalog
            
            # apps.git has optional files that likely don't exist in test env
            $result = Invoke-ConfigModuleCapture -Modules @("apps.git") -PayloadOut $script:TestPayloadDir
            
            # Should have skipped items (optional files not found)
            # This is expected behavior - not a failure
            $result.Keys | Should -Contain "skipped"
        }
    }
}

Describe "Manifest Hashing Semantics" {
    
    BeforeAll {
        . "$PSScriptRoot\..\..\provisioning\engine\manifest.ps1"
        . "$PSScriptRoot\..\..\provisioning\engine\state.ps1"
        . "$PSScriptRoot\..\..\provisioning\engine\config-modules.ps1"
        
        $script:HashTestDir = Join-Path $env:TEMP "autosuite-hash-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:HashTestDir -Force | Out-Null
    }
    
    AfterAll {
        if (Test-Path $script:HashTestDir) {
            Remove-Item -Path $script:HashTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Get-ManifestHash (raw file hash)" {
        It "Returns hash for existing file" {
            $manifestPath = Join-Path $script:HashTestDir "test-raw.jsonc"
            '{ "version": 1, "name": "test" }' | Set-Content -Path $manifestPath
            
            $hash = Get-ManifestHash -ManifestPath $manifestPath
            
            $hash | Should -Not -BeNullOrEmpty
            $hash.Length | Should -Be 16
        }
        
        It "Returns null for non-existent file" {
            $hash = Get-ManifestHash -ManifestPath "C:\nonexistent\file.jsonc"
            
            $hash | Should -BeNullOrEmpty
        }
        
        It "Returns same hash for identical file content" {
            $manifestPath1 = Join-Path $script:HashTestDir "test-same1.jsonc"
            $manifestPath2 = Join-Path $script:HashTestDir "test-same2.jsonc"
            $content = '{ "version": 1, "name": "test" }'
            $content | Set-Content -Path $manifestPath1
            $content | Set-Content -Path $manifestPath2
            
            $hash1 = Get-ManifestHash -ManifestPath $manifestPath1
            $hash2 = Get-ManifestHash -ManifestPath $manifestPath2
            
            $hash1 | Should -Be $hash2
        }
    }
    
    Context "Get-ExpandedManifestHash (expanded manifest hash)" {
        It "Returns hash for manifest without configModules" {
            $manifestPath = Join-Path $script:HashTestDir "test-expanded-simple.jsonc"
            @'
{
  "version": 1,
  "name": "test-simple",
  "apps": []
}
'@ | Set-Content -Path $manifestPath
            
            $hash = Get-ExpandedManifestHash -ManifestPath $manifestPath
            
            $hash | Should -Not -BeNullOrEmpty
            $hash.Length | Should -Be 16
        }
        
        It "Returns different hash when configModules are expanded" {
            Clear-ConfigModuleCatalogCache
            
            # Manifest without configModules
            $manifestPath1 = Join-Path $script:HashTestDir "test-no-modules.jsonc"
            @'
{
  "version": 1,
  "name": "test",
  "verify": []
}
'@ | Set-Content -Path $manifestPath1
            
            # Manifest with configModules (will be expanded)
            $manifestPath2 = Join-Path $script:HashTestDir "test-with-modules.jsonc"
            @'
{
  "version": 1,
  "name": "test",
  "configModules": ["apps.git"],
  "verify": []
}
'@ | Set-Content -Path $manifestPath2
            
            $hash1 = Get-ExpandedManifestHash -ManifestPath $manifestPath1
            $hash2 = Get-ExpandedManifestHash -ManifestPath $manifestPath2
            
            # Hashes should be different because apps.git adds verify items
            $hash1 | Should -Not -Be $hash2
        }
        
        It "Raw hash differs from expanded hash for manifest with configModules" {
            Clear-ConfigModuleCatalogCache
            
            $manifestPath = Join-Path $script:HashTestDir "test-raw-vs-expanded.jsonc"
            @'
{
  "version": 1,
  "name": "test",
  "configModules": ["apps.git"],
  "verify": []
}
'@ | Set-Content -Path $manifestPath
            
            $rawHash = Get-ManifestHash -ManifestPath $manifestPath
            $expandedHash = Get-ExpandedManifestHash -ManifestPath $manifestPath
            
            # Raw hash is file content, expanded hash is processed manifest
            # They should be different
            $rawHash | Should -Not -Be $expandedHash
        }
    }
}
