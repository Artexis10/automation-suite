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

# Worker scriptblock for background jobs
$worker = {
    param($in, $sourceRootFull, $destRootFull)

    $name = Split-Path -Path $in -Leaf

    # Compute relative path under source root
    $relativePath = $in.Substring($sourceRootFull.Length) -replace "^[\\/]+",""
    $relDir       = Split-Path -Path $relativePath -Parent

    if ([string]::IsNullOrEmpty($relDir)) {
        $destDir = $destRootFull
    } else {
        $destDir = Join-Path -Path $destRootFull -ChildPath $relDir
    }

    # Ensure destination directory exists
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Keep same file name in the mirrored tree
    $out = Join-Path -Path $destDir -ChildPath $name

    if (Test-Path -LiteralPath $out) {
        Write-Host "[SKIP] Already exists: $relativePath"
        return
    }

    # Probe audio tracks
    $probeJson = & ffprobe -v error -print_format json -show_streams -select_streams a "$in" 2>$null
    $probe = $null
    if ($probeJson) {
        $probe = $probeJson | ConvertFrom-Json
    }

    # If no audio streams found, still copy the file to destination
    if (-not $probeJson -or -not $probe.streams) {
        Write-Host "[INFO] No audio streams in $relativePath, copying as-is"

        if ($in -ieq $out) {
            Write-Host "[SKIP] Source and destination are the same, skipping copy: $relativePath"
            return
        }

        Copy-Item -LiteralPath $in -Destination $out -Force
        Write-Host "[OK] Copied (no audio): $relativePath"
        return
    }

    # Detect DTS or TrueHD audio
    $hasUnsupported = $probe.streams | Where-Object {
        $_.codec_name -match "^dts" -or $_.codec_name -eq "truehd"
    }

    # If nothing unsupported, just copy the file over
    if (-not $hasUnsupported) {
        Write-Host "[SKIP] No DTS/TrueHD found, copying: $relativePath"

        # Guard against accidental in-place overwrite if SourceRoot equals DestRoot
        if ($in -ieq $out) {
            Write-Host "[SKIP] Source and destination are the same, skipping copy: $relativePath"
            return
        }

        Copy-Item -LiteralPath $in -Destination $out -Force
        Write-Host "[OK] Copied (compatible): $relativePath"
        return
    }

    # Build per-track codec args for audio only
    $codecArgs = @()
    for ($i = 0; $i -lt $probe.streams.Count; $i++) {
        $codec = $probe.streams[$i].codec_name

        if ($codec -match "^dts" -or $codec -eq "truehd") {
            # Convert DTS/TrueHD to FLAC
            $codecArgs += @("-c:a:$i", "flac", "-compression_level", "12")
        } else {
            # Copy all other audio streams
            $codecArgs += @("-c:a:$i", "copy")
        }
    }

    Write-Host "[CONVERT] Converting DTS/TrueHD to FLAC: $relativePath"

    & ffmpeg -i "$in" -map 0 -map_chapters 0 -c:v copy -c:s copy @codecArgs "$out"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[ERROR] ffmpeg failed on: $relativePath"
        return
    }

    # Quick verification: ensure no DTS/TrueHD in the output
    $check = & ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nw=1:nk=1 "$out" 2>$null

    if ($check -match "^dts" -or $check -match "^truehd") {
        Write-Warning "[WARN] Unsupported audio still present in $out (unexpected) for $relativePath."
    } else {
        Write-Host "[OK] Done (converted): $relativePath"
    }
}

# Queue and manage jobs with throttling and progress
foreach ($file in $files) {

    while ($jobs.Count -ge $MaxParallel) {
        $finished = Wait-Job -Job $jobs -Any -Timeout 2
        if ($finished) {
            Receive-Job $finished | Write-Host
            $jobs = $jobs | Where-Object { $_.Id -ne $finished.Id }
            $completed++
            $percent = [int](($completed / [double]$total) * 100)
            Write-Progress -Activity "Converting MKVs for S95C" `
                           -Status "$completed of $total file(s) done" `
                           -PercentComplete $percent
        }
    }

    $relativePath = $file.FullName.Substring($sourceRootFull.Length) -replace "^[\\/]+",""
    Write-Host "[QUEUE] Queueing: $relativePath"

    $job = Start-Job -ScriptBlock $worker -ArgumentList $file.FullName, $sourceRootFull, $destRootFull
    $jobs += $job
}

# Drain remaining jobs
while ($jobs.Count -gt 0) {
    $finished = Wait-Job -Job $jobs -Any -Timeout 2
    if ($finished) {
        Receive-Job $finished | Write-Host
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
Write-Host "  - Converted:  (see details above)"
Write-Host "  - Skipped:    (already exist or no DTS/TrueHD)"
Write-Host "  - Warnings:   (check output for details)"
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Output location: $destRootFull" -ForegroundColor Green
