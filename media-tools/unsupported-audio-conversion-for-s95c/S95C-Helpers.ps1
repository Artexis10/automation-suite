<#
.SYNOPSIS
    Helper functions for S95C audio conversion.

.DESCRIPTION
    Pure functions extracted for testability. These functions contain the core logic
    for codec detection and path computation without side effects.
#>

<#
.SYNOPSIS
    Tests if a codec name represents an unsupported audio codec for S95C.

.PARAMETER CodecName
    The codec name from ffprobe (e.g., "dts", "truehd", "aac", "flac").

.OUTPUTS
    Boolean - True if the codec is unsupported (DTS variants or TrueHD).
#>
function Test-UnsupportedCodec {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CodecName
    )
    
    if ([string]::IsNullOrWhiteSpace($CodecName)) {
        return $false
    }
    
    # Normalize: trim whitespace and lowercase
    $normalized = $CodecName.Trim().ToLowerInvariant()
    
    # DTS variants: dts, dts-hd, dts_hd_ma, etc.
    # TrueHD: truehd
    return ($normalized -like "dts*" -or $normalized -eq "truehd")
}

<#
.SYNOPSIS
    Computes the destination path for a file, mirroring source structure.

.PARAMETER SourceFilePath
    Full path to the source file.

.PARAMETER SourceRoot
    Root directory of the source tree.

.PARAMETER DestRoot
    Root directory of the destination tree.

.OUTPUTS
    Hashtable with:
    - DestDir: Destination directory path
    - DestFile: Full destination file path
    - RelativePath: Relative path from source root
#>
function Get-MirroredDestination {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        
        [Parameter(Mandatory = $true)]
        [string]$DestRoot
    )
    
    # Normalize paths: trim trailing slashes and normalize separators
    $sourceRootNorm = $SourceRoot.TrimEnd("\", "/").Replace("/", "\")
    $destRootNorm = $DestRoot.TrimEnd("\", "/").Replace("/", "\")
    $sourceFileNorm = $SourceFilePath.TrimEnd("\", "/").Replace("/", "\")
    
    # Validate: source file must start with source root (case-insensitive on Windows)
    if (-not $sourceFileNorm.StartsWith($sourceRootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "SourceFilePath '$SourceFilePath' is not under SourceRoot '$SourceRoot'"
    }
    
    # Compute relative path by removing source root prefix
    $relativePath = $sourceFileNorm.Substring($sourceRootNorm.Length).TrimStart("\", "/")
    
    # Additional validation: reject if relative path is empty (file IS the root) or contains ..
    if ([string]::IsNullOrEmpty($relativePath)) {
        throw "SourceFilePath '$SourceFilePath' is not under SourceRoot '$SourceRoot'"
    }
    if ($relativePath.Contains("..")) {
        throw "SourceFilePath '$SourceFilePath' is not under SourceRoot '$SourceRoot'"
    }
    
    $fileName = Split-Path -Path $sourceFileNorm -Leaf
    $relDir = Split-Path -Path $relativePath -Parent
    
    # Compute destination directory
    if ([string]::IsNullOrEmpty($relDir)) {
        $destDir = $destRootNorm
    } else {
        $destDir = Join-Path -Path $destRootNorm -ChildPath $relDir
    }
    
    # Compute full destination path
    $destFile = Join-Path -Path $destDir -ChildPath $fileName
    
    return @{
        DestDir = $destDir
        DestFile = $destFile
        RelativePath = $relativePath
    }
}

<#
.SYNOPSIS
    Builds ffmpeg codec arguments for audio stream conversion.

.PARAMETER AudioStreams
    Array of audio stream objects from ffprobe (must have codec_name property).

.OUTPUTS
    Array of ffmpeg arguments for audio codec handling.
#>
function Get-AudioCodecArgs {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AudioStreams
    )
    
    $codecArgs = @()
    
    for ($i = 0; $i -lt $AudioStreams.Count; $i++) {
        $codec = $AudioStreams[$i].codec_name
        
        if (Test-UnsupportedCodec -CodecName $codec) {
            # Convert DTS/TrueHD to FLAC with per-stream compression
            $codecArgs += @("-c:a:$i", "flac", "-compression_level:a:$i", "12")
        } else {
            # Copy all other audio streams
            $codecArgs += @("-c:a:$i", "copy")
        }
    }
    
    return $codecArgs
}

<#
.SYNOPSIS
    Determines if any audio streams contain unsupported codecs.

.PARAMETER AudioStreams
    Array of audio stream objects from ffprobe.

.OUTPUTS
    Boolean - True if any stream has an unsupported codec.
#>
function Test-HasUnsupportedAudio {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AudioStreams
    )
    
    foreach ($stream in $AudioStreams) {
        if (Test-UnsupportedCodec -CodecName $stream.codec_name) {
            return $true
        }
    }
    
    return $false
}
