# Automation Suite

A collection of automation tools and utilities for personal workflows.

**Author:** Hugo Ander Kivi  
**Primary Language:** PowerShell  
**Status:** Active

[![CI](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml)

---

## Note: Provisioning Has Moved

The provisioning system is now maintained separately at **[Autosuite](https://github.com/Artexis10/autosuite)**.

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

## Testing

Tests use **Pester v5** and require **Windows PowerShell 5.1** (`powershell.exe`).

### Run Unit Tests (Default)

```powershell
# From repo root - uses vendored Pester
.\tests\run-tests.ps1
```

### Run Integration Tests

```powershell
.\tests\run-tests.ps1 -Integration
```

### Run Optional Tooling Tests

Tests requiring external tools (ffmpeg, ffprobe, yt-dlp) are tagged `OptionalTooling` and skipped by default.

```powershell
# Only if ffmpeg/ffprobe are installed
.\tests\run-tests.ps1 -OptionalTooling
```

### Run All Tests

```powershell
.\tests\run-tests.ps1 -All
```

### Advanced: Direct Invoke-Pester Usage

For manual configuration or CI integration, call `pester.config.ps1` directly:

```powershell
Invoke-Pester -Configuration (& .\pester.config.ps1)
Invoke-Pester -Configuration (& .\pester.config.ps1 -IncludeIntegration)
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [TOOL-INDEX.md](TOOL-INDEX.md) | Complete index of all scripts |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development conventions |
| [provisioning/README.md](provisioning/README.md) | Migration notice — provisioning moved to Autosuite |

---

## License

Public repository. All rights reserved.
