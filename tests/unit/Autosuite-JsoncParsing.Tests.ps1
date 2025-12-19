<#
.SYNOPSIS
    Regression test for JSONC parsing in autosuite.ps1
.DESCRIPTION
    Tests that autosuite apply correctly parses JSONC manifests with header comments.
    This test catches the bug where autosuite.ps1 had a broken regex-based Read-Manifest
    that bypassed the canonical JSONC loader.
#>

# Resolve paths properly
$script:TestRoot = $PSScriptRoot
$script:AutosuiteRoot = (Resolve-Path (Join-Path $script:TestRoot "..\..")).Path
$script:AutosuiteScript = Join-Path $script:AutosuiteRoot "autosuite.ps1"

# Load autosuite functions without running main logic
. $script:AutosuiteScript -LoadFunctionsOnly

# Verify AutosuiteRoot was set correctly
if (-not $script:AutosuiteRoot) {
    throw "Failed to resolve AutosuiteRoot"
}

Describe "Autosuite.JsoncParsing.Regression" {
    
    Context "Read-Manifest function (PS5.1+ compatible)" {
        
        It "Should parse JSONC with header comments at lines 2-6 (regression test)" {
            # This is the exact bug that was failing: manifests with // comments at line 6
            # were throwing "Invalid object passed in, ':' or '}' expected. (6)"
            
            $tempDir = Join-Path $script:AutosuiteRoot ".autosuite\temp-test"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $tempFile = Join-Path $tempDir "header-comments-test.jsonc"
            $content = @"
{
  // Provisioning Manifest
  // Generated: 2025-12-19 21:39:29
  // Machine: HUGO
  // Format: JSONC (JSON with comments)

  "version": 1,
  "name": "header-comments-test",
  "apps": [
    {
      "id": "test-app",
      "refs": {
        "windows": "Test.App"
      }
    }
  ]
}
"@
            $content | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
            
            try {
                # This should NOT throw on PS5.1 or PS7+
                { Read-Manifest -Path $tempFile } | Should Not Throw
                
                $manifest = Read-Manifest -Path $tempFile
                
                # Verify parsed correctly
                $manifest | Should Not BeNullOrEmpty
                $manifest.version | Should Be 1
                $manifest.name | Should Be "header-comments-test"
                $manifest.apps | Should Not BeNullOrEmpty
                $manifest.apps.Count | Should Be 1
                $manifest.apps[0].id | Should Be "test-app"
                
                # Verify we got a hashtable (not PSCustomObject)
                $manifest | Should BeOfType [hashtable]
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
        
        It "Should preserve http:// URLs inside strings (not strip as comment)" {
            # Critical: ensure we don't strip // inside JSON strings
            $tempDir = Join-Path $script:AutosuiteRoot ".autosuite\temp-test"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $tempFile = Join-Path $tempDir "url-test.jsonc"
            $content = @"
{
  "version": 1,
  "name": "url-test",
  "homepage": "http://example.com",
  "docs": "https://example.com/docs",
  "apps": []
}
"@
            $content | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
            
            try {
                $manifest = Read-Manifest -Path $tempFile
                
                $manifest | Should Not BeNullOrEmpty
                $manifest.homepage | Should Be "http://example.com"
                $manifest.docs | Should Be "https://example.com/docs"
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
        
        It "Should parse inline comments after values" {
            $tempDir = Join-Path $script:AutosuiteRoot ".autosuite\temp-test"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $tempFile = Join-Path $tempDir "inline-comments-test.jsonc"
            $content = @"
{
  "version": 1, // version comment
  "name": "test",
  "apps": []
}
"@
            $content | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
            
            try {
                $manifest = Read-Manifest -Path $tempFile
                
                $manifest | Should Not BeNullOrEmpty
                $manifest.version | Should Be 1
                $manifest.name | Should Be "test"
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
        
        It "Should parse multi-line /* */ comments" {
            $tempDir = Join-Path $script:AutosuiteRoot ".autosuite\temp-test"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $tempFile = Join-Path $tempDir "multiline-comments-test.jsonc"
            $content = @"
{
  /* This is a multi-line comment
     spanning multiple lines */
  "version": 1,
  "name": "test",
  "apps": []
}
"@
            $content | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
            
            try {
                $manifest = Read-Manifest -Path $tempFile
                
                $manifest | Should Not BeNullOrEmpty
                $manifest.version | Should Be 1
                $manifest.name | Should Be "test"
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
        
        It "Should work on both PS5.1 and PS7+" {
            # Verify PS version compatibility
            $psVersion = $PSVersionTable.PSVersion.Major
            
            $tempDir = Join-Path $script:AutosuiteRoot ".autosuite\temp-test"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $tempFile = Join-Path $tempDir "ps-version-test.jsonc"
            $content = @"
{
  // Comment at top
  "version": 1,
  "name": "ps-version-test",
  "psVersion": $psVersion,
  "apps": []
}
"@
            $content | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
            
            try {
                # Should not throw on either PS version
                { Read-Manifest -Path $tempFile } | Should Not Throw
                
                $manifest = Read-Manifest -Path $tempFile
                $manifest | Should Not BeNullOrEmpty
                $manifest.version | Should Be 1
                
                # Verify we got a hashtable (not PSCustomObject)
                $manifest | Should BeOfType [hashtable]
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
        
        It "Should parse real fixture-test.jsonc manifest" {
            # Test with actual committed manifest
            $fixtureManifest = Join-Path $script:AutosuiteRoot "provisioning\manifests\fixture-test.jsonc"
            
            if (Test-Path $fixtureManifest) {
                $manifest = Read-Manifest -Path $fixtureManifest
                
                $manifest | Should Not BeNullOrEmpty
                $manifest.version | Should Be 1
                $manifest.name | Should Be "fixture-test"
                $manifest.apps | Should Not BeNullOrEmpty
            }
        }
    }
}
