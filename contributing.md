# Contributing

Development conventions for the automation-suite repository.

This is a single-author repository. These guidelines ensure consistency and maintainability as the toolkit grows.

---

## Branching Strategy

### Branch Types

| Branch | Purpose | Naming |
|--------|---------|--------|
| `main` | Stable, production-ready code | - |
| `develop` | Integration branch for features | - |
| `feature/*` | New tools or capabilities | `feature/tool-name` |
| `fix/*` | Bug fixes | `fix/issue-description` |
| `docs/*` | Documentation updates | `docs/topic` |
| `refactor/*` | Code restructuring | `refactor/scope` |

### Workflow

1. Create feature branch from `develop`
2. Implement and test changes
3. Merge to `develop` via pull request (or direct merge for small changes)
4. Periodically merge `develop` to `main` for releases

For small fixes or documentation updates, direct commits to `develop` are acceptable.

---

## Commit Conventions

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature or tool |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `refactor` | Code restructuring (no functional change) |
| `style` | Formatting, whitespace (no functional change) |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks, dependency updates |

### Scope

Use the tool or folder name:
- `backup` - backup-tools
- `media` - media-tools
- `podcast` - podcast-tools
- `youtube` - youtube-tools
- `setup` - archive-setup
- `provisioning` - provisioning
- `root` - Root-level files

### Examples

```
feat(youtube): add superchat filtering to chat downloader

fix(backup): handle paths with special characters

docs(media): update S95C converter usage guide

refactor(youtube): extract JSON parsing to separate function

chore: update .gitignore for Python virtual environments
```

### Subject Guidelines

- Use imperative mood ("add" not "added")
- No period at the end
- Maximum 50 characters
- Lowercase (except proper nouns)

---

## Code Style

### PowerShell

- Use `PascalCase` for function names and parameters
- Use `$camelCase` for local variables
- Include comment-based help for all public functions
- Use `[CmdletBinding()]` for advanced functions
- Prefer named parameters over positional

```powershell
<#
.SYNOPSIS
Brief description.

.DESCRIPTION
Detailed description.

.PARAMETER Name
Parameter description.

.EXAMPLE
.\Script.ps1 -Name "Value"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Name
)
```

### File Naming

| Type | Convention | Example |
|------|------------|---------|
| PowerShell scripts | `Verb-Noun.ps1` | `Backup-XMPs.ps1` |
| Python scripts | `snake_case.py` | `download_chats.py` |
| Documentation | `UPPERCASE.md` or `Title Case.md` | `README.md`, `USAGE_GUIDE.md` |
| Config files | `lowercase` | `.gitignore`, `urls.txt` |

## Documentation Conventions

Canonical project documents (README.md, CONTRIBUTING.md, etc.) use UPPERCASE filenames. All supporting documentation uses lowercase filenames. See `.windsurf/rules/project-ruleset.md` for the authoritative naming convention rules.

### Folder Naming

- Use lowercase kebab-case for all directories: `backup-tools`, `media-tools`
- Use descriptive kebab-case names for subfolders: `live-chat-downloader`

---

## Documentation Standards

### README Files

Each folder should have a `README.md` containing:

1. **Title and description**
2. **Scripts list** with brief descriptions
3. **For each script:**
   - Purpose
   - Parameters table
   - Usage examples
   - Dependencies
   - Output description
4. **Planned features** (optional)

### Script Documentation

Every implemented script should include:

1. **Comment-based help** (PowerShell) or docstrings (Python)
2. **Parameter descriptions**
3. **At least one usage example**
4. **Dependencies listed**

---

## Testing

### Manual Testing Checklist

Before committing:

- [ ] Script runs without errors
- [ ] Dry-run mode works (if applicable)
- [ ] Output is correct
- [ ] Edge cases handled (empty input, missing files, etc.)
- [ ] No hardcoded paths (or documented if intentional)

### Test Data

- Do not commit test data to the repository
- Use `.gitignore` to exclude output directories
- Document test scenarios in script comments

---

## Versioning

### Semantic Versioning

Format: `MAJOR.MINOR.PATCH`

- **MAJOR** - Breaking changes, significant restructuring
- **MINOR** - New tools, features, backward-compatible changes
- **PATCH** - Bug fixes, documentation updates

### Version Bumping

Update version in:
1. `README.md` (Current version line)
2. Git tag: `git tag -a v1.2.3 -m "Release 1.2.3"`

---

## Release Process

1. Ensure all changes are committed to `develop`
2. Update version number
3. Update `roadmap.md` (move completed items)
4. Merge `develop` to `main`
5. Create git tag
6. (Optional) Create GitHub release with changelog

---

## Adding New Tools

### Checklist

1. [ ] Create script in appropriate folder
2. [ ] Add comment-based help
3. [ ] Update folder `README.md`
4. [ ] Update `tool-index.md`
5. [ ] Update root `README.md` (tool table)
6. [ ] Test thoroughly
7. [ ] Commit with `feat(<scope>): add <tool-name>`

### Folder Selection

| Tool Type | Folder |
|-----------|--------|
| File backup, hashing, verification | `backup-tools/` |
| Photo/video processing | `media-tools/` |
| Podcast production | `podcast-tools/` |
| YouTube utilities | `youtube-tools/` |
| Environment setup | `archive-setup/` |
| Machine provisioning | `provisioning/` |
| General utilities | Root or new category |

---

## Questions and Decisions

For significant changes, document the decision rationale in commit messages or create a `docs/decisions/` folder for Architecture Decision Records (ADRs) if needed.
