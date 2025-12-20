<#
.SYNOPSIS
Converts MKVs for Samsung S95C playback by converting unsupported audio codecs to FLAC.

.DESCRIPTION
This script processes MKV files and converts any DTS / DTS-HD / DTS-MA / Dolby TrueHD audio
to FLAC (lossless). All other streams (video, subtitles, chapters, other audio) are copied
unchanged. Output files are written to a separate destination while mirroring the source
directory structure.

.PARAMETER SourceRoot
The root directory containing MKV files to process. Defaults to current directory (.)

.PARAMETER DestRoot
The destination root directory where converted files will be saved. Defaults to .\S95C_Converted
The directory will be created if it doesn't exist.

.PARAMETER Recurse
If specified, recursively processes all subdirectories. Without this flag, only processes
MKV files in the top-level SourceRoot directory.

.PARAMETER MaxParallel
Maximum number of concurrent encoding jobs. Defaults to 2. Increase for faster processing
on multi-core systems, but be mindful of CPU and disk I/O load.

.EXAMPLE
# Convert MKVs in D:\Movies (top-level only, 2 parallel jobs)
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C"

.EXAMPLE
# Recursively convert all MKVs with 4 parallel jobs
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse -MaxParallel 4

.EXAMPLE
# Convert current directory recursively
.\Convert-Unsupported-Audio-for-S95C.ps1 -Recurse

.NOTES
Requires: ffmpeg and ffprobe (must be in PATH)
Output: Files are written to DestRoot with the same directory structure as SourceRoot
Status: [INFO], [SKIP], [WARN], [OK], [CONVERT], [ERROR], [QUEUE], [DONE]
#>

param(
    [string]$SourceRoot = ".",
    [string]$DestRoot   = ".\S95C_Converted",
    [switch]$Recurse,
    [int]$MaxParallel   = 2
)

# Resolve roots to full paths
$sourceResolved = Resolve-Path -LiteralPath $SourceRoot -ErrorAction SilentlyContinue
if (-not $sourceResolved) {
    Write-Host "[ERROR] Source path does not exist: $SourceRoot"
    return
}
$sourceRootFull = $sourceResolved.Path.TrimEnd("\","/")

$destResolved = Resolve-Path -LiteralPath $DestRoot -ErrorAction SilentlyContinue
if ($destResolved) {
    $destRootFull = $destResolved.Path.TrimEnd("\","/")
} else {
    $destRootFull = (New-Item -ItemType Directory -Path $DestRoot -Force).FullName.TrimEnd("\","/")
}

# Build Get-ChildItem args
$gciArgs = @{
    LiteralPath   = $sourceRootFull
    Filter = "*.mkv"
    File   = $true
}
if ($Recurse) {
    $gciArgs.Recurse = $true
}

# Force array so .Count works even with 1 item
$files = @(Get-ChildItem @gciArgs)

if (-not $files -or $files.Count -eq 0) {
    Write-Host "[INFO] No MKV files found under $sourceRootFull."
    return
}

$total     = $files.Count
$completed = 0
$skipped   = 0
$copied    = 0
$converted = 0
$failed    = 0
$jobs      = @()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "MKV S95C Converter" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Found $total MKV file(s) to process"
Write-Host ""
Write-Host "  Source:  $sourceRootFull"
Write-Host "  Dest:    $destRootFull"
Write-Host "  Recurse: $($Recurse.IsPresent)"
Write-Host "  Parallel jobs: $MaxParallel"
Write-Host "========================================`n" -ForegroundColor Cyan

# Resolve path to helpers (same directory as this script)
$helpersPath = Join-Path -Path $PSScriptRoot -ChildPath "S95C-Helpers.ps1"
if (-not (Test-Path -LiteralPath $helpersPath)) {
    Write-Host "[ERROR] S95C-Helpers.ps1 not found at: $helpersPath"
    return
}

# Worker scriptblock for background jobs
$worker = {
    param($in, $sourceRootFull, $destRootFull, $helpersPath)

    # Load helper functions inside job context
    . $helpersPath

    # Build result object helper
    function New-Result {
        param($Status, $RelativePath, $SourcePath, $DestPath, $Message)
        [PSCustomObject]@{
            Status       = $Status
            RelativePath = $RelativePath
            SourcePath   = $SourcePath
            DestPath     = $DestPath
            Message      = $Message
        }
    }

    # Use helper to compute mirrored destination
    $dest = Get-MirroredDestination -SourceFilePath $in -SourceRoot $sourceRootFull -DestRoot $destRootFull
    $relativePath = $dest.RelativePath
    $destDir = $dest.DestDir
    $out = $dest.DestFile

    # Ensure destination directory exists
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Check if destination already exists
    if (Test-Path -LiteralPath $out) {
        return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Already exists"
    }

    # Probe audio tracks
    $probeJson = & ffprobe -v error -print_format json -show_streams -select_streams a "$in" 2>$null
    $probe = $null
    if ($probeJson) {
        $probe = $probeJson | ConvertFrom-Json
    }

    # If no audio streams found, copy the file
    if (-not $probeJson -or -not $probe.streams) {
        if ($in -ieq $out) {
            return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Source equals destination"
        }
        Copy-Item -LiteralPath $in -Destination $out -Force
        return New-Result -Status "CopiedNoAudio" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "No audio streams"
    }

    # Use helper to check for unsupported audio
    $hasUnsupported = Test-HasUnsupportedAudio -AudioStreams $probe.streams

    # If nothing unsupported, just copy the file
    if (-not $hasUnsupported) {
        if ($in -ieq $out) {
            return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Source equals destination"
        }
        Copy-Item -LiteralPath $in -Destination $out -Force
        return New-Result -Status "CopiedCompatible" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Compatible audio"
    }

    # Use helper to build codec args
    $codecArgs = Get-AudioCodecArgs -AudioStreams $probe.streams

    # Run ffmpeg conversion
    & ffmpeg -i "$in" -map 0 -map_chapters 0 -c:v copy -c:s copy @codecArgs "$out" 2>$null

    if ($LASTEXITCODE -ne 0) {
        return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "ffmpeg failed"
    }

    # Quick verification: ensure no DTS/TrueHD in the output
    $check = & ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nw=1:nk=1 "$out" 2>$null

    if ($check -match "^dts" -or $check -match "^truehd") {
        return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Unsupported audio still present"
    }

    return New-Result -Status "Converted" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "DTS/TrueHD to FLAC"
}

# Helper to process job result and update counters
function Process-JobResult {
    param($result)
    
    if ($null -eq $result) {
        return @{ skipped = 0; copied = 0; converted = 0; failed = 1 }
    }
    
    switch ($result.Status) {
        "SkippedExists" {
            Write-Host "[SKIP] $($result.RelativePath): $($result.Message)"
            return @{ skipped = 1; copied = 0; converted = 0; failed = 0 }
        }
        "CopiedNoAudio" {
            Write-Host "[OK] Copied (no audio): $($result.RelativePath)"
            return @{ skipped = 0; copied = 1; converted = 0; failed = 0 }
        }
        "CopiedCompatible" {
            Write-Host "[OK] Copied (compatible): $($result.RelativePath)"
            return @{ skipped = 0; copied = 1; converted = 0; failed = 0 }
        }
        "Converted" {
            Write-Host "[CONVERT] $($result.RelativePath): $($result.Message)" -ForegroundColor Green
            return @{ skipped = 0; copied = 0; converted = 1; failed = 0 }
        }
        "Failed" {
            Write-Host "[ERROR] $($result.RelativePath): $($result.Message)" -ForegroundColor Red
            return @{ skipped = 0; copied = 0; converted = 0; failed = 1 }
        }
        default {
            Write-Host "[WARN] Unknown status for $($result.RelativePath)"
            return @{ skipped = 0; copied = 0; converted = 0; failed = 1 }
        }
    }
}

# Queue and manage jobs with throttling and progress
foreach ($file in $files) {

    while ($jobs.Count -ge $MaxParallel) {
        $finished = Wait-Job -Job $jobs -Any -Timeout 2
        if ($finished) {
            $result = Receive-Job $finished
            $counts = Process-JobResult -result $result
            $skipped += $counts.skipped
            $copied += $counts.copied
            $converted += $counts.converted
            $failed += $counts.failed
            Remove-Job $finished
            $jobs = $jobs | Where-Object { $_.Id -ne $finished.Id }
            $completed++
            $percent = [int](($completed / [double]$total) * 100)
            Write-Progress -Activity "Converting MKVs for S95C" `
                           -Status "$completed of $total file(s) done" `
                           -PercentComplete $percent
        }
    }

    $relativePath = $file.FullName.Substring($sourceRootFull.Length) -replace "^[\\/]+",""
    Write-Host "[QUEUE] $relativePath"

    $job = Start-Job -ScriptBlock $worker -ArgumentList $file.FullName, $sourceRootFull, $destRootFull, $helpersPath
    $jobs += $job
}

# Drain remaining jobs
while ($jobs.Count -gt 0) {
    $finished = Wait-Job -Job $jobs -Any -Timeout 2
    if ($finished) {
        $result = Receive-Job $finished
        $counts = Process-JobResult -result $result
        $skipped += $counts.skipped
        $copied += $counts.copied
        $converted += $counts.converted
        $failed += $counts.failed
        Remove-Job $finished
        $jobs = $jobs | Where-Object { $_.Id -ne $finished.Id }
        $completed++
        $percent = [int](($completed / [double]$total) * 100)
        Write-Progress -Activity "Converting MKVs" `
                       -Status "$completed of $total file(s) done" `
                       -PercentComplete $percent
    }
}

Write-Progress -Activity "Converting MKVs" -Completed

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Conversion Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total files processed: $completed of $total"
Write-Host "  - Skipped:    $skipped"
Write-Host "  - Copied:     $copied"
Write-Host "  - Converted:  $converted"
Write-Host "  - Failed:     $failed"
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Output location: $destRootFull" -ForegroundColor Green
