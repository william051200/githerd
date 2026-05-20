<#
.SYNOPSIS
    Updates this GitHerd install in place to the latest GitHub release.

.DESCRIPTION
    Reads the local VERSION file, queries the GitHub releases API for the
    latest tag, and (if newer or -Force) re-runs install.ps1 against the
    current install directory in Portable mode so PATH is left alone.

    config.json is preserved by install.ps1; this script also makes a
    config.json.bak just before the upgrade as a belt-and-suspenders.

.PARAMETER Check
    Print whether an update is available and exit. Don't install anything.

.PARAMETER Force
    Re-install even if the local version equals the latest tag.

.PARAMETER Quiet
    Suppress informational output (errors still print).

.PARAMETER DevZip
    Forwarded to install.ps1 for local smoke testing.

.PARAMETER InstallScriptUrl
    Override the URL used to fetch install.ps1. Mainly for tests.
#>
[CmdletBinding()]
param(
    [Alias('c')][switch]$Check,
    [Alias('f')][switch]$Force,
    [Alias('q')][switch]$Quiet,
    [string]$DevZip,
    [string]$InstallScriptUrl = 'https://raw.githubusercontent.com/william051200/githerd/main/install.ps1'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'version-utils.ps1')

$Owner = 'william051200'
$Repo  = 'githerd'

function Write-Info([string]$Msg) {
    if (-not $Quiet) { Write-Host $Msg }
}

function Get-InstallDir {
    # lib/update.ps1 -> install dir is the parent of $PSScriptRoot
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-LocalVersion([string]$InstallDir) {
    $vf = Join-Path $InstallDir 'VERSION'
    if (-not (Test-Path -LiteralPath $vf)) { return $null }
    try {
        $v = (Get-Content -LiteralPath $vf -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        return $v
    } catch { return $null }
}

function Get-LatestTag {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    $url = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $resp = Invoke-RestMethod -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'githerd-updater' } -TimeoutSec 10
    if (-not $resp.tag_name) { throw "GitHub response did not include a tag_name." }
    return [string]$resp.tag_name
}

function Backup-Config([string]$InstallDir) {
    $cfg = Join-Path $InstallDir 'config.json'
    if (-not (Test-Path -LiteralPath $cfg)) { return $null }
    $backupRoot = Join-Path $env:LOCALAPPDATA 'GitHerd\config-backups'
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = Join-Path $backupRoot "config-$stamp.json"
    try {
        Copy-Item -LiteralPath $cfg -Destination $bak -Force
        Write-Info "Backed up config to $bak"
        return $bak
    } catch {
        Write-Warning "Could not back up config.json: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-Installer([string]$InstallDir, [string]$Tag) {
    Write-Info "Fetching installer from $InstallScriptUrl"
    $script = Invoke-RestMethod -Uri $InstallScriptUrl -UseBasicParsing -TimeoutSec 30
    $sb = [scriptblock]::Create($script)
    $params = @{
        Mode    = 'Portable'
        Dest    = $InstallDir
        Version = $Tag
        Quiet   = [bool]$Quiet
    }
    if ($DevZip) { $params['DevZip'] = $DevZip }
    & $sb @params
}

# ---- main -----------------------------------------------------------------

$installDir = Get-InstallDir
$local      = Get-LocalVersion $installDir
$localShown = if ($local) { "v$local" } else { 'unknown' }
Write-Info "GitHerd install: $installDir"
Write-Info "Local version : $localShown"

try {
    $latestTag = Get-LatestTag
} catch {
    Write-Error "Could not check latest version: $($_.Exception.Message)"
    exit 1
}
$latestNum = Normalize-Tag $latestTag
Write-Info "Latest release : v$latestNum ($latestTag)"

$needsUpdate = $true
if ($local -and -not $Force) {
    $cmp = Compare-SemVer $local $latestNum
    if ($cmp -ge 0) { $needsUpdate = $false }
}

if (-not $needsUpdate) {
    Write-Info "Already on the latest version (v$local)."
    exit 0
}

if ($Check) {
    Write-Host ("Update available: v{0} (you have {1})" -f $latestNum, $localShown)
    exit 0
}

Write-Info ("Updating GitHerd {0} -> v{1}..." -f $localShown, $latestNum)
Backup-Config $installDir
try {
    Invoke-Installer -InstallDir $installDir -Tag $latestTag
} catch {
    Write-Error "Update failed: $($_.Exception.Message)"
    exit 1
}
Write-Info ("Done. GitHerd is now v{0}." -f $latestNum)
exit 0
