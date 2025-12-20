<#
.SYNOPSIS
    Test helper functions for Pester tests in automation-suite.

.DESCRIPTION
    Provides common utilities for test setup, sandbox creation, and tool invocation.
    All functions are compatible with Windows PowerShell 5.1.

.NOTES
    This file should be dot-sourced in BeforeAll blocks of test files.
#>

# Strict mode for catching common errors
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Returns the repository root path.
#>
function Get-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    # Walk up from this script's location to find repo root
    $current = $PSScriptRoot
    while ($current -and -not (Test-Path (Join-Path $current ".git"))) {
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            # Reached filesystem root without finding .git
            throw "Could not find repository root (no .git folder found)"
        }
        $current = $parent
    }
    
    if (-not $current) {
        throw "Could not determine repository root"
    }
    
    return $current
}

<#
.SYNOPSIS
    Creates a unique temporary sandbox directory for test isolation.

.DESCRIPTION
    Creates a uniquely-named directory under $env:TEMP for test isolation.
    Returns a hashtable with the sandbox path. Caller is responsible for cleanup.

.PARAMETER Prefix
    Optional prefix for the sandbox folder name. Default: "autosuite-test"

.OUTPUTS
    Hashtable with:
    - Path: Full path to the sandbox directory
    - Cleanup: ScriptBlock to remove the sandbox (best-effort)
#>
function New-TestSandbox {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prefix = "autosuite-test"
    )
    
    $uniqueId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $sandboxPath = Join-Path $env:TEMP "$Prefix-$uniqueId"
    
    # Create the directory
    $null = New-Item -ItemType Directory -Path $sandboxPath -Force
    
    # Return sandbox info with cleanup scriptblock
    return @{
        Path = $sandboxPath
        Cleanup = { 
            param([string]$SandboxToClean)
            if (Test-Path $SandboxToClean) {
                Remove-Item -Path $SandboxToClean -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

<#
.SYNOPSIS
    Tests whether a command exists in the current environment.

.PARAMETER Name
    The command name to check (e.g., "ffmpeg", "git").

.OUTPUTS
    Boolean indicating whether the command exists.
#>
function Test-HasCommand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    
    $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

<#
.SYNOPSIS
    Invokes a PowerShell script using Windows PowerShell 5.1 (powershell.exe).

.DESCRIPTION
    Runs a script in a clean PowerShell 5.1 process with -NoProfile -NonInteractive
    -ExecutionPolicy Bypass. Captures stdout/stderr to files in the sandbox.

.PARAMETER ScriptPath
    Full path to the script to execute.

.PARAMETER Arguments
    Optional hashtable of arguments to pass to the script.

.PARAMETER WorkingDirectory
    Working directory for the script execution.

.PARAMETER SandboxPath
    Path to sandbox directory where logs will be written.

.OUTPUTS
    Hashtable with:
    - ExitCode: Process exit code
    - StdOutPath: Path to stdout log file
    - StdErrPath: Path to stderr log file
    - StdOut: Content of stdout (string)
    - StdErr: Content of stderr (string)
#>
function Invoke-ToolScript {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Arguments = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$SandboxPath
    )
    
    # Validate script exists
    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }
    
    # Ensure sandbox exists
    if (-not (Test-Path $SandboxPath)) {
        $null = New-Item -ItemType Directory -Path $SandboxPath -Force
    }
    
    # Generate unique log file names
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $uniqueId = [guid]::NewGuid().ToString('N').Substring(0, 4)
    $stdOutPath = Join-Path $SandboxPath "stdout-$timestamp-$uniqueId.log"
    $stdErrPath = Join-Path $SandboxPath "stderr-$timestamp-$uniqueId.log"
    
    # Build argument string for the script
    $argString = ""
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [switch] -or $value -eq $true) {
            $argString += " -$key"
        } elseif ($value -eq $false) {
            # Skip false switches
        } elseif ($value -is [string] -and $value -match '\s') {
            $argString += " -$key `"$value`""
        } else {
            $argString += " -$key $value"
        }
    }
    
    # Build the command to execute
    $command = "& `"$ScriptPath`"$argString"
    
    # Prepare process start info
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$command`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    
    if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    
    # Start the process
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    
    try {
        $null = $process.Start()
        
        # Read output streams
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
    
    # Write logs to files
    Set-Content -Path $stdOutPath -Value $stdout -Encoding UTF8
    Set-Content -Path $stdErrPath -Value $stderr -Encoding UTF8
    
    return @{
        ExitCode = $exitCode
        StdOutPath = $stdOutPath
        StdErrPath = $stdErrPath
        StdOut = $stdout
        StdErr = $stderr
    }
}

<#
.SYNOPSIS
    Skips a test if a required command is not available.

.DESCRIPTION
    Use this in BeforeAll or It blocks to skip tests that require optional tooling.

.PARAMETER CommandName
    The command that must be available.

.PARAMETER TestName
    Description of what's being skipped (for the skip message).
#>
function Skip-IfMissingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [Parameter(Mandatory = $false)]
        [string]$TestName = "this test"
    )
    
    if (-not (Test-HasCommand -Name $CommandName)) {
        Set-ItResult -Skipped -Because "$CommandName not found; skipping $TestName"
    }
}

# Note: Functions are available when this file is dot-sourced
# No Export-ModuleMember needed since this is not a module
