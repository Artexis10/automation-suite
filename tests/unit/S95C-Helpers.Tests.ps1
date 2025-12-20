<#
.SYNOPSIS
    Unit tests for S95C audio conversion helper functions.

.DESCRIPTION
    Tests pure functions in S95C-Helpers.ps1 without requiring ffmpeg/ffprobe.
#>

BeforeAll {
    # Load test helpers
    . (Join-Path $PSScriptRoot "..\TestHelpers.ps1")
    
    # Load the module under test
    $helpersPath = Join-Path (Get-RepoRoot) "media-tools\unsupported-audio-conversion-for-s95c\S95C-Helpers.ps1"
    . $helpersPath
}

Describe "Test-UnsupportedCodec" {
    Context "DTS variants" {
        It "returns true for 'dts'" {
            Test-UnsupportedCodec -CodecName "dts" | Should -BeTrue
        }
        
        It "returns true for 'dts_hd_ma'" {
            Test-UnsupportedCodec -CodecName "dts_hd_ma" | Should -BeTrue
        }
        
        It "returns true for 'dts-hd'" {
            Test-UnsupportedCodec -CodecName "dts-hd" | Should -BeTrue
        }
    }
    
    Context "TrueHD" {
        It "returns true for 'truehd'" {
            Test-UnsupportedCodec -CodecName "truehd" | Should -BeTrue
        }
    }
    
    Context "Supported codecs" {
        It "returns false for 'aac'" {
            Test-UnsupportedCodec -CodecName "aac" | Should -BeFalse
        }
        
        It "returns false for 'flac'" {
            Test-UnsupportedCodec -CodecName "flac" | Should -BeFalse
        }
        
        It "returns false for 'ac3'" {
            Test-UnsupportedCodec -CodecName "ac3" | Should -BeFalse
        }
        
        It "returns false for 'eac3'" {
            Test-UnsupportedCodec -CodecName "eac3" | Should -BeFalse
        }
        
        It "returns false for 'pcm_s16le'" {
            Test-UnsupportedCodec -CodecName "pcm_s16le" | Should -BeFalse
        }
    }
    
    Context "Edge cases" {
        It "returns false for empty string" {
            Test-UnsupportedCodec -CodecName "" | Should -BeFalse
        }
        
        It "returns false for whitespace" {
            Test-UnsupportedCodec -CodecName "   " | Should -BeFalse
        }
    }
}

Describe "Get-MirroredDestination" {
    Context "Top-level file" {
        It "computes correct destination for file in source root" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output"
            
            $result.DestDir | Should -Be "C:\Output"
            $result.DestFile | Should -Be "C:\Output\test.mkv"
            $result.RelativePath | Should -Be "test.mkv"
        }
    }
    
    Context "Nested file" {
        It "computes correct destination for file in subdirectory" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\Action\2024\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output"
            
            $result.DestDir | Should -Be "C:\Output\Action\2024"
            $result.DestFile | Should -Be "C:\Output\Action\2024\test.mkv"
            $result.RelativePath | Should -Be "Action\2024\test.mkv"
        }
    }
    
    Context "Path normalization" {
        It "handles trailing slashes in source root" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\test.mkv" `
                -SourceRoot "C:\Movies\" `
                -DestRoot "C:\Output"
            
            $result.DestFile | Should -Be "C:\Output\test.mkv"
        }
        
        It "handles trailing slashes in dest root" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output\"
            
            $result.DestFile | Should -Be "C:\Output\test.mkv"
        }
    }
}

Describe "Test-HasUnsupportedAudio" {
    Context "Streams with unsupported codecs" {
        It "returns true when DTS is present" {
            $streams = @(
                @{ codec_name = "aac" },
                @{ codec_name = "dts" }
            )
            Test-HasUnsupportedAudio -AudioStreams $streams | Should -BeTrue
        }
        
        It "returns true when TrueHD is present" {
            $streams = @(
                @{ codec_name = "truehd" },
                @{ codec_name = "ac3" }
            )
            Test-HasUnsupportedAudio -AudioStreams $streams | Should -BeTrue
        }
    }
    
    Context "Streams with only supported codecs" {
        It "returns false for AAC only" {
            $streams = @(
                @{ codec_name = "aac" }
            )
            Test-HasUnsupportedAudio -AudioStreams $streams | Should -BeFalse
        }
        
        It "returns false for mixed supported codecs" {
            $streams = @(
                @{ codec_name = "aac" },
                @{ codec_name = "ac3" },
                @{ codec_name = "flac" }
            )
            Test-HasUnsupportedAudio -AudioStreams $streams | Should -BeFalse
        }
    }
    
    Context "Edge cases" {
        It "returns false for empty array" {
            Test-HasUnsupportedAudio -AudioStreams @() | Should -BeFalse
        }
    }
}

Describe "Get-AudioCodecArgs" {
    Context "Mixed streams" {
        It "generates correct args for DTS stream" {
            $streams = @(
                @{ codec_name = "dts" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "flac"
            $codecArgs | Should -Contain "-compression_level"
            $codecArgs | Should -Contain "12"
        }
        
        It "generates copy args for supported stream" {
            $streams = @(
                @{ codec_name = "aac" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "copy"
        }
        
        It "handles multiple streams correctly" {
            $streams = @(
                @{ codec_name = "dts" },
                @{ codec_name = "aac" },
                @{ codec_name = "truehd" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # Stream 0: DTS -> FLAC
            $codecArgs | Should -Contain "-c:a:0"
            # Stream 1: AAC -> copy
            $codecArgs | Should -Contain "-c:a:1"
            # Stream 2: TrueHD -> FLAC
            $codecArgs | Should -Contain "-c:a:2"
        }
    }
    
    Context "Edge cases" {
        It "returns empty array for no streams" {
            $codecArgs = Get-AudioCodecArgs -AudioStreams @()
            # In PS 5.1, empty array may return $null, so check both cases
            if ($null -eq $codecArgs) {
                $true | Should -BeTrue
            } else {
                $codecArgs.Count | Should -Be 0
            }
        }
    }
}
