# YouTube Tools

Utilities for YouTube content extraction and processing, with a focus on live chat archival.

---

## Live Chat Downloader

Located in: `live-chat-downloader/`

Tools for downloading and converting YouTube live stream chat replays to readable text format.

### Overview

Two scripts are provided, each using a different backend:

| Script | Backend | Best For |
|--------|---------|----------|
| `download_chats.ps1` | chat_downloader | Simpler setup, metadata-based naming |
| `download_chats_ytdlp.ps1` | yt-dlp | More reliable, better format support |

Both scripts:
- Read URLs from `urls.txt`
- Skip already-downloaded chats
- Generate human-readable output with timestamps

---

### download_chats_ytdlp.ps1 (Recommended)

Downloads live chat using yt-dlp and converts the JSON output to formatted plain text.

#### Features

- **yt-dlp backend** - Reliable, actively maintained
- **Dual output** - Both raw JSON and formatted text
- **Relative timestamps** - Shows time offset from stream start
- **Absolute timestamps** - UTC datetime for each message
- **Event classification** - Tags superchats, memberships, stickers
- **UTF-8 support** - Preserves emojis and special characters
- **Idempotent** - Skips videos with existing output

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-YtDlpPath` | string | `yt-dlp` | Path to yt-dlp executable |

#### Input

**urls.txt** - One YouTube URL per line:
```
https://www.youtube.com/live/VIDEO_ID_1
https://www.youtube.com/live/VIDEO_ID_2
```

#### Usage

```powershell
# Using yt-dlp from PATH
.\download_chats_ytdlp.ps1

# Using local yt-dlp.exe
.\download_chats_ytdlp.ps1 -YtDlpPath ".\yt-dlp.exe"
```

#### Output

Files are saved to `output_ytdlp/` with naming pattern:
```
YYYYMMDD - Title (VIDEO_ID).live_chat.json
YYYYMMDD - Title (VIDEO_ID).live_chat.txt
```

**Text format:**
```
[00:05:23 / 2024-01-15 19:05:23 UTC] [MSG] Username: Message text here
[00:06:01 / 2024-01-15 19:06:01 UTC] [SUPERCHAT] Donor: Thank you for the stream!
[00:07:45 / 2024-01-15 19:07:45 UTC] [MEMBERSHIP] NewMember: Just joined!
```

#### Event Types

| Tag | Description |
|-----|-------------|
| `[MSG]` | Regular chat message |
| `[SUPERCHAT]` | Paid message (Super Chat) |
| `[STICKER]` | Paid sticker |
| `[MEMBERSHIP]` | Membership event |

#### Dependencies

- **yt-dlp** - YouTube downloader
- **PowerShell 5.1+**

Installation:
```powershell
# Via Chocolatey
choco install yt-dlp

# Via pip
pip install yt-dlp

# Or download from https://github.com/yt-dlp/yt-dlp/releases
```

---

### download_chats.ps1 (Alternative)

Downloads live chat using the `chat_downloader` Python package.

#### Features

- **chat_downloader backend** - Python-based
- **Metadata extraction** - Fetches video title and publish date
- **Sanitized filenames** - Safe characters only
- **Text output** - Direct text format (no JSON intermediate)

#### Input

**urls.txt** - One YouTube URL per line (same format as above)

#### Usage

```powershell
.\download_chats.ps1
```

#### Output

Files are saved to `output/` with naming pattern:
```
YYYY-MM-DD__Sanitized_Title__VIDEO_ID.txt
```

#### Dependencies

- **chat_downloader** - Python package
- **PowerShell 5.1+**

Installation:
```powershell
pip install chat-downloader
```

---

## File Structure

```
live-chat-downloader/
├── download_chats.ps1          # chat_downloader backend
├── download_chats_ytdlp.ps1    # yt-dlp backend (recommended)
├── urls.txt                    # Input URLs (one per line)
├── output/                     # Output from download_chats.ps1
└── output_ytdlp/               # Output from download_chats_ytdlp.ps1
    ├── *.live_chat.json        # Raw JSON from yt-dlp
    └── *.live_chat.txt         # Converted text format
```

---

## Workflow

1. Add YouTube live stream URLs to `urls.txt`
2. Run the preferred script
3. Review output in the respective output folder
4. Re-run anytime to download new URLs (existing downloads are skipped)

---

## Troubleshooting

### "yt-dlp not found"
Ensure yt-dlp is installed and in PATH, or specify the path explicitly:
```powershell
.\download_chats_ytdlp.ps1 -YtDlpPath "C:\Tools\yt-dlp.exe"
```

### "chat_downloader not found"
Install via pip:
```powershell
pip install chat-downloader
```

### No chat data downloaded
- Verify the video has a chat replay available
- Some videos may have chat disabled or deleted
- Private/unlisted videos may not be accessible

### Encoding issues
Both scripts use UTF-8 encoding. If you see garbled text, ensure your text editor supports UTF-8.

---

## Planned Features

- Batch URL import from file or clipboard
- Chat statistics and analysis
- Search/filter functionality
- Export to other formats (CSV, HTML)
- Integration with video download
