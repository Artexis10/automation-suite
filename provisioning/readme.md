# Provisioning Has Moved

> **⚠️ DEPRECATED** — This folder is a stub. The provisioning system has moved to its own repository.

## New Location

**[Autosuite](https://github.com/Artexis10/autosuite)** — Standalone machine provisioning and configuration management tool.

## Migration

```powershell
# Clone the new repository
git clone https://github.com/Artexis10/autosuite.git
cd autosuite

# Use the CLI
.\cli.ps1 capture
.\cli.ps1 apply -Manifest manifests/my-machine.jsonc
```

## What Remains in automation-suite?

This repository (`automation-suite`) continues to host:

- **backup-tools/** — File backup and integrity verification
- **media-tools/** — Photo/video processing utilities  
- **podcast-tools/** — Podcast production helpers
- **youtube-tools/** — YouTube content utilities
- **archive-setup/** — Environment setup scripts

---

**For provisioning, use [Autosuite](https://github.com/Artexis10/autosuite).**
