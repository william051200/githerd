#Requires -Version 5.0

function Read-GitHerdConfigText {
    param([Parameter(Mandatory = $true)] [string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        throw "Failed to read config '$Path': $($_.Exception.Message)"
    }
}

function Write-GitHerdConfigText {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [string]$Text
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Config destination directory does not exist: $directory"
    }

    $tempPath = Join-Path $directory ('.githerd-config-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $directory ('.githerd-config-{0}.bak' -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tempPath, $Text, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $fullPath, $backupPath)
        } else {
            [System.IO.File]::Move($tempPath, $fullPath)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}
