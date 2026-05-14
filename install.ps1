<#
.SYNOPSIS
    GitHerd installer.

.DESCRIPTION
    Downloads the latest GitHerd release ZIP from GitHub and installs it
    either into the per-user programs folder (and adds it to the user PATH)
    or into a portable directory you choose.

    Designed to be runnable as a one-liner:

        irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1 | iex

    To pass parameters via the one-liner, wrap in a script block:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1))) -Mode Portable -Dest C:\tools\githerd

.PARAMETER Mode
    'User'     - install into %LOCALAPPDATA%\Programs\GitHerd and add to user PATH (default)
    'Portable' - install into the directory passed via -Dest, no PATH changes

.PARAMETER Dest
    Required when -Mode Portable. The folder to extract GitHerd into.

.PARAMETER Version
    Specific release tag to install (e.g. v0.1.0). Defaults to the latest
    release on the GitHub repo.

.PARAMETER NoPath
    Skip adding the install directory to the user PATH (User mode only).

.PARAMETER Quiet
    Suppress informational output.

.PARAMETER DevZip
    Path to a local release ZIP to use instead of downloading from GitHub.
    Used by the project's own smoke tests.
#>
[CmdletBinding()]
param(
    [ValidateSet('User','Portable')]
    [string]$Mode = 'User',

    [string]$Dest,

    [string]$Version,

    [switch]$NoPath,

    [switch]$Quiet,

    [string]$DevZip
)

$ErrorActionPreference = 'Stop'

# -- Repo coordinates --------------------------------------------------------
$Owner = 'william051200'
$Repo  = 'githerd'

# -- Helpers -----------------------------------------------------------------
function Write-Info($msg)  { if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan } }
function Write-Ok  ($msg)  { if (-not $Quiet) { Write-Host $msg -ForegroundColor Green } }
function Write-Warn2($msg) { Write-Warning $msg }

function Test-PSVersion {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.1 or newer is required (you have $($PSVersionTable.PSVersion))."
    }
}

function Resolve-LatestVersion {
    Write-Info "Looking up latest GitHerd release ..."
    $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    try {
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = "githerd-installer" } -ErrorAction Stop
    } catch {
        throw "Could not query GitHub releases API ($api): $($_.Exception.Message). " +
              "If no release has been cut yet, pass -DevZip <localZip> or -Version <tag>."
    }
    if (-not $json.tag_name) { throw "No tag_name returned from $api." }
    return [string]$json.tag_name
}

function Get-ReleaseZip([string]$Tag) {
    $clean = $Tag.TrimStart('v')
    $assetUrl = "https://github.com/$Owner/$Repo/releases/download/$Tag/githerd-v$clean.zip"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("githerd-install-" + [guid]::NewGuid().ToString('N') + ".zip")
    Write-Info "Downloading $assetUrl"
    try {
        Invoke-WebRequest -Uri $assetUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        throw "Could not download release ZIP for $Tag from $assetUrl. $($_.Exception.Message)"
    }
    return $tmp
}

function Expand-ToInstallDir([string]$ZipPath, [string]$InstallDir) {
    if (Test-Path $InstallDir) {
        # Wipe everything except a sibling config.json the user may have
        # placed there manually before re-running the installer.
        Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object { $_.Name -ne 'config.json' } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    } else {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("githerd-extract-" + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $stage -Force

        # The ZIP wraps everything in a single githerd-vX.Y.Z folder.
        $rootDirs = Get-ChildItem -LiteralPath $stage -Directory
        $payload = if ($rootDirs.Count -eq 1) { $rootDirs[0].FullName } else { $stage }

        Get-ChildItem -LiteralPath $payload -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $InstallDir -Recurse -Force
        }
    } finally {
        if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    }
}

function Add-ToUserPath([string]$Folder) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { $current = '' }
    $parts = $current -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $Folder.TrimEnd('\')) }
    if ($parts.Count -gt 0) {
        Write-Info "PATH already contains $Folder (no change)."
        return $false
    }
    $new = if ($current -and -not $current.EndsWith(';')) { "$current;$Folder" } else { "$current$Folder" }
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')

    # Broadcast WM_SETTINGCHANGE so already-running shells & Explorer notice.
    try {
        $sig = @"
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
        $type = Add-Type -MemberDefinition $sig -Name GitherdInstallerNative -Namespace GitherdInstaller -PassThru -ErrorAction Stop
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1A
        $SMTO_ABORTIFHUNG = 0x2
        [UIntPtr]$result = [UIntPtr]::Zero
        [void]$type::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', $SMTO_ABORTIFHUNG, 5000, [ref]$result)
    } catch {
        # Non-fatal; new shells will pick it up regardless.
    }
    return $true
}

# -- Main --------------------------------------------------------------------
Test-PSVersion

if ($Mode -eq 'Portable' -and -not $Dest) {
    throw "Portable mode requires -Dest <path>."
}

# Resolve install directory
if ($Mode -eq 'User') {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\GitHerd'
} else {
    $resolved = Resolve-Path -LiteralPath $Dest -ErrorAction SilentlyContinue
    if ($resolved) { $InstallDir = $resolved.Path } else { $InstallDir = $Dest }
}

Write-Info ""
Write-Info "GitHerd installer"
Write-Info "  Mode       : $Mode"
Write-Info "  Install dir: $InstallDir"

# Acquire the ZIP
$cleanupZip = $false
$zipPath = $null
try {
    if ($DevZip) {
        if (-not (Test-Path $DevZip)) { throw "DevZip not found: $DevZip" }
        $zipPath = (Resolve-Path -LiteralPath $DevZip).Path
        Write-Info "Using local ZIP: $zipPath"
    } else {
        if (-not $Version) { $Version = Resolve-LatestVersion }
        Write-Info "  Version    : $Version"
        $zipPath = Get-ReleaseZip $Version
        $cleanupZip = $true
    }

    Expand-ToInstallDir -ZipPath $zipPath -InstallDir $InstallDir
} finally {
    if ($cleanupZip -and $zipPath -and (Test-Path $zipPath)) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
}

# PATH wiring (User mode only)
$pathAdded = $false
if ($Mode -eq 'User' -and -not $NoPath) {
    $pathAdded = Add-ToUserPath -Folder $InstallDir
}

# Summary
Write-Ok  ""
Write-Ok  "GitHerd installed."
Write-Info "  Location: $InstallDir"
if ($Mode -eq 'User') {
    if ($NoPath) {
        Write-Info "  PATH: not modified (-NoPath). Invoke directly: `"$InstallDir\githerd.cmd`""
    } elseif ($pathAdded) {
        Write-Info "  PATH: added to user PATH. Open a NEW terminal, then run:"
        Write-Info "        githerd --config       (open config UI)"
        Write-Info "        githerd                (sync configured repos)"
    } else {
        Write-Info "  PATH: already configured. Run: githerd --config"
    }
} else {
    Write-Info "  Run it directly:"
    Write-Info "        `"$InstallDir\githerd.cmd`" --config"
    Write-Info "        `"$InstallDir\githerd.cmd`""
}
Write-Info ""
