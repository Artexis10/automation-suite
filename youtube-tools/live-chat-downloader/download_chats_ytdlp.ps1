param(
    # Path to yt-dlp. If yt-dlp.exe is in this folder, run script with:
    # .\download_chats_ytdlp.ps1 -YtDlpPath ".\yt-dlp.exe"
    [string]$YtDlpPath = "yt-dlp"
)

# download_chats_ytdlp.ps1
# Download YouTube live chat via yt-dlp and convert to plain text

function Convert-LiveChatJsonToText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )

    if (!(Test-Path $JsonPath)) {
        Write-Warning "JSON not found, cannot convert: $JsonPath"
        return
    }

    Write-Host "  Converting JSON → text: $([System.IO.Path]::GetFileName($JsonPath))" -ForegroundColor DarkCyan

    # IMPORTANT: force UTF-8 so emojis/quotes aren't mangled
    $lines = Get-Content -Path $JsonPath -Encoding utf8

    # Collect entries first so we can compute relative timestamps if needed
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line) { continue }

        try {
            $obj = $line | ConvertFrom-Json
        } catch {
            continue
        }

        # Locate the item containing the renderer
        $item = $null
        if ($obj.replayChatItemAction) {
            $actions = $obj.replayChatItemAction.actions
            if ($actions -and $actions.Count -gt 0) {
                $item = $actions[0].addChatItemAction.item
            }
        } elseif ($obj.addChatItemAction) {
            $item = $obj.addChatItemAction.item
        }
        if (-not $item) { continue }

        # Find renderer (liveChatTextMessageRenderer, liveChatPaidMessageRenderer, etc.)
        $renderer = $null
        $rendererName = $null
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -like "*Renderer") {
                $rendererName = $prop.Name
                $renderer = $prop.Value
                break
            }
        }
        if (-not $renderer) { continue }

        # Try to get relative offset (ms) from replayChatItemAction
        $offsetMs = $null
        if ($obj.replayChatItemAction -and $obj.replayChatItemAction.videoOffsetTimeMsec) {
            $offsetVal = $obj.replayChatItemAction.videoOffsetTimeMsec -as [double]
            if ($null -ne $offsetVal) {
                $offsetMs = $offsetVal
            }
        }

        # Absolute timestampUsec on the renderer (UNIX time, microseconds)
        $timestampUsec = $null
        if ($renderer.timestampUsec) {
            $tsVal = $renderer.timestampUsec -as [double]
            if ($null -ne $tsVal) {
                $timestampUsec = $tsVal
            }
        }

        # Pre-format absolute timestamp string (UTC) if we have one
        $absoluteTimeStr = $null
        if ($timestampUsec) {
            try {
                $unixSeconds = [long][math]::Floor($timestampUsec / 1000000)
                $absoluteTimeStr = [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
            } catch {
                $absoluteTimeStr = $null
            }
        }

        # Author
        $author = "UNKNOWN"
        if ($renderer.authorName) {
            if ($renderer.authorName.simpleText) {
                $author = $renderer.authorName.simpleText
            } elseif ($renderer.authorName.runs) {
                $author = ($renderer.authorName.runs | ForEach-Object { $_.text }) -join ""
            }
        }

        # Message text
        $msg = ""
        if ($renderer.message) {
            if ($renderer.message.simpleText) {
                $msg = $renderer.message.simpleText
            } elseif ($renderer.message.runs) {
                $parts = @()
                foreach ($run in $renderer.message.runs) {
                    if ($run.text) { $parts += $run.text }
                    elseif ($run.emoji -and $run.emoji.emojiId) { $parts += $run.emoji.emojiId }
                }
                $msg = ($parts -join "")
            }
        } elseif ($renderer.headerSubtext -and $renderer.headerSubtext.runs) {
            $msg = ($renderer.headerSubtext.runs | ForEach-Object { $_.text }) -join ""
        }

        if (-not $msg) {
            if ($rendererName -eq "liveChatPaidStickerRenderer") {
                $msg = "[STICKER]"
            } else {
                continue
            }
        }

        # Classify event kind
        $kind = "MSG"
        switch ($rendererName) {
            "liveChatPaidMessageRenderer"      { $kind = "SUPERCHAT" }
            "liveChatPaidStickerRenderer"      { $kind = "STICKER" }
            "liveChatMembershipItemRenderer"   { $kind = "MEMBERSHIP" }
            default {
                if ($rendererName -like "*TextMessageRenderer*") { $kind = "MSG" }
            }
        }

        $entries.Add([PSCustomObject]@{
            OffsetMs       = $offsetMs
            TimestampUsec  = $timestampUsec
            AbsoluteTime   = $absoluteTimeStr
            Kind           = $kind
            Author         = $author
            Message        = $msg
        })
    }

    # Decide how to compute relative timestamps
    $useOffset = $entries | Where-Object { $_.OffsetMs -ne $null } | Select-Object -First 1
    $baseTimestamp = $null
    if (-not $useOffset) {
        $baseTimestamp = ($entries |
            Where-Object { $_.TimestampUsec -ne $null } |
            Measure-Object -Property TimestampUsec -Minimum).Minimum
    }

    $outputLines = New-Object System.Collections.Generic.List[string]

    foreach ($e in $entries) {
        $relTime = "--:--:--"

        try {
            $seconds = $null
            if ($useOffset -and $e.OffsetMs -ne $null) {
                $seconds = [math]::Floor($e.OffsetMs / 1000)
            } elseif ($baseTimestamp -and $e.TimestampUsec -ne $null) {
                $seconds = [math]::Floor( ($e.TimestampUsec - $baseTimestamp) / 1000000 )
            }

            if ($null -ne $seconds -and $seconds -ge 0) {
                $hh = [math]::Floor($seconds / 3600)
                $mm = [math]::Floor(($seconds % 3600) / 60)
                $ss = $seconds % 60
                $relTime = "{0:00}:{1:00}:{2:00}" -f ([int]$hh), ([int]$mm), ([int]$ss)
            }
        } catch {
            $relTime = "--:--:--"
        }

        if ($e.AbsoluteTime) {
            $outLine = "[{0} / {1}] [{2}] {3}: {4}" -f $relTime, $e.AbsoluteTime, $e.Kind, $e.Author, $e.Message
        } else {
            $outLine = "[{0}] [{1}] {2}: {3}" -f $relTime, $e.Kind, $e.Author, $e.Message
        }

        $outputLines.Add($outLine)
    }

    # Write text file (UTF-8)
    $outputLines | Set-Content -Path $OutPath -Encoding utf8
}

# ----------------- MAIN SCRIPT -----------------

$BaseDir = $PSScriptRoot
$UrlFile = Join-Path $BaseDir "urls.txt"
$OutDir  = Join-Path $BaseDir "output_ytdlp"

if (!(Test-Path $UrlFile)) {
    Write-Host "ERROR: urls.txt not found in $BaseDir" -ForegroundColor Red
    exit 1
}

# Optional: check yt-dlp availability
try {
    & $YtDlpPath --version | Out-Null
} catch {
    Write-Host "ERROR: yt-dlp not found or not executable at: $YtDlpPath" -ForegroundColor Red
    Write-Host "Hint: put yt-dlp.exe next to this script and run:" -ForegroundColor Yellow
    Write-Host "      .\download_chats_ytdlp.ps1 -YtDlpPath '.\yt-dlp.exe'" -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$urls = Get-Content $UrlFile | Where-Object { $_.Trim() -ne "" }

Write-Host "Loaded $($urls.Count) URLs..." -ForegroundColor Cyan
Write-Host "Using yt-dlp: $YtDlpPath" -ForegroundColor Cyan

foreach ($url in $urls) {

    # Extract video ID (last path segment, strip query)
    try {
        $videoId = ($url -split "/")[-1] -replace "\?.*$",""
    } catch {
        Write-Warning "Skipping invalid URL: $url"
        continue
    }

    # If we already have any TXT containing this video ID, skip
    $existingTxt = Get-ChildItem $OutDir -Filter "*$videoId*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingTxt) {
        Write-Host "Skipping (text already exists): $videoId" -ForegroundColor DarkGray
        continue
    }

    Write-Host "Downloading chat (yt-dlp) for: $videoId" -ForegroundColor Yellow

    # Use upload_date + title + video id in the filename; yt-dlp will sanitize
    $template = Join-Path $OutDir "%(upload_date)s - %(title)s (%(id)s).%(ext)s"

    & $YtDlpPath $url `
        --skip-download `
        --write-subs `
        --sub-langs live_chat `
        --output $template `
        | Write-Output

    # Find the JSON we just created for this video
    $jsonFileItem = Get-ChildItem $OutDir -Filter "*$videoId*.live_chat.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $jsonFileItem) {
        Write-Warning "Expected JSON not found for $videoId. Check yt-dlp output above."
        continue
    }

    # Text file uses the same base name but .txt
    $txtFile = [System.IO.Path]::ChangeExtension($jsonFileItem.FullName, ".txt")

    Convert-LiveChatJsonToText -JsonPath $jsonFileItem.FullName -OutPath $txtFile
}

Write-Host "DONE. Chats saved in: $OutDir (JSON + TXT)" -ForegroundColor Green
