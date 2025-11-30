# MKV S95C Converter - Usage Guide

## Overview

This PowerShell script converts MKV files for Samsung S95C playback by converting unsupported audio codecs to FLAC format.

**What it does:**
- Converts DTS / DTS-HD / DTS-MA / Dolby TrueHD audio → FLAC (lossless)
- Copies all other streams unchanged (video, subtitles, chapters, other audio)
- Outputs to a separate destination while mirroring source directory structure
- Supports parallel encoding for faster processing

## Requirements

- **PowerShell 5.0+** (Windows 10/11)
- **ffmpeg** and **ffprobe** installed and in your system PATH
  - Download from: https://ffmpeg.org/download.html
  - Or install via: `choco install ffmpeg` (if using Chocolatey)

## Quick Start

### Basic Usage (Current Directory)
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1
```
Processes MKV files in the current directory (top-level only) and outputs to `.\S95C_Converted`

### Convert Specific Folder
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C"
```
Processes all MKV files in `D:\Movies` and saves to `D:\Movies_S95C`

### Recursive Processing (All Subdirectories)
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse
```
Processes all MKV files in `D:\Movies` and all subdirectories

### Parallel Processing (Faster)
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse -MaxParallel 4
```
Processes 4 files simultaneously (adjust based on your CPU cores)

## Parameters

### -SourceRoot
- **Description:** Root directory containing MKV files to process
- **Default:** `.` (current directory)
- **Example:** `"D:\Movies"` or `"C:\Videos\[2024]"`

### -DestRoot
- **Description:** Destination directory where converted files will be saved
- **Default:** `.\S95C_Converted`
- **Note:** Directory will be created if it doesn't exist
- **Example:** `"D:\Movies_S95C"`

### -Recurse
- **Description:** Recursively process all subdirectories
- **Default:** Not set (top-level only)
- **Usage:** Add `-Recurse` flag to enable

### -MaxParallel
- **Description:** Maximum number of concurrent encoding jobs
- **Default:** `2`
- **Recommended:** 
  - 2-4 for general use
  - 4-8 for high-end systems
  - Adjust based on CPU cores and available disk I/O
- **Example:** `-MaxParallel 4`

## Output Status Indicators

During processing, you'll see status messages:

| Status | Meaning |
|--------|---------|
| `[QUEUE]` | File queued for processing |
| `[CONVERT]` | Converting DTS/TrueHD to FLAC |
| `[OK]` | Successfully processed |
| `[SKIP]` | Skipped (already exists or no conversion needed) |
| `[WARN]` | Warning (check details) |
| `[ERROR]` | Error occurred |
| `[INFO]` | Information message |

## Examples

### Example 1: Convert a Movie Collection
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\Movies" -DestRoot "E:\Movies_S95C" -Recurse -MaxParallel 3
```
- Processes all MKV files in `E:\Movies` and subdirectories
- Runs 3 conversions simultaneously
- Saves output to `E:\Movies_S95C` with same directory structure

### Example 2: Convert Single Folder (No Recursion)
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies\Action" -DestRoot "D:\Movies_S95C\Action"
```
- Only processes MKV files directly in `D:\Movies\Action`
- Ignores subdirectories

### Example 3: Test Run (Current Directory)
```powershell
.\Convert-Unsupported-Audio-for-S95C.ps1
```
- Processes current directory
- Output goes to `.\S95C_Converted`

## Directory Structure

The script mirrors your source directory structure in the destination:

**Source:**
```
D:\Movies\
├── Action/
│   ├── Movie1.mkv
│   └── Movie2.mkv
└── Drama/
    └── Movie3.mkv
```

**Output (with -Recurse):**
```
D:\Movies_S95C\
├── Action/
│   ├── Movie1.mkv (converted)
│   └── Movie2.mkv (converted)
└── Drama/
    └── Movie3.mkv (converted)
```

## Progress Tracking

The script shows:
1. **Initial Summary** - Total files found, source/destination paths, settings
2. **Live Progress** - Files being queued and processed with status indicators
3. **Progress Bar** - Visual indicator of completion percentage
4. **Final Summary** - Total files processed with output location

## Performance Tips

1. **Adjust MaxParallel based on your system:**
   - CPU-bound: Use 2-4 jobs
   - High-end system: Try 4-8 jobs
   - Monitor CPU/disk usage and adjust accordingly

2. **Use fast storage:**
   - SSD recommended for both source and destination
   - Avoid network drives if possible

3. **Run during off-peak hours:**
   - Encoding is CPU-intensive
   - Consider running overnight for large collections

4. **Check available disk space:**
   - Ensure destination has enough space for all converted files
   - Converted files are typically similar size to originals

## Troubleshooting

### "ffprobe not found" or "ffmpeg not found"
- **Solution:** Install ffmpeg and ensure it's in your system PATH
- Verify: Open PowerShell and run `ffmpeg -version`

### "Cannot find path" error
- **Solution:** Verify the `-SourceRoot` path exists and is accessible
- Check for typos in the path
- Ensure you have read permissions

### "Missing closing '}'" error
- **Solution:** This was a file encoding issue that has been fixed
- If you still see this, try running the script from a different PowerShell session

### Slow processing
- **Solution:** Increase `-MaxParallel` value (e.g., 4 or 6)
- Check system resources (CPU, disk I/O)
- Ensure no other heavy processes are running

### Some files skipped
- **Normal behavior** - Files are skipped if:
  - Output file already exists
  - No DTS/TrueHD audio detected (file is already compatible)
  - File has no audio streams

## Getting Help

View the built-in help:
```powershell
Get-Help .\Convert-Unsupported-Audio-for-S95C.ps1
Get-Help .\Convert-Unsupported-Audio-for-S95C.ps1 -Full
Get-Help .\Convert-Unsupported-Audio-for-S95C.ps1 -Examples
```

## Notes

- **Non-destructive:** Original files are never modified
- **Safe to re-run:** Already converted files are skipped
- **Lossless conversion:** FLAC maintains audio quality
- **Preserves structure:** Directory hierarchy is maintained in output
- **Background jobs:** Processing happens in parallel for efficiency

## Common Workflows

### Workflow 1: Convert Entire Movie Library
```powershell
# First run - convert everything
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\Movies" -DestRoot "E:\Movies_S95C" -Recurse -MaxParallel 4

# Later - convert new movies added to source
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\Movies" -DestRoot "E:\Movies_S95C" -Recurse -MaxParallel 4
# (Already converted files will be skipped automatically)
```

### Workflow 2: Convert and Replace
```powershell
# Convert to temporary location
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_Temp" -Recurse

# Verify results, then manually move/replace original files
# (Keep backups of originals just in case)
```

### Workflow 3: Batch Convert Multiple Folders
```powershell
# Create a batch script (convert_all.ps1)
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\Movies" -DestRoot "E:\Movies_S95C" -Recurse -MaxParallel 4
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\TV" -DestRoot "E:\TV_S95C" -Recurse -MaxParallel 4
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "E:\Documentaries" -DestRoot "E:\Documentaries_S95C" -Recurse -MaxParallel 4
```

---

**Last Updated:** November 2025
**Version:** 1.0
