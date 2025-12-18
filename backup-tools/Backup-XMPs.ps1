<# Backup-XMPs.ps1 — backs up *.xmp preserving structure (safe, no deletes) #>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [string]$Source = "D:\Archive\Personal Archive\10 Cameras",

  [Parameter(Mandatory=$false)]
  [string]$Destination = "D:\Archive\Personal Archive\70 System Backups\XMPs",

  # Central logs root (all logs & manifests go here)
  [Parameter(Mandatory=$false)]
  [string]$LogsRoot = "D:\Archive\Personal Archive\05 Logs\XMP Backup",

  [switch]$DryRun,
  [switch]$MakeManifest,
  [switch]$Hash,

  [int]$Threads = 16,
  [int]$Retries = 5,
  [int]$WaitSec = 3,

  # Optional housekeeping: keep only N most recent logs/manifests (0 = keep all)
  [int]$KeepRecent = 12
)

function Ensure-Folder { param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

# Validate source
if (-not (Test-Path -LiteralPath $Source)) {
  Write-Error "Source not found: $Source"; exit 1
}

# Prepare logging paths under 05 Logs
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogDir    = $LogsRoot
$ManDir    = Join-Path $LogsRoot "_manifests"
Ensure-Folder -Path $LogDir
Ensure-Folder -Path $ManDir
$LogFile   = Join-Path $LogDir ("xmp_backup_{0}.log" -f $TimeStamp)

# Build ROBOCOPY args
$robo = @(
  $Source, $Destination, '*.xmp',
  '/S','/XO','/COPY:DAT','/DCOPY:T','/FFT',
  '/NP','/NFL','/NDL',
  "/MT:$Threads","/R:$Retries","/W:$WaitSec",
  '/TEE', ('/LOG+:"{0}"' -f $LogFile)
)
if ($DryRun) { $robo += '/L' }

# Ensure destination exists
Ensure-Folder -Path $Destination

Write-Host "==> Backing up XMPs"
Write-Host "    Source     : $Source"
Write-Host "    Destination: $Destination"
Write-Host "    Logs       : $LogFile"
Write-Host ("    Mode       : {0}" -f ($(if($DryRun){'DRY-RUN'} else {'COPY'})))

& robocopy @robo
$rc = $LASTEXITCODE
if ($rc -ge 8) { Write-Error "ROBOCOPY error (exit code $rc). See $LogFile"; exit $rc }
Write-Host "ROBOCOPY finished (exit code: $rc). Log: $LogFile"

# Optional manifest (stored alongside logs)
if ($MakeManifest) {
  $ManifestPath = Join-Path $ManDir ("xmp_manifest_{0}.csv" -f $TimeStamp)
  Write-Host "Building manifest at $ManifestPath ..."

  $files = Get-ChildItem -LiteralPath $Destination -Recurse -Filter *.xmp -File
  $rows = foreach ($f in $files) {
    $relPath = $f.FullName.Substring($Destination.Length).TrimStart('\','/')
    if ($Hash) {
      $h = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256
      [PSCustomObject]@{
        RelativePath = $relPath
        SizeBytes    = $f.Length
        LastWriteUtc = $f.LastWriteTimeUtc.ToString('o')
        SHA256       = $h.Hash
      }
    } else {
      [PSCustomObject]@{
        RelativePath = $relPath
        SizeBytes    = $f.Length
        LastWriteUtc = $f.LastWriteTimeUtc.ToString('o')
        SHA256       = ''
      }
    }
  }

  $rows | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
  Write-Host "Manifest complete: $ManifestPath"
}

# Optional housekeeping for logs/manifests
if ($KeepRecent -gt 0) {
  foreach ($dir in @($LogDir, $ManDir)) {
    if (Test-Path $dir) {
      Get-ChildItem -LiteralPath $dir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepRecent |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }
  }
}

Write-Host "Done."
