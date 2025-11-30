# Roadmap

Future development plans for the automation-suite repository.

---

## Current Status

**Version:** 0.1.0  
**Last Updated:** November 2025

### Implemented

- [x] XMP backup with manifest generation (`Backup-XMPs.ps1`)
- [x] MKV audio conversion for S95C (`Convert-Unsupported-Audio-for-S95C.ps1`)
- [x] YouTube live chat download via yt-dlp (`download_chats_ytdlp.ps1`)
- [x] YouTube live chat download via chat_downloader (`download_chats.ps1`)
- [x] Podcast structure export (`ExportPodcastTree.ps1`)
- [x] Repository documentation and structure

### Stubs (Planned)

- [ ] SHA256 hash generation (`HashAll.ps1`)
- [ ] Hash comparison tool (`CompareHashes.ps1`)
- [ ] Trip view photo organizer (`New-TripView.ps1`)
- [ ] Archive structure setup (`Setup-ArchiveStructure.ps1`)

---

## Short-Term (Next Release)

### Backup Tools

- **HashAll.ps1** - Full implementation
  - Recursive directory scanning
  - SHA256SUMS.txt output (GNU coreutils compatible)
  - Progress indicator for large directories
  - Exclude patterns support

- **CompareHashes.ps1** - Full implementation
  - Diff report (added, removed, modified, unchanged)
  - Exit codes for scripting
  - Optional detailed output

### YouTube Tools

- **Chat filtering** - Filter by message type, author, keywords
- **Chat statistics** - Message counts, top chatters, activity timeline
- **Batch URL management** - Import URLs from clipboard or file

---

## Medium-Term

### Backup Tools

- **Backup verification** - Compare source and destination integrity
- **Incremental hash updates** - Only hash new/modified files
- **Backup scheduling** - Windows Task Scheduler integration
- **Notification system** - Email/webhook on completion or failure

### Media Tools

- **Photo organization**
  - EXIF metadata extraction
  - Date-based folder organization
  - Duplicate detection (hash-based)
  - RAW + JPEG pairing

- **Video utilities**
  - Thumbnail generation
  - Duration/codec summary
  - Batch transcoding presets

- **New-TripView.ps1** - Full implementation
  - Trip/event metadata input
  - Symlink or copy modes
  - Date range filtering

### Podcast Tools

- **Parameterized export** - Configurable source/destination
- **Episode metadata extraction** - Duration, file sizes, formats
- **RSS feed helpers** - Generate or validate podcast RSS

### Setup

- **Setup-ArchiveStructure.ps1** - Full implementation
  - Template-based folder creation
  - README generation per folder
  - Configurable structure

- **Setup-Dependencies.ps1** - Automated tool installation
  - ffmpeg, yt-dlp, chat_downloader
  - Version checking
  - PATH configuration

---

## Long-Term

### Cross-Platform Support

- Bash equivalents for Linux/macOS
- Python alternatives for complex scripts
- Docker containers for isolated execution

### Integration

- **Cloud sync** - Integration with rclone for cloud backup
- **NAS support** - SMB/NFS path handling
- **API integrations** - YouTube Data API, cloud storage APIs

### Automation

- **Workflow orchestration** - Chain multiple tools
- **Event triggers** - File system watchers
- **Reporting dashboard** - Web-based status overview

### Archive Management

- **Catalog system** - Searchable index of archived content
- **Deduplication** - Cross-archive duplicate detection
- **Integrity monitoring** - Scheduled hash verification

---

## Ideas / Backlog

Items under consideration but not yet prioritized:

- Lightroom catalog backup
- Photo watermarking tool
- Video chapter marker extraction
- Subtitle extraction and conversion
- Audio normalization batch tool
- Disk space analyzer
- File age reporter (find old files)
- Symbolic link manager
- Config file backup (dotfiles)

---

## Completed

### v0.1.0 (November 2025)

- Initial repository formalization
- Documentation structure established
- Existing tools documented
- TOOL_INDEX.md created
- CONTRIBUTING.md created
- Per-folder README files

---

## Contributing Ideas

To suggest new tools or features:

1. Open an issue (if using GitHub)
2. Add to the "Ideas / Backlog" section
3. Include use case and expected behavior

Priority is given to tools that:
- Automate repetitive tasks
- Protect data integrity
- Integrate with existing workflows
