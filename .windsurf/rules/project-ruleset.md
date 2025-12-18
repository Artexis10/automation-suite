---
trigger: always
---

# Automation Suite Project Ruleset

This ruleset governs development and operation of the Automation Suite repository.

---

## Glossary

| Term | Definition |
|------|------------|
| **Manifest** | Declarative JSONC/JSON/YAML file describing desired machine state (apps, configs, verifications) |
| **Plan** | Generated execution steps derived from a manifest, showing exactly what will happen |
| **State** | Persistent record of previous runs, applied manifests, and checksums for drift detection |
| **Driver** | Platform-specific adapter for installing software (e.g., winget, apt, brew) |
| **Restorer** | Module that applies configuration (copy files, merge JSON/INI, append lines) |
| **Verifier** | Module that confirms desired state is achieved (file exists, command responds, hash matches) |
| **Report** | JSON artifact summarizing a run: what was intended, applied, skipped, and failed |

---

## Repository Structure

```
automation-suite/
├── backup-tools/           # File backup and integrity verification
├── media-tools/            # Photo/video processing utilities
├── podcast-tools/          # Podcast production helpers
├── youtube-tools/          # YouTube content utilities
├── archive-setup/          # Environment and archive setup scripts
├── provisioning/           # Machine provisioning system
│   ├── cli.ps1             # CLI entrypoint
│   ├── engine/             # Core logic (manifest, plan, apply, verify, state, logging)
│   ├── drivers/            # Software installers (winget.ps1)
│   ├── restorers/          # Config restoration (copy, merge-json, merge-ini, append)
│   ├── verifiers/          # State verification (file-exists)
│   ├── manifests/          # User manifest files
│   │   └── includes/       # Template and modular manifest includes
│   ├── plans/              # Generated execution plans
│   ├── state/              # Run history and checksums
│   ├── logs/               # Execution logs
│   └── tests/              # Pester tests
├── scripts/                # Cross-cutting scripts
│   └── test_pester.ps1     # Root test runner
├── HashAll.ps1             # (Stub) SHA256 checksums
├── CompareHashes.ps1       # (Stub) Compare checksums
└── New-TripView.ps1        # (Stub) Trip view structure
```

### Subsystem Status

| Subsystem | Status | Location |
|-----------|--------|----------|
| Provisioning CLI | Functional | `provisioning/cli.ps1` |
| Manifest parsing (JSONC/JSON/YAML) | Functional | `provisioning/engine/manifest.ps1` |
| Plan generation | Functional | `provisioning/engine/plan.ps1` |
| Apply execution | Functional | `provisioning/engine/apply.ps1` |
| Capture (winget export) | Functional | `provisioning/engine/capture.ps1` |
| Verify | Functional | `provisioning/engine/verify.ps1` |
| State persistence | Functional | `provisioning/engine/state.ps1` |
| Logging | Functional | `provisioning/engine/logging.ps1` |
| Winget driver | Functional | `provisioning/drivers/winget.ps1` |
| Restorers (copy, merge, append) | Functional | `provisioning/restorers/` |
| Verifiers | Functional | `provisioning/verifiers/` |
| apt/dnf/brew drivers | Planned | `provisioning/drivers/` |
| Backup Tools | Functional | `backup-tools/` |
| Media Tools | Functional | `media-tools/` |
| Podcast Tools | Functional | `podcast-tools/` |
| YouTube Tools | Functional | `youtube-tools/` |

---

## Design Principles

### 1. Platform-Agnostic
Manifests express intent, not OS-specific commands. Drivers adapt intent to the platform.

### 2. Idempotent by Default
Re-running any operation must:
- Converge to the same result
- Never duplicate work
- Never corrupt existing state
- Log what was skipped and why

### 3. Non-Destructive + Safe
- Defaults preserve original data
- Backups created before overwrites
- Destructive operations require explicit opt-in flags
- No secrets auto-exported (sensitive paths excluded from capture)

### 4. Declarative Desired State
Describe *what should be true*, not imperative steps. The system decides how to reach that state.

### 5. Separation of Concerns
- **Drivers** install software
- **Restorers** apply configuration
- **Verifiers** prove correctness
- No step silently assumes success

### 6. First-Class Verification
Every meaningful action must be verifiable. "It ran" is not success—success means the desired state is observable.

### 7. Deterministic Output
- Stable manifest hashing (16-char SHA256 prefix)
- Stable key ordering in JSON reports
- Reproducible plans given same inputs
- Capture output sorted alphabetically by app id

---

## How to Run

### Provisioning Commands

```powershell
# Navigate to provisioning directory
cd provisioning

# Capture current machine state (profile-based, recommended)
.\cli.ps1 -Command capture -Profile my-machine

# Capture with templates for restore and verify
.\cli.ps1 -Command capture -Profile my-machine -IncludeRestoreTemplate -IncludeVerifyTemplate

# Capture with all apps (including runtimes and store apps)
.\cli.ps1 -Command capture -Profile my-machine -IncludeRuntimes -IncludeStoreApps

# Capture minimized (drop entries without stable refs)
.\cli.ps1 -Command capture -Profile my-machine -Minimize

# Capture with discovery mode (detect non-winget-managed software)
.\cli.ps1 -Command capture -Profile my-machine -Discover

# Capture with discovery but skip manual include generation
.\cli.ps1 -Command capture -Profile my-machine -Discover -DiscoverWriteManualInclude $false

# Capture to explicit path (legacy mode, backward compatible)
.\cli.ps1 -Command capture -OutManifest .\manifests\my-machine.jsonc

# Generate plan (preview what would happen)
.\cli.ps1 -Command plan -Manifest .\manifests\my-machine.jsonc

# Apply with dry-run (preview only)
.\cli.ps1 -Command apply -Manifest .\manifests\my-machine.jsonc -DryRun

# Apply for real
.\cli.ps1 -Command apply -Manifest .\manifests\my-machine.jsonc

# Verify current state matches manifest
.\cli.ps1 -Command verify -Manifest .\manifests\my-machine.jsonc

# Diagnose environment issues
.\cli.ps1 -Command doctor

# Compare two plan/run artifacts
.\cli.ps1 -Command diff -FileA .\plans\run1.json -FileB .\plans\run2.json

# Diff with JSON output
.\cli.ps1 -Command diff -FileA .\plans\run1.json -FileB .\plans\run2.json -Json

# Restore configuration files (requires explicit opt-in)
.\cli.ps1 -Command restore -Manifest .\manifests\my-machine.jsonc -EnableRestore

# Restore with dry-run preview
.\cli.ps1 -Command restore -Manifest .\manifests\my-machine.jsonc -EnableRestore -DryRun

# Apply with restore enabled (installs apps + restores configs)
.\cli.ps1 -Command apply -Manifest .\manifests\my-machine.jsonc -EnableRestore
```

### Capture Command Options

| Option | Default | Description |
|--------|---------|-------------|
| `-Profile <name>` | - | Profile name; writes to `manifests/<name>.jsonc` |
| `-OutManifest <path>` | - | Explicit output path (overrides -Profile) |
| `-IncludeRuntimes` | false | Include runtime packages (VCRedist, .NET, UI.Xaml, etc.) |
| `-IncludeStoreApps` | false | Include Microsoft Store apps (msstore source or 9N*/XP* IDs) |
| `-Minimize` | false | Drop entries without stable refs (no windows ref) |
| `-IncludeRestoreTemplate` | false | Generate `./includes/<profile>-restore.jsonc` (requires -Profile) |
| `-IncludeVerifyTemplate` | false | Generate `./includes/<profile>-verify.jsonc` (requires -Profile) |
| `-Discover` | false | Enable discovery mode: detect software present but not winget-managed |
| `-DiscoverWriteManualInclude` | true (when -Discover) | Generate `./includes/<profile>-manual.jsonc` with commented suggestions (requires -Profile) |

### Running Tests

```powershell
# From repo root - run all Pester tests
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\test_pester.ps1

# Run provisioning tests only
pwsh -NoProfile -ExecutionPolicy Bypass -File provisioning\tests\run-tests.ps1

# Run specific test file
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Path provisioning\tests\unit\Plan.Tests.ps1"

# Run capture tests
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Path provisioning\tests\unit\Capture.Tests.ps1"

# Run discovery tests
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Path provisioning\tests\unit\Discovery.Tests.ps1"
```

### Other Scripts

| Script | Command | Status |
|--------|---------|--------|
| Backup XMPs | `.\backup-tools\Backup-XMPs.ps1 -SourcePath <path>` | Functional |
| Convert Audio | `.\media-tools\unsupported-audio-conversion-for-s95c\Convert-Unsupported-Audio-for-S95C.ps1` | Functional |
| Export Podcast Tree | `.\podcast-tools\ExportPodcastTree.ps1` | Functional |
| Download YouTube Chat | `.\youtube-tools\live-chat-downloader\download_chats_ytdlp.ps1` | Functional |

---

## Engineering Discipline

### Idempotency Requirements
- Every operation must detect current state before acting
- Skip actions when desired state already exists
- Log skipped actions with reason: `[SKIP] <item> - already installed`
- Drift detection: compare current state hash against last-run state

### Backup Policy
- Restorers must backup existing files before overwriting
- Backup location: `provisioning/state/backups/<runId>/`
- Backup format: original path structure preserved

### Security
- No secrets auto-exported during capture
- Sensitive paths excluded: `.ssh`, `.aws`, `.azure`, `Credentials`
- API keys never hardcoded; use environment variables
- Warn user when sensitive paths detected

### Testing Requirements
- Mock all external calls (winget, network) in tests
- No real installs in CI/tests
- Tests must be deterministic and idempotent
- Use fixtures in `provisioning/tests/fixtures/`

### Deterministic Output
- Manifest hash: 16-character SHA256 prefix
- RunId format: `yyyyMMdd-HHmmss`
- JSON reports: ordered keys (runId, timestamp, manifest, summary, actions)
- Plans reproducible given same manifest + installed state
- Capture apps sorted alphabetically by id

### Logging + Reports
- All runs produce logs in `provisioning/logs/<runId>.log`
- Reports saved as JSON in `provisioning/state/runs/<runId>.json`
- Report schema: `runId`, `timestamp`, `manifest`, `summary`, `actions`
- Human-readable console output with color coding

---

## Change Management

### Ruleset Sync
If any of the following change, update this ruleset in the same commit:
- CLI commands or parameters
- Environment variables
- Directory structure
- New drivers/restorers/verifiers
- Test commands

### Destructive Operations
- Restore is opt-in: requires `-EnableRestore` flag
- Backups stored in `provisioning/state/backups/<runId>/` preserving path structure
- Sensitive paths (.ssh, .aws, credentials, etc.) trigger warnings
- Must be explicitly opt-in (require flags like `-Force` or `-Confirm`)
- Must log clearly: `[DESTRUCTIVE] <action>`
- Must backup before proceeding

### Reboot Markers
- Operations requiring reboot must set `requiresReboot: true` in plan/report
- CLI must warn user at end of run if reboot required
- Planned: `--reboot-if-needed` flag (not implemented yet)

---

## Manifest Format (v1)

Supported formats: `.jsonc` (preferred), `.json`, `.yaml`, `.yml`

```jsonc
{
  "version": 1,
  "name": "my-workstation",
  "captured": "2025-01-01T00:00:00Z",
  
  "includes": [
    "./includes/my-workstation-restore.jsonc",
    "./includes/my-workstation-verify.jsonc"
  ],
  
  "apps": [
    {
      "id": "vscode",
      "refs": {
        "windows": "Microsoft.VisualStudioCode",
        "linux": "code",
        "macos": "visual-studio-code"
      }
    }
  ],
  
  "restore": [
    // Copy: simple file/directory copy
    { "type": "copy", "source": "./configs/.gitconfig", "target": "~/.gitconfig", "backup": true },
    
    // JSON merge: deep-merge objects, arrays replace by default
    {
      "type": "merge",
      "format": "json",
      "source": "./state/capture/vscode/settings.json",
      "target": "$env:APPDATA/Code/User/settings.json",
      "backup": true,
      "arrayStrategy": "replace"  // or "union" for deterministic union
    },
    
    // INI merge: merge sections and keys
    {
      "type": "merge",
      "format": "ini",
      "source": "./state/capture/app/config.ini",
      "target": "$env:PROGRAMFILES/App/config.ini",
      "backup": true
    },
    
    // Append: add missing lines (idempotent)
    {
      "type": "append",
      "source": "./state/capture/gitconfig-extra.txt",
      "target": "~/.gitconfig",
      "backup": true,
      "dedupe": true  // default: true
    }
  ],
  
  "verify": [
    { "type": "file-exists", "path": "~/.gitconfig" }
  ]
}
```

### Restore Types

| Type | Format | Description |
|------|--------|-------------|
| `copy` | - | Simple file/directory copy (default) |
| `merge` | `json` | Deep-merge JSON/JSONC files; sorted keys for determinism |
| `merge` | `ini` | Merge INI sections/keys; preserves keys not in source |
| `append` | - | Append missing lines to text file; idempotent with dedupe |

### Merge Behavior

**JSON merge:**
- Objects: deep-merge recursively
- Arrays: `replace` (default) or `union` (deterministic)
- Scalars: source overwrites target
- Output: sorted keys, 2-space indent

**INI merge:**
- Keys from source overwrite/add into target
- Existing keys not in source are preserved
- Comments are NOT preserved (v1 limitation)

**Append:**
- Adds lines from source not already in target
- `dedupe: true` (default) removes duplicates
- Idempotent: re-run produces same result

---

## Not Yet Implemented

The following are planned but not yet functional:

- **apt/dnf/brew drivers** - Linux/macOS package managers
- **Verifier modules** - Custom verification beyond file-exists
- **Report command** - `cli.ps1 -Command report` (shows run history)
- **Reboot handling** - Automatic reboot detection and `--reboot-if-needed`
- **Rollback** - Undo last apply using backup state

---

## References

- [provisioning/readme.md](../provisioning/readme.md) - Full provisioning architecture
- [contributing.md](../contributing.md) - Development conventions
- [roadmap.md](../roadmap.md) - Future development plans
- [tool-index.md](../tool-index.md) - Complete script index