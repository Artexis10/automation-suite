# Live Chat Downloader

Download and convert YouTube live stream chat replays to readable text format.

---

## Quick Start

1. Add YouTube live stream URLs to `urls.txt` (one per line)
2. Run the download script:
   ```powershell
   .\download_chats_ytdlp.ps1
   ```
3. Find output in `output_ytdlp/`

---

## Scripts

### download_chats_ytdlp.ps1 (Recommended)

Uses yt-dlp to download chat and converts JSON to formatted text.

**Output format:**
```
[00:05:23 / 2024-01-15 19:05:23 UTC] [MSG] Username: Message text
[00:06:01 / 2024-01-15 19:06:01 UTC] [SUPERCHAT] Donor: Paid message
```

**Usage:**
```powershell
.\download_chats_ytdlp.ps1
.\download_chats_ytdlp.ps1 -YtDlpPath ".\yt-dlp.exe"
```

### download_chats.ps1 (Alternative)

Uses chat_downloader Python package.

**Usage:**
```powershell
.\download_chats.ps1
```

---

## Input

**urls.txt** - One URL per line:
```
https://www.youtube.com/live/VIDEO_ID_1
https://www.youtube.com/live/VIDEO_ID_2
```

---

## Output

| Script | Output Directory | Files |
|--------|------------------|-------|
| `download_chats_ytdlp.ps1` | `output_ytdlp/` | `.live_chat.json` + `.live_chat.txt` |
| `download_chats.ps1` | `output/` | `.txt` only |

---

## Dependencies

| Script | Dependency | Installation |
|--------|------------|--------------|
| `download_chats_ytdlp.ps1` | yt-dlp | `choco install yt-dlp` or `pip install yt-dlp` |
| `download_chats.ps1` | chat_downloader | `pip install chat-downloader` |

---

## Notes

- Both scripts skip already-downloaded videos
- UTF-8 encoding preserves emojis and special characters
- Only works with videos that have chat replay enabled
