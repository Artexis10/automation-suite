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

.PARAMETER Overwrite
If specified, reprocesses files even if the output already exists. By default, existing
output files are skipped. Uses atomic temp-file writes for safety.

.PARAMETER Quiet
If specified, suppresses per-file success output (COPY/CONVERT/SKIP lines). Error lines
and the final summary are still printed.

.PARAMETER LogPath
Optional path to a JSONL log file. If provided, appends one JSON line per completed file
with fields: timestampUtc, status, relativePath, sourcePath, destPath, durationSec, message.
The directory will be created if it doesn't exist.

.EXAMPLE
# Convert MKVs in D:\Movies (top-level only, 2 parallel jobs)
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C"

.EXAMPLE
# Recursively convert all MKVs with 4 parallel jobs
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse -MaxParallel 4

.EXAMPLE
# Convert current directory recursively
.\Convert-Unsupported-Audio-for-S95C.ps1 -Recurse

.EXAMPLE
# Reprocess all files, overwriting existing outputs
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Overwrite

.EXAMPLE
# Quiet mode with logging
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Quiet -LogPath "C:\Logs\s95c.jsonl"

.NOTES
Requires: ffmpeg and ffprobe (must be in PATH)
Output: Files are written to DestRoot with the same directory structure as SourceRoot
Status: [CONVERT], [COPY], [SKIP], [ERROR]
#>

param(
    [string]$SourceRoot = ".",
    [string]$DestRoot   = ".\S95C_Converted",
    [switch]$Recurse,
    [ValidateRange(1, 64)]
    [int]$MaxParallel   = 2,
    [switch]$Overwrite,
    [switch]$Quiet,
    [string]$LogPath
)

# Resolve roots to full paths
$sourceResolved = Resolve-Path -LiteralPath $SourceRoot -ErrorAction SilentlyContinue
if (-not $sourceResolved) {
    Write-Host "[ERROR] Source path does not exist: $SourceRoot" -ForegroundColor Red
    exit 1
}
$sourceRootFull = $sourceResolved.Path.TrimEnd("\","/")

$destResolved = Resolve-Path -LiteralPath $DestRoot -ErrorAction SilentlyContinue
if ($destResolved) {
    $destRootFull = $destResolved.Path.TrimEnd("\","/")
} else {
    $destRootFull = (New-Item -ItemType Directory -Path $DestRoot -Force).FullName.TrimEnd("\","/")
}

# Validate: DestRoot must not equal SourceRoot
if ($sourceRootFull -ieq $destRootFull) {
    Write-Host "[ERROR] DestRoot cannot be the same as SourceRoot: $destRootFull" -ForegroundColor Red
    exit 1
}

# Validate: When -Recurse, DestRoot must not be inside SourceRoot (would cause infinite loop)
if ($Recurse) {
    $destNorm = $destRootFull.Replace("/", "\").TrimEnd("\")
    $srcNorm = $sourceRootFull.Replace("/", "\").TrimEnd("\")
    if ($destNorm.StartsWith($srcNorm + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "[ERROR] DestRoot '$destRootFull' is inside SourceRoot '$sourceRootFull'. This would cause infinite recursion." -ForegroundColor Red
        exit 1
    }
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
$jobStartTimes = @{}
$durations = [System.Collections.ArrayList]::new()
$running   = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "MKV S95C Converter" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Found $total MKV file(s) to process"
Write-Host ""
Write-Host "  Source:    $sourceRootFull"
Write-Host "  Dest:      $destRootFull"
Write-Host "  Recurse:   $($Recurse.IsPresent)"
Write-Host "  Parallel:  $MaxParallel"
Write-Host "  Overwrite: $($Overwrite.IsPresent)"
Write-Host "  Quiet:     $($Quiet.IsPresent)"
if ($LogPath) {
    Write-Host "  LogPath:   $LogPath"
}
Write-Host "========================================`n" -ForegroundColor Cyan

# Prepare log file if specified
$logFileReady = $false
if ($LogPath) {
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFileReady = $true
    } catch {
        Write-Host "[WARN] Could not create log directory: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Helper to write JSONL log entry (called from parent process only)
function Write-LogEntry {
    param($Entry)
    if (-not $logFileReady -or -not $LogPath) { return }
    try {
        $json = $Entry | ConvertTo-Json -Compress
        Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
    } catch {
        Write-Host "[WARN] Log write failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Helper to format duration as hh:mm:ss
function Format-Duration {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds
}

# Resolve path to helpers (same directory as this script)
$helpersPath = Join-Path -Path $PSScriptRoot -ChildPath "S95C-Helpers.ps1"
if (-not (Test-Path -LiteralPath $helpersPath)) {
    Write-Host "[ERROR] S95C-Helpers.ps1 not found at: $helpersPath" -ForegroundColor Red
    exit 1
}

# Worker scriptblock for background jobs
$worker = {
    param($in, $sourceRootFull, $destRootFull, $helpersPath, $forceOverwrite)

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

    # Check if destination already exists (skip unless -Overwrite)
    if ((Test-Path -LiteralPath $out) -and -not $forceOverwrite) {
        return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "output exists"
    }

    # Probe audio tracks with safe path handling
    $probeJson = $null
    $probe = $null
    try {
        $probeJson = & ffprobe -hide_banner -loglevel error -print_format json -show_streams -select_streams a -i "$in" 2>&1
        if ($LASTEXITCODE -eq 0 -and $probeJson) {
            $probe = $probeJson | ConvertFrom-Json -ErrorAction Stop
        }
    } catch {
        return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "ffprobe JSON parse failed: $($_.Exception.Message)"
    }

    # If no audio streams found, copy the file (atomic)
    if (-not $probe -or -not $probe.streams) {
        if ($in -ieq $out) {
            return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "source equals destination"
        }
        # Atomic copy: write to temp then move
        $tempCopy = Join-Path -Path $destDir -ChildPath (".tmp_" + [System.Guid]::NewGuid().ToString("N") + ".mkv")
        try {
            Copy-Item -LiteralPath $in -Destination $tempCopy -Force
            Move-Item -LiteralPath $tempCopy -Destination $out -Force
        } catch {
            if (Test-Path -LiteralPath $tempCopy) {
                Remove-Item -LiteralPath $tempCopy -Force -ErrorAction SilentlyContinue
            }
            return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Copy failed: $($_.Exception.Message)"
        }
        return New-Result -Status "CopiedNoAudio" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "no audio streams"
    }

    # Use helper to check for unsupported audio
    $hasUnsupported = Test-HasUnsupportedAudio -AudioStreams $probe.streams

    # If nothing unsupported, just copy the file (atomic)
    if (-not $hasUnsupported) {
        if ($in -ieq $out) {
            return New-Result -Status "SkippedExists" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "source equals destination"
        }
        # Atomic copy: write to temp then move
        $tempCopy = Join-Path -Path $destDir -ChildPath (".tmp_" + [System.Guid]::NewGuid().ToString("N") + ".mkv")
        try {
            Copy-Item -LiteralPath $in -Destination $tempCopy -Force
            Move-Item -LiteralPath $tempCopy -Destination $out -Force
        } catch {
            if (Test-Path -LiteralPath $tempCopy) {
                Remove-Item -LiteralPath $tempCopy -Force -ErrorAction SilentlyContinue
            }
            return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Copy failed: $($_.Exception.Message)"
        }
        return New-Result -Status "CopiedCompatible" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "compatible audio"
    }

    # Use helper to build codec args
    $codecArgs = Get-AudioCodecArgs -AudioStreams $probe.streams

    # Atomic output: write to temp file first, then rename on success
    $tempFile = Join-Path -Path $destDir -ChildPath (".tmp_" + [System.Guid]::NewGuid().ToString("N") + ".mkv")

    try {
        # Run ffmpeg conversion with safer flags
        & ffmpeg -hide_banner -loglevel error -nostdin -i "$in" -map 0 -map_chapters 0 -c:v copy -c:s copy @codecArgs "$tempFile" 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            # Clean up temp file on failure
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
            return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "ffmpeg failed (exit code: $LASTEXITCODE)"
        }

        # Quick verification: ensure no DTS/TrueHD in the output
        $check = & ffprobe -hide_banner -loglevel error -select_streams a -show_entries stream=codec_name -of default=nw=1:nk=1 -i "$tempFile" 2>&1

        if ($check -match "dts" -or $check -match "truehd") {
            # Clean up temp file on verification failure
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
            return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Unsupported audio still present after conversion"
        }

        # Atomic rename: move temp file to final destination
        Move-Item -LiteralPath $tempFile -Destination $out -Force

        return New-Result -Status "Converted" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "DTS/TrueHD -> FLAC"
    } catch {
        # Clean up temp file on any error
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        return New-Result -Status "Failed" -RelativePath $relativePath -SourcePath $in -DestPath $out -Message "Unexpected error: $($_.Exception.Message)"
    }
}

# Helper to process job result, update counters, and output
function Process-JobResult {
    param($result, $durationSec, $quietMode)
    
    $counts = @{ skipped = 0; copied = 0; converted = 0; failed = 0 }
    $logStatus = "unknown"
    $logMessage = ""
    
    if ($null -eq $result) {
        $counts.failed = 1
        $logStatus = "error"
        $logMessage = "null result"
        Write-Host "[ERROR]   <unknown> - null result from job" -ForegroundColor Red
    } else {
        $durStr = if ($durationSec -ge 0) { "({0:N1}s)" -f $durationSec } else { "" }
        
        switch ($result.Status) {
            "SkippedExists" {
                $counts.skipped = 1
                $logStatus = "skip"
                $logMessage = $result.Message
                if (-not $quietMode) {
                    Write-Host "[SKIP]    $($result.RelativePath) - $($result.Message)"
                }
            }
            "CopiedNoAudio" {
                $counts.copied = 1
                $logStatus = "copy"
                $logMessage = $result.Message
                if (-not $quietMode) {
                    Write-Host "[COPY]    $($result.RelativePath) $durStr - $($result.Message)"
                }
            }
            "CopiedCompatible" {
                $counts.copied = 1
                $logStatus = "copy"
                $logMessage = $result.Message
                if (-not $quietMode) {
                    Write-Host "[COPY]    $($result.RelativePath) $durStr - $($result.Message)"
                }
            }
            "Converted" {
                $counts.converted = 1
                $logStatus = "convert"
                $logMessage = $result.Message
                if (-not $quietMode) {
                    Write-Host "[CONVERT] $($result.RelativePath) $durStr - $($result.Message)" -ForegroundColor Green
                }
            }
            "Failed" {
                $counts.failed = 1
                $logStatus = "error"
                $logMessage = $result.Message
                # Always print errors even in quiet mode
                Write-Host "[ERROR]   $($result.RelativePath) - $($result.Message)" -ForegroundColor Red
            }
            default {
                $counts.failed = 1
                $logStatus = "error"
                $logMessage = "Unknown status: $($result.Status)"
                Write-Host "[ERROR]   $($result.RelativePath) - unknown status" -ForegroundColor Red
            }
        }
    }
    
    # Return counts plus log info
    return @{
        skipped = $counts.skipped
        copied = $counts.copied
        converted = $counts.converted
        failed = $counts.failed
        logStatus = $logStatus
        logMessage = $logMessage
    }
}

# Load helpers for Get-MirroredDestination (used for consistent [QUEUE] path display)
. $helpersPath

# Helper to handle completed job
function Complete-Job {
    param($finishedJob)
    
    $result = Receive-Job $finishedJob
    
    # Compute duration from start time
    $durationSec = -1
    if ($jobStartTimes.ContainsKey($finishedJob.Id)) {
        $startTime = $jobStartTimes[$finishedJob.Id]
        $durationSec = ((Get-Date) - $startTime).TotalSeconds
        $jobStartTimes.Remove($finishedJob.Id)
        [void]$durations.Add($durationSec)
    }
    
    $counts = Process-JobResult -result $result -durationSec $durationSec -quietMode $Quiet.IsPresent
    
    $script:skipped += $counts.skipped
    $script:copied += $counts.copied
    $script:converted += $counts.converted
    $script:failed += $counts.failed
    $script:running--
    $script:completed++
    
    # Write log entry if logging enabled
    if ($logFileReady -and $result) {
        $logEntry = @{
            timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
            status       = $counts.logStatus
            relativePath = $result.RelativePath
            sourcePath   = $result.SourcePath
            destPath     = $result.DestPath
            durationSec  = [Math]::Round($durationSec, 2)
            message      = $counts.logMessage
        }
        Write-LogEntry -Entry $logEntry
    }
    
    Remove-Job $finishedJob
    $script:jobs = @($script:jobs | Where-Object { $_.Id -ne $finishedJob.Id })
}

# Helper to update progress bar
function Update-ProgressBar {
    $percent = if ($total -gt 0) { [int](($completed / [double]$total) * 100) } else { 0 }
    
    # Compute average duration and ETA
    $avgSec = 0
    $etaStr = "--:--:--"
    if ($durations.Count -gt 0) {
        $avgSec = ($durations | Measure-Object -Average).Average
        $remaining = $total - $completed
        $etaSec = $avgSec * $remaining
        $etaStr = Format-Duration -Seconds $etaSec
    }
    
    $statusLine = "$completed/$total done | running $running | skip $skipped | copy $copied | conv $converted | fail $failed | avg {0:N1}s | ETA $etaStr" -f $avgSec
    
    Write-Progress -Activity "Converting MKVs for S95C" `
                   -Status $statusLine `
                   -PercentComplete $percent
}

# Queue and manage jobs with throttling and progress
foreach ($file in $files) {

    while ($jobs.Count -ge $MaxParallel) {
        $finished = Wait-Job -Job $jobs -Any -Timeout 2
        if ($finished) {
            Complete-Job -finishedJob $finished
            Update-ProgressBar
        }
    }

    # Start new job
    $job = Start-Job -ScriptBlock $worker -ArgumentList $file.FullName, $sourceRootFull, $destRootFull, $helpersPath, $Overwrite.IsPresent
    $jobs += $job
    $jobStartTimes[$job.Id] = Get-Date
    $running++
    
    Update-ProgressBar
}

# Drain remaining jobs
while ($jobs.Count -gt 0) {
    $finished = Wait-Job -Job $jobs -Any -Timeout 2
    if ($finished) {
        Complete-Job -finishedJob $finished
        Update-ProgressBar
    }
}

Write-Progress -Activity "Converting MKVs for S95C" -Completed

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

# Exit with non-zero code if any failures occurred (for automation detection)
if ($failed -gt 0) {
    exit 1
}
