# download_chats.ps1
# Reusable YouTube Live Chat Downloader (date + title + video ID)

$BaseDir = $PSScriptRoot
$UrlFile = Join-Path $BaseDir "urls.txt"
$OutDir  = Join-Path $BaseDir "output"

if (!(Test-Path $UrlFile)) {
    Write-Host "ERROR: urls.txt not found in $BaseDir" -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$urls = Get-Content $UrlFile | Where-Object { $_.Trim() -ne "" }

Write-Host "Loaded $($urls.Count) URLs..." -ForegroundColor Cyan

foreach ($url in $urls) {

    # Extract video ID
    try {
        $videoId = ($url -split "/")[-1] -replace "\?.*$",""
    } catch {
        Write-Warning "Skipping invalid URL: $url"
        continue
    }

    Write-Host "Fetching metadata for: $videoId" -ForegroundColor DarkCyan

    # Temp metadata file
    $metaTmp = Join-Path $OutDir ("meta_{0}.json" -f $videoId)

    # Metadata-only fetch
    chat_downloader $url --max-comments 0 --output $metaTmp --format json > $null 2>&1

    # Read metadata JSON
    $meta = Get-Content $metaTmp -Raw | ConvertFrom-Json

    # Extract publish date
    $date = $meta.video_details.publish_date.ToString("yyyy-MM-dd")

    # Extract & sanitize title
    $title = $meta.video_details.title

    # Replace unsafe characters
    $safeTitle = $title -replace '[\/:*?"<>|]', ''
    $safeTitle = $safeTitle -replace '\s+', '_'   # spaces → underscores
    $safeTitle = $safeTitle -replace '[^A-Za-z0-9_\-]', '' # remove accents, symbols
    $safeTitle = $safeTitle.Trim('_')             # clean leftover underscores

    # Final output filename
    $outFileName = "{0}__{1}__{2}.txt" -f $date, $safeTitle, $videoId
    $outFile = Join-Path $OutDir $outFileName

    if (Test-Path $outFile) {
        Write-Host "Skipping (already exists): $outFile" -ForegroundColor DarkGray
        Remove-Item $metaTmp -Force
        continue
    }

    Write-Host "Downloading chat for: $safeTitle ($date)" -ForegroundColor Yellow
    chat_downloader $url --message_type text --output $outFile

    # Clean metadata file
    Remove-Item $metaTmp -Force
}

Write-Host "DONE. Chats saved in: $OutDir" -ForegroundColor Green
