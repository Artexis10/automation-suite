# Automation Suite — Current State Architecture

> **⚠️ HISTORICAL DOCUMENT** — This document describes the architecture of the provisioning system that has since been split into a separate repository ([github.com/Artexis10/endstate](https://github.com/Artexis10/endstate)). It is retained for historical reference only and does not reflect the current state of this repository.
>
> *Note: The provisioning system was originally called "Autosuite" during early development. It has since been renamed to "Endstate" and moved to a separate repository.*

**Generated:** 2025-12-19  
**Based on:** Code analysis of repository at commit time  
**Purpose:** Historical reference — describes the provisioning system before it was split out

---

## High-Level Summary

Automation Suite is a PowerShell-based provisioning framework designed to rebuild Windows machines from declarative manifests. The core workflow is: **capture** current machine state → **plan** what needs to change → **apply** changes → **verify** desired state is achieved.

The system has two entry points: `autosuite.ps1` (root orchestrator) and `provisioning/cli.ps1` (provisioning subsystem). The root orchestrator provides a unified CLI that delegates most commands to the provisioning subsystem, but also implements its own versions of `apply`, `verify`, and `report` with additional state management. The provisioning subsystem contains the engine logic for capture, plan, apply, restore, verify, diff, and report operations.

---

## Implemented Features

### Core Commands (Fully Functional)

- **`capture`** — Captures installed applications via `winget export`, generates JSONC manifests
  - Filters: runtime packages, store apps, minimize (drop entries without refs)
  - Discovery mode: detects non-winget-managed software
  - Update mode: merges new capture into existing manifest
  - Template generation: restore and verify templates
  - Sanitization: removes machine-specific data for shareable examples

- **`plan`** — Generates deterministic execution plan from manifest
  - Compares manifest apps against `winget list` output
  - Produces JSON plan file with install/skip/restore/verify actions
  - Plans are saved to `provisioning/plans/`

- **`apply`** — Executes plan to install apps and optionally restore configs
  - Dry-run mode for preview
  - Idempotent: skips already-installed apps
  - Version constraint checking (exact match, minimum version)
  - Supports pre-generated plans via `-Plan` parameter
  - State recording after apply

- **`verify`** — Checks current state against manifest
  - App installation verification via winget
  - Explicit verify items: `file-exists`, `command-exists`, `registry-key-exists`
  - Records results to state file

- **`restore`** — Restores configuration files from manifest
  - Opt-in via `-EnableRestore` flag (safety)
  - Backup-before-overwrite
  - Types: `copy`, `merge` (JSON/INI), `append`
  - Sensitive path warnings

- **`report`** — Shows state summary and drift
  - Human-readable and JSON output modes
  - Drift detection: missing apps, extra apps, version mismatches
  - Atomic file output with `-Out`

- **`doctor`** — Environment diagnostics
  - Checks winget availability
  - Verifies directory structure
  - Lists available manifests

- **`state`** — State management subcommands
  - `reset` — Deletes state file
  - `export` — Exports state to file
  - `import` — Imports state (merge or replace modes)

- **`bootstrap`** — Installs autosuite to user PATH

### Drivers (App Installation)

| Driver | Status | Description |
|--------|--------|-------------|
| `winget` | **Implemented** | Primary driver, uses Windows Package Manager |
| `custom` | **Implemented** | Runs custom install scripts with file/registry detection |

### Restorers (Config Restoration)

| Restorer | Status | Description |
|----------|--------|-------------|
| `copy` | **Implemented** | File/directory copy with backup |
| `merge` (JSON) | **Implemented** | Deep-merge JSON files |
| `merge` (INI) | **Implemented** | Merge INI files |
| `append` | **Implemented** | Append lines to text files with deduplication |

### Verifiers (State Verification)

| Verifier | Status | Description |
|----------|--------|-------------|
| `file-exists` | **Implemented** | Checks file/directory existence |
| `command-exists` | **Implemented** | Checks command resolvable in PATH |
| `registry-key-exists` | **Implemented** | Checks Windows registry key/value |

### State Management

- **Location:** `.autosuite/state.json` (repo-local, gitignored)
- **Schema version:** 1
- **Contents:**
  - `lastApplied` — manifest path, hash, timestamp
  - `lastVerify` — results, counts, timestamp
  - `appsObserved` — per-app installation status, version, driver

### Manifest System

- **Format:** JSONC (JSON with comments), JSON, YAML supported
- **Includes:** Recursive manifest composition with circular dependency detection
- **Locations:**
  - `provisioning/manifests/local/` — Machine-specific (gitignored)
  - `provisioning/manifests/examples/` — Sanitized shareable examples
  - `provisioning/manifests/includes/` — Modular restore/verify/manual fragments
  - `provisioning/manifests/*.jsonc` — Named profile manifests

---

## Partially Implemented / Stubs

### Command Verification in Apply

- `command-succeeds` verify type is referenced in `apply.ps1` but returns a stub message: "Command verification not yet implemented"

### Version Constraint Handling

- Exact (`1.2.3`) and minimum (`>=1.2.3`) constraints are implemented
- No support for: ranges, wildcards, or semantic versioning operators (`^`, `~`)
- Version mismatch for custom driver apps requires manual intervention (no auto-upgrade)

### Discovery Mode

- Detects non-winget-managed software via registry and file system probes
- Generates manual include file with suggestions
- **Limitation:** Detection is heuristic-based, may miss some software

### Diff Command

- `diff` command exists in `cli.ps1` and `engine/diff.ps1`
- Compares two plan/run artifacts
- **Not exposed** via root `autosuite.ps1` orchestrator

---

## Missing or Unimplemented Concepts

### Not Present in Code

1. **macOS/Linux support** — All drivers and paths are Windows-specific
2. **Rollback mechanism** — Backups are created but no automated rollback command
3. **Parallel installation** — Apps are installed sequentially
4. **Dependency ordering** — No explicit dependency graph between apps
5. **Pre/post hooks** — No lifecycle hooks for custom scripts before/after install
6. **Remote manifest fetching** — Manifests must be local files
7. **Credential/secret management** — Sensitive paths are warned but not handled
8. **GUI or TUI** — CLI only
9. **Scheduled/automated runs** — No built-in scheduler integration
10. **Cross-machine state sync** — Export/import exists but no automated sync

### Verify Types Not Implemented

- `command-succeeds` — Stub only
- `service-running` — Not present
- `env-var-set` — Not present

---

## Command-by-Command Behavior Summary

### `autosuite.ps1` (Root Orchestrator)

| Command | Behavior |
|---------|----------|
| `capture` | Delegates to provisioning CLI or runs sanitization logic locally |
| `apply` | Runs `Invoke-ApplyCore` locally with driver abstraction, then auto-verifies |
| `verify` | Runs `Invoke-VerifyCore` locally, updates state file |
| `plan` | Delegates to provisioning CLI |
| `report` | Runs `Invoke-ReportCore` locally, reads `.autosuite/state.json` |
| `doctor` | Runs `Invoke-DoctorCore` locally, checks winget and drift |
| `state reset` | Deletes `.autosuite/state.json` |
| `state export` | Exports state to file |
| `state import` | Imports state with merge or replace |
| `bootstrap` | Installs CLI to `%LOCALAPPDATA%\Autosuite\bin` |

### `provisioning/cli.ps1` (Provisioning Subsystem)

| Command | Behavior |
|---------|----------|
| `capture` | Runs `engine/capture.ps1`, uses `winget export` |
| `plan` | Runs `engine/plan.ps1`, compares manifest to `winget list` |
| `apply` | Runs `engine/apply.ps1`, executes plan actions |
| `restore` | Runs `engine/restore.ps1`, requires `-EnableRestore` |
| `verify` | Runs `engine/verify.ps1`, checks apps and verify items |
| `doctor` | Checks directories and winget availability |
| `report` | Runs `engine/report.ps1`, reads `provisioning/state/` |
| `diff` | Runs `engine/diff.ps1`, compares two artifacts |

**Note:** The root orchestrator and provisioning CLI have overlapping but different implementations for some commands (apply, verify, report). The root orchestrator's versions include additional state management and driver abstraction.

---

## Data Model Summary

### Manifest Schema

```jsonc
{
  "version": 1,                    // Schema version
  "name": "profile-name",          // Human-readable name
  "captured": "ISO-8601",          // Capture timestamp (optional)
  "includes": ["./path.jsonc"],    // Included manifests (optional)
  "apps": [
    {
      "id": "app-id",              // Platform-agnostic ID
      "refs": {
        "windows": "Winget.PackageId"
      },
      "version": ">=1.0.0",        // Version constraint (optional)
      "driver": "winget|custom",   // Driver type (optional, default: winget)
      "custom": {                  // Custom driver config (optional)
        "installScript": "./path.ps1",
        "detect": {
          "type": "file|registry",
          "path": "...",
          "key": "...",
          "value": "..."
        }
      }
    }
  ],
  "restore": [
    {
      "type": "copy|merge|append",
      "source": "./path",
      "target": "~/path",
      "backup": true,
      "format": "json|ini",        // For merge type
      "requiresAdmin": false
    }
  ],
  "verify": [
    {
      "type": "file-exists|command-exists|registry-key-exists",
      "path": "...",
      "command": "...",
      "name": "..."
    }
  ]
}
```

### State Schema (`.autosuite/state.json`)

```json
{
  "schemaVersion": 1,
  "lastApplied": {
    "manifestPath": "...",
    "manifestHash": "sha256-hex",
    "timestampUtc": "ISO-8601"
  },
  "lastVerify": {
    "manifestPath": "...",
    "manifestHash": "sha256-hex",
    "timestampUtc": "ISO-8601",
    "okCount": 0,
    "missingCount": 0,
    "versionMismatchCount": 0,
    "missingApps": [],
    "versionMismatchApps": [],
    "success": true
  },
  "appsObserved": {
    "Winget.PackageId": {
      "installed": true,
      "driver": "winget",
      "version": "1.2.3",
      "versionConstraint": ">=1.0.0",
      "versionSatisfied": true,
      "lastSeenUtc": "ISO-8601"
    }
  }
}
```

### Plan Schema (`provisioning/plans/*.json`)

```json
{
  "runId": "uuid",
  "timestamp": "ISO-8601",
  "manifest": {
    "path": "...",
    "name": "...",
    "hash": "sha256-short"
  },
  "summary": {
    "install": 0,
    "skip": 0,
    "restore": 0,
    "verify": 0
  },
  "actions": [
    {
      "type": "app|restore|verify",
      "id": "...",
      "ref": "...",
      "driver": "winget",
      "status": "install|skip|restore|verify",
      "reason": "..."
    }
  ]
}
```

### Run State Schema (`provisioning/state/*.json`)

```json
{
  "runId": "uuid",
  "timestamp": "ISO-8601",
  "machine": "COMPUTERNAME",
  "user": "USERNAME",
  "command": "apply|verify|restore",
  "dryRun": false,
  "manifest": {
    "path": "...",
    "hash": "..."
  },
  "summary": {
    "success": 0,
    "skipped": 0,
    "failed": 0
  },
  "actions": [...]
}
```

---

## Mental Model Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          autosuite.ps1                                      │
│                      (Root Orchestrator CLI)                                │
│  Commands: capture, apply, verify, plan, report, doctor, state, bootstrap   │
└─────────────────────────────────────────────────────────────────────────────┘
           │                        │                        │
           │ (delegates)            │ (local impl)           │ (local impl)
           ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────────┐
│ provisioning/   │    │ Invoke-ApplyCore    │    │ .autosuite/state.json   │
│ cli.ps1         │    │ Invoke-VerifyCore   │    │ (Local State Store)     │
│                 │    │ Invoke-ReportCore   │    │                         │
└─────────────────┘    │ Invoke-DoctorCore   │    │ - lastApplied           │
         │             └─────────────────────┘    │ - lastVerify            │
         ▼                        │               │ - appsObserved          │
┌─────────────────────────────────┴───────────────┴─────────────────────────┐
│                           provisioning/engine/                             │
│  capture.ps1 │ plan.ps1 │ apply.ps1 │ restore.ps1 │ verify.ps1 │ etc.     │
└─────────────────────────────────────────────────────────────────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────────┐
│ drivers/        │    │ restorers/          │    │ verifiers/              │
│ - winget.ps1    │    │ - copy.ps1          │    │ - file-exists.ps1       │
│                 │    │ - merge-json.ps1    │    │ - command-exists.ps1    │
│                 │    │ - merge-ini.ps1     │    │ - registry-key-exists   │
│                 │    │ - append.ps1        │    │                         │
└─────────────────┘    └─────────────────────┘    └─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SYSTEM                                         │
│                    (winget, filesystem, registry)                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
CAPTURE:
  winget export → parse JSON → filter apps → generate manifest → save .jsonc

PLAN:
  read manifest → resolve includes → winget list → compare → generate plan

APPLY:
  read manifest/plan → for each app:
    → check installed (driver) → install if missing → record result
  → run verify (optional) → update state

VERIFY:
  read manifest → for each app:
    → check installed (driver) → check version constraint
  → for each verify item:
    → run verifier
  → update state with results

RESTORE:
  read manifest → for each restore item:
    → expand paths → check sensitive → backup target → execute restorer

REPORT:
  read .autosuite/state.json → compute drift (optional) → output human/JSON
```

---

## Ambiguities and Unclear Intent

1. **Dual Implementation of Commands**
   - Both `autosuite.ps1` and `provisioning/cli.ps1` implement `apply`, `verify`, `report`
   - The root orchestrator's versions have different behavior (state management, driver abstraction)
   - *Inference:* Root orchestrator is the intended user-facing CLI; provisioning CLI is lower-level

2. **State File Location**
   - Root orchestrator uses `.autosuite/state.json` (repo root)
   - Provisioning subsystem uses `provisioning/state/*.json` (per-run files)
   - *Inference:* Two separate state systems exist; root orchestrator's is the "current" state

3. **Custom Driver Security**
   - Install scripts must be under repo root (path traversal prevention)
   - No signature verification or sandboxing
   - *Inference:* Trust model assumes user controls the repo

4. **Version Constraint on Custom Driver**
   - Version mismatch for custom apps reports "manual intervention needed"
   - No upgrade path for custom driver apps
   - *Inference:* Custom driver is for apps that can't be managed automatically

5. **Restore Opt-In**
   - Restore requires explicit `-EnableRestore` flag
   - *Inference:* Safety-first design; restore is considered higher-risk than install

---

## Test Coverage

The repository includes Pester tests in `tests/unit/Autosuite.Tests.ps1` covering:

- Banner and help display
- Command delegation
- Capture (default paths, example generation)
- Apply (dry-run, idempotent installs)
- Verify (structured results, exit codes)
- Report and Doctor (wrapper lines)
- State store (creation, read/write, atomic writes)
- Manifest hashing (deterministic, CRLF normalization)
- Drift detection
- State reset
- Version constraint parsing and comparison
- Driver abstraction

Tests use mock winget script and mock provisioning CLI for isolation.

---

## File Inventory

### Core Scripts

| File | Purpose |
|------|---------|
| `autosuite.ps1` | Root CLI orchestrator (~2365 lines) |
| `provisioning/cli.ps1` | Provisioning subsystem CLI (~633 lines) |

### Engine

| File | Purpose |
|------|---------|
| `engine/apply.ps1` | Apply execution logic |
| `engine/capture.ps1` | Capture via winget export |
| `engine/diff.ps1` | Artifact comparison |
| `engine/discovery.ps1` | Non-winget software detection |
| `engine/external.ps1` | External command helpers |
| `engine/logging.ps1` | Structured logging |
| `engine/manifest.ps1` | Manifest parsing/writing |
| `engine/plan.ps1` | Plan generation |
| `engine/report.ps1` | Report generation |
| `engine/restore.ps1` | Restore orchestration |
| `engine/state.ps1` | Run state management |
| `engine/verify.ps1` | Verification logic |

### Drivers

| File | Purpose |
|------|---------|
| `drivers/winget.ps1` | Winget installation driver |

### Restorers

| File | Purpose |
|------|---------|
| `restorers/copy.ps1` | File/directory copy |
| `restorers/merge-json.ps1` | JSON deep merge |
| `restorers/merge-ini.ps1` | INI file merge |
| `restorers/append.ps1` | Line append with dedup |
| `restorers/helpers.ps1` | Shared utilities |

### Verifiers

| File | Purpose |
|------|---------|
| `verifiers/file-exists.ps1` | File existence check |
| `verifiers/command-exists.ps1` | Command availability check |
| `verifiers/registry-key-exists.ps1` | Registry check |

---

*End of document.*
