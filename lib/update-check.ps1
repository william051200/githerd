<#
.SYNOPSIS
    Quietly checks GitHub for a newer GitHerd release, at most once per
    Malaysia day after 12:00 PM MYT (UTC+8). Prints a one-line hint if a
    newer version is available; never blocks `sync.bat` on network errors.

.DESCRIPTION
    Cache file: %LOCALAPPDATA%\GitHerd\update-check.json
        { "last_checked_utc": "2026-05-14T04:00:00Z", "latest_tag": "v0.3.0" }

    Throttle rule:
        * Compute today's "noon MYT" as a UTC instant: that's today's MYT
          calendar date at 04:00 UTC.
        * If last_checked_utc >= todays_noon_myt_utc, skip the network
          call and just print the cached hint.
        * Otherwise hit the GitHub releases API (3-10s timeout), update
          the cache, print the hint if a newer tag is available.

    Honors $env:GITHERD_NO_UPDATE_CHECK = '1' (skip entirely).
#>
[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Force   # ignore cache & throttle, mainly for tests
)

$ErrorActionPreference = 'SilentlyContinue'   # never crash sync.bat

if ($env:GITHERD_NO_UPDATE_CHECK -eq '1') { exit 0 }

$Owner = 'william051200'
$Repo  = 'githerd'

function Get-LocalVersion {
    $vf = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'VERSION'
    if (-not (Test-Path -LiteralPath $vf)) { return $null }
    try { return ((Get-Content -LiteralPath $vf -Raw).Trim()) } catch { return $null }
}

function Normalize-Tag([string]$Tag) {
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    return $Tag.Trim().TrimStart('v','V')
}

function Compare-SemVer([string]$A, [string]$B) {
    $pa = ($A -split '[.+-]') | ForEach-Object { [int]($_ -replace '\D','0') }
    $pb = ($B -split '[.+-]') | ForEach-Object { [int]($_ -replace '\D','0') }
    $len = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return  1 }
    }
    return 0
}

function Get-CacheFile {
    $dir = Join-Path $env:LOCALAPPDATA 'GitHerd'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return Join-Path $dir 'update-check.json'
}

function Load-Cache([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
}

function Save-Cache([string]$Path, [string]$LatestTag) {
    $obj = [pscustomobject]@{
        last_checked_unix = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        last_checked_utc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")  # human-readable
        latest_tag        = $LatestTag
    }
    try {
        $obj | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {}
}

function Get-TodaysNoonMytUtc {
    # Today in MYT (UTC+8) at 12:00 -> as a UTC instant that's today MYT-date 04:00:00Z.
    $nowUtc = (Get-Date).ToUniversalTime()
    $nowMyt = $nowUtc.AddHours(8)
    $mytDate = $nowMyt.Date     # midnight MYT
    # noon MYT in UTC = mytDate (which is wall-clock midnight) + 12h - 8h offset
    return $mytDate.AddHours(4) # this is a UTC DateTime (kind=Unspecified treated as UTC instant here)
}

function Get-LatestTag {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    $url = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $resp = Invoke-RestMethod -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'githerd-updater' } -TimeoutSec 5
    if (-not $resp.tag_name) { return $null }
    return [string]$resp.tag_name
}

function Print-Hint([string]$Tag) {
    if ($Quiet) { return }
    if (-not $Tag) { return }
    $local = Get-LocalVersion
    $latestNum = Normalize-Tag $Tag
    if (-not $latestNum) { return }
    if ($local) {
        if ((Compare-SemVer $local $latestNum) -ge 0) { return }
    }
    Write-Host ("[update] v{0} is available. Run ``githerd --update`` to install." -f $latestNum)
}

# ---- main ------------------------------------------------------------------

$cacheFile = Get-CacheFile
$cache     = Load-Cache $cacheFile

$nowUtc      = (Get-Date).ToUniversalTime()
$todaysNoon  = Get-TodaysNoonMytUtc
$lastChecked = $null
if ($cache -and $cache.last_checked_unix) {
    try {
        $lastChecked = [DateTimeOffset]::FromUnixTimeSeconds([int64]$cache.last_checked_unix).UtcDateTime
    } catch {}
}

$shouldFetch = $true
if (-not $Force) {
    if ($nowUtc -lt $todaysNoon) {
        # Before noon MYT today -> never call out; show cached hint.
        $shouldFetch = $false
    } elseif ($lastChecked -and $lastChecked -ge $todaysNoon) {
        # Already checked since today's noon MYT.
        $shouldFetch = $false
    }
}

if ($shouldFetch) {
    $tag = $null
    try { $tag = Get-LatestTag } catch { $tag = $null }
    if ($tag) {
        Save-Cache $cacheFile $tag
        Print-Hint $tag
        exit 0
    }
    # Network failed; fall through to cached hint if any.
}

if ($cache -and $cache.latest_tag) {
    Print-Hint $cache.latest_tag
}
exit 0
