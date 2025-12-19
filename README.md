# Automation Suite

A unified collection of automation scripts for backup workflows, media processing, podcast production, and YouTube utilities.

**Author:** Hugo Ander Kivi  
**Primary Language:** PowerShell  
**Status:** Active Development

---

## Overview

This repository consolidates automation tools used across various personal and professional workflows. Each tool is designed to be modular, reusable, and well-documented.

### Design Principles

- **Modular structure** - Each domain has its own folder with self-contained tools
- **Non-destructive defaults** - Scripts preserve original data unless explicitly configured otherwise
- **Idempotent operations** - Safe to re-run; already-processed items are skipped
- **Comprehensive logging** - Operations produce logs for audit and debugging

---

## Repository Structure

```
automation-suite/
├── backup-tools/           # File backup, hashing, and integrity verification
│   └── Backup-XMPs.ps1
├── media-tools/            # Photo/video processing utilities
│   └── unsupported-audio-conversion-for-s95c/
├── podcast-tools/          # Podcast production helpers
│   └── ExportPodcastTree.ps1
├── youtube-tools/          # YouTube content utilities
│   └── live-chat-downloader/
├── archive-setup/          # Environment and archive setup scripts
│   └── Setup-ArchiveStructure.ps1
├── autosuite.ps1           # Root orchestrator CLI (primary entrypoint)
├── tests/                  # Root-level Pester tests
│   └── unit/
├── provisioning/           # Machine provisioning and configuration management
│   ├── cli.ps1
│   ├── drivers/
│   ├── restorers/
│   ├── verifiers/
│   └── ...
├── HashAll.ps1             # (Stub) Generate SHA256 checksums
├── CompareHashes.ps1       # (Stub) Compare SHA256 checksum files
├── New-TripView.ps1        # (Stub) Create trip view structure
├── tool-index.md           # Complete index of all tools
├── contributing.md         # Development conventions
└── roadmap.md              # Future development plans
```

---

## Quickstart

### Autosuite CLI (Primary Entrypoint)

```powershell
# Apply a profile (installs apps, optionally restores configs)
.\autosuite.ps1 apply -Profile hugo-win11

# Preview what would be applied (dry-run)
.\autosuite.ps1 apply -Profile hugo-win11 -DryRun

# Apply with config restoration enabled
.\autosuite.ps1 apply -Profile hugo-win11 -EnableRestore

# Capture current machine state to a profile
.\autosuite.ps1 capture -Profile hugo-win11

# Generate execution plan from profile
.\autosuite.ps1 plan -Profile hugo-win11

# Verify current state matches profile
.\autosuite.ps1 verify -Profile hugo-win11

# Show most recent provisioning run
.\autosuite.ps1 report -Latest

# Show last 5 runs
.\autosuite.ps1 report -Last 5

# Diagnose environment issues
.\autosuite.ps1 doctor
```

Use `-Manifest <path>` instead of `-Profile` to specify a manifest file directly.

---

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 5.1+ | Script execution |
| ffmpeg / ffprobe | Latest | Media conversion (Media Tools) |
| yt-dlp | Latest | YouTube chat extraction |
| chat_downloader | Latest | Alternative chat extraction |
| robocopy | Built-in | File synchronization (Windows) |

### Installation

1. Clone the repository:
   ```powershell
   git clone https://github.com/your-username/automation-suite.git
   cd automation-suite
   ```

2. Ensure external dependencies are installed and available in PATH:
   ```powershell
   # Verify ffmpeg
   ffmpeg -version

   # Verify yt-dlp
   yt-dlp --version
   ```

3. (Optional) Unblock downloaded scripts:
   ```powershell
   Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
   ```

### Running Scripts

All scripts support standard PowerShell parameter syntax:

```powershell
# View help for any script
Get-Help .\ScriptName.ps1 -Full

# Run with parameters
.\ScriptName.ps1 -Parameter Value

# Run with switches
.\ScriptName.ps1 -DryRun -Verbose
```

---

## Tool Categories

### Backup Tools

Tools for file backup, integrity verification, and manifest generation.

| Script | Description |
|--------|-------------|
| `Backup-XMPs.ps1` | Backs up XMP sidecar files preserving directory structure |

See [backup-tools/readme.md](backup-tools/readme.md) for details.

### Media Tools

Utilities for photo and video processing.

| Script | Description |
|--------|-------------|
| `Convert-Unsupported-Audio-for-S95C.ps1` | Converts DTS/TrueHD audio to FLAC for Samsung S95C compatibility |

See [media-tools/readme.md](media-tools/readme.md) for details.

### Podcast Tools

Scripts for podcast production workflows.

| Script | Description |
|--------|-------------|
| `ExportPodcastTree.ps1` | Exports podcast folder structure to text file |

See [podcast-tools/readme.md](podcast-tools/readme.md) for details.

### YouTube Tools

Utilities for YouTube content extraction and processing.

| Script | Description |
|--------|-------------|
| `download_chats.ps1` | Downloads live chat using chat_downloader |
| `download_chats_ytdlp.ps1` | Downloads and converts live chat using yt-dlp |

See [youtube-tools/readme.md](youtube-tools/readme.md) for details.

### Archive Setup

Environment and archive structure initialization.

| Script | Description |
|--------|-------------|
| `Setup-ArchiveStructure.ps1` | (Stub) Initialize archive folder skeleton |

See [archive-setup/readme.md](archive-setup/readme.md) for details.

### Provisioning

Machine provisioning and configuration management — install apps, restore configs, verify state.

Provisioning transforms a machine from an unknown state into a known, verified desired state. It is Windows-first in implementation but platform-agnostic in design via pluggable drivers.

| Component | Description |
|-----------|-------------|
| `cli.ps1` | CLI entrypoint (stub) |
| `drivers/` | Software installation adapters (winget, apt, brew) |
| `restorers/` | Configuration restoration modules |
| `verifiers/` | State verification modules |

See [provisioning/readme.md](provisioning/readme.md) for the full manifesto and architecture.

---

## Documentation

| Document | Description |
|----------|-------------|
| [tool-index.md](tool-index.md) | Complete index of all scripts with inputs, outputs, and examples |
| [contributing.md](contributing.md) | Development conventions, branching, and commit style |
| [roadmap.md](roadmap.md) | Planned features and future development |

---

## Versioning

This repository uses semantic versioning for releases:

- **MAJOR.MINOR.PATCH** (e.g., `1.2.3`)
- **MAJOR** - Breaking changes or significant restructuring
- **MINOR** - New tools or features
- **PATCH** - Bug fixes and documentation updates

Current version: **0.1.0** (Initial formalization)

---

## License

Public repository. All rights reserved.
