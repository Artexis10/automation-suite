<#
.SYNOPSIS
    Frees the Elgato Cam Link 4K by terminating known offender processes.

.DESCRIPTION
    Checks if the Cam Link 4K is in use, and if so, terminates known applications
    that commonly hijack the device. After termination, re-checks the device state.

    Known offenders:
    - CameraHub.exe (Elgato Camera Hub)
    - obs64.exe (OBS Studio)
    - nvbroadcast.exe (NVIDIA Broadcast)
    - Discord.exe
    - ms-teams.exe (Microsoft Teams)
    - Zoom.exe

.OUTPUTS
    Prints actions taken and final device status.

.EXAMPLE
    .\Fix-CamLink.ps1

.NOTES
    Requires Sysinternals handle64.exe. See README.md for setup instructions.
    This script requires elevation to terminate some processes.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Known offender process names (without .exe extension for Stop-Process)
$KnownOffenders = @(
    'CameraHub'
    'obs64'
    'nvbroadcast'
    'Discord'
    'ms-teams'
    'Zoom'
)

# Cam Link 4K device identifiers
$VID = '0FD9'
$PID_DEVICE = '007B'
$INTERFACE = 'MI_00'

function Find-Handle64 {
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
    
    $searchPattern = "vid_$VID&pid_$PID_DEVICE&mi_$INTERFACE"
    $handleOutput = & $handleExe -a -nobanner 2>&1
    
    $matchingLines = $handleOutput | Where-Object { 
        $_ -is [string] -and $_ -match [regex]::Escape($searchPattern) 
    }
    
    $processes = @()
    
    foreach ($line in $matchingLines) {
        if ($line -match '^(\S+)\s+pid:\s*(\d+)') {
            $processes += [PSCustomObject]@{
                Name = $Matches[1]
                PID  = [int]$Matches[2]
            }
        }
    }
    
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

function Stop-KnownOffenders {
    <#
    .SYNOPSIS
        Terminates known offender processes. Ignores errors if processes are not running.
    #>
    
    $terminated = @()
    
    foreach ($offender in $KnownOffenders) {
        $procs = Get-Process -Name $offender -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($proc in $procs) {
                try {
                    Write-Host "  Terminating: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    $terminated += [PSCustomObject]@{
                        Name = $proc.ProcessName
                        PID  = $proc.Id
                    }
                }
                catch {
                    Write-Host "  Warning: Could not terminate $($proc.ProcessName) (PID: $($proc.Id)): $($_.Exception.Message)" -ForegroundColor DarkYellow
                }
            }
        }
    }
    
    return $terminated
}

# Main execution
try {
    Write-Host "=== Cam Link 4K Fix Utility ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Initial check
    Write-Host "Checking device status..." -ForegroundColor Cyan
    $initialStatus = Get-CamLinkStatus
    
    if ($initialStatus.Status -eq 'FREE') {
        Write-Host "Cam Link 4K Status: FREE" -ForegroundColor Green
        Write-Host "The device is already available. No action needed."
        exit 0
    }
    
    Write-Host "Cam Link 4K Status: IN USE" -ForegroundColor Red
    Write-Host ""
    Write-Host "Processes holding the device:"
    foreach ($proc in $initialStatus.Processes) {
        Write-Host "  - $($proc.Name) (PID: $($proc.PID))" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Terminate known offenders
    Write-Host "Terminating known offenders..." -ForegroundColor Cyan
    $terminated = Stop-KnownOffenders
    
    if ($terminated.Count -eq 0) {
        Write-Host "  No known offenders were running." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Terminated $($terminated.Count) process(es)." -ForegroundColor Green
    }
    Write-Host ""
    
    # Brief pause to allow handles to release
    Start-Sleep -Milliseconds 500
    
    # Re-check status
    Write-Host "Re-checking device status..." -ForegroundColor Cyan
    $finalStatus = Get-CamLinkStatus
    
    Write-Host ""
    if ($finalStatus.Status -eq 'FREE') {
        Write-Host "Cam Link 4K Status: FREE" -ForegroundColor Green
        Write-Host "The device is now available for use."
        exit 0
    }
    else {
        Write-Host "Cam Link 4K Status: STILL IN USE" -ForegroundColor Red
        Write-Host ""
        Write-Host "Remaining processes holding the device:"
        foreach ($proc in $finalStatus.Processes) {
            Write-Host "  - $($proc.Name) (PID: $($proc.PID))" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "These processes are not in the known offenders list."
        Write-Host "You may need to manually terminate them or add them to the offenders list."
        exit 1
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
