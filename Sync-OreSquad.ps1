param(
    [switch]$Pull,
    [switch]$Push,
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

function Get-SaveStats($slot) {
    $result = @{ Title = $null; Level = $null; Prog = $null; Day = $null; Players = $null; Entities = $null }
    try {
        $metaPath = Join-Path $scriptRoot "$slot\game_data.meta"
        if (Test-Path -LiteralPath $metaPath) {
            $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json
            $result.Title = $meta.m_Title
            $result.Level = $meta.m_CharLevel
            $result.Prog = $meta.m_Progression
        }
    } catch {}
    try {
        $gzPath = Join-Path $scriptRoot "$slot\SAVE.GZ"
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
    return $result
}

function Invoke-Pull {
    $porcelain = Get-Porcelain
    if (@($porcelain | Where-Object { $_ }).Count -gt 0) {
        Write-Warn "Uncommitted changes found; skipping pull (your local save is newer)."
        return
    }
    Write-Step "Pulling latest save..."
    & git -C $scriptRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Pull failed. Rule: stop, keep the newest save, push that one over the remote."
        exit 1
    }
    Write-OK "Up to date."
}

function Invoke-Push {
    $porcelain = Get-Porcelain
    $changed = @($porcelain | Where-Object { $_ })
    if ($changed.Count -eq 0) {
        Write-OK "Nothing to commit or push - save is up to date."
        return
    }

    $stats = Get-SaveStats $Slot
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

    $p2 = "Changed: $($changed.Count) file(s) ($chunksDug chunk(s) dug) | slot $Slot"
    $p3parts = @()
    if ($stats.Title)   { $p3parts += $stats.Title }
    if ($stats.Players) { $p3parts += "players: $($stats.Players)" }
    if ($stats.Prog)    { $p3parts += "progression: $($stats.Prog)" }
    if ($stats.Entities) { $p3parts += "entities: $($stats.Entities)" }
    $p3 = "World: " + ($p3parts -join ' | ')

    Write-Host ""
    Write-Host "Proposed commit message:" -ForegroundColor Magenta
    Write-Host "  $subject" -ForegroundColor Magenta
    Write-Host "  $p2" -ForegroundColor Magenta
    Write-Host "  $p3" -ForegroundColor Magenta
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

    & git -C $scriptRoot add -A
    $commitArgs = @('-m', $subject, '-m', $p2, '-m', $p3)
    if ($note) { $commitArgs += @('-m', "Note: $note") }
    & git -C $scriptRoot commit @commitArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Commit failed."
        exit 1
    }
    Write-OK "Committed: $subject"

    Write-Step "Pushing..."
    & git -C $scriptRoot push
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Push failed. Rule: stop, keep the newest save, then push that one over the remote."
        exit 1
    }
    Write-OK "Pushed. Handoff ready - tell the next host to pull."
}

if ($Pull) {
    Invoke-Pull
} elseif ($Push) {
    Invoke-Push
} else {
    Write-Step "Full sync: pull + push"
    Invoke-Pull
    Invoke-Push
}
