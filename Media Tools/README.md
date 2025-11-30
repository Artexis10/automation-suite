# Media Tools

Utilities for photo and video processing, format conversion, and media organization.

---

## Scripts

### Unsupported Audio Conversion for S95C

Located in: `Unsupported Audio Conversion for S95C/`

#### Convert-Unsupported-Audio-for-S95C.ps1

Converts MKV files for Samsung S95C TV playback by transcoding unsupported audio codecs (DTS, DTS-HD, DTS-MA, Dolby TrueHD) to FLAC.

#### Purpose

Samsung S95C OLED TVs do not natively support certain lossless audio codecs. This script converts those codecs to FLAC (also lossless) while preserving all other streams unchanged.

#### Features

- **Lossless conversion** - DTS/TrueHD to FLAC maintains audio quality
- **Stream preservation** - Video, subtitles, chapters, and compatible audio copied unchanged
- **Structure mirroring** - Output directory mirrors source directory hierarchy
- **Parallel processing** - Multiple files processed simultaneously
- **Idempotent** - Already-converted files are skipped
- **Non-destructive** - Original files are never modified

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SourceRoot` | string | `.` | Root directory containing MKV files |
| `-DestRoot` | string | `.\S95C_Converted` | Output directory for converted files |
| `-Recurse` | switch | false | Process subdirectories recursively |
| `-MaxParallel` | int | 2 | Maximum concurrent encoding jobs |

#### Usage Examples

```powershell
# Convert current directory (top-level only)
.\Convert-Unsupported-Audio-for-S95C.ps1

# Convert with recursion
.\Convert-Unsupported-Audio-for-S95C.ps1 -Recurse

# Specify source and destination
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C"

# Parallel processing (4 concurrent jobs)
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse -MaxParallel 4
```

#### Output

- Converted MKV files in `<DestRoot>` with identical directory structure
- Files without DTS/TrueHD are copied as-is
- Progress bar and status indicators during processing

#### Status Indicators

| Status | Meaning |
|--------|---------|
| `[QUEUE]` | File queued for processing |
| `[CONVERT]` | Converting DTS/TrueHD to FLAC |
| `[OK]` | Successfully processed |
| `[SKIP]` | Already exists or no conversion needed |
| `[WARN]` | Warning (check details) |
| `[ERROR]` | Error occurred |
| `[INFO]` | Information message |

#### Dependencies

- **ffmpeg** - For audio transcoding
- **ffprobe** - For stream analysis
- **PowerShell 5.1+**

Installation:
```powershell
# Via Chocolatey
choco install ffmpeg

# Or download from https://ffmpeg.org/download.html
```

#### Additional Documentation

See [USAGE_GUIDE.md](Unsupported%20Audio%20Conversion%20for%20S95C/USAGE_GUIDE.md) for detailed usage instructions, troubleshooting, and workflow examples.

---

## Stub Scripts (Root Level)

### New-TripView.ps1

**Status:** Stub

**Intended Purpose:** Create a "trip view" folder structure for organizing photos by trip/event, potentially with:
- Date-based organization
- Symlinks or copies from master archive
- Metadata extraction for automatic categorization

---

## Planned Features

- Photo organization utilities
- Batch EXIF/metadata extraction
- Duplicate detection
- Format conversion tools (RAW to JPEG, etc.)
- Video thumbnail generation
