# Podcast Tools

Scripts for podcast production workflows, including file organization and structure documentation.

---

## Scripts

### ExportPodcastTree.ps1

Exports the folder structure of a podcast project directory to a text file for documentation or reference.

#### Purpose

Provides a quick way to document the current state of a podcast project's file structure, useful for:
- Project documentation
- Backup verification
- Sharing structure with collaborators
- Archival records

#### Features

- **Full tree export** - Captures all files and subdirectories
- **Text output** - Simple, portable text format
- **Windows tree command** - Uses native `tree /F` for reliable output

#### Parameters

None (paths are currently hardcoded).

#### Current Configuration

| Setting | Value |
|---------|-------|
| Source Directory | `G:\My Drive\Podcasts\Together, Unprocessed Podcast` |
| Output File | `podcast-structure.txt` (in source directory) |

#### Usage

```powershell
# Run from any location
.\ExportPodcastTree.ps1
```

#### Output

Creates `podcast-structure.txt` in the podcast directory containing a tree view:

```
G:\MY DRIVE\PODCASTS\TOGETHER, UNPROCESSED PODCAST
├── Episodes/
│   ├── Episode 001/
│   │   ├── audio.wav
│   │   ├── notes.txt
│   │   └── ...
│   └── ...
├── Assets/
└── ...
```

#### Dependencies

- **tree** - Built into Windows
- **PowerShell 5.1+**

#### Limitations

- Hardcoded paths (requires script modification for different projects)
- No date stamping on output filename
- Overwrites previous output

---

## Planned Features

- Parameterized source and output paths
- Timestamped output filenames
- Episode metadata extraction
- RSS feed generation helpers
- Audio file validation (format, bitrate, duration)
- Transcript organization tools
