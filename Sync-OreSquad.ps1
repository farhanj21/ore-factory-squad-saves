param(
    [switch]$Pull,
    [switch]$Push,
    [switch]$Resolve,
    [switch]$AutoPush,
    [string]$Message,
    [string]$Slot = 'OFS_0001'
)

$ErrorActionPreference = 'Continue'
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
$expectedRemote = 'https://github.com/farhanj21/ore-factory-squad-saves.git'

function Write-Step($text)  { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-OK($text)    { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text)  { Write-Host "    WARN: $text" -ForegroundColor Yellow }
function Write-Fail($text)  { Write-Host "    ERROR: $text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath (Join-Path $scriptRoot '.git'))) {
    Write-Fail "This is not a git repo. Clone the save repo into the Saves folder first."
    exit 1
}

$gameProc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)ore.*(factory|squad)|factory.*squad' }
if ($gameProc) {
    Write-Fail "The game is running. Close it before any git operation."
    exit 1
}

$remote = (& git -C $scriptRoot remote get-url origin 2>$null).Trim()
if ($remote -ne $expectedRemote) {
    Write-Fail "Remote '$remote' does not match expected '$expectedRemote'. Refusing to continue."
    exit 1
}

$scriptName = [System.IO.Path]::GetFileName($PSCommandPath)
$headBlob = (& git -C $scriptRoot rev-parse "HEAD:$scriptName" 2>$null).Trim()
if ($LASTEXITCODE -eq 0 -and $headBlob) {
    $localBlob = (& git -C $scriptRoot hash-object (Join-Path $scriptRoot $scriptName)).Trim()
    if ($localBlob -ne $headBlob) {
        Write-Fail "This script differs from the committed version in the repo. It may have been modified by someone else. Review it before running."
        exit 1
    }
}

function Get-Porcelain {
    return @(& git -C $scriptRoot status --porcelain)
}

function Get-SaveStats {
    param($slot, $fromGitRef = $null)
    $result = @{ Title = $null; Level = $null; Prog = $null; Day = $null; Players = $null; Entities = $null }
    $metaPath = Join-Path $scriptRoot "$slot\game_data.meta"
    $gzPath = Join-Path $scriptRoot "$slot\SAVE.GZ"
    $tmpMeta = $null
    $tmpGz = $null
    try {
        if ($fromGitRef) {
            $tmpMeta = Join-Path $env:TEMP ("ofs_meta_" + [guid]::NewGuid().ToString('N'))
            & cmd /c ('git -C "' + $scriptRoot + '" show "' + $fromGitRef + ':' + $slot + '/game_data.meta" > "' + $tmpMeta + '"')
            $metaPath = $tmpMeta
            $tmpGz = Join-Path $env:TEMP ("ofs_gz_" + [guid]::NewGuid().ToString('N'))
            & cmd /c ('git -C "' + $scriptRoot + '" show "' + $fromGitRef + ':' + $slot + '/SAVE.GZ" > "' + $tmpGz + '"')
            $gzPath = $tmpGz
        }
        if (Test-Path -LiteralPath $metaPath) {
            $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json
            $result.Title = $meta.m_Title
            $result.Level = $meta.m_CharLevel
            $result.Prog = $meta.m_Progression
        }
    } catch {}
    try {
        if (Test-Path -LiteralPath $gzPath) {
            $bytes = [System.IO.File]::ReadAllBytes($gzPath)
            $ms = New-Object System.IO.MemoryStream(,$bytes)
            $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $sr = New-Object System.IO.StreamReader($gz)
            $json = $sr.ReadToEnd()
            $sr.Dispose(); $gz.Dispose(); $ms.Dispose()
            $dm = [regex]::Match($json, '\\"currentGameDay\\":\s*(\d+)')
            if ($dm.Success) { $result.Day = $dm.Groups[1].Value }
            $ids = @([regex]::Matches($json, '\\"steamId64\\":\s*(\d+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '0' } | Sort-Object -Unique)
            if ($ids.Count -gt 0) { $result.Players = $ids.Count }
            $result.Entities = [regex]::Matches($json, '"m_Key"').Count
        }
    } catch {}
    if ($tmpMeta) { Remove-Item -LiteralPath $tmpMeta -ErrorAction SilentlyContinue }
    if ($tmpGz)   { Remove-Item -LiteralPath $tmpGz -ErrorAction SilentlyContinue }
    return $result
}

function Show-SaveStats($s) {
    $any = $false
    if ($s.Title)   { Write-Host "    World:   $($s.Title)";   $any = $true }
    if ($s.Day)     { Write-Host "    Day:     $($s.Day)";     $any = $true }
    if ($s.Level)   { Write-Host "    Level:   $($s.Level)";   $any = $true }
    if ($s.Players) { Write-Host "    Players: $($s.Players)"; $any = $true }
    if ($s.Prog)    { Write-Host "    Prog:    $($s.Prog)";    $any = $true }
    if ($s.Entities){ Write-Host "    Entities:$($s.Entities)"; $any = $true }
    if (-not $any)  { Write-Host "    (no readable save data)" -ForegroundColor Yellow }
}

function New-CommitMessage($slot) {
    $porcelain = Get-Porcelain
    $changed = @($porcelain | Where-Object { $_ })
    $stats = Get-SaveStats $slot
    $chunksDug = @($porcelain | Where-Object { $_ -match '\.vox3$' }).Count

    $subject = $Message
    if (-not $subject) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
        $parts = @("save $ts")
        if ($stats.Title) { $parts += $stats.Title }
        if ($stats.Day)   { $parts += "day $($stats.Day)" }
        if ($stats.Level) { $parts += "Lv$($stats.Level)" }
        $hostName = (& git -C $scriptRoot config user.name 2>$null).Trim()
        if (-not $hostName) { $hostName = $env:USERNAME }
        $parts += $hostName
        $subject = $parts -join ' | '
    }

    $p2 = "Changed: $($changed.Count) file(s) ($chunksDug chunk(s) dug) | slot $slot"
    $p3parts = @()
    if ($stats.Title)   { $p3parts += $stats.Title }
    if ($stats.Players) { $p3parts += "players: $($stats.Players)" }
    if ($stats.Prog)    { $p3parts += "progression: $($stats.Prog)" }
    if ($stats.Entities){ $p3parts += "entities: $($stats.Entities)" }
    $p3 = "World: " + ($p3parts -join ' | ')

    return @{ Subject = $subject; Body = $p2; World = $p3 }
}

function Write-CommitFile($msg, $note) {
    $tmp = Join-Path $env:TEMP ("ofs_commit_" + [guid]::NewGuid().ToString('N') + ".txt")
    $text = $msg.Subject + "`n`n" + $msg.Body + "`n" + $msg.World
    if ($note) { $text += "`n`nNote: $note" }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $text + "`n", $utf8)
    return $tmp
}

function Invoke-Pull {
    Write-Step "Fetching latest save..."
    & git -C $scriptRoot fetch origin 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Fetch failed. Check your network connection and git credentials."
        exit 1
    }
    $localHead = (& git -C $scriptRoot rev-parse HEAD).Trim()
    $remoteHead = (& git -C $scriptRoot rev-parse origin/main).Trim()
    $behind = 0; $ahead = 0
    try { $behind = [int]((& git -C $scriptRoot rev-list --count HEAD..origin/main).Trim()) } catch {}
    try { $ahead  = [int]((& git -C $scriptRoot rev-list --count origin/main..HEAD).Trim()) } catch {}
    $dirty = @((Get-Porcelain) | Where-Object { $_ }).Count

    if ($dirty -gt 0) {
        if ($behind -gt 0) {
            Write-Warn "You have unsaved local changes AND the remote has moved ahead."
            Write-Host "    Run Resolve (option 4 / -Resolve) to compare both saves and keep the newest one." -ForegroundColor Yellow
            exit 1
        }
        Write-Warn "You have an unsaved hosted session (you played and saved, but haven't handed it off)."
        Write-Host "    Run Push (option 2) or Full sync (option 3) to upload it for the next host." -ForegroundColor Yellow
        return
    }
    if ($behind -eq 0 -and $ahead -eq 0) {
        Write-OK "Up to date."
        return
    }
    if ($ahead -gt 0) {
        Write-Warn "Local has un-pushed commit(s) from a previous session."
        Write-Host "    Run Push (option 2) to hand the save off to the next host." -ForegroundColor Yellow
        return
    }
    Write-Step "Pulling latest save..."
    & git -C $scriptRoot merge --ff-only origin/main
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Pull failed. Rule: stop, keep the newest save, then run Resolve (option 4)."
        exit 1
    }
    Write-OK "Up to date."
}

function Invoke-Push {
    $porcelain = Get-Porcelain
    $changed = @($porcelain | Where-Object { $_ })
    $pending = 0
    try { $pending = [int]((& git -C $scriptRoot rev-list --count origin/main..HEAD).Trim()) } catch {}

    if ($changed.Count -eq 0 -and $pending -eq 0) {
        Write-OK "Nothing to commit or push - save is up to date."
        return
    }

    if ($changed.Count -gt 0) {
        $msg = New-CommitMessage $Slot

        Write-Host ""
        Write-Host "Proposed commit message:" -ForegroundColor Magenta
        Write-Host "  $($msg.Subject)" -ForegroundColor Magenta
        Write-Host "  $($msg.Body)" -ForegroundColor Magenta
        Write-Host "  $($msg.World)" -ForegroundColor Magenta
        Write-Host ""

        if (-not $AutoPush) {
            $answer = Read-Host "Commit and push? (y/n)"
            if ($answer -notmatch '^y') {
                Write-Warn "Skipping. Nothing was committed - run with -Push when ready."
                return
            }
            $note = Read-Host "Note for this session? (Enter to skip)"
        } else {
            $note = ''
        }

        $commitFile = Write-CommitFile $msg $note
        & git -C $scriptRoot add -A
        & git -C $scriptRoot commit -F $commitFile
        Remove-Item -LiteralPath $commitFile -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Commit failed."
            exit 1
        }
        Write-OK "Committed: $($msg.Subject)"
    } else {
        Write-Warn "$pending earlier commit(s) were never pushed - pushing them now."
        if (-not $AutoPush) {
            $answer = Read-Host "Push now? (y/n)"
            if ($answer -notmatch '^y') {
                Write-Warn "Skipping. Nothing was pushed - run with -Push when ready."
                return
            }
        }
    }

    Write-Step "Pushing..."
    & git -C $scriptRoot push
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Push failed. Rule: stop, keep the newest save, then run Resolve (option 4)."
        exit 1
    }
    Write-OK "Pushed. Handoff ready - tell the next host to pull."
}

function Invoke-Resolve {
    Write-Step "Fetching latest save..."
    & git -C $scriptRoot fetch origin 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Fetch failed. Check your network connection and git credentials."
        exit 1
    }
    $localHead = (& git -C $scriptRoot rev-parse HEAD).Trim()
    $remoteHead = (& git -C $scriptRoot rev-parse origin/main).Trim()
    $dirty = @((Get-Porcelain) | Where-Object { $_ }).Count

    if ($localHead -eq $remoteHead -and $dirty -eq 0) {
        Write-OK "Nothing to resolve - local and remote are already in sync."
        return
    }

    $localStats = Get-SaveStats $Slot
    $remoteStats = Get-SaveStats $Slot 'origin/main'

    Write-Host ""
    Write-Host "Local save  (this machine):" -ForegroundColor Magenta
    Show-SaveStats $localStats
    Write-Host "Remote save (origin/main):" -ForegroundColor Magenta
    Show-SaveStats $remoteStats
    Write-Host ""

    $choice = Read-Host "Which save is newer? [L]ocal / [R]emote / [C]ancel"
    if ($choice -match '^[Ll]') {
        $confirm = Read-Host "Overwrite the REMOTE save with your LOCAL one? Type 'KEEP-LOCAL' to confirm"
        if ($confirm -ne 'KEEP-LOCAL') {
            Write-Warn "Cancelled. Nothing was changed."
            return
        }
        $changed = @((Get-Porcelain) | Where-Object { $_ })
        if ($changed.Count -gt 0) {
            $msg = New-CommitMessage $Slot
            $note = Read-Host "Note for this commit? (Enter to skip)"
            $commitFile = Write-CommitFile $msg $note
            & git -C $scriptRoot add -A
            & git -C $scriptRoot commit -F $commitFile
            Remove-Item -LiteralPath $commitFile -ErrorAction SilentlyContinue
            if ($LASTEXITCODE -ne 0) {
                Write-Fail "Commit failed. Aborting without pushing."
                exit 1
            }
            Write-OK "Committed: $($msg.Subject)"
        }
        Write-Step "Force-pushing local save over the remote (newest save wins)..."
        & git -C $scriptRoot push --force-with-lease origin main
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Force push failed. The remote moved again - re-run Resolve and compare once more."
            exit 1
        }
        Write-OK "Resolved. Your local save is now the shared save - tell the next host to pull."
    } elseif ($choice -match '^[Rr]') {
        $confirm = Read-Host "Discard the LOCAL save and use the REMOTE one? Type 'KEEP-REMOTE' to confirm. This deletes your uncommitted local changes."
        if ($confirm -ne 'KEEP-REMOTE') {
            Write-Warn "Cancelled. Nothing was changed."
            return
        }
        Write-Step "Restoring the remote save (discarding local changes)..."
        & git -C $scriptRoot reset --hard origin/main
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Reset failed. Aborting."
            exit 1
        }
        & git -C $scriptRoot clean -fd
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Clean failed."
            exit 1
        }
        Write-OK "Resolved. Your local save was replaced by the remote save."
    } else {
        Write-Warn "Cancelled."
    }
}

if ($Resolve) {
    Invoke-Resolve
} elseif ($Pull) {
    Invoke-Pull
} elseif ($Push) {
    Invoke-Push
} else {
    Write-Step "Full sync: pull + push"
    Invoke-Pull
    Invoke-Push
}
