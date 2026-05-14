<#
.SYNOPSIS
    Builds a release ZIP of GitHerd at dist/githerd-vX.Y.Z.zip.

.DESCRIPTION
    Packages a clean copy of the repo (no .git/, no .github/, no config.json,
    no DESIGN.md, no dist/, no scripts/) into a single ZIP suitable for a
    GitHub Release attachment.

.PARAMETER Version
    Version string without a leading "v" (e.g. 0.1.0). The output filename
    becomes githerd-v<Version>.zip.

.PARAMETER OutDir
    Where to write the ZIP. Defaults to <repo>/dist.

.EXAMPLE
    .\scripts\build-release.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+].+)?$')]
    [string]$Version,

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Include = @(
    'sync.bat',
    'githerd.cmd',
    'README.md',
    'LICENSE',
    'config.example.json',
    'lib',
    'ui',
    'docs'
)

$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ("githerd-build-" + [guid]::NewGuid().ToString('N'))
$PackageDirName = "githerd-v$Version"
$Pkg = Join-Path $Stage $PackageDirName
New-Item -ItemType Directory -Force -Path $Pkg | Out-Null

try {
    foreach ($entry in $Include) {
        $src = Join-Path $RepoRoot $entry
        if (-not (Test-Path $src)) {
            Write-Warning "Skipping missing entry: $entry"
            continue
        }
        $dst = Join-Path $Pkg $entry
        if ((Get-Item $src).PSIsContainer) {
            Copy-Item $src $dst -Recurse
        } else {
            $parent = Split-Path -Parent $dst
            if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Copy-Item $src $dst
        }
    }

    $ZipPath = Join-Path $OutDir "githerd-v$Version.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $ZipPath -Force

    $bytes = (Get-Item $ZipPath).Length
    $sha   = (Get-FileHash -Algorithm SHA256 $ZipPath).Hash
    Write-Host ""
    Write-Host "Built: $ZipPath"
    Write-Host ("  Size  : {0:N0} bytes" -f $bytes)
    Write-Host ("  SHA256: $sha")
} finally {
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
}
