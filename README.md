# Automation Suite

A collection of automation tools and utilities for personal workflows.

**Author:** Hugo Ander Kivi  
**Primary Language:** PowerShell  
**Status:** Active

[![CI](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml)

---

## Important: Provisioning Has Moved

**The provisioning system has been split into a standalone repository: [Autosuite](https://github.com/Artexis10/autosuite)**

If you're looking for machine provisioning and configuration management, use Autosuite instead. See [provisioning/README.md](provisioning/README.md) for migration details.

---

## What's Here

This repository contains various automation tools and utilities:

```
automation-suite/
├── backup-tools/              # File backup and integrity verification
├── media-tools/               # Photo/video processing utilities
├── podcast-tools/             # Podcast production helpers
├── youtube-tools/             # YouTube content utilities
├── archive-setup/             # Environment setup scripts
├── tools/                     # Shared utilities
└── tests/                     # Pester unit tests
```

---

## Tools

| Folder | Purpose |
|--------|---------|
| `backup-tools/` | XMP backup, hash generation, integrity verification |
| `media-tools/` | Audio/video conversion (e.g., DTS→FLAC for Samsung TVs) |
| `podcast-tools/` | Podcast folder structure export |
| `youtube-tools/` | Live chat download and extraction |
| `archive-setup/` | Archive folder skeleton initialization |

See [TOOL-INDEX.md](TOOL-INDEX.md) for the complete script inventory.

---

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 5.1+ | Script execution |
| ffmpeg / ffprobe | Latest | Media conversion (optional) |
| yt-dlp | Latest | YouTube utilities (optional) |

### Installation

```powershell
git clone https://github.com/Artexis10/automation-suite.git
cd automation-suite

# (Optional) Unblock downloaded scripts
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [provisioning/README.md](provisioning/README.md) | **Migration notice** — provisioning has moved to Autosuite |
| [TOOL-INDEX.md](TOOL-INDEX.md) | Complete index of all scripts |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development conventions |

---

## Status

**Current:** Active — various automation tools for personal workflows.

**Note:** The provisioning system has been split into the standalone [Autosuite](https://github.com/Artexis10/autosuite) repository.

---

## License

Public repository. All rights reserved.
