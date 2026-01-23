# Automation Suite

A collection of automation tools and utilities for personal workflows.

**Author:** Hugo Ander Kivi  
**Primary Language:** PowerShell  
**Status:** Active

[![CI](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml)

---

## Note: Provisioning Has Moved

The provisioning system has been split into a separate repository: **[github.com/Artexis10/endstate](https://github.com/Artexis10/endstate)**.

---

## What's Here

```
automation-suite/
├── backup-tools/     # File backup and integrity verification
├── media-tools/      # Photo/video processing utilities
├── podcast-tools/    # Podcast production helpers
├── youtube-tools/    # YouTube content utilities
├── archive-setup/    # Environment setup scripts
├── tools/            # Shared utilities (vendored Pester)
└── tests/            # Pester unit/integration tests
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
| PowerShell | 5.1+ | Script execution (Windows PowerShell required) |
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

## Running Tests Locally

Tests use **Pester v5** and require **Windows PowerShell 5.1** (`powershell.exe`).

### Install Pester 5

```powershell
Install-Module Pester -Scope CurrentUser -Force
```

### Run Tests

```powershell
.\scripts\test.ps1
```

The script will:
- Verify Pester >= 5 is available (vendored or installed)
- Run all unit tests with detailed output
- Return non-zero exit code on failure

### Advanced Options

For integration tests or tests requiring external tools (ffmpeg, ffprobe, yt-dlp):

```powershell
.\tests\run-tests.ps1 -Integration      # Include integration tests
.\tests\run-tests.ps1 -OptionalTooling  # Include tests requiring external tools
.\tests\run-tests.ps1 -All              # Run all tests
```

For manual Pester configuration:

```powershell
Invoke-Pester -Configuration (& .\pester.config.ps1)
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [TOOL-INDEX.md](TOOL-INDEX.md) | Complete index of all scripts |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development conventions |
| [provisioning/README.md](provisioning/README.md) | Migration notice — provisioning moved to separate repository |

---

## AI-Assisted Development

This repository includes AI-facing infrastructure for deterministic, reviewable AI collaboration. See `docs/ai/`.

---

## License

Public repository. All rights reserved.
