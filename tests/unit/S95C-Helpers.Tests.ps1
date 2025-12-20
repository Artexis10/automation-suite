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
        
        It "returns true for 'DTS' (uppercase)" {
            Test-UnsupportedCodec -CodecName "DTS" | Should -BeTrue
        }
        
        It "returns true for 'DTS-HD MA' (mixed case with spaces)" {
            Test-UnsupportedCodec -CodecName "  DTS-HD MA  " | Should -BeTrue
        }
    }
    
    Context "TrueHD" {
        It "returns true for 'truehd'" {
            Test-UnsupportedCodec -CodecName "truehd" | Should -BeTrue
        }
        
        It "returns true for 'TrueHD' (mixed case)" {
            Test-UnsupportedCodec -CodecName "TrueHD" | Should -BeTrue
        }
        
        It "returns true for 'TRUEHD' (uppercase)" {
            Test-UnsupportedCodec -CodecName "TRUEHD" | Should -BeTrue
        }
        
        It "returns true for ' truehd ' (with whitespace)" {
            Test-UnsupportedCodec -CodecName " truehd " | Should -BeTrue
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
        
        It "returns false for 'opus'" {
            Test-UnsupportedCodec -CodecName "opus" | Should -BeFalse
        }
    }
    
    Context "Edge cases" {
        It "returns false for empty string" {
            Test-UnsupportedCodec -CodecName "" | Should -BeFalse
        }
        
        It "returns false for whitespace only" {
            Test-UnsupportedCodec -CodecName "   " | Should -BeFalse
        }
        
        It "returns false for tab characters" {
            Test-UnsupportedCodec -CodecName "`t`t" | Should -BeFalse
        }
        
        It "returns false for null coerced to empty string" {
            Test-UnsupportedCodec -CodecName $null | Should -BeFalse
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
        
        It "computes correct destination for deeply nested file" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\Genre\Year\Studio\film.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "D:\Converted"
            
            $result.DestDir | Should -Be "D:\Converted\Genre\Year\Studio"
            $result.DestFile | Should -Be "D:\Converted\Genre\Year\Studio\film.mkv"
            $result.RelativePath | Should -Be "Genre\Year\Studio\film.mkv"
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
        
        It "handles trailing slashes in both roots" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\Sub\test.mkv" `
                -SourceRoot "C:\Movies\" `
                -DestRoot "C:\Output\"
            
            $result.DestDir | Should -Be "C:\Output\Sub"
            $result.DestFile | Should -Be "C:\Output\Sub\test.mkv"
        }
    }
    
    Context "Case handling" {
        It "preserves original case in relative path" {
            $result = Get-MirroredDestination `
                -SourceFilePath "C:\Movies\ACTION\Movie.MKV" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output"
            
            $result.RelativePath | Should -Be "ACTION\Movie.MKV"
            $result.DestFile | Should -Be "C:\Output\ACTION\Movie.MKV"
        }
    }
    
    Context "Path escape validation" {
        It "throws when source file is not under source root" {
            { Get-MirroredDestination `
                -SourceFilePath "C:\Other\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output" } | Should -Throw "*not under SourceRoot*"
        }
        
        It "throws when source file uses parent directory escape" {
            { Get-MirroredDestination `
                -SourceFilePath "C:\Movies\..\Other\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output" } | Should -Throw "*not under SourceRoot*"
        }
        
        It "throws for completely different drive" {
            { Get-MirroredDestination `
                -SourceFilePath "D:\Videos\test.mkv" `
                -SourceRoot "C:\Movies" `
                -DestRoot "C:\Output" } | Should -Throw "*not under SourceRoot*"
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
    Context "Single stream conversion" {
        It "generates correct args for DTS stream with per-stream compression" {
            $streams = @(
                @{ codec_name = "dts" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "flac"
            $codecArgs | Should -Contain "-compression_level:a:0"
            $codecArgs | Should -Contain "12"
        }
        
        It "generates copy args for supported stream" {
            $streams = @(
                @{ codec_name = "aac" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "copy"
            $codecArgs | Should -Not -Contain "-compression_level:a:0"
        }
        
        It "generates correct args for TrueHD stream" {
            $streams = @(
                @{ codec_name = "truehd" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "flac"
            $codecArgs | Should -Contain "-compression_level:a:0"
        }
    }
    
    Context "Mixed streams with correct indexing" {
        It "handles dts + aac + truehd with correct stream indices" {
            $streams = @(
                @{ codec_name = "dts" },
                @{ codec_name = "aac" },
                @{ codec_name = "truehd" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # Stream 0: DTS -> FLAC with per-stream compression
            $codecArgs | Should -Contain "-c:a:0"
            $codecArgs | Should -Contain "-compression_level:a:0"
            
            # Stream 1: AAC -> copy (no compression flag)
            $codecArgs | Should -Contain "-c:a:1"
            
            # Stream 2: TrueHD -> FLAC with per-stream compression
            $codecArgs | Should -Contain "-c:a:2"
            $codecArgs | Should -Contain "-compression_level:a:2"
        }
        
        It "verifies correct argument order for conversion" {
            $streams = @(
                @{ codec_name = "dts" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # Find indices
            $codecIndex = [array]::IndexOf($codecArgs, "-c:a:0")
            $flacIndex = [array]::IndexOf($codecArgs, "flac")
            $compressionIndex = [array]::IndexOf($codecArgs, "-compression_level:a:0")
            $levelIndex = [array]::IndexOf($codecArgs, "12")
            
            # Verify order: -c:a:0 flac -compression_level:a:0 12
            $codecIndex | Should -BeLessThan $flacIndex
            $flacIndex | Should -BeLessThan $compressionIndex
            $compressionIndex | Should -BeLessThan $levelIndex
        }
        
        It "verifies correct argument order for copy" {
            $streams = @(
                @{ codec_name = "aac" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # Find indices
            $codecIndex = [array]::IndexOf($codecArgs, "-c:a:0")
            $copyIndex = [array]::IndexOf($codecArgs, "copy")
            
            # Verify order: -c:a:0 copy
            $codecIndex | Should -BeLessThan $copyIndex
            ($copyIndex - $codecIndex) | Should -Be 1
        }
        
        It "generates exactly 4 args per converted stream and 2 per copied stream" {
            $streams = @(
                @{ codec_name = "dts" },
                @{ codec_name = "aac" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # DTS: 4 args (-c:a:0, flac, -compression_level:a:0, 12)
            # AAC: 2 args (-c:a:1, copy)
            # Total: 6 args
            $codecArgs.Count | Should -Be 6
        }
    }
    
    Context "Edge cases" {
        It "returns empty or null for no streams" {
            $codecArgs = Get-AudioCodecArgs -AudioStreams @()
            # In PS 5.1, empty array may return $null, so check both cases
            if ($null -eq $codecArgs) {
                $true | Should -BeTrue
            } else {
                $codecArgs.Count | Should -Be 0
            }
        }
        
        It "handles stream with null codec_name gracefully" {
            $streams = @(
                @{ codec_name = $null },
                @{ codec_name = "dts" }
            )
            $codecArgs = Get-AudioCodecArgs -AudioStreams $streams
            
            # Stream 0: null -> copy
            $codecArgs | Should -Contain "-c:a:0"
            # Stream 1: DTS -> FLAC
            $codecArgs | Should -Contain "-c:a:1"
            $codecArgs | Should -Contain "-compression_level:a:1"
        }
    }
}
