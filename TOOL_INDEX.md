# Tool Index

Complete index of all scripts in the automation-suite repository.

---

## Summary

| Category | Scripts | Status |
|----------|---------|--------|
| Backup Tools | 3 | 1 implemented, 2 stubs |
| Media Tools | 2 | 1 implemented, 1 stub |
| Podcast Tools | 1 | 1 implemented |
| YouTube Tools | 2 | 2 implemented |
| Setup | 1 | 1 stub |
| **Total** | **9** | **5 implemented, 4 stubs** |

---

## Backup Tools

### Backup-XMPs.ps1

| Property | Value |
|----------|-------|
| **Path** | `Backup Tools/Backup-XMPs.ps1` |
| **Status** | Implemented |
| **Description** | Backs up XMP sidecar files preserving directory structure using robocopy |

**Inputs:**
- Source directory containing XMP files
- Destination directory for backups
- Configuration parameters (threads, retries, log retention)

**Outputs:**
- Copied XMP files in destination (mirrored structure)
- Log file: `<LogsRoot>/xmp_backup_<timestamp>.log`
- Manifest (optional): `<LogsRoot>/_manifests/xmp_manifest_<timestamp>.csv`

**Dependencies:**
- robocopy (Windows built-in)
- PowerShell 5.1+

**Example:**
```powershell
# Basic backup
.\Backup-XMPs.ps1

# Dry run with manifest
.\Backup-XMPs.ps1 -DryRun -MakeManifest -Hash

# Custom paths
.\Backup-XMPs.ps1 -Source "E:\Photos" -Destination "F:\Backup\XMPs" -LogsRoot "F:\Logs"
```

---

### HashAll.ps1

| Property | Value |
|----------|-------|
| **Path** | `HashAll.ps1` (root) |
| **Status** | Stub |
| **Description** | Generate SHA256 checksums for all files in a directory |

**Intended Inputs:**
- Target directory
- Output filename (default: `SHA256SUMS.txt`)
- Recursive flag

**Intended Outputs:**
- `SHA256SUMS.txt` with format: `<hash>  <relative_path>`

**Dependencies:**
- PowerShell 5.1+ (Get-FileHash)

---

### CompareHashes.ps1

| Property | Value |
|----------|-------|
| **Path** | `CompareHashes.ps1` (root) |
| **Status** | Stub |
| **Description** | Compare two SHA256SUMS.txt files to identify changes |

**Intended Inputs:**
- Reference hash file (baseline)
- Comparison hash file (current)

**Intended Outputs:**
- Report of added, removed, modified, and unchanged files

**Dependencies:**
- PowerShell 5.1+

---

## Media Tools

### Convert-Unsupported-Audio-for-S95C.ps1

| Property | Value |
|----------|-------|
| **Path** | `Media Tools/Unsupported Audio Conversion for S95C/Convert-Unsupported-Audio-for-S95C.ps1` |
| **Status** | Implemented |
| **Description** | Converts DTS/TrueHD audio in MKV files to FLAC for Samsung S95C compatibility |

**Inputs:**
- Source directory containing MKV files
- Destination directory for converted files
- Parallelism setting

**Outputs:**
- Converted MKV files with FLAC audio (or copied if already compatible)
- Console progress and status indicators

**Dependencies:**
- ffmpeg
- ffprobe
- PowerShell 5.1+

**Example:**
```powershell
# Convert current directory
.\Convert-Unsupported-Audio-for-S95C.ps1

# Recursive with 4 parallel jobs
.\Convert-Unsupported-Audio-for-S95C.ps1 -SourceRoot "D:\Movies" -DestRoot "D:\Movies_S95C" -Recurse -MaxParallel 4
```

---

### New-TripView.ps1

| Property | Value |
|----------|-------|
| **Path** | `New-TripView.ps1` (root) |
| **Status** | Stub |
| **Description** | Create trip/event-based photo organization view |

**Intended Inputs:**
- Source photo archive
- Trip/event metadata
- Output directory

**Intended Outputs:**
- Organized folder structure by trip/event

**Dependencies:**
- PowerShell 5.1+

---

## Podcast Tools

### ExportPodcastTree.ps1

| Property | Value |
|----------|-------|
| **Path** | `Podcast Tools/ExportPodcastTree.ps1` |
| **Status** | Implemented |
| **Description** | Exports podcast folder structure to text file |

**Inputs:**
- Hardcoded: `G:\My Drive\Podcasts\Together, Unprocessed Podcast`

**Outputs:**
- `podcast-structure.txt` in source directory

**Dependencies:**
- tree (Windows built-in)
- PowerShell 5.1+

**Example:**
```powershell
.\ExportPodcastTree.ps1
```

---

## YouTube Tools

### download_chats.ps1

| Property | Value |
|----------|-------|
| **Path** | `YouTube Tools/Live Chat Downloader/download_chats.ps1` |
| **Status** | Implemented |
| **Description** | Downloads YouTube live chat using chat_downloader |

**Inputs:**
- `urls.txt` - One YouTube URL per line

**Outputs:**
- Text files in `output/` with format: `YYYY-MM-DD__Title__VIDEO_ID.txt`

**Dependencies:**
- chat_downloader (Python package)
- PowerShell 5.1+

**Example:**
```powershell
.\download_chats.ps1
```

---

### download_chats_ytdlp.ps1

| Property | Value |
|----------|-------|
| **Path** | `YouTube Tools/Live Chat Downloader/download_chats_ytdlp.ps1` |
| **Status** | Implemented |
| **Description** | Downloads YouTube live chat using yt-dlp and converts to formatted text |

**Inputs:**
- `urls.txt` - One YouTube URL per line
- `-YtDlpPath` parameter (optional)

**Outputs:**
- JSON files: `output_ytdlp/YYYYMMDD - Title (VIDEO_ID).live_chat.json`
- Text files: `output_ytdlp/YYYYMMDD - Title (VIDEO_ID).live_chat.txt`

**Dependencies:**
- yt-dlp
- PowerShell 5.1+

**Example:**
```powershell
# Using yt-dlp from PATH
.\download_chats_ytdlp.ps1

# Using local executable
.\download_chats_ytdlp.ps1 -YtDlpPath ".\yt-dlp.exe"
```

---

## Setup

### Setup-ArchiveStructure.ps1

| Property | Value |
|----------|-------|
| **Path** | `Setup/Setup-ArchiveStructure.ps1` |
| **Status** | Stub |
| **Description** | Initialize archive folder skeleton |

**Intended Inputs:**
- Base path for archive
- Template configuration

**Intended Outputs:**
- Directory structure with README files

**Dependencies:**
- PowerShell 5.1+

---

## Quick Reference

| Script | One-liner |
|--------|-----------|
| Backup XMPs | `.\Backup-XMPs.ps1 -MakeManifest` |
| Convert MKVs | `.\Convert-Unsupported-Audio-for-S95C.ps1 -Recurse` |
| Export podcast tree | `.\ExportPodcastTree.ps1` |
| Download chats (yt-dlp) | `.\download_chats_ytdlp.ps1` |
| Download chats (chat_downloader) | `.\download_chats.ps1` |
