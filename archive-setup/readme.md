# Archive Setup

Environment and archive structure initialization scripts.

---

## Scripts

### Setup-ArchiveStructure.ps1

**Status:** Stub

Creates the initial folder skeleton for a personal archive system.

#### Intended Purpose

Initialize a standardized directory structure for organizing:
- Camera imports
- Project files
- System backups
- Logs
- Exports

#### Planned Features

- Configurable base path
- Template-based folder creation
- Permission setting
- README generation in each folder
- Integration with backup tools

---

## Planned Scripts

### Setup-Dependencies.ps1

Automated installation of required external tools:
- ffmpeg / ffprobe
- yt-dlp
- chat_downloader
- Other utilities

### Setup-ScheduledTasks.ps1

Configure Windows Task Scheduler for automated:
- Backup jobs
- Maintenance tasks
- Sync operations

---

## Archive Structure Template

The intended archive structure (to be implemented):

```
Archive Root/
├── 00 Inbox/              # Unsorted incoming files
├── 05 Logs/               # Operation logs
│   ├── XMP Backup/
│   └── ...
├── 10 Cameras/            # Camera imports by date/device
├── 20 Projects/           # Active project files
├── 30 Exports/            # Final exports and deliverables
├── 40 Reference/          # Reference materials
├── 50 Archive/            # Cold storage / completed projects
├── 60 System/             # System files and configs
└── 70 System Backups/     # Backup destinations
    ├── XMPs/
    └── ...
```
