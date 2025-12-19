# Automation Suite

A provisioning-centric automation framework for rebuilding machines and workflows safely and repeatably.

**Author:** Hugo Ander Kivi  
**Primary Language:** PowerShell  
**Status:** MVP — functional, evolving

[![CI](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/Artexis10/automation-suite/actions/workflows/ci.yml)

---

## Why This Exists

Rebuilding a machine after a clean install is tedious, error-prone, and mentally draining. Configuration drift accumulates silently. Manual steps get forgotten. The result is machines that cannot be reliably reconstructed.

Automation Suite exists to eliminate this **clean install tax**.

A machine should be:

- **Rebuildable** — from a single manifest
- **Auditable** — with clear records of what was applied
- **Deterministic** — same inputs produce same outcomes
- **Safe to re-run** — at any time, without side effects

---

## Core Principles

- **Declarative desired state** — describe *what should be true*, not *how to do it*
- **Idempotence** — re-running converges to the same result without duplicating work
- **Non-destructive defaults** — no silent deletions, explicit opt-in for destructive operations
- **Verification-first** — "it ran" is not success; success means the desired state is observable
- **Separation of concerns** — install ≠ configure ≠ verify

---

## Architecture

**Provisioning** is the core system. It transforms a machine from an unknown state into a known, verified desired state.

Other tool folders (`backup-tools/`, `media-tools/`, etc.) are supporting automation — useful, but secondary to the provisioning system.

```
automation-suite/
├── autosuite.ps1              # Root CLI — delegates to provisioning
├── provisioning/              # Core provisioning system
│   ├── cli.ps1                # Provisioning CLI
│   ├── engine/                # Core logic (capture, plan, apply, verify, etc.)
│   ├── drivers/               # Software installation adapters (winget)
│   ├── restorers/             # Configuration restoration (copy, merge, append)
│   ├── verifiers/             # State verification (file-exists, command-exists)
│   ├── manifests/             # Desired state declarations
│   ├── state/                 # Run history and checksums
│   └── logs/                  # Execution logs
├── backup-tools/              # File backup and integrity verification
├── media-tools/               # Photo/video processing utilities
├── podcast-tools/             # Podcast production helpers
├── youtube-tools/             # YouTube content utilities
├── archive-setup/             # Environment setup scripts
└── tests/                     # Pester unit tests
```

For the complete provisioning architecture, see **[provisioning/README.md](provisioning/README.md)**.

---

## Quickstart

### Provisioning Workflow

```powershell
# 1. Capture current machine state
.\autosuite.ps1 capture

# 2. Preview what would be applied (dry-run)
.\autosuite.ps1 apply -Manifest provisioning/manifests/hugo-win11.jsonc -DryRun

# 3. Apply the manifest
.\autosuite.ps1 apply -Manifest provisioning/manifests/hugo-win11.jsonc

# 4. Verify desired state is achieved
.\autosuite.ps1 verify -Manifest provisioning/manifests/hugo-win11.jsonc

# 5. Check environment health
.\autosuite.ps1 doctor
```

### Manifest Locations

| Path | Purpose | Git Status |
|------|---------|------------|
| `provisioning/manifests/local/` | Machine-specific captures | **Gitignored** |
| `provisioning/manifests/examples/` | Sanitized shareable examples | **Committed** |
| `provisioning/manifests/*.jsonc` | Named profile manifests | **Committed** |
| `.autosuite/state.json` | Local machine state | **Gitignored** |

### State and Drift Detection

Autosuite tracks state in `.autosuite/state.json`:

- **lastApplied** — manifest path, hash, and timestamp
- **lastVerify** — verification results and timestamp
- **appsObserved** — installed apps and versions

Drift detection compares current state against a manifest:

```
[autosuite] Drift: Missing=2 Extra=5 VersionMismatches=0
```

### Machine-Readable Reports

Generate JSON reports for automation pipelines:

```powershell
# JSON to stdout (pure JSON, no wrapper text)
.\autosuite.ps1 report -Json

# JSON to stdout AND file (atomic write)
.\autosuite.ps1 report -Json -Out report.json

# Include drift against a manifest
.\autosuite.ps1 report -Json -Manifest provisioning/manifests/hugo-win11.jsonc
```

JSON output includes: `schemaVersion`, `timestampUtc`, state snapshot, optional manifest hash/path, and drift summary.

### Portable State (Export/Import)

Transfer state between machines or backup/restore:

```powershell
# Export state (atomic write, valid schema even if empty)
.\autosuite.ps1 state export -Out backup-state.json

# Import with merge (default: newer timestamps win)
.\autosuite.ps1 state import -In backup-state.json

# Import with replace (backup existing first)
.\autosuite.ps1 state import -In backup-state.json -Replace
```

**Merge behavior:** Incoming `lastApplied`/`lastVerify` overwrites only if timestamp is newer.

**Replace behavior:** Backs up existing state to `.autosuite/backup/state.<timestamp>.json` before replacing.

### Output Stream Hygiene

Stable wrapper lines use **Information stream (6)**, not stdout:

- `report -Json` outputs **only** valid JSON to stdout (stream 1)
- Wrapper lines like `[autosuite] ...` go to stream 6
- Capture wrapper lines with: `$output = & .\autosuite.ps1 verify ... 6>&1`

---

## Supporting Tools

These tools are secondary to provisioning but follow the same principles (idempotent, non-destructive, logged).

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
| winget | Latest | App installation (provisioning) |
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
| [provisioning/README.md](provisioning/README.md) | **Provisioning system contract** — architecture, lifecycle, manifest format |
| [VISION.md](VISION.md) | Project intent, boundaries, and non-goals |
| [TOOL-INDEX.md](TOOL-INDEX.md) | Complete index of all scripts |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development conventions |
| [ROADMAP.md](ROADMAP.md) | Planned development |

---

## Status

**Current:** MVP functional — capture, apply, verify, and drift detection work. Restore operations are opt-in. Custom drivers are supported but winget is the primary driver.

**Maturity:** This is a personal/small-team tool. It is not enterprise software. It prioritizes correctness and safety over features.

---

## License

Public repository. All rights reserved.
