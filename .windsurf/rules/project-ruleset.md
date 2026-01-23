---
trigger: always_on
---

# Automation Suite Project Ruleset

This ruleset governs development and operation of the Automation Suite repository.

---

## Important: Provisioning Has Moved

**The provisioning system has been split into a separate repository: [github.com/Artexis10/endstate](https://github.com/Artexis10/endstate)**

This repository (`automation-suite`) now contains only:
- Backup tools
- Media processing utilities
- YouTube tools
- Podcast tools
- Archive setup scripts

---

## Repository Structure

```
automation-suite/
├── backup-tools/           # File backup and integrity verification
├── media-tools/            # Photo/video processing utilities
├── podcast-tools/          # Podcast production helpers
├── youtube-tools/          # YouTube content utilities
├── archive-setup/          # Environment and archive setup scripts
├── provisioning/           # STUB ONLY - migration notice to separate repo
├── scripts/                # Test runner scripts
├── tools/                  # Vendored dependencies (Pester)
└── tests/                  # Pester tests
    ├── unit/               # Unit tests (no external deps)
    ├── integration/        # Integration tests
    ├── fixtures/           # Test fixtures
    ├── run-tests.ps1       # Canonical test entrypoint
    └── TestHelpers.ps1     # Shared test utilities
```

---

## PowerShell Compatibility

**All code must be compatible with Windows PowerShell 5.1** (`powershell.exe`).

Do NOT use PowerShell 7-only features:
- No `??` null-coalescing operator
- No `?.` null-conditional operator
- No `ForEach-Object -Parallel`
- No `$PSStyle`
- No ternary operator `? :`

---

## Testing

### Test Framework

- **Pester v5.7.1** (vendored in `tools/pester/`)
- Tests run under **Windows PowerShell 5.1**
- Configuration via `pester.config.ps1`

### Test Categories

| Tag | Description | Default |
|-----|-------------|---------|
| (none) | Unit tests | Included |
| `Integration` | Integration tests | Excluded |
| `OptionalTooling` | Requires ffmpeg/ffprobe/yt-dlp | Excluded |

### Running Tests

**Primary entrypoint:** `tests/run-tests.ps1`

```powershell
# Unit tests only (default, CI)
.\tests\run-tests.ps1

# Include integration tests
.\tests\run-tests.ps1 -Integration

# Include optional tooling tests (requires ffmpeg/ffprobe)
.\tests\run-tests.ps1 -OptionalTooling

# All tests
.\tests\run-tests.ps1 -All
```

**Advanced/Manual:** Direct `Invoke-Pester` usage

```powershell
Invoke-Pester -Configuration (& .\pester.config.ps1)
Invoke-Pester -Configuration (& .\pester.config.ps1 -IncludeIntegration)
```

### Test Helpers

`tests/TestHelpers.ps1` provides:
- `Get-RepoRoot` - Returns repository root path
- `New-TestSandbox` - Creates unique temp directory for test isolation
- `Test-HasCommand` - Checks if a command exists
- `Invoke-ToolScript` - Runs a script in PS 5.1 subprocess with captured output
- `Skip-IfMissingCommand` - Skips test if required command is missing

### Writing Tests

1. Dot-source `TestHelpers.ps1` in `BeforeAll`
2. Use `New-TestSandbox` for file operations
3. Clean up sandbox in `AfterEach`
4. Tag tests requiring external tools with `OptionalTooling`
5. Use `Skip-IfMissingCommand` for graceful skipping

---

## CI (GitHub Actions)

Location: `.github/workflows/ci.yml`

### CI Configuration

- **Runner:** `windows-latest`
- **Shell:** `powershell` (Windows PowerShell 5.1)
- **Tests:** Unit tests only (Integration and OptionalTooling excluded)
- **Output:** `tests/test-results.xml` (NUnit format)

### CI Triggers

- Push to `main`
- Pull requests to `main`
- Excludes: `**/*.md`, `docs/**`

---

## Tools

| Folder | Purpose | Dependencies |
|--------|---------|--------------|
| `backup-tools/` | XMP backup, hash generation | robocopy (built-in) |
| `media-tools/` | Audio/video conversion | ffmpeg, ffprobe (optional) |
| `podcast-tools/` | Podcast folder export | tree (built-in) |
| `youtube-tools/` | Live chat download | yt-dlp, chat_downloader (optional) |
| `archive-setup/` | Archive folder setup | None |

---

## Change Management

### Ruleset Sync

If any of the following change, update this ruleset in the same commit:
- Test commands or configuration
- CI workflow
- Directory structure
- New test categories or tags

---

## References

- [README.md](../../README.md) - Project overview
- [TOOL-INDEX.md](../../TOOL-INDEX.md) - Complete script index
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Development conventions
- [provisioning/README.md](../../provisioning/README.md) - Migration notice to separate provisioning repo
