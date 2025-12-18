# Backup Tools

Tools for file backup, integrity verification, and manifest generation.

---

## Scripts

### Backup-XMPs.ps1

Backs up XMP sidecar files from a source directory to a destination, preserving the original directory structure. Uses robocopy for efficient, incremental synchronization.

#### Purpose

XMP files contain photo editing metadata (Lightroom, Camera Raw, etc.). This script ensures these files are safely backed up without modifying originals.

#### Features

- **Structure preservation** - Mirrors source directory hierarchy in destination
- **Incremental backup** - Only copies new or modified files (`/XO` flag)
- **Non-destructive** - Never deletes files from destination
- **Manifest generation** - Optional CSV manifest with file metadata and SHA256 hashes
- **Log rotation** - Automatic cleanup of old logs (configurable)
- **Multi-threaded** - Parallel file operations via robocopy

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Source` | string | `D:\Archive\Personal Archive\10 Cameras` | Source directory containing XMP files |
| `-Destination` | string | `D:\Archive\Personal Archive\70 System Backups\XMPs` | Backup destination directory |
| `-LogsRoot` | string | `D:\Archive\Personal Archive\05 Logs\XMP Backup` | Directory for logs and manifests |
| `-DryRun` | switch | false | Preview changes without copying |
| `-MakeManifest` | switch | false | Generate CSV manifest after backup |
| `-Hash` | switch | false | Include SHA256 hashes in manifest |
| `-Threads` | int | 16 | Number of parallel robocopy threads |
| `-Retries` | int | 5 | Retry count for failed operations |
| `-WaitSec` | int | 3 | Wait time between retries (seconds) |
| `-KeepRecent` | int | 12 | Number of recent logs to keep (0 = keep all) |

#### Usage Examples

```powershell
# Basic backup with default paths
.\Backup-XMPs.ps1

# Dry run to preview changes
.\Backup-XMPs.ps1 -DryRun

# Backup with manifest (no hashes)
.\Backup-XMPs.ps1 -MakeManifest

# Backup with manifest including SHA256 hashes
.\Backup-XMPs.ps1 -MakeManifest -Hash

# Custom source and destination
.\Backup-XMPs.ps1 -Source "E:\Photos" -Destination "F:\Backup\XMPs"

# Increase parallelism for faster backup
.\Backup-XMPs.ps1 -Threads 32
```

#### Output

**Logs:**
- Location: `<LogsRoot>/xmp_backup_<timestamp>.log`
- Format: Robocopy log with file-level details

**Manifests (if `-MakeManifest`):**
- Location: `<LogsRoot>/_manifests/xmp_manifest_<timestamp>.csv`
- Columns: `RelativePath`, `SizeBytes`, `LastWriteUtc`, `SHA256`

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0-7 | Success (robocopy standard codes) |
| 8+ | Error occurred (see log for details) |

#### Dependencies

- **robocopy** - Built into Windows
- **PowerShell 5.1+**

---

## Stub Scripts (Root Level)

The following scripts exist at the repository root as placeholders for future implementation:

### HashAll.ps1

**Status:** Stub

**Intended Purpose:** Generate SHA256 checksums for all files in a directory, outputting to `SHA256SUMS.txt` in a format compatible with standard verification tools.

### CompareHashes.ps1

**Status:** Stub

**Intended Purpose:** Compare two `SHA256SUMS.txt` files to identify:
- Added files
- Removed files
- Modified files (hash mismatch)
- Unchanged files

---

## Planned Features

- Full implementation of `HashAll.ps1` and `CompareHashes.ps1`
- Backup verification tool to compare source and destination
- Support for additional sidecar formats (`.dop`, `.on1`, etc.)
- Email/notification on backup completion or failure
