# Cam Link 4K Device Management

PowerShell utilities to detect and resolve Elgato Cam Link 4K device contention on Windows.

## Problem

The Cam Link 4K is a **single-client UVC device**. Only one process can hold the video interface (`MI_00`) at a time. If any application opens the device before your target application (e.g., Riverside, Chrome WebRTC), camera access fails or 4K negotiation breaks.

Common offenders that hijack the device:
- Elgato Camera Hub (`CameraHub.exe`)
- OBS Studio (`obs64.exe`)
- NVIDIA Broadcast (`nvbroadcast.exe`)
- Discord (`Discord.exe`)
- Microsoft Teams (`ms-teams.exe`)
- Zoom (`Zoom.exe`)

## Prerequisites

These scripts require **Sysinternals Handle** (`handle64.exe`) to detect which processes hold device handles.

### Quick Setup

1. Download Sysinternals Handle from Microsoft:
   https://learn.microsoft.com/en-us/sysinternals/downloads/handle

2. Extract and copy `handle64.exe` to:
   ```
   %USERPROFILE%\Tools\Sysinternals\handle64.exe
   ```
   (e.g., `C:\Users\YourName\Tools\Sysinternals\handle64.exe`)

3. No PATH modification needed.

### Alternative Locations

The scripts search for `handle64.exe` in this order:

1. `$env:SYSINTERNALS_HANDLE` - Environment variable override (full path)
2. `%USERPROFILE%\Tools\Sysinternals\handle64.exe` - Default user location
3. `C:\Program Files\Sysinternals\handle64.exe` - System location
4. `PATH` - Fallback via `Get-Command`

To use a custom location, set the environment variable:
```powershell
$env:SYSINTERNALS_HANDLE = "D:\MyTools\handle64.exe"
```

## Usage

### Check Device Status

```powershell
.\Check-CamLink.ps1
```

Output when device is free:
```
Cam Link 4K Status: FREE
The device is available for use.
```

Output when device is in use:
```
Cam Link 4K Status: IN USE

Processes holding the device:
  - CameraHub.exe (PID: 12345)

Run Fix-CamLink.ps1 to terminate known offenders.
```

### Fix Device Contention

```powershell
.\Fix-CamLink.ps1
```

This script:
1. Checks current device status
2. Terminates known offender processes (ignores errors if not running)
3. Re-checks and reports final status

Example output:
```
=== Cam Link 4K Fix Utility ===

Checking device status...
Cam Link 4K Status: IN USE

Processes holding the device:
  - CameraHub.exe (PID: 12345)

Terminating known offenders...
  Terminating: CameraHub (PID: 12345)
  Terminated 1 process(es).

Re-checking device status...

Cam Link 4K Status: FREE
The device is now available for use.
```

## Notes

- Scripts are idempotent and safe to run repeatedly
- Elevation may be required to terminate some processes
- If an unknown process holds the device, you will need to terminate it manually
- Device identifier: VID_0FD9, PID_007B, MI_00

## Adding New Offenders

Edit `Fix-CamLink.ps1` and add the process name (without `.exe`) to the `$KnownOffenders` array:

```powershell
$KnownOffenders = @(
    'CameraHub'
    'obs64'
    'nvbroadcast'
    'Discord'
    'ms-teams'
    'Zoom'
    'YourNewOffender'  # Add here
)
```
