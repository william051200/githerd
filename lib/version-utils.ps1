<#
.SYNOPSIS
    Shared semver helpers used by lib/update.ps1 and lib/update-check.ps1.

.DESCRIPTION
    Dot-source this file to expose Normalize-Tag and Compare-SemVer in the
    caller's scope:

        . (Join-Path $PSScriptRoot 'version-utils.ps1')

    Behavior is intentionally identical to the original copies that lived
    inline in update.ps1 and update-check.ps1; this file is the single
    source of truth.
#>

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
