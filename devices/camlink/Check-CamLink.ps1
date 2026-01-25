<#
.SYNOPSIS
    Checks if the Elgato Cam Link 4K is currently in use by any process.

.DESCRIPTION
    Uses Sysinternals handle64.exe to detect whether the Cam Link 4K video interface
    (VID_0FD9, PID_007B, MI_00) is currently held by any process.

    The Cam Link 4K is a single-client UVC device. If any process opens the video
    interface before WebRTC applications (e.g., Riverside/Chrome), camera access
    or 4K negotiation will fail.

.OUTPUTS
    Prints device status: FREE or IN USE
    If IN USE, prints the process name(s) and PID(s) holding the device.

.EXAMPLE
    .\Check-CamLink.ps1

.NOTES
    Requires Sysinternals handle64.exe. See README.md for setup instructions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cam Link 4K device identifiers
$VID = '0FD9'
$PID_DEVICE = '007B'
$INTERFACE = 'MI_00'

function Find-Handle64 {
    <#
    .SYNOPSIS
        Locates handle64.exe using a priority-based search.
    #>
    
    # 1. Environment variable override
    if ($env:SYSINTERNALS_HANDLE -and (Test-Path -LiteralPath $env:SYSINTERNALS_HANDLE)) {
        return $env:SYSINTERNALS_HANDLE
    }
    
    # 2. Default user location
    $userPath = Join-Path $env:USERPROFILE 'Tools\Sysinternals\handle64.exe'
    if (Test-Path -LiteralPath $userPath) {
        return $userPath
    }
    
    # 3. System location
    $systemPath = 'C:\Program Files\Sysinternals\handle64.exe'
    if (Test-Path -LiteralPath $systemPath) {
        return $systemPath
    }
    
    # 4. PATH fallback
    $pathCmd = Get-Command -Name 'handle64.exe' -ErrorAction SilentlyContinue
    if ($pathCmd) {
        return $pathCmd.Source
    }
    
    return $null
}

function Get-CamLinkStatus {
    <#
    .SYNOPSIS
        Returns the current status of the Cam Link 4K device.
    .OUTPUTS
        PSCustomObject with properties:
        - Status: 'FREE' or 'IN_USE'
        - Processes: Array of objects with Name and PID (empty if FREE)
    #>
    
    $handleExe = Find-Handle64
    
    if (-not $handleExe) {
        $searchedLocations = @(
            "  1. `$env:SYSINTERNALS_HANDLE (not set or file not found)"
            "  2. $env:USERPROFILE\Tools\Sysinternals\handle64.exe"
            "  3. C:\Program Files\Sysinternals\handle64.exe"
            "  4. PATH (handle64.exe not found)"
        )
        
        $errorMsg = @(
            "ERROR: handle64.exe not found."
            ""
            "Searched locations:"
            $searchedLocations
            ""
            "To fix:"
            "  1. Download Sysinternals Handle from:"
            "     https://learn.microsoft.com/en-us/sysinternals/downloads/handle"
            "  2. Extract and copy handle64.exe to:"
            "     %USERPROFILE%\Tools\Sysinternals\handle64.exe"
            "  3. (Optional) Set SYSINTERNALS_HANDLE environment variable to override location."
        ) -join "`n"
        
        throw $errorMsg
    }
    
    # Build the device path pattern to search for
    # Cam Link 4K appears as: \Device\XXXXXXXX#vid_0fd9&pid_007b&mi_00#XXXXXXXX
    $searchPattern = "vid_$VID&pid_$PID_DEVICE&mi_$INTERFACE"
    
    # Run handle64.exe to find all handles matching the pattern
    # -a: show all handles
    # -nobanner: suppress banner
    $handleOutput = & $handleExe -a -nobanner 2>&1
    
    # Filter for lines containing our device pattern (case-insensitive)
    $matchingLines = $handleOutput | Where-Object { 
        $_ -is [string] -and $_ -match [regex]::Escape($searchPattern) 
    }
    
    $processes = @()
    
    foreach ($line in $matchingLines) {
        # handle64 output format: "ProcessName pid: PID type handle: path"
        # Example: "CameraHub.exe pid: 1234 type: File 1A4: \Device\..."
        if ($line -match '^(\S+)\s+pid:\s*(\d+)') {
            $processes += [PSCustomObject]@{
                Name = $Matches[1]
                PID  = [int]$Matches[2]
            }
        }
    }
    
    # Deduplicate by PID (a process may hold multiple handles)
    $uniqueProcesses = @($processes | Sort-Object -Property PID -Unique)
    
    if ($uniqueProcesses.Count -eq 0) {
        return [PSCustomObject]@{
            Status    = 'FREE'
            Processes = @()
        }
    }
    else {
        return [PSCustomObject]@{
            Status    = 'IN_USE'
            Processes = $uniqueProcesses
        }
    }
}

# Main execution
try {
    $status = Get-CamLinkStatus
    
    if ($status.Status -eq 'FREE') {
        Write-Host "Cam Link 4K Status: FREE" -ForegroundColor Green
        Write-Host "The device is available for use."
    }
    else {
        Write-Host "Cam Link 4K Status: IN USE" -ForegroundColor Red
        Write-Host ""
        Write-Host "Processes holding the device:"
        foreach ($proc in $status.Processes) {
            Write-Host "  - $($proc.Name) (PID: $($proc.PID))" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Run Fix-CamLink.ps1 to terminate known offenders."
    }
    
    # Return status object for programmatic use
    return $status
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
