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
    
    Context "Directory structure mirroring" {
        # Tool-free test: directory creation happens before probe/conversion attempt
        # The script creates destination directories when queuing files, regardless of conversion outcome
        
        It "creates destination directory structure before conversion attempt" {
            # Create nested source structure
            $nestedDir = Join-Path $script:SourceDir "Movies\Action\Sci-Fi"
            New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
            
            # Create a minimal dummy MKV file (invalid content, will fail probe)
            $testFile = Join-Path $nestedDir "test.mkv"
            [System.IO.File]::WriteAllBytes($testFile, [byte[]](0x1A, 0x45, 0xDF, 0xA3))
            
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                    Recurse = $true
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Destination structure should be created (even though conversion fails on dummy file)
            # The worker creates directories before attempting ffprobe
            $expectedDestDir = Join-Path $script:DestDir "Movies\Action\Sci-Fi"
            Test-Path $expectedDestDir | Should -BeTrue
        }
    }
}

Describe "S95C Converter -Overwrite behavior" -Tag "Integration" {
    
    BeforeEach {
        $script:Sandbox = New-TestSandbox -Prefix "s95c-overwrite"
        $script:SourceDir = Join-Path $script:Sandbox.Path "source"
        $script:DestDir = Join-Path $script:Sandbox.Path "dest"
        New-Item -ItemType Directory -Path $script:SourceDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:DestDir -Force | Out-Null
    }
    
    AfterEach {
        if ($script:Sandbox -and $script:Sandbox.Path -and (Test-Path $script:Sandbox.Path)) {
            Remove-Item -Path $script:Sandbox.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Without -Overwrite (default skip behavior)" {
        It "skips processing when output already exists" {
            # Create a dummy MKV in source
            $sourceMkv = Join-Path $script:SourceDir "test.mkv"
            [System.IO.File]::WriteAllBytes($sourceMkv, [byte[]](0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00, 0x00, 0x00))
            
            # Pre-create output file (simulating previous run)
            $destMkv = Join-Path $script:DestDir "test.mkv"
            [System.IO.File]::WriteAllText($destMkv, "existing output")
            $originalContent = Get-Content -LiteralPath $destMkv -Raw
            
            # Run without -Overwrite
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Should report SKIP
            $result.StdOut | Should -Match "\[SKIP\]"
            
            # Output file should be unchanged
            $newContent = Get-Content -LiteralPath $destMkv -Raw
            $newContent | Should -Be $originalContent
        }
    }
    
    Context "With -Overwrite" {
        It "reprocesses file when output exists and -Overwrite is set" {
            # Create a dummy MKV in source (will be copied as "no audio")
            $sourceMkv = Join-Path $script:SourceDir "test.mkv"
            [System.IO.File]::WriteAllBytes($sourceMkv, [byte[]](0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00, 0x00, 0x00))
            
            # Pre-create output file with different content
            $destMkv = Join-Path $script:DestDir "test.mkv"
            [System.IO.File]::WriteAllText($destMkv, "old output content")
            $originalSize = (Get-Item $destMkv).Length
            
            # Run with -Overwrite
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                    Overwrite = $true
                } `
                -SandboxPath $script:Sandbox.Path
            
            # Should NOT report SKIP (should process the file)
            $result.StdOut | Should -Not -Match "\[SKIP\].*test\.mkv"
            
            # Output file should have been replaced (different size from original text)
            $newSize = (Get-Item $destMkv).Length
            $newSize | Should -Not -Be $originalSize
        }
        
        It "processes file normally on first run, skips on second, processes with -Overwrite on third" {
            # Create a dummy MKV in source
            $sourceMkv = Join-Path $script:SourceDir "sequence.mkv"
            [System.IO.File]::WriteAllBytes($sourceMkv, [byte[]](0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00, 0x00, 0x00))
            
            # First run: should process (COPY or ERROR, but not SKIP)
            $result1 = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            $result1.StdOut | Should -Not -Match "\[SKIP\].*sequence\.mkv"
            
            # Output should exist now
            $destMkv = Join-Path $script:DestDir "sequence.mkv"
            Test-Path $destMkv | Should -BeTrue
            
            # Second run without -Overwrite: should SKIP
            $result2 = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            $result2.StdOut | Should -Match "\[SKIP\].*sequence\.mkv"
            
            # Third run with -Overwrite: should process again
            $result3 = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                    Overwrite = $true
                } `
                -SandboxPath $script:Sandbox.Path
            
            $result3.StdOut | Should -Not -Match "\[SKIP\].*sequence\.mkv"
        }
    }
}

Describe "S95C Converter with real media" -Tag "OptionalTooling" {
    
    BeforeAll {
        # Skip entire describe block if ffmpeg/ffprobe not available
        $script:HasFFmpeg = Test-HasCommand -Name "ffmpeg"
        $script:HasFFprobe = Test-HasCommand -Name "ffprobe"
        
        # Check if DTS encoder (dca) is available
        $script:HasDTSEncoder = $false
        if ($script:HasFFmpeg) {
            $encoders = & ffmpeg -hide_banner -encoders 2>&1
            $script:HasDTSEncoder = $encoders -match "\bdca\b"
        }
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
                "-hide_banner", "-loglevel", "error", "-nostdin",
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
    
    Context "DTS to FLAC conversion" {
        It "converts DTS audio to FLAC, no DTS remains" {
            if (-not $script:HasDTSEncoder) {
                Set-ItResult -Skipped -Because "DTS encoder (dca) not available in ffmpeg build"
                return
            }
            
            # Generate a tiny test MKV with DTS audio
            $testMkv = Join-Path $script:SourceDir "dts-test.mkv"
            
            # Create 1-second video with DTS audio (dca encoder, requires -strict -2)
            $ffmpegArgs = @(
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "lavfi", "-i", "color=black:s=64x64:d=1",
                "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                "-t", "1",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a", "dca", "-b:a", "768k", "-strict", "-2",
                "-y", $testMkv
            )
            
            $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $script:Sandbox.Path "ffmpeg-create-dts.log")
            
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $testMkv)) {
                Set-ItResult -Skipped -Because "Failed to create DTS test MKV file"
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
            
            # Output file should exist and be non-zero
            $outputMkv = Join-Path $script:DestDir "dts-test.mkv"
            Test-Path $outputMkv | Should -BeTrue
            (Get-Item $outputMkv).Length | Should -BeGreaterThan 0
            
            # Probe output with JSON to verify codecs
            $probeJson = & ffprobe -hide_banner -loglevel error -print_format json -show_streams -select_streams a -i $outputMkv 2>&1
            $probe = $probeJson | ConvertFrom-Json
            
            # Assert: no DTS or TrueHD audio streams remain
            $audioCodecs = $probe.streams | ForEach-Object { $_.codec_name }
            $audioCodecs | ForEach-Object {
                $_ | Should -Not -Match "^dts"
                $_ | Should -Not -Be "truehd"
            }
            
            # Assert: at least one FLAC stream exists
            $hasFlac = $audioCodecs -contains "flac"
            $hasFlac | Should -BeTrue
            
            # Should indicate conversion happened
            $result.StdOut | Should -Match "\[CONVERT\]"
        }
    }
    
    Context "Mixed streams conversion" {
        It "AAC copied, DTS converted to FLAC" {
            if (-not $script:HasDTSEncoder) {
                Set-ItResult -Skipped -Because "DTS encoder (dca) not available in ffmpeg build"
                return
            }
            
            # Generate MKV with two audio streams: AAC + DTS
            $testMkv = Join-Path $script:SourceDir "mixed-audio.mkv"
            
            # Create 1-second video with AAC (stream 0) and DTS (stream 1) audio
            $ffmpegArgs = @(
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "lavfi", "-i", "color=black:s=64x64:d=1",
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                "-t", "1",
                "-map", "0:v", "-map", "1:a", "-map", "2:a",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a:0", "aac",
                "-c:a:1", "dca", "-b:a:1", "768k", "-strict", "-2",
                "-y", $testMkv
            )
            
            $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $script:Sandbox.Path "ffmpeg-create-mixed.log")
            
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $testMkv)) {
                Set-ItResult -Skipped -Because "Failed to create mixed audio test MKV file"
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
            
            # Output file should exist and be non-zero
            $outputMkv = Join-Path $script:DestDir "mixed-audio.mkv"
            Test-Path $outputMkv | Should -BeTrue
            (Get-Item $outputMkv).Length | Should -BeGreaterThan 0
            
            # Probe output with JSON to verify codecs
            $probeJson = & ffprobe -hide_banner -loglevel error -print_format json -show_streams -select_streams a -i $outputMkv 2>&1
            $probe = $probeJson | ConvertFrom-Json
            
            # Collect audio codecs (order-independent assertions)
            $audioCodecs = @($probe.streams | ForEach-Object { $_.codec_name })
            
            # Assert: no DTS or TrueHD audio streams remain
            $audioCodecs | ForEach-Object {
                $_ | Should -Not -Match "^dts"
                $_ | Should -Not -Be "truehd"
            }
            
            # Assert: should have exactly 2 audio streams
            $audioCodecs.Count | Should -Be 2
            
            # Assert: one stream is AAC (copied) and one is FLAC (converted from DTS)
            $hasAac = $audioCodecs -contains "aac"
            $hasFlac = $audioCodecs -contains "flac"
            $hasAac | Should -BeTrue -Because "AAC stream should be copied unchanged"
            $hasFlac | Should -BeTrue -Because "DTS stream should be converted to FLAC"
        }
    }
    
    Context "Progress file behavior" {
        It "creates progress file during DTS conversion and removes it after completion" {
            if (-not $script:HasDTSEncoder) {
                Set-ItResult -Skipped -Because "DTS encoder (dca) not available in ffmpeg build"
                return
            }
            
            # Generate a small test MKV with DTS audio (longer duration for progress visibility)
            $testMkv = Join-Path $script:SourceDir "progress-test.mkv"
            
            # Create 2-second video with DTS audio
            $ffmpegArgs = @(
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "lavfi", "-i", "color=black:s=64x64:d=2",
                "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                "-t", "2",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a", "dca", "-b:a", "768k", "-strict", "-2",
                "-y", $testMkv
            )
            
            $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $script:Sandbox.Path "ffmpeg-create-progress.log")
            
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $testMkv)) {
                Set-ItResult -Skipped -Because "Failed to create DTS test MKV file"
                return
            }
            
            $expectedProgressFile = Join-Path $script:DestDir "progress-test.mkv.progress.json"
            $progressFileObserved = $false
            
            # Start the converter as a background job so we can poll for progress file
            $converterJob = Start-Job -ScriptBlock {
                param($scriptPath, $sourceDir, $destDir)
                & $scriptPath -SourceRoot $sourceDir -DestRoot $destDir
            } -ArgumentList $script:ScriptPath, $script:SourceDir, $script:DestDir
            
            # Poll for progress file existence (up to 10 seconds)
            $pollStart = Get-Date
            while (((Get-Date) - $pollStart).TotalSeconds -lt 10) {
                if (Test-Path -LiteralPath $expectedProgressFile) {
                    $progressFileObserved = $true
                    # Try to read and validate content
                    try {
                        $content = Get-Content -LiteralPath $expectedProgressFile -Raw -ErrorAction SilentlyContinue
                        if ($content) {
                            $progress = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($progress -and $progress.state -eq "running") {
                                # Valid progress file observed
                                break
                            }
                        }
                    } catch {
                        # Ignore parse errors during polling
                    }
                }
                Start-Sleep -Milliseconds 200
            }
            
            # Wait for job to complete
            $converterJob | Wait-Job -Timeout 60 | Out-Null
            $converterJob | Remove-Job -Force -ErrorAction SilentlyContinue
            
            # Assert: progress file was observed during run
            $progressFileObserved | Should -BeTrue -Because "Progress file should appear during DTS conversion"
            
            # Assert: progress file is removed after completion
            Test-Path -LiteralPath $expectedProgressFile | Should -BeFalse -Because "Progress file should be cleaned up after completion"
            
            # Assert: no orphan progress files remain
            $orphanProgressFiles = Get-ChildItem -Path $script:DestDir -Filter "*.progress.json" -Recurse -ErrorAction SilentlyContinue
            $orphanProgressFiles | Should -BeNullOrEmpty -Because "No progress files should remain after run"
            
            # Assert: output file exists (conversion succeeded)
            $outputMkv = Join-Path $script:DestDir "progress-test.mkv"
            Test-Path $outputMkv | Should -BeTrue
        }
    }
    
    Context "Atomic temp file cleanup on failure" {
        It "cleans up temp files when ffprobe fails on corrupt input" {
            # The script copies files when ffprobe fails (no audio detected).
            # This test verifies that corrupt files don't leave temp files behind.
            # The script's temp file pattern is .tmp_*.mkv
            
            # Create a fake MKV file that will cause ffprobe to fail
            $fakeMkv = Join-Path $script:SourceDir "corrupt.mkv"
            # Write minimal bytes that look like MKV header but are invalid
            [System.IO.File]::WriteAllBytes($fakeMkv, [byte[]](0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00, 0x00, 0x00))
            
            # Run the converter
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # No temp files matching .tmp_*.mkv should remain in destination
            $tempFiles = Get-ChildItem -Path $script:DestDir -Filter ".tmp_*.mkv" -Recurse -ErrorAction SilentlyContinue
            $tempFiles | Should -BeNullOrEmpty
            
            # When ffprobe fails to detect audio, the script copies the file
            # (this is expected behavior - the file is treated as "no audio")
            # The key assertion is that no temp files are left behind
        }
        
        It "cleans up temp files when ffmpeg conversion fails" {
            if (-not $script:HasDTSEncoder) {
                Set-ItResult -Skipped -Because "DTS encoder (dca) not available in ffmpeg build"
                return
            }
            
            # Create a valid MKV with DTS audio, then corrupt it partially
            # so ffprobe succeeds but ffmpeg conversion fails
            $testMkv = Join-Path $script:SourceDir "partial-corrupt.mkv"
            
            # First create a valid DTS MKV
            $ffmpegArgs = @(
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "lavfi", "-i", "color=black:s=64x64:d=1",
                "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                "-t", "1",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a", "dca", "-b:a", "768k", "-strict", "-2",
                "-y", $testMkv
            )
            
            $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $script:Sandbox.Path "ffmpeg-create-partial.log")
            
            if ($proc.ExitCode -ne 0 -or -not (Test-Path $testMkv)) {
                Set-ItResult -Skipped -Because "Failed to create test MKV file"
                return
            }
            
            # Truncate the file to corrupt it (keep header intact so ffprobe works)
            $bytes = [System.IO.File]::ReadAllBytes($testMkv)
            $truncatedBytes = $bytes[0..([Math]::Min(2000, $bytes.Length - 1))]
            [System.IO.File]::WriteAllBytes($testMkv, $truncatedBytes)
            
            # Run the converter
            $result = Invoke-ToolScript `
                -ScriptPath $script:ScriptPath `
                -Arguments @{
                    SourceRoot = $script:SourceDir
                    DestRoot = $script:DestDir
                } `
                -SandboxPath $script:Sandbox.Path
            
            # No temp files matching .tmp_*.mkv should remain in destination
            $tempFiles = Get-ChildItem -Path $script:DestDir -Filter ".tmp_*.mkv" -Recurse -ErrorAction SilentlyContinue
            $tempFiles | Should -BeNullOrEmpty
            
            # Final output file should NOT exist (conversion failed)
            $outputMkv = Join-Path $script:DestDir "partial-corrupt.mkv"
            Test-Path $outputMkv | Should -BeFalse
            
            # Script should report failure
            $result.ExitCode | Should -Be 1
            $result.StdOut | Should -Match "\[ERROR\]"
        }
    }
}
