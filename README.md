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

### Capture → Apply → Verify Loop

```powershell
# 1. CAPTURE: Export current machine state to local manifest (gitignored)
.\autosuite.ps1 capture
# Output: provisioning/manifests/local/<machine>.jsonc

# Capture to specific path
.\autosuite.ps1 capture -Out my-manifest.jsonc

# Generate sanitized example manifest (no machine/timestamps, stable sort)
.\autosuite.ps1 capture -Sanitize -Name example-windows-core
# Output: provisioning/manifests/examples/example-windows-core.jsonc

# Legacy: Generate static example manifest
.\autosuite.ps1 capture -Example

# 2. APPLY: Install apps from manifest
.\autosuite.ps1 apply -Manifest provisioning/manifests/fixture-test.jsonc

# Preview what would be installed (dry-run)
.\autosuite.ps1 apply -Manifest manifest.jsonc -DryRun

# Install apps only (skip auto-verify at end)
.\autosuite.ps1 apply -Manifest manifest.jsonc -OnlyApps

# 3. VERIFY: Check all apps are installed
.\autosuite.ps1 verify -Manifest provisioning/manifests/fixture-test.jsonc
# Exit code: 0 = all installed, 1 = missing apps
```

### Other Commands

```powershell
# Show state summary (last applied, last verify)
.\autosuite.ps1 report

# Show state summary with current drift against manifest
.\autosuite.ps1 report -Manifest manifest.jsonc

# Diagnose environment issues (includes drift detection if manifest provided)
.\autosuite.ps1 doctor
.\autosuite.ps1 doctor -Manifest manifest.jsonc

# Reset autosuite state (deletes .autosuite/state.json)
.\autosuite.ps1 state reset
```

### State & Drift Detection

Autosuite tracks state in `.autosuite/state.json` (repo-local, gitignored):

- **lastApplied**: Manifest path, hash, and timestamp of last `apply`
- **lastVerify**: Manifest path, hash, timestamp, and results of last `verify`
- **appsObserved**: Map of winget IDs to installed status and version

Drift detection compares current installed apps against a manifest:
- **Missing**: Apps required by manifest but not installed
- **Extra**: Apps installed but not in manifest

The `verify` command emits a drift summary line:
```
[autosuite] Drift: Missing=<n> Extra=<n> VersionMismatches=<n>
```

### Manifest Locations

| Path | Purpose |
|------|---------|
| `provisioning/manifests/fixture-test.jsonc` | Committed test fixture (deterministic) |
| `provisioning/manifests/examples/` | Sanitized example manifests (committed, shareable) |
| `provisioning/manifests/local/` | Machine-specific captures (gitignored) |
| `.autosuite/state.json` | State file for drift detection (gitignored) |

### Capture Options

| Option | Description |
|--------|-------------|
| `-Out <path>` | Output path (overrides all defaults) |
| `-Sanitize` | Remove machine-specific fields, secrets, local paths; stable sort |
| `-Name <string>` | Manifest name (used for filename when `-Sanitize`) |
| `-ExamplesDir <path>` | Examples directory (default: `provisioning/manifests/examples/`) |
| `-Force` | Overwrite existing example manifests without prompting |
| `-Example` | (Legacy) Generate static example manifest |

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
