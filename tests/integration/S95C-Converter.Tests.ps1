<#
.SYNOPSIS
    Integration tests for Convert-Unsupported-Audio-for-S95C.ps1

.DESCRIPTION
    Tests the script execution in a sandbox environment.
    Tests tagged 'OptionalTooling' require ffmpeg/ffprobe and are skipped by default.
#>

BeforeAll {
    # Load test helpers
    . (Join-Path $PSScriptRoot "..\TestHelpers.ps1")
    
    $script:RepoRoot = Get-RepoRoot
    $script:ScriptPath = Join-Path $script:RepoRoot "media-tools\unsupported-audio-conversion-for-s95c\Convert-Unsupported-Audio-for-S95C.ps1"
}

Describe "Convert-Unsupported-Audio-for-S95C.ps1" -Tag "Integration" {
    
    BeforeEach {
        $script:Sandbox = New-TestSandbox -Prefix "s95c-test"
        $script:SourceDir = Join-Path $script:Sandbox.Path "source"
        $script:DestDir = Join-Path $script:Sandbox.Path "dest"
        New-Item -ItemType Directory -Path $script:SourceDir -Force | Out-Null
    }
    
    AfterEach {
        # Cleanup sandbox
        if ($script:Sandbox -and $script:Sandbox.Path -and (Test-Path $script:Sandbox.Path)) {
            Remove-Item -Path $script:Sandbox.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Script validation" {
        It "script file exists" {
            Test-Path $script:ScriptPath | Should -BeTrue
        }
        
        It "script has valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }
    
    Context "Empty source directory" {
        It "handles empty source gracefully" {
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Script should complete without error
            $result.ExitCode | Should -Be 0
            # Should mention no MKV files found
            $result.StdOut | Should -Match "No MKV files found"
        }
    }
    
    Context "Non-existent source directory" {
        It "reports error for missing source" {
            $nonExistent = Join-Path $script:Sandbox.Path "does-not-exist"
            
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $nonExistent
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Should report error about source path
            $result.StdOut | Should -Match "\[ERROR\].*Source path does not exist"
            $result.ExitCode | Should -Be 1
        }
    }
    
    Context "Parameter validation" {
        It "rejects DestRoot equal to SourceRoot" {
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:SourceDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            $result.StdOut | Should -Match "\[ERROR\].*DestRoot cannot be the same as SourceRoot"
            $result.ExitCode | Should -Be 1
        }
        
        It "rejects DestRoot inside SourceRoot with -Recurse" {
            $nestedDest = Join-Path $script:SourceDir "output"
            
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $nestedDest
                    Recurse = $true
                } `
                -SandboxPath $script:Sandbox.Path
            
            $result.StdOut | Should -Match "\[ERROR\].*inside SourceRoot.*infinite recursion"
            $result.ExitCode | Should -Be 1
        }
        
        It "allows DestRoot inside SourceRoot without -Recurse" {
            $nestedDest = Join-Path $script:SourceDir "output"
            
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $nestedDest
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Should not error about recursion (no -Recurse flag)
            $result.StdOut | Should -Not -Match "infinite recursion"
            # May report no MKV files, which is fine
        }
        
        It "rejects MaxParallel above 64" {
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                    MaxParallel = 100
                } `
                -SandboxPath $script:Sandbox.Path
            
            # PowerShell ValidateRange should reject this - check all outputs for validation error
            $hasError = ($result.ExitCode -ne 0) -or 
                        ($result.StdErr -match "greater than the maximum") -or 
                        ($result.StdOut -match "greater than the maximum")
            $hasError | Should -BeTrue
        }
    }
    
    Context "Directory structure mirroring" -Tag "OptionalTooling" {
        BeforeEach {
            # Skip if ffmpeg not available
            if (-not (Test-HasCommand -Name "ffmpeg")) {
                Set-ItResult -Skipped -Because "ffmpeg not found; skipping OptionalTooling tests"
            }
            if (-not (Test-HasCommand -Name "ffprobe")) {
                Set-ItResult -Skipped -Because "ffprobe not found; skipping OptionalTooling tests"
            }
        }
        
        It "creates destination directory structure" {
            # Create nested source structure
            $nestedDir = Join-Path $script:SourceDir "Movies\Action"
            New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
            
            # Create a minimal dummy MKV file (just touch for structure test)
            # Note: This test verifies directory creation, not actual conversion
            $testFile = Join-Path $nestedDir "test.mkv"
            [System.IO.File]::WriteAllBytes($testFile, [byte[]](0x1A, 0x45, 0xDF, 0xA3))
            
            $null = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                    Recurse = $true
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Destination structure should be created (even if conversion fails on dummy file)
            # The script creates directories before attempting conversion
            $expectedDestDir = Join-Path $script:DestDir "Movies\Action"
            Test-Path $expectedDestDir | Should -BeTrue
        }
    }
}

Describe "S95C Converter with real media" -Tag "OptionalTooling" {
    
    BeforeAll {
        # Skip entire describe block if ffmpeg/ffprobe not available
        $script:HasFFmpeg = Test-HasCommand -Name "ffmpeg"
        $script:HasFFprobe = Test-HasCommand -Name "ffprobe"
    }
    
    BeforeEach {
        if (-not $script:HasFFmpeg -or -not $script:HasFFprobe) {
            Set-ItResult -Skipped -Because "ffmpeg/ffprobe not found; skipping OptionalTooling tests"
            return
        }
        
        $script:Sandbox = New-TestSandbox -Prefix "s95c-media"
        $script:SourceDir = Join-Path $script:Sandbox.Path "source"
        $script:DestDir = Join-Path $script:Sandbox.Path "dest"
        New-Item -ItemType Directory -Path $script:SourceDir -Force | Out-Null
    }
    
    AfterEach {
        if ($script:Sandbox -and $script:Sandbox.Path -and (Test-Path $script:Sandbox.Path)) {
            Remove-Item -Path $script:Sandbox.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "AAC audio passthrough" {
        It "copies MKV with AAC audio unchanged" {
            if (-not $script:HasFFmpeg) {
                Set-ItResult -Skipped -Because "ffmpeg not found"
                return
            }
            
            # Generate a tiny test MKV with AAC audio using ffmpeg
            $testMkv = Join-Path $script:SourceDir "aac-test.mkv"
            
            # Create 1-second silent video with AAC audio
            $ffmpegArgs = @(
                "-f", "lavfi", "-i", "color=black:s=64x64:d=1",
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                "-t", "1",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a", "aac",
                "-y", $testMkv
            )
            
            $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $script:Sandbox.Path "ffmpeg-create.log")
            
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $testMkv)) {
                Set-ItResult -Skipped -Because "Failed to create test MKV file"
                return
            }
            
            # Run the converter
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Output file should exist
            $outputMkv = Join-Path $script:DestDir "aac-test.mkv"
            Test-Path $outputMkv | Should -BeTrue
            
            # Output should be non-zero size
            (Get-Item $outputMkv).Length | Should -BeGreaterThan 0
            
            # Should indicate it was copied (not converted)
            $result.StdOut | Should -Match "(\[SKIP\]|\[OK\].*[Cc]opied)"
        }
    }
}
