# mpv Configuration

## Authoritative Source

`profiles/mpv/` is the canonical source of truth for mpv configuration.

## Files

- `mpv.conf` - Main configuration
- `input.conf` - Key bindings

## Target Locations

- **Windows:** `%APPDATA%\mpv\`
- **Linux/macOS:** `~/.config/mpv/`

## Setup

### Method A: Symlink (Preferred)

**Windows (PowerShell as Administrator):**
```powershell
New-Item -ItemType SymbolicLink -Path "$env:APPDATA\mpv\mpv.conf" -Target "c:\Users\win-laptop\Desktop\projects\automation-suite\profiles\mpv\mpv.conf"
New-Item -ItemType SymbolicLink -Path "$env:APPDATA\mpv\input.conf" -Target "c:\Users\win-laptop\Desktop\projects\automation-suite\profiles\mpv\input.conf"
```

**Linux/macOS:**
```bash
ln -s ~/path/to/automation-suite/profiles/mpv/mpv.conf ~/.config/mpv/mpv.conf
ln -s ~/path/to/automation-suite/profiles/mpv/input.conf ~/.config/mpv/input.conf
```

### Method B: Copy (Fallback)

**Windows (PowerShell):**
```powershell
Copy-Item "c:\Users\win-laptop\Desktop\projects\automation-suite\profiles\mpv\mpv.conf" "$env:APPDATA\mpv\mpv.conf"
Copy-Item "c:\Users\win-laptop\Desktop\projects\automation-suite\profiles\mpv\input.conf" "$env:APPDATA\mpv\input.conf"
```

**Linux/macOS:**
```bash
cp ~/path/to/automation-suite/profiles/mpv/mpv.conf ~/.config/mpv/mpv.conf
cp ~/path/to/automation-suite/profiles/mpv/input.conf ~/.config/mpv/input.conf
```
